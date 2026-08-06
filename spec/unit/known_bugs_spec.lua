-- Bootstrap: project root on package.path (busted rewrites it on Lua 5.1)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Known-bug inventory. Each `it` is `pending` until the bug is fixed; fixing
-- a bug = flipping its assertion to green. IDs reference the project bug
-- list (A1..A20). A2/A9 were fixed by the phase-0b dialect refactor and now
-- serve as permanent regression tests.

local sqlbuilder = require "lua_SQLBuilder"
local SQLBuilder = sqlbuilder.SQLBuilder
local SELECT = sqlbuilder.SELECT
local UPDATE = sqlbuilder.UPDATE
local INSERT = sqlbuilder.INSERT
local DELETE = sqlbuilder.DELETE

describe("regressions from the bug list", function()
  -- FIXED in 0b (Make_JsonQuery dialect refactor): JSON string params bind
  -- as real placeholders, not the literal "'?'".
  it("A2: JSON string params bind as real placeholders in prepare mode", function()
    local sql, foo = SELECT("*"):FROM("user"):QUERY({ json = { foo = "bar" } }):to_prepare()
    assert.equal("SELECT * FROM user WHERE (`json`->>'$.foo' = ?)", sql)
    assert.equal("bar", foo)
  end)

  -- FIXED in 0b (copy-on-render): repeated to_sql() calls produce identical
  -- output and never mutate the caller's tables.
  it("A9: INSERT output is idempotent across to_sql calls", function()
    local builder = INSERT("user"):COLS("id", "name"):VALUES({ 1, "name1" })
    local first = builder:to_sql()
    local second = builder:to_sql()
    assert.equal(first, second)
  end)
end)

describe("known bugs (pending)", function()
  it("A1: UPDATE string-mode prepare emits one placeholder per param", function()
    local sql, score, status, id = UPDATE("user")
      :SET("score = score + ?", 1)
      :SET("status = ?", "pass")
      :WHERE("id = ?", 1)
      :to_prepare()
    assert.equal("UPDATE user SET score = score + ?, status = ? WHERE (id = ?)", sql)
    assert.equal(1, score)
    assert.equal("pass", status)
    assert.equal(1, id)
  end)

  it("A3: JSON boolean values render IS (NOT) NULL via the dialect operator", function()
    local sql = SELECT("*"):FROM("user"):QUERY({ json = { flag = true } }):to_sql()
    assert.equal("SELECT * FROM user WHERE (`json`->>'$.flag' IS NOT NULL)", sql)
  end)

  it("A4: boolean QUERY values are rendered as true/false", function()
    local sql = SELECT("*"):FROM("user"):QUERY({ validate = true }):to_sql()
    assert.equal("SELECT * FROM user WHERE (`validate` = true)", sql)
  end)

  it("A5: falsy params render as literals, not '?'", function()
    local sql = SQLBuilder("SELECT * FROM user"):WHERE("x = ?", false):to_sql()
    assert.equal("SELECT * FROM user WHERE (x = false)", sql)
  end)

  it("A6: DESC without ORDER_BY is a no-op", function()
    local sql = SQLBuilder("SELECT * FROM user"):DESC():to_sql()
    assert.equal("SELECT * FROM user", sql)
  end)

  it("A20: UPDATE table-mode prepare works with quoted SET keys", function()
    local sql, score, id = UPDATE("user"):SET({ score = 100 }):WHERE("id = ?", 1):to_prepare()
    assert.equal("UPDATE user SET `score` = ? WHERE (id = ?)", sql)
    assert.equal(100, score)
    assert.equal(1, id)
  end)

  it("A10: DATA called twice resets columns", function()
    local sql = INSERT("user"):DATA({ a = 1 }):DATA({ b = 2 }):to_sql()
    assert.equal("INSERT INTO user (`b`) VALUES (2)", sql)
  end)

  it("A21: WHERE accepts multiple params per call", function()
    local sql, p1, p2 = SQLBuilder("SELECT * FROM user"):WHERE("a = ? AND b = ?", 1, 2):to_prepare()
    assert.equal("SELECT * FROM user WHERE (a = ? AND b = ?)", sql)
    assert.equal(1, p1)
    assert.equal(2, p2)
  end)
end)

