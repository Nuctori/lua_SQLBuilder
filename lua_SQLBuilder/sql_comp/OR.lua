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
    -- OR 子对象只允许携带 WHERE/OR 条件；其它子句（ORDER/LIMIT/GROUP 等）
    -- 在 OR 上下文中无意义且会被静默丢弃 —— 显式报错（NB-8）
    for _, comp in ipairs({ "_order", "_limit", "_group", "_having" }) do
        local part = sqlBuilder[comp]
        if part and next(part.orders or part.limit or part.groups or part.conditions or {}) then
            error("OR sub-builder cannot carry " .. comp:sub(2):upper() .. " clauses (only WHERE/OR are supported)", 3)
        end
    end
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
