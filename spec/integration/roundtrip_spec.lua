-- Bootstrap: project root on package.path (busted rewrites it on Lua 5.1)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Integration: generated SQL actually executes against the real database.
-- Dialect comes from env LUA_SQLBUILDER_DB (sqlite | mysql | postgres).
--
-- Includes the to_sql / to_prepare cross-check: the same logical query built
-- both ways must return identical rows (the "dual-path parity" audit).

local db = require "spec.helpers.db"
local fixtures = require "spec.helpers.fixtures"
local SQLBuilder = require "lua_SQLBuilder"

local unpack = table.unpack or unpack -- luacheck: ignore 143

local conn, reason = db.connect()
if not conn then
  describe("integration round-trip (skipped)", function()
    it("requires a driver", function()
      pending("driver unavailable: " .. tostring(reason))
    end)
  end)
  return
end

-- Build objects bound to the dialect under test.
local function B(...) return SQLBuilder.SQLBuilder(..., db.opts()) end
local function S(...) return SQLBuilder.SELECT(..., db.opts()) end
local function U(...) return SQLBuilder.UPDATE(..., db.opts()) end
local function I(...) return SQLBuilder.INSERT(..., db.opts()) end
local function D(...) return SQLBuilder.DELETE(..., db.opts()) end

local function deep_equal(x, y)
  if type(x) ~= type(y) then
    return false
  end
  if type(x) ~= "table" then
    return x == y
  end
  for k, v in pairs(x) do
    if not deep_equal(v, y[k]) then
      return false
    end
  end
  for k in pairs(y) do
    if x[k] == nil then
      return false
    end
  end
  return true
end

local function eq_rows(a, b)
  assert.equal(#a, #b, "row count")
  for i = 1, #a do
    for k, v in pairs(a[i]) do
      local bv = b[i][k]
      if type(v) == "table" and type(bv) == "table" then
        -- pgmoon auto-decodes jsonb columns into Lua tables; mysql/sqlite
        -- return the raw text - compare structurally in that case
        assert(deep_equal(v, bv), "col " .. k .. " of row " .. i)
      else
        assert.equal(v, bv, "col " .. k .. " of row " .. i)
      end
    end
  end
end

describe("integration round-trip (" .. conn.dialect .. ")", function()
  before_each(function()
    fixtures.prepare(conn)
  end)

  it("SELECT QUERY returns the expected rows", function()
    local rows = conn:query(S("*"):FROM("users"):QUERY({ status = 1 }):ORDER_BY("id"):to_sql())
    assert.equal(3, #rows)
    assert.equal("alice", rows[1].name)
    assert.equal("carol", rows[2].name)
    assert.equal("dave O'Brien", rows[3].name)
  end)

  it("to_sql and to_prepare return identical rows (parity)", function()
    if not conn.supports_params then
      pending("driver binding unsupported on " .. conn.dialect .. " (LuaSQL 2.x) - covered by sqlite/pg")
      return
    end
    local inline_sql = S("*"):FROM("users"):WHERE("status = ?", 1):ORDER_BY("id"):to_sql()
    local prep_sql, p = S("*"):FROM("users"):WHERE("status = ?", 1):ORDER_BY("id"):to_prepare()
    eq_rows(conn:query(inline_sql), conn:query(prep_sql, p))
  end)

  it("WHERE with table param (IN clause) round-trips", function()
    local rows = conn:query(S("*"):FROM("users"):WHERE("id in ?", { 1, 2 }):ORDER_BY("id"):to_sql())
    assert.equal(2, #rows)
    assert.equal(1, rows[1].id)
    assert.equal(2, rows[2].id)
  end)

  it("LIKE pattern round-trips", function()
    local rows = conn:query(S("id"):FROM("users"):WHERE("name like ?", "%a%"):ORDER_BY("id"):to_sql())
    assert.equal(3, #rows)
  end)

  it("pagination returns the right slice", function()
    local rows = conn:query(S("*"):FROM("users"):ORDER_BY("id"):PAGE(2):PER(2):to_sql())
    assert.equal(2, #rows)
    assert.equal(3, rows[1].id)
    assert.equal(4, rows[2].id)
  end)

  it("UPDATE round-trips", function()
    if conn.dialect == "clickhouse" then
      pending("clickhouse has no standard UPDATE (uses ALTER TABLE ... UPDATE mutations)")
      return
    end
    assert(conn:exec(U("users"):SET({ score = 999 }):WHERE("id = ?", 1):to_sql()))
    local rows = conn:query("SELECT score FROM users WHERE id = 1")
    assert.equal(999, rows[1].score)
  end)

  it("INSERT round-trips (prepare path with quotes in value)", function()
    if not conn.supports_params then
      pending("driver binding unsupported on " .. conn.dialect .. " (LuaSQL 2.x) - covered by sqlite/pg")
      return
    end
    local sql, row = I("users"):COLS("id", "name", "status"):VALUES({ 99, "O'Brien", 1 }):to_prepare()
    assert(conn:exec(sql, unpack(row)))
    local rows = conn:query("SELECT name FROM users WHERE id = 99")
    assert.equal("O'Brien", rows[1].name)
  end)

  it("DELETE round-trips", function()
    if conn.dialect == "clickhouse" then
      pending("clickhouse Memory engine has no DELETE (lightweight delete needs MergeTree + flag)")
      return
    end
    assert(conn:exec(I("users"):COLS("id", "name", "status"):VALUES({ 98, "temp", 0 }):to_sql()))
    assert(conn:exec(D("users"):QUERY({ id = 98 }):to_sql()))
    local rows = conn:query("SELECT id FROM users WHERE id = 98")
    assert.equal(0, #rows)
  end)

  it("OR query round-trips", function()
    local sql = B("SELECT * FROM users")
      :WHERE("status = ?", 1)
      :OR(SQLBuilder.SQLBuilder("", db.opts()):WHERE("id = ?", 2))
      :ORDER_BY("id")
      :to_sql()
    local rows = conn:query(sql)
    assert.equal(4, #rows)
  end)

  it("GROUP BY / HAVING round-trips", function()
    local sql = B("SELECT status, COUNT(*) AS num FROM users")
      :GROUP_BY("status")
      :HAVING("COUNT(*) > ?", 1)
      :to_sql()
    local rows = conn:query(sql)
    assert.equal(1, #rows)
    assert.equal(1, rows[1].status)
    assert.equal(3, rows[1].num)
  end)
end)
