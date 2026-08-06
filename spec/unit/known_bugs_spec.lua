-- Bootstrap: project root on package.path (busted rewrites it on Lua 5.1)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Known-bug inventory. Each `it` is `pending` until the bug is fixed; fixing
-- a bug = flipping its assertion to green. IDs reference the project bug
-- list (A1..A20). A2/A9 were fixed by the phase-0b dialect refactor and now
-- serve as permanent regression tests.

local SQLBuilder = require "lua_SQLBuilder".SQLBuilder
local SELECT = require "lua_SQLBuilder".SELECT
local UPDATE = require "lua_SQLBuilder".UPDATE
local INSERT = require "lua_SQLBuilder".INSERT

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
  it("A1: UPDATE string-mode prepare emits a duplicate placeholder", function()
    pending("A1 - fixed in phase 1")
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

  it("A3: JSON boolean values produce garbage SQL (plain-string entries)", function()
    pending("A3 - fixed in phase 1")
    local sql = SELECT("*"):FROM("user"):QUERY({ json = { flag = true } }):to_sql()
    assert.equal("SELECT * FROM user WHERE (`json`->>'$.flag' IS NOT NULL)", sql)
  end)

  it("A4: boolean QUERY values are rendered as quoted strings", function()
    pending("A4 - fixed in phase 1")
    local sql = SELECT("*"):FROM("user"):QUERY({ validate = true }):to_sql()
    assert.equal("SELECT * FROM user WHERE (`validate` = true)", sql)
  end)

  it("A5: falsy params leave a literal '?' in the SQL", function()
    pending("A5 - fixed in phase 1")
    local sql = SQLBuilder("SELECT * FROM user"):WHERE("x = ?", false):to_sql()
    assert.equal("SELECT * FROM user WHERE (x = false)", sql)
  end)

  it("A6: DESC without ORDER_BY crashes", function()
    pending("A6 - fixed in phase 1")
    local sql = SQLBuilder("SELECT * FROM user"):DESC():to_sql()
    assert.equal("SELECT * FROM user", sql)
  end)

  it("A20: UPDATE table-mode prepare works with quoted SET keys", function()
    pending("A20 - regression-locked (sort fixed in 0b)")
    local sql, score, id = UPDATE("user"):SET({ score = 100 }):WHERE("id = ?", 1):to_prepare()
    assert.equal("UPDATE user SET `score` = ? WHERE (id = ?)", sql)
    assert.equal(100, score)
    assert.equal(1, id)
  end)

  it("A10: DATA called twice corrupts columns", function()
    pending("A10 - fixed in phase 1")
    local sql = INSERT("user"):DATA({ a = 1 }):DATA({ b = 2 }):to_sql()
    assert.equal("INSERT INTO user (`b`) VALUES (2)", sql)
  end)

  it("A21: WHERE accepts a single param; multi-placeholder queries can't bind", function()
    pending("A21 - fixed in phase 1")
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
    pending("NB-1 - fixed in phase 1 (unified value renderer)")
    local sql = SQLBuilder("SELECT * FROM user"):WHERE("name LIKE ?", "50%"):to_sql()
    assert.equal("SELECT * FROM user WHERE (name LIKE '50%')", sql)
  end)

  it("NB-2: nil params leave holes in to_prepare (params shift)", function()
    pending("NB-2 - fixed in phase 1")
    local sql, p = SQLBuilder("SELECT * FROM user"):WHERE("a = ?", nil):WHERE("b = ?", 2):to_prepare()
    assert.equal("SELECT * FROM user WHERE (a = ? AND b = ?)", sql)
    assert.equal(2, p)
  end)

  it("NB-3: DELETE:QUERY with false renders a literal '?'", function()
    pending("NB-3 - fixed in phase 1")
    local sql = SQLBuilder.DELETE("user"):QUERY({ flag = false }):to_sql()
    assert.equal("DELETE FROM user WHERE (`flag` = false)", sql)
  end)

  it("NB-4: DELETE:QUERY userdata renders '= NULL' (SELECT uses 'is NULL')", function()
    pending("NB-4 - fixed in phase 1")
    local null = io.stderr -- real userdata on every Lua version
    local sql = SQLBuilder.DELETE("user"):QUERY({ deleted = null }):to_sql()
    assert.equal("DELETE FROM user WHERE (`deleted` is NULL)", sql)
  end)

  it("NB-5: HAVING params are inlined even in to_prepare mode", function()
    pending("NB-5 - fixed in phase 1")
    local sql, p = SQLBuilder("SELECT status, COUNT(*) FROM user")
      :GROUP_BY("status")
      :HAVING("COUNT(*) > ?", 5)
      :to_prepare()
    assert.equal("SELECT status, COUNT(*) FROM user GROUP BY status HAVING COUNT(*) > ?", sql)
    assert.equal(5, p)
  end)

  it("NB-6: JSON sub-conditions iterate pairs() (non-deterministic order)", function()
    pending("NB-6 - fixed in phase 1 (sort keys)")
    local a = SQLBuilder.SELECT("*"):FROM("u"):QUERY({ j = { x = 1, y = 2, z = 3 } }):to_sql()
    local b = SQLBuilder.SELECT("*"):FROM("u"):QUERY({ j = { x = 1, y = 2, z = 3 } }):to_sql()
    assert.equal(a, b)
  end)

  it("NB-8: OR sub-builders silently drop ORDER/LIMIT/GROUP clauses", function()
    pending("NB-8 - fixed in phase 1 (error or honor)")
    local sql = SQLBuilder("SELECT * FROM user")
      :OR(SQLBuilder():WHERE("x = ?", 1):LIMIT(5))
      :to_sql()
    assert.equal("SELECT * FROM user OR (x = 1) LIMIT 5", sql)
  end)

  it("NB-9: UPDATE string-mode SET values are not quoted", function()
    pending("NB-9 - fixed in phase 1")
    local sql = SQLBuilder.UPDATE("user"):SET("name = ?", "Bob"):WHERE("id = ?", 1):to_sql()
    assert.equal("UPDATE user SET name = 'Bob' WHERE (id = 1)", sql)
  end)

  it("NB-10: UPDATE string-mode SET with false renders a literal '?'", function()
    pending("NB-10 - fixed in phase 1")
    local sql = SQLBuilder.UPDATE("user"):SET("flag = ?", false):WHERE("id = ?", 1):to_sql()
    assert.equal("UPDATE user SET flag = false WHERE (id = 1)", sql)
  end)

  it("NB-13: WHERE table param with a boolean crashes table.concat", function()
    pending("NB-13 - fixed in phase 1")
    local sql = SQLBuilder("SELECT * FROM user"):WHERE("x in ?", { 1, false }):to_sql()
    assert.equal("SELECT * FROM user WHERE (x in (1, false))", sql)
  end)

  it("NB-14: INSERT DATA after COLS misaligns columns", function()
    pending("NB-14 - fixed in phase 1")
    local sql = SQLBuilder.INSERT("user"):COLS("id"):DATA({ a = 1 }):to_sql()
    assert.equal("INSERT INTO user (`a`) VALUES (1)", sql)
  end)

  it("NB-15: SELECT with no fields renders invalid 'SELECT  FROM'", function()
    pending("NB-15 - fixed in phase 1")
    local sql = SQLBuilder.SELECT():FROM("user"):to_sql()
    assert.equal("SELECT * FROM user", sql)
  end)

  it("ORDER_BY with two args appends 'DESC' as a column", function()
    pending("fixed in phase 1")
    local sql = SQLBuilder("SELECT * FROM user"):ORDER_BY("id", "DESC"):to_sql()
    assert.equal("SELECT * FROM user ORDER BY id DESC", sql)
  end)

  it("PAGE(0) produces a negative OFFSET", function()
    pending("fixed in phase 1")
    local sql = SQLBuilder.SELECT("*"):FROM("user"):PAGE(0):to_sql()
    assert.equal("SELECT * FROM user LIMIT 10", sql)
  end)
end)
