local class = require "lua_SQLBuilder.class"
local sqlBuilder = require "lua_SQLBuilder.SQLBuilder"
---@class SELECT : sqlBuilder
local SELECT = class("SELECT", sqlBuilder)
local utils = require "lua_SQLBuilder.utils"

local fmt = string.format
-- SELECT():FIELD():FROM():QUERY():JSON_QUERY():PAGE():PER()
function SELECT:ctor(...)
    self.fileds = {table.unpack({...})}
    self.froms = {}
    self.page = nil
    self.per = nil
    self.init(self)
end

function SELECT:TableOperator()
    return fmt("SELECT %s FROM %s", table.concat(self.fileds, ", "), table.concat(self.froms, ", "))
end

function SELECT:FIELD(...)
    for _, field in ipairs({...}) do
        self.fileds[#self.fileds + 1] = field
    end
    return self
end

function SELECT:FROM(...)
    for _, from in ipairs({...}) do
        self.froms[#self.froms + 1] = from
    end
    return self
end

function SELECT:QUERY(queryTable)
    local sortTable = {}
    for k, v in pairs(queryTable) do
        sortTable[#sortTable + 1] = {k,v}
    end
    table.sort(sortTable, function(a, b)
        return tostring(type(a)) < tostring(type(b))
    end)
    for _, data in pairs(sortTable) do
        local field, query = data[1], data[2]
        if type(query) == "table" then -- json 查询
            local jsonSQLs = utils.Make_JsonQuery(field, query)
            for i, jsonSQL in ipairs(jsonSQLs) do
                local field, query = jsonSQL[1], jsonSQL[2]
                self:WHERE(field, query)
            end
        elseif type(query) == "userdata"  then
            self:WHERE(fmt("`%s` is NULL", field))
        else
            self:WHERE(fmt("`%s` = ?", field), query)
        end
    end
    return self
end

function SELECT:PAGE(page)
    self.page = tonumber(page)
    self.per = self.per or 10
    self:LIMIT(self.per * (self.page - 1), self.per)
    return self
end

function SELECT:PER(per)
    assert(self.page)
    self.per = tonumber(per)
    self:PAGE(self.page)
    return self
end

return SELECT