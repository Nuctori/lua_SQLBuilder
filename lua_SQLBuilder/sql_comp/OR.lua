local class = require "lua_SQLBuilder.class"
local OR = class("OR")
local fmt = string.format

function OR:ctor()
    self.subSqlObjs = {}
end

function OR:_add(sqlObj)
    self.subSqlObjs[#self.subSqlObjs + 1] = sqlObj
end

function OR:add(sqlBuilder)
    self:_add(sqlBuilder)
end

function OR:to_sql()
    local ors = {}
    for i, subSqlObj in ipairs(self.subSqlObjs) do
        local sqlStr = subSqlObj._where:to_sql()
        if sqlStr and sqlStr ~= "" then
            ors[#ors + 1] = sqlStr
        end
        local sqlStr = subSqlObj._or:to_sql()
        if sqlStr and sqlStr ~= "" then
            ors[#ors + 1] = sqlStr
        end
    end
    return table.concat(ors, " OR ")
end

function OR:to_prepare()
    local ors = {}
    local params = {}
    for i, subSqlObj in ipairs(self.subSqlObjs) do
        local sqlStr, retParams = subSqlObj._where:to_prepare()
        if sqlStr and sqlStr ~= "" then
            ors[#ors + 1] = sqlStr
            for i, retParam in ipairs(retParams or {}) do
                params[#params + 1] = retParam
            end
        end
        local sqlStr, retParams = subSqlObj._or:to_prepare()
        if sqlStr and sqlStr ~= "" then
            ors[#ors + 1] = sqlStr
            for i, retParam in ipairs(retParams or {}) do
                params[#params + 1] = retParam
            end
        end
    end
    return table.concat(ors, " OR "), params
end

return OR