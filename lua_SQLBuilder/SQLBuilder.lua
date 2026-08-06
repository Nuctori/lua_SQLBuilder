local class = require "lua_SQLBuilder.class"
local dialect_mod = require "lua_SQLBuilder.dialect"
local WHERE = require "lua_SQLBuilder.sql_comp.WHERE"
local OR = require "lua_SQLBuilder.sql_comp.OR"
local ORDER = require "lua_SQLBuilder.sql_comp.ORDER"
local GROUP = require "lua_SQLBuilder.sql_comp.GROUP"
local HAVING = require "lua_SQLBuilder.sql_comp.HAVING"
local LIMIT = require "lua_SQLBuilder.sql_comp.LIMIT"

---@class sqlBuilder
local SQLBuilder = class("SQLBuilder")

local fmt = string.format
local unpack = table.unpack or unpack -- luacheck: ignore 143

local function MakeSql(op, sql)
    if sql and sql ~= "" then
        return fmt(" %s %s", op, sql)
    else
        return ""
    end
end

-- LIMIT 片段可能以 OFFSET 开头（mssql/oracle 的 OFFSET/FETCH 语法）——
-- 此时不加 "LIMIT" 关键字。
local function MakeLimitSql(fragment)
    if fragment == nil or fragment == "" then
        return ""
    end
    if fragment:match("^OFFSET") then
        return " " .. fragment
    end
    return fmt(" LIMIT %s", fragment)
end

function SQLBuilder:ctor(...)
    local tableOperator = ...
    local opts = select(2, ...)
    self:init(tableOperator, opts)
end

function SQLBuilder:init(TableOperator, opts)
    self._tableOperator = TableOperator
    self._dialect = dialect_mod.snapshot(opts and opts.dialect)
    self._where = WHERE.new(self._dialect)
    self._or = OR.new(self._dialect)
    self._order = ORDER.new(self._dialect)
    self._group = GROUP.new(self._dialect)
    self._having = HAVING.new(self._dialect)
    self._limit = LIMIT.new(self._dialect)
    self._forUpdate = false
    self._procedure = ""
end

function SQLBuilder:Dialect()
    return self._dialect.name
end

function SQLBuilder:TableOperator()
    return self._tableOperator
end

function SQLBuilder:PrepareTableOperator()
    return self:TableOperator()
end

function SQLBuilder:WHERE(query, ...)
    self._where:add(query, ...)
    return self
end

function SQLBuilder:OR(sqlBuilder)
    self._or:add(sqlBuilder)
    return self
end

function SQLBuilder:ORDER_BY(fieldName, sortType)
    self._order:add(fieldName)
    if sortType then
        local st = tostring(sortType):upper()
        assert(st == "DESC" or st == "ASC", "sortType must be 'DESC' or 'ASC', got: " .. tostring(sortType))
        self._order:desc(st == "DESC")
    end
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
        MakeLimitSql(self._limit:to_sql()),
        MakeSql("PROCEDURE", self._procedure),
        self._forUpdate and " FOR UPDATE" or "",
    }
    return table.concat(sql, "")
end

function SQLBuilder:to_prepare()
    local params = {}
    local headSql, params1 = self:PrepareTableOperator()
    local whereSql, params2 = self._where:to_prepare()
    local havingSql, params4 = self._having:to_prepare()
    for _, v in ipairs(params1 or {}) do
        params[#params + 1] = v
    end
    for _, v in ipairs(params2 or {}) do
        params[#params + 1] = v
    end
    local orSql, params3 = self._or:to_prepare()
    for _, v in ipairs(params3 or {}) do
        params[#params + 1] = v
    end
    for _, v in ipairs(params4 or {}) do
        params[#params + 1] = v
    end
    local sql = {
        headSql,
        MakeSql("WHERE", whereSql),
        MakeSql("OR",orSql),
        MakeSql("GROUP BY",self._group:to_sql()),
        MakeSql("HAVING",havingSql),
        MakeSql("ORDER BY",self._order:to_sql()),
        MakeLimitSql(self._limit:to_sql()),
        MakeSql("PROCEDURE", self._procedure),
        self._forUpdate and " FOR UPDATE" or "",
    }
    return table.concat(sql, ""), unpack(params)
end

return SQLBuilder
