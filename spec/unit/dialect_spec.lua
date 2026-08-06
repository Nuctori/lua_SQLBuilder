-- Bootstrap: project root on package.path (busted rewrites it on Lua 5.1)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Direct tests for the dialect module + module-level defaults
-- (audit gap: set_default_dialect / resolve had zero coverage).

local sqlbuilder = require "lua_SQLBuilder"
local dialect_mod = require "lua_SQLBuilder.dialect"

describe("dialect", function()
  it("defaults to ansi (standard SQL, no dialect-specific features)", function()
    assert.equal("ansi", sqlbuilder.get_default_dialect())
    assert.equal("ansi", dialect_mod.resolve(nil).name)
    -- ansi: double-quoted identifiers, no backticks
    local sql = sqlbuilder.SELECT("*"):FROM("user"):QUERY({ id = 1 }):to_sql()
    assert.equal('SELECT * FROM user WHERE ("id" = 1)', sql)
  end)

  it("set_default_dialect affects later builders", function()
    local before = sqlbuilder.get_default_dialect()
    sqlbuilder.set_default_dialect("postgres")
    local sql = sqlbuilder.SELECT("*"):FROM("user"):QUERY({ id = 1 }):to_sql()
    assert.equal('SELECT * FROM user WHERE ("id" = 1)', sql)
    sqlbuilder.set_default_dialect(before)
  end)

  it("resolve rejects unknown dialects", function()
    assert.has_error(function()
      dialect_mod.resolve("oracle9")
    end, "unknown dialect: oracle9 (built-ins: ansi, mysql, mariadb, postgres, "
      .. "sqlite, mssql, oracle, duckdb, clickhouse)")
  end)

  it("per-instance opts override the module default", function()
    local before = sqlbuilder.get_default_dialect()
    sqlbuilder.set_default_dialect("sqlite")
    local sql = sqlbuilder.SELECT("*", { dialect = "mysql" }):FROM("user"):QUERY({ id = 1 }):to_sql()
    assert.equal("SELECT * FROM user WHERE (`id` = 1)", sql)
    sqlbuilder.set_default_dialect(before)
  end)

  it("Dialect() accessor reports the effective dialect", function()
    local b = sqlbuilder.SELECT("*", { dialect = "postgres" })
    assert.equal("postgres", b:Dialect())
  end)
end)

