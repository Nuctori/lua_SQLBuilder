local class = require "lua_SQLBuilder.class"
local sqlBuilder = require "lua_SQLBuilder.SQLBuilder"

local DELETE = class("DELETE", sqlBuilder)
local utils = require "lua_SQLBuilder.utils"

local fmt = string.format
-- DELETE():FIELD():FROM():QUERY():JSON_QUERY():PAGE():PER()
function DELETE:ctor(tableName, opts)
    self.tableName = tableName
    self.page = nil
    self.per = nil
    self.init(self, nil, opts)
end

function DELETE:TableOperator()
    return fmt("DELETE FROM %s", self.tableName)
end

local function sort_keys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

function DELETE:QUERY(queryTable)
    local quote = self._dialect.quote_ident
    for _, field in ipairs(sort_keys(queryTable)) do
        local query = queryTable[field]
        if type(query) == "table" then -- json 查询
            local jsonSQLs = utils.Make_JsonQuery(field, query, self._dialect)
            for _, jsonSQL in ipairs(jsonSQLs) do
                local jfield, jquery = jsonSQL[1], jsonSQL[2]
                self:WHERE(jfield, jquery)
            end
        elseif type(query) == "userdata" then
            -- 与 SELECT:QUERY 一致：NULL 用 is NULL（= NULL 永不匹配）
            self:WHERE(fmt("%s is NULL", quote(field)))
        else
            self:WHERE(fmt("%s = ?", quote(field)), query)
        end
    end
    return self
end

return DELETE