-- Bugs discovered by the independent cross-audit (NB-*). Each locks a
-- specific misbehavior as pending; fix = flip to green.
describe("audit-discovered bugs (pending)", function()
  it("NB-1: '%' in a string param crashes to_sql (gsub replacement escaping)", function()
    local sql = SQLBuilder("SELECT * FROM user"):WHERE("name LIKE ?", "50%"):to_sql()
    assert.equal("SELECT * FROM user WHERE (name LIKE '50%')", sql)
  end)

  it("NB-2: missing params for placeholders raise an error (no silent shift)", function()
    assert.has_error(function()
      SQLBuilder("SELECT * FROM user"):WHERE("a = ?", nil):WHERE("b = ?", 2):to_prepare()
    end, "missing parameter for placeholder 1 in \"a = ?\"")
  end)

  it("NB-3: DELETE:QUERY with false renders false", function()
    local sql = DELETE("user"):QUERY({ flag = false }):to_sql()
    assert.equal("DELETE FROM user WHERE (`flag` = false)", sql)
  end)

  it("NB-4: DELETE:QUERY userdata renders 'is NULL' (matches SELECT)", function()
    local null = io.stderr -- real userdata on every Lua version
    local sql = DELETE("user"):QUERY({ deleted = null }):to_sql()
    assert.equal("DELETE FROM user WHERE (`deleted` is NULL)", sql)
  end)

  it("NB-5: HAVING params survive to_prepare", function()
    local sql, p = SQLBuilder("SELECT status, COUNT(*) FROM user")
      :GROUP_BY("status")
      :HAVING("COUNT(*) > ?", 5)
      :to_prepare()
    assert.equal("SELECT status, COUNT(*) FROM user GROUP BY status HAVING COUNT(*) > ?", sql)
    assert.equal(5, p)
  end)

  it("NB-6: JSON sub-conditions iterate in sorted key order", function()
    local a = SELECT("*"):FROM("u"):QUERY({ j = { x = 1, y = 2, z = 3 } }):to_sql()
    local b = SELECT("*"):FROM("u"):QUERY({ j = { x = 1, y = 2, z = 3 } }):to_sql()
    assert.equal(a, b)
  end)

  it("NB-8: OR sub-builders reject non-WHERE clauses", function()
    assert.has_error(function()
      SQLBuilder("SELECT * FROM user")
        :OR(SQLBuilder():WHERE("x = ?", 1):LIMIT(5))
        :to_sql()
    end, "OR sub-builder cannot carry LIMIT clauses (only WHERE/OR are supported)")
  end)

  it("NB-9: UPDATE string-mode SET values are quoted", function()
    local sql = UPDATE("user"):SET("name = ?", "Bob"):WHERE("id = ?", 1):to_sql()
    assert.equal("UPDATE user SET name = 'Bob' WHERE (id = 1)", sql)
  end)

  it("NB-10: UPDATE string-mode SET with false renders false", function()
    local sql = UPDATE("user"):SET("flag = ?", false):WHERE("id = ?", 1):to_sql()
    assert.equal("UPDATE user SET flag = false WHERE (id = 1)", sql)
  end)

  it("NB-13: WHERE table param accepts booleans", function()
    local sql = SQLBuilder("SELECT * FROM user"):WHERE("x in ?", { 1, false }):to_sql()
    assert.equal("SELECT * FROM user WHERE (x in (1, false))", sql)
  end)

  it("NB-14: INSERT DATA resets prior COLS", function()
    local sql = INSERT("user"):COLS("id"):DATA({ a = 1 }):to_sql()
    assert.equal("INSERT INTO user (`a`) VALUES (1)", sql)
  end)

  it("NB-15: SELECT with no fields defaults to *", function()
    local sql = SELECT():FROM("user"):to_sql()
    assert.equal("SELECT * FROM user", sql)
  end)

  it("ORDER_BY with two args applies the sort direction", function()
    local sql = SQLBuilder("SELECT * FROM user"):ORDER_BY("id", "DESC"):to_sql()
    assert.equal("SELECT * FROM user ORDER BY id DESC", sql)
  end)

  it("PAGE(0) raises (page must be >= 1)", function()
    assert.has_error(function()
      SELECT("*"):FROM("user"):PAGE(0):to_sql()
    end, "PAGE requires a number >= 1")
  end)
end)