describe("dialect: oracle / duckdb / clickhouse presets", function()
  it("oracle: double quotes (UPPERCASE), OFFSET/FETCH limit, JSON_VALUE", function()
    local sql = sqlbuilder.SELECT("*", { dialect = "oracle" })
      :FROM("user"):QUERY({ id = 1 }):LIMIT(10, 20):to_sql()
    assert.equal('SELECT * FROM user WHERE ("ID" = 1) OFFSET 10 ROWS FETCH NEXT 20 ROWS ONLY', sql)
    local jsql = sqlbuilder.SELECT("*", { dialect = "oracle" })
      :FROM("user"):QUERY({ json = { star = 5 } }):to_sql()
    assert.equal("SELECT * FROM user WHERE (JSON_VALUE(\"JSON\", '$.star') = '5')", jsql)
  end)

  it("duckdb: double quotes, ANSI limit, ON CONFLICT, json_extract_string", function()
    local sql = sqlbuilder.SELECT("*", { dialect = "duckdb" })
      :FROM("user"):QUERY({ id = 1 }):LIMIT(10, 20):to_sql()
    assert.equal('SELECT * FROM user WHERE ("id" = 1) LIMIT 20 OFFSET 10', sql)
    local jsql = sqlbuilder.SELECT("*", { dialect = "duckdb" })
      :FROM("user"):QUERY({ json = { star = 5 } }):to_sql()
    assert.equal("SELECT * FROM user WHERE (json_extract_string(\"json\", '$.star') = '5')", jsql)
    local usql = sqlbuilder.INSERT("likes", { dialect = "duckdb" })
      :DATA({ user_id = 1, like_count = 1 })
      :ON_DUPLICATE_KEY_UPDATE({ like_count = 1 }, "user_id"):to_sql()
    assert.equal('INSERT INTO likes ("like_count", "user_id") VALUES (1, 1) '
      .. 'ON CONFLICT ("user_id") DO UPDATE SET "like_count" = excluded."like_count"', usql)
  end)

  it("clickhouse: backticks, backslash escape, JSONExtractString, ANSI limit", function()
    local sql = sqlbuilder.SELECT("*", { dialect = "clickhouse" })
      :FROM("user"):QUERY({ id = 1 }):LIMIT(10, 20):to_sql()
    assert.equal("SELECT * FROM user WHERE (`id` = 1) LIMIT 20 OFFSET 10", sql)
    local jsql = sqlbuilder.SELECT("*", { dialect = "clickhouse" })
      :FROM("user"):QUERY({ json = { star = 5, tags = { "x" } } }):to_sql()
    assert.equal(
      "SELECT * FROM user WHERE (JSONExtractString(`json`, 'star') = '5' "
        .. "AND JSONExtractString(`json`, 'tags', 0) = 'x')",
      jsql)
    -- backslash escaping like MySQL; 0x1A renders \x1A (not \Z)
    local wsql = sqlbuilder.SQLBuilder("SELECT 1", { dialect = "clickhouse" })
      :WHERE("name = ?", "O'Brien"):to_sql()
    assert.equal("SELECT 1 WHERE (name = 'O\\'Brien')", wsql)
    local zsql = sqlbuilder.SQLBuilder("SELECT 1", { dialect = "clickhouse" })
      :WHERE("b = ?", "\26"):to_sql()
    assert.equal("SELECT 1 WHERE (b = '\\x1A')", zsql)
  end)

  it("JSON array paths render without a stray dot (P1)", function()
    -- Lua array key 1 → JSON index 0: $.tags[0] (mysql/sqlite), ->0 (pg),
    -- 'tags', 0 (clickhouse key-list)
    local m = sqlbuilder.SELECT("*", { dialect = "mysql" })
      :FROM("user"):QUERY({ tags = { "x" } }):to_sql()
    assert.equal("SELECT * FROM user WHERE (`tags`->>'$.[0]' = 'x')", m)
    local p = sqlbuilder.SELECT("*", { dialect = "postgres" })
      :FROM("user"):QUERY({ tags = { "x" } }):to_sql()
    assert.equal('SELECT * FROM user WHERE ("tags"->>0 = \'x\')', p)
    local s = sqlbuilder.SELECT("*", { dialect = "sqlite" })
      :FROM("user"):QUERY({ tags = { "x" } }):to_sql()
    assert.equal("SELECT * FROM user WHERE (CAST(json_extract(\"tags\", '$.[0]') AS TEXT) = 'x')", s)
  end)

  it("clickhouse boolean JSON uses != '' (missing key returns empty string, P2)", function()
    local t = sqlbuilder.SELECT("*", { dialect = "clickhouse" })
      :FROM("user"):QUERY({ json = { flag = true } }):to_sql()
    assert.equal("SELECT * FROM user WHERE (JSONExtractString(`json`, 'flag') != '')", t)
    local f = sqlbuilder.SELECT("*", { dialect = "clickhouse" })
      :FROM("user"):QUERY({ json = { flag = false } }):to_sql()
    assert.equal("SELECT * FROM user WHERE (JSONExtractString(`json`, 'flag') = '')", f)
    -- other dialects keep IS (NOT) NULL
    local m = sqlbuilder.SELECT("*", { dialect = "mysql" })
      :FROM("user"):QUERY({ json = { flag = true } }):to_sql()
    assert.equal("SELECT * FROM user WHERE (`json`->>'$.flag' IS NOT NULL)", m)
  end)
end)
