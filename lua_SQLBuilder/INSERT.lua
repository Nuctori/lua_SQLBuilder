local class = require "lua_SQLBuilder.class"
local sqlBuilder = require "lua_SQLBuilder.SQLBuilder"
---@class INSERT : sqlBuilder
local INSERT = class("INSERT", sqlBuilder)
local json = require "lua_SQLBuilder.json"
local utils = require "lua_SQLBuilder.utils"
local render_value = utils.render_value
local fmt = string.format
local tconcat = table.concat
local tsort = table.sort

function INSERT:__getInsertValue()
    local t = {}
    for _, value in ipairs(self.values) do
        local row = {}
        for i, v in ipairs(value) do
            row[i] = render_value(v, self._dialect)
        end
        t[#t + 1] = fmt("(%s)", tconcat(row, ", "))
    end
    return tconcat(t, ", ")
end

function INSERT:__getPrepareInsertValue()
    local t = {}
    local params = {}
    for _, value in ipairs(self.values) do
        local placeholders = {}
        local row = {}
        for i, v in ipairs(value) do
            if type(v) == "boolean" then
                row[i] = tostring(v)
            else
                row[i] = v
            end
            placeholders[#placeholders + 1] = "?"
        end
        t[#t + 1] = fmt("(%s)", tconcat(placeholders, ", "))
        params[#params + 1] = row
    end
    return tconcat(t, ", "), params
end

function INSERT:ctor(tableName, opts)
    self.tableName = tableName
    self.cols = {}
    self.values = {}
    self.update = {}
    self.conflictCols = nil
    self.init(self, nil, opts)
end

local function sort_keys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    tsort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

function INSERT:__renderUpsert()
    if not next(self.update) then
        return ""
    end
    local dialect = self._dialect
    local upsert = dialect.upsert
    if not upsert then
        error("dialect '" .. dialect.name .. "' has no upsert support (use mysql/mariadb/postgres/sqlite)", 2)
    end
    local quote = dialect.quote_ident
    local keys = sort_keys(self.update)
    if upsert.needs_conflict then
        local conflict = self.conflictCols
        assert(conflict ~= nil,
            "dialect '" .. dialect.name .. "' requires conflict target columns (pass them to ON_DUPLICATE_KEY_UPDATE)")
        local cols
        if type(conflict) == "table" then
            cols = conflict
        else
            cols = { conflict }
        end
        local conflictSql = {}
        for _, col in ipairs(cols) do
            conflictSql[#conflictSql + 1] = quote(col)
        end
        local sets = {}
        for _, key in ipairs(keys) do
            sets[#sets + 1] = fmt("%s = %s.%s", quote(key), dialect.upsert.ref, quote(key))
        end
        return fmt("ON CONFLICT (%s) DO UPDATE SET %s", tconcat(conflictSql, ", "), tconcat(sets, ", "))
    end
    local sets = {}
    for _, key in ipairs(keys) do
        sets[#sets + 1] = fmt("%s = %s", quote(key), render_value(self.update[key], self._dialect))
    end
    return "ON DUPLICATE KEY UPDATE " .. tconcat(sets, ", ")
end

function INSERT:TableOperator()
    local sql = fmt("INSERT INTO %s (%s) VALUES %s", self.tableName, tconcat(self.cols, ", "), self:__getInsertValue())
    local upsert = self:__renderUpsert()
    if upsert ~= "" then
        sql = sql .. " " .. upsert
    end
    return sql
end

function INSERT:PrepareTableOperator()
    local valueStr, params = self:__getPrepareInsertValue()
    local sql = fmt("INSERT INTO %s (%s) VALUES %s", self.tableName, tconcat(self.cols, ", "), valueStr)
    local upsert = self:__renderUpsert()
    if upsert ~= "" then
        sql = sql .. " " .. upsert
    end
    return sql, params
end

function INSERT:COLS(...)
    for _, col in ipairs({...}) do
        assert(type(col) == "string")
        self.cols[#self.cols + 1] = self._dialect.quote_ident(col)
    end
    return self
end

function INSERT:VALUES(...)
    for _, value in ipairs({...}) do
        assert(type(value) == "table")
        local row = {}
        for i, v in ipairs(value) do
            if type(v) == "table" then
                row[i] = json.encode(v)
            else
                row[i] = v
            end
        end
        self.values[#self.values + 1] = row
    end
    return self
end

function INSERT:DATA(t)
    -- DATA owns the columns and rows: reset any prior COLS/VALUES/DATA so
    -- mixing calls cannot misalign columns (A10/NB-14)
    self.cols = {}
    self.values = {}
    local value = {}
    self.values[1] = value
    -- 给插入数据的字段排序，确保生成一致性
    for _, col in ipairs(sort_keys(t)) do
        local val = t[col]
        self.cols[#self.cols + 1] = self._dialect.quote_ident(col)
        if type(val) == "table" then
            val = json.encode(val)
        end
        value[#value + 1] = val
    end
    return self
end

---@param t table 字段 → 更新值
---@param conflictCols string|table|nil 冲突目标列（postgres/sqlite 必须提供）
function INSERT:ON_DUPLICATE_KEY_UPDATE(t, conflictCols)
    self.update = t
    self.conflictCols = conflictCols
    return self
end

return INSERT
