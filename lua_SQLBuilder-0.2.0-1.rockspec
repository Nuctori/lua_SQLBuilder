package = "lua_SQLBuilder"
version = "0.2.0-1"

source = {
  url = "git://github.com/Nuctori/lua_SQLBuilder.git",
  tag = "v0.2.0",
}

description = {
  summary = "Flexible SQL builder for Lua with multi-dialect support (MySQL / PostgreSQL / SQLite)",
  detailed = [[
    A dependency-free SQL statement builder for Lua 5.1-5.4 and LuaJIT.

    - Chainable WHERE / OR / ORDER BY / GROUP BY / HAVING / LIMIT / FOR UPDATE
    - SELECT / UPDATE / INSERT / DELETE helpers with QUERY, SET, DATA, COLS,
      VALUES and upsert (ON DUPLICATE KEY UPDATE / ON CONFLICT) support
    - to_sql() inline rendering with dialect-aware string escaping, and
      to_prepare() with bound parameters for injection-safe execution
    - Dialect-aware identifier quoting, JSON path operators and LIMIT/OFFSET
    - Deterministic output: keys are sorted, repeated renders are identical
    - Verified against real MySQL 8, PostgreSQL 16 and SQLite on CI
      (Lua 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT)
  ]],
  homepage = "https://github.com/Nuctori/lua_SQLBuilder",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["lua_SQLBuilder"] = "lua_SQLBuilder/init.lua",
    ["lua_SQLBuilder.SQLBuilder"] = "lua_SQLBuilder/SQLBuilder.lua",
    ["lua_SQLBuilder.SELECT"] = "lua_SQLBuilder/SELECT.lua",
    ["lua_SQLBuilder.UPDATE"] = "lua_SQLBuilder/UPDATE.lua",
    ["lua_SQLBuilder.INSERT"] = "lua_SQLBuilder/INSERT.lua",
    ["lua_SQLBuilder.DELETE"] = "lua_SQLBuilder/DELETE.lua",
    ["lua_SQLBuilder.class"] = "lua_SQLBuilder/class.lua",
    ["lua_SQLBuilder.dialect"] = "lua_SQLBuilder/dialect.lua",
    ["lua_SQLBuilder.json"] = "lua_SQLBuilder/json.lua",
    ["lua_SQLBuilder.utils"] = "lua_SQLBuilder/utils.lua",
    ["lua_SQLBuilder.sql_comp.WHERE"] = "lua_SQLBuilder/sql_comp/WHERE.lua",
    ["lua_SQLBuilder.sql_comp.OR"] = "lua_SQLBuilder/sql_comp/OR.lua",
    ["lua_SQLBuilder.sql_comp.ORDER"] = "lua_SQLBuilder/sql_comp/ORDER.lua",
    ["lua_SQLBuilder.sql_comp.GROUP"] = "lua_SQLBuilder/sql_comp/GROUP.lua",
    ["lua_SQLBuilder.sql_comp.HAVING"] = "lua_SQLBuilder/sql_comp/HAVING.lua",
    ["lua_SQLBuilder.sql_comp.LIMIT"] = "lua_SQLBuilder/sql_comp/LIMIT.lua",
  },
}
