local class = require "lua_SQLBuilder.class"
local sqlBuilder = require "lua_SQLBuilder.SQLBuilder"
---@class UPDATE : sqlBuilder
local UPDATE = class("UPDATE", sqlBuilder)

local json = require "lua_SQLBuilder.json"
local utils = require "lua_SQLBuilder.utils"
local render_value = utils.render_value
local fmt = string.format
local tconcat = table.concat

function UPDATE:ctor(tableName, opts)
    self.tableName = tableName
    self.setData = {}
    self.setDataTable = {}
    self.page = nil
    self.per = nil
    self.init(self, nil, opts)
end

local function sort_keys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

function UPDATE:TableOperator()
    local quote = self._dialect.quote_ident
    local sets = {}
    for _, v in ipairs(self.setData) do
        local field, val = v[1], v[2]
        if val then
            if type(val) == "userdata" then
                val = "NULL"
            end
            sets[#sets + 1] = string.gsub(field, "?", tostring(val), 1)
        else
            sets[#sets + 1] = field
        end
    end
    for _, key in ipairs(sort_keys(self.setDataTable)) do
        sets[#sets + 1] = fmt("%s = %s", quote(key), render_value(self.setDataTable[key]))
    end
    return fmt("UPDATE %s SET %s", self.tableName, tconcat(sets, ", "))
end

function UPDATE:PrepareTableOperator()
    local quote = self._dialect.quote_ident
    local fields, params = {}, {}
    -- table mode: deterministic key order so prepare params are stable
    for _, key in ipairs(sort_keys(self.setDataTable)) do
        local val = self.setDataTable[key]
        if type(val) == "table" then
            val = json.encode(val)
        end
        fields[#fields + 1] = fmt("%s = ?", quote(key))
        params[#params + 1] = val
    end
    -- string mode: keep current behavior (placeholder handling fixed in phase 1)
    for _, v in ipairs(self.setData) do
        local field, val = v[1], v[2]
        if val ~= nil then
            fields[#fields + 1] = fmt("%s = ?", field)
            params[#params + 1] = val
        else
            fields[#fields + 1] = fmt("%s?", field)
            params[#params + 1] = ""
        end
    end
    return fmt("UPDATE %s SET %s", self.tableName, tconcat(fields, ", ")), params
end

function UPDATE:SET(setData, param)
    if type(setData) == "table" then
        self.setDataTable = setData
    else
        assert(type(setData) == "string", "setData must table or string:" .. type(setData))
        self.setData[#self.setData + 1] = { setData, param }
    end
    return self
end

return UPDATE
