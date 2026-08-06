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
      dialect_mod.resolve("oracle")
    end, "unknown dialect: oracle (built-ins: ansi, mysql, mariadb, postgres, sqlite, mssql)")
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
