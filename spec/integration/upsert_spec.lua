-- Bootstrap: ensure the project root is on package.path (works with busted on every Lua version, incl. 5.1 where busted rewrites the path)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Integration: upsert behavior on real databases.
-- MySQL renders ON DUPLICATE KEY UPDATE; PG/SQLite render ON CONFLICT.

local db = require "spec.helpers.db"
local fixtures = require "spec.helpers.fixtures"
local SQLBuilder = require "lua_SQLBuilder"

local conn, reason = db.connect()
if not conn then
  describe("integration upsert (skipped)", function()
    it("requires a driver", function()
      pending("driver unavailable: " .. tostring(reason))
    end)
  end)
  return
end

local function I(...) return SQLBuilder.INSERT(..., db.opts()) end

describe("integration upsert (" .. conn.dialect .. ")", function()
  before_each(function()
    fixtures.prepare(conn)
  end)

  it("updates the conflicting row instead of failing", function()
    -- seeded: likes has (user_id=1, like_count=7); re-insert the same key
    local builder = I("likes"):DATA({ user_id = 1, like_count = 1 })
    if conn.dialect == "mysql" then
      builder:ON_DUPLICATE_KEY_UPDATE({ like_count = 1 })
    else
      builder:ON_DUPLICATE_KEY_UPDATE({ like_count = 1 }, "user_id")
    end
    assert(conn:exec(builder:to_sql()))

    local rows = conn:query("SELECT like_count FROM likes WHERE user_id = 1")
    assert.equal(1, #rows)
    assert.equal(1, rows[1].like_count)
  end)

  it("inserts a fresh row when there is no conflict", function()
    local builder = I("likes"):DATA({ user_id = 99, like_count = 5 })
    if conn.dialect == "mysql" then
      builder:ON_DUPLICATE_KEY_UPDATE({ like_count = 5 })
    else
      builder:ON_DUPLICATE_KEY_UPDATE({ like_count = 5 }, "user_id")
    end
    assert(conn:exec(builder:to_sql()))

    local rows = conn:query("SELECT like_count FROM likes WHERE user_id = 99")
    assert.equal(1, #rows)
    assert.equal(5, rows[1].like_count)
  end)
end)
