local class = require "lua_SQLBuilder.class"
local OR = class("OR")

function OR:ctor(dialect)
    self.subSqlObjs = {}
    self._dialect = dialect
end

function OR:_add(sqlObj)
    self.subSqlObjs[#self.subSqlObjs + 1] = sqlObj
end

function OR:add(sqlBuilder)
    self:_add(sqlBuilder)
end

local function collect_from(obj, collector)
    local sqlStr = obj._where:to_sql()
    if sqlStr and sqlStr ~= "" then
        collector(sqlStr)
    end
    local orStr = obj._or:to_sql()
    if orStr and orStr ~= "" then
        collector(orStr)
    end
end

function OR:to_sql()
    local ors = {}
    for _, subSqlObj in ipairs(self.subSqlObjs) do
        collect_from(subSqlObj, function(s) ors[#ors + 1] = s end)
    end
    return table.concat(ors, " OR ")
end

local function collect_prepare_from(obj, ors, params)
    local sqlStr, whereParams = obj._where:to_prepare()
    if sqlStr and sqlStr ~= "" then
        ors[#ors + 1] = sqlStr
        for _, retParam in ipairs(whereParams or {}) do
            params[#params + 1] = retParam
        end
    end
    local orStr, orParams = obj._or:to_prepare()
    if orStr and orStr ~= "" then
        ors[#ors + 1] = orStr
        for _, retParam in ipairs(orParams or {}) do
            params[#params + 1] = retParam
        end
    end
end

function OR:to_prepare()
    local ors = {}
    local params = {}
    for _, subSqlObj in ipairs(self.subSqlObjs) do
        collect_prepare_from(subSqlObj, ors, params)
    end
    return table.concat(ors, " OR "), params
end

return OR
