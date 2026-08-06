-- Bootstrap: ensure the project root is on package.path (works with busted on every Lua version, incl. 5.1 where busted rewrites the path)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Integration: JSON field queries against real databases.
-- Dialect-specific operator rendering is verified by executing the SQL.

local db = require "spec.helpers.db"
local fixtures = require "spec.helpers.fixtures"
local SQLBuilder = require "lua_SQLBuilder"

local conn, reason = db.connect()
if not conn then
  describe("integration JSON (skipped)", function()
    it("requires a driver", function()
      pending("driver unavailable: " .. tostring(reason))
    end)
  end)
  return
end

local function S(...) return SQLBuilder.SELECT(..., db.opts()) end

describe("integration JSON (" .. conn.dialect .. ")", function()
  before_each(function()
    fixtures.prepare(conn)
  end)

  it("matches a JSON number equality", function()
    -- users with profile.star = 5: alice (id 1), dave O'Brien (id 4)
    local rows = conn:query(S("*"):FROM("users"):QUERY({ profile = { star = 5 } }):ORDER_BY("id"):to_sql())
    assert.equal(2, #rows)
    assert.equal(1, rows[1].id)
    assert.equal(4, rows[2].id)
  end)

  it("matches a JSON string equality", function()
    -- alice has profile.kind = "admin"
    local rows = conn:query(S("id"):FROM("users"):QUERY({ profile = { kind = "admin" } }):to_sql())
    assert.equal(1, #rows)
    assert.equal(1, rows[1].id)
  end)

  it("matches a nested JSON path", function()
    -- alice has profile.nested.k = 1
    local rows = conn:query(S("id"):FROM("users"):QUERY({ profile = { nested = { k = 1 } } }):to_sql())
    assert.equal(1, #rows)
    assert.equal(1, rows[1].id)
  end)

  it("does not match when the JSON key is missing", function()
    local rows = conn:query(S("id"):FROM("users"):QUERY({ profile = { nope = 1 } }):to_sql())
    assert.equal(0, #rows)
  end)

  it("to_prepare JSON parity", function()
    if not conn.supports_params then
      pending("driver binding unsupported on " .. conn.dialect .. " (LuaSQL 2.x) - covered by sqlite/pg")
      return
    end
    local inline = conn:query(S("id"):FROM("users"):QUERY({ profile = { star = 5 } }):ORDER_BY("id"):to_sql())
    local sql, p = S("id"):FROM("users"):QUERY({ profile = { star = 5 } }):ORDER_BY("id"):to_prepare()
    local prepared = conn:query(sql, p)
    assert.equal(#inline, #prepared)
    assert.equal(inline[1].id, prepared[1].id)
    assert.equal(inline[2].id, prepared[2].id)
  end)
end)
