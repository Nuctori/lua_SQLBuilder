local class = require "lua_SQLBuilder.class"
local sqlBuilder = require "lua_SQLBuilder.SQLBuilder"
---@class SELECT : sqlBuilder
local SELECT = class("SELECT", sqlBuilder)
local utils = require "lua_SQLBuilder.utils"

local fmt = string.format
-- SELECT():FIELD():FROM():QUERY():JSON_QUERY():PAGE():PER()
function SELECT:ctor(...)
    local fields = { ... }
    local opts
    if type(fields[#fields]) == "table" then
        opts = fields[#fields]
        fields[#fields] = nil
    end
    self.fields = fields
    self.fileds = self.fields -- legacy alias (typo kept for compatibility)
    self.froms = {}
    self.page = nil
    self.per = nil
    self.init(self, nil, opts)
end

function SELECT:TableOperator()
    return fmt("SELECT %s FROM %s", table.concat(self.fields, ", "), table.concat(self.froms, ", "))
end

function SELECT:FIELD(...)
    for _, field in ipairs({...}) do
        self.fields[#self.fields + 1] = field
    end
    return self
end

function SELECT:FROM(...)
    for _, from in ipairs({...}) do
        self.froms[#self.froms + 1] = from
    end
    return self
end

local function sort_keys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

function SELECT:QUERY(queryTable)
    local dialect = self._dialect
    local quote = dialect.quote_ident
    for _, field in ipairs(sort_keys(queryTable)) do
        local query = queryTable[field]
        if type(query) == "table" then -- json 查询
            local jsonSQLs = utils.Make_JsonQuery(field, query, dialect)
            for i, jsonSQL in ipairs(jsonSQLs) do
                local jfield, jquery = jsonSQL[1], jsonSQL[2]
                self:WHERE(jfield, jquery)
            end
        elseif type(query) == "userdata" then
            self:WHERE(fmt("%s is NULL", quote(field)))
        elseif type(query) == "boolean" then
            self:WHERE(fmt("%s = ?", quote(field)), tostring(query))
        else
            self:WHERE(fmt("%s = ?", quote(field)), query)
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
