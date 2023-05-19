
local class = require "lua_SQLBuilder.class"
local sqlBuilder = require "lua_SQLBuilder.SQLBuilder"

local DELETE = class("DELETE", sqlBuilder)
local utils = require "lua_SQLBuilder.utils"

local fmt = string.format
-- DELETE():FIELD():FROM():QUERY():JSON_QUERY():PAGE():PER()
function DELETE:ctor(tableName)
    self.tableName = tableName
    self.page = nil
    self.per = nil
    self.init(self)
end

function DELETE:TableOperator()
    return fmt("DELETE FROM %s", self.tableName)
end

function DELETE:QUERY(queryTable)
    -- do sth
    for field, query in pairs(queryTable) do
        if type(query) == "table" then -- json 查询
            local jsonSQLs = utils.Make_JsonQuery(field, query)
            for i, jsonSQL in ipairs(jsonSQLs) do
                local field, query = jsonSQL[1], jsonSQL[2]
                self:WHERE(field, query)
            end
        else
            self:WHERE(fmt("%s = ?", field), query)
        end
    end
    return self
end

return DELETE