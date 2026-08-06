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

  it("A20: UPDATE table-mode prepare used to crash (tsort without comparator)", function()
    pending("A20 - fixed in phase 1")
    local sql, score, id = UPDATE("user"):SET({ score = 100 }):WHERE("id = ?", 1):to_prepare()
    assert.equal("UPDATE user SET score = ? WHERE (id = ?)", sql)
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
