-- Bootstrap: project root on package.path (busted rewrites it on Lua 5.1)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Injection regression: values containing quotes, backslashes and control
-- characters must round-trip through to_sql (inline) on the real database.
-- to_prepare is covered by the driver; this locks the inline escaping.

local db = require "spec.helpers.db"
local fixtures = require "spec.helpers.fixtures"
local SQLBuilder = require "lua_SQLBuilder"

local conn, reason = db.connect()
if not conn then
  describe("integration injection (skipped)", function()
    it("requires a driver", function()
      pending("driver unavailable: " .. tostring(reason))
    end)
  end)
  return
end

local function I(...) return SQLBuilder.INSERT(..., db.opts()) end
local function S(...) return SQLBuilder.SELECT(..., db.opts()) end

describe("integration injection (" .. conn.dialect .. ")", function()
  before_each(function()
    fixtures.prepare(conn)
  end)

  it("round-trips quotes/backslashes/control chars via to_sql INSERT", function()
    local evil = "O'Brien \\ \\0 \n\t'\""
    local sql = I("users"):COLS("id", "name", "status"):VALUES({ 50, evil, 1 }):to_sql()
    assert(conn:exec(sql), "exec: " .. sql)
    local rows, qerr = conn:query("SELECT name FROM users WHERE id = 50")
    assert(rows, "query failed: " .. tostring(qerr))
    assert.equal(1, #rows)
    assert.equal(evil, rows[1].name)
  end)

  it("round-trips via WHERE equality", function()
    local evil = "it's \"quoted\""
    assert(conn:exec(I("users"):COLS("id", "name", "status"):VALUES({ 51, evil, 1 }):to_sql()))
    local rows = conn:query(S("*"):FROM("users"):WHERE("name = ?", evil):to_sql())
    assert.equal(1, #rows)
    assert.equal(51, rows[1].id)
  end)

  it("escapes comment-based injection payloads as plain data", function()
    local evil = "x'; DROP TABLE users; --"
    assert(conn:exec(I("users"):COLS("id", "name", "status"):VALUES({ 52, evil, 1 }):to_sql()))
    -- the table still exists and the payload landed as a value
    local rows = conn:query("SELECT COUNT(*) AS n FROM users")
    assert.equal(5, rows[1].n)
    local stored = conn:query("SELECT name FROM users WHERE id = 52")
    assert.equal(1, #stored)
    assert.equal(evil, stored[1].name)
  end)
end)
