
local class = require "lua_SQLBuilder.class"
local sqlBuilder = require "lua_SQLBuilder.SQLBuilder"
---@class INSERT : sqlBuilder
local INSERT = class("INSERT", sqlBuilder)
local json = require "lua_SQLBuilder.json"
local table_format = require "lua_SQLBuilder.utils".table_format
local fmt = string.format
local tconcat = table.concat
local tsort = table.sort

function INSERT:__getInsertValue()
    local t = {}
    for _, value in ipairs(self.values) do
        for i, v in ipairs(value) do
            if type(v) == "string" then
                value[i] = fmt("'%s'", v)
            elseif type(v) == "boolean" then
                value[i] = tostring(v)
            end
        end
        t[#t + 1] = fmt("(%s)", tconcat(value, ", "))
    end
    return tconcat(t, ", ")
end

function INSERT:__getPrepareInsertValue()
    local t = {}
    local params = {}
    for _, value in ipairs(self.values) do
        local placeholders = {}
        for i, v in ipairs(value) do
            if type(v) == "boolean" then
                value[i] = tostring(v)
            end
            placeholders[#placeholders + 1] = "?"
        end
        t[#t + 1] = fmt("(%s)", tconcat(placeholders, ", "))
        params[#params + 1] = value
    end
    return tconcat(t, ", "), params
end

function INSERT:ctor(tableName)
    self.tableName = tableName
    self.cols = {}
    self.values = {}
    self.update = {}
    self.init(self)
end

function INSERT:TableOperator()
    local sql = fmt("INSERT INTO %s (%s) VALUES %s", self.tableName, tconcat(self.cols, ", "), self:__getInsertValue())
    if next(self.update) then
        sql = sql..fmt(" ON DUPLICATE KEY UPDATE %s", table_format(self.update, ", "))
    end
    return sql
end

function INSERT:PrepareTableOperator()
    local valueStr, params = self:__getPrepareInsertValue()
    local sql = fmt("INSERT INTO %s (%s) VALUES %s", self.tableName, tconcat(self.cols, ", "), valueStr)
    if next(self.update) then
        sql = sql..fmt(" ON DUPLICATE KEY UPDATE %s", table_format(self.update, ", "))
    end
    return sql, params
end



function INSERT:COLS(...)
    for _, col in ipairs({...}) do
        assert(type(col) == "string")
        self.cols[#self.cols + 1] = fmt("`%s`", col)
    end
    return self
end

function INSERT:VALUES(...)
    for _, value in ipairs({...}) do
        assert(type(value) == "table")
        for i, v in ipairs(value) do
            if type(v) == "table" then
                value[i] = json.encode(v)
            end
        end
        self.values[#self.values + 1] = value
    end
    return self
end

function INSERT:DATA(t)
    local value = {}
    self.values[1] = value
    -- 给插入数据的字段排序，确保生成一致性
    for col, val in pairs(t) do
        self.cols[#self.cols + 1] = fmt("`%s`", col)
        if type(val) == "table" then
            val = json.encode(val)
        end
        value[#value + 1] = val
    end
    return self
end

function INSERT:ON_DUPLICATE_KEY_UPDATE(t)
    for key, value in pairs(t) do
        self.update[fmt("`%s`", key)] = value
    end
    return self
end

return INSERT