
local class = require "lua_SQLBuilder.class"
local WHERE = require "lua_SQLBuilder.sql_comp.WHERE"
local OR = require "lua_SQLBuilder.sql_comp.OR"
local ORDER = require "lua_SQLBuilder.sql_comp.ORDER"
local GROUP = require "lua_SQLBuilder.sql_comp.GROUP"
local HAVING = require "lua_SQLBuilder.sql_comp.HAVING"
local LIMIT = require "lua_SQLBuilder.sql_comp.LIMIT"

---@class sqlBuilder
local SQLBuilder = class("SQLBuilder")

local fmt = string.format

local function MakeSql(op, sql)
    if sql and sql ~= "" then
        return fmt(" %s %s", op, sql)
    else
        return ""
    end
end

function SQLBuilder:ctor(...)
    self:init(...)
end

function SQLBuilder:init(TableOperator)
    self._tableOperator = TableOperator
    self._where = WHERE.new()
    self._or = OR.new()
    self._order = ORDER.new()
    self._group = GROUP.new()
    self._having = HAVING.new()
    self._limit = LIMIT.new()
    self._forUpdate = false
    self._procedure = ""
end

function SQLBuilder:TableOperator()
    return self._tableOperator
end

function SQLBuilder:PrepareTableOperator()
    return self:TableOperator()
end

function SQLBuilder:WHERE(query, param)
    self._where:add(query, param)
    return self
end

function SQLBuilder:OR(sqlBuilder)
    self._or:add(sqlBuilder)
    return self
end

function SQLBuilder:ORDER_BY(fieldName, sortType)
    self._order:add(fieldName, sortType)
    return self
end

function SQLBuilder:DESC(isDesc)
    if type(isDesc) == "nil" then
        isDesc = true
    end
    self._order:desc(isDesc)
    return self
end

function SQLBuilder:ASC(isAsc)
    if type(isAsc) == "nil" then
        isAsc = true
    end
    self._order:desc(not isAsc)
    return self
end

function SQLBuilder:GROUP_BY(...)
    self._group:add(...)
    return self
end

function SQLBuilder:HAVING(query, param)
    self._having:add(query, param)
    return self
end

function SQLBuilder:LIMIT(offset, count)
    self._limit:add(offset, count)
    return self
end

function SQLBuilder:FOR_UPDATE()
    self._forUpdate = true
    return self
end

function SQLBuilder:PROCEDURE(procedure)
    assert(type(procedure) == "string")
    self._procedure = procedure
    return self
end

function SQLBuilder:to_sql()
    local sql = {
        self:TableOperator(),
        MakeSql("WHERE",self._where:to_sql()),
        MakeSql("OR",self._or:to_sql()),
        MakeSql("GROUP BY",self._group:to_sql()),
        MakeSql("HAVING",self._having:to_sql()),
        MakeSql("ORDER BY",self._order:to_sql()),
        MakeSql("LIMIT",self._limit:to_sql()),
        MakeSql("PROCEDURE", self._procedure),
        self._forUpdate and " FOR UPDATE" or "",
    }
    return table.concat(sql, "")
end

function SQLBuilder:to_prepare()
    local params = {}
    local headSql, params1 = self:PrepareTableOperator()
    local whereSql, params2 = self._where:to_prepare()
    for i, v in ipairs(params1 or {}) do
        params[#params + 1] = v
    end
    for i, v in ipairs(params2 or {}) do
        params[#params + 1] = v
    end
    local orSql, params3 = self._or:to_prepare()
    for i, v in ipairs(params3 or {}) do
        params[#params + 1] = v
    end
    local sql = {
        headSql,
        MakeSql("WHERE", whereSql),
        MakeSql("OR",orSql),
        MakeSql("GROUP BY",self._group:to_sql()),
        MakeSql("HAVING",self._having:to_sql()),
        MakeSql("ORDER BY",self._order:to_sql()),
        MakeSql("LIMIT",self._limit:to_sql()),
        MakeSql("PROCEDURE", self._procedure),
        self._forUpdate and " FOR UPDATE" or "",
    }
    return table.concat(sql, ""), table.unpack(params)
end

return SQLBuilder