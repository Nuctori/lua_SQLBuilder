-- Bootstrap: ensure the project root is on package.path (works with busted on every Lua version, incl. 5.1 where busted rewrites the path)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Golden SQL tests for the base SQLBuilder (mysql dialect by default).
-- These lock the library's exact output so regressions are caught at CI.

local SQLBuilder = require "lua_SQLBuilder".SQLBuilder
local sqlBuilder = SQLBuilder

describe("SQLBuilder", function()
  it("builds a SELECT with WHERE and ORDER", function()
    local sql = sqlBuilder("SELECT * FROM user")
      :WHERE("id > ?", 2)
      :ORDER_BY("user"):DESC()
      :ORDER_BY("id"):ASC()
      :to_sql()
    assert.equal("SELECT * FROM user WHERE (id > 2) ORDER BY user DESC, id ASC", sql)
  end)

  it("prepares placeholders and returns params", function()
    local sql, id = sqlBuilder("SELECT * FROM user")
      :WHERE("id > ?", 2)
      :ORDER_BY("user"):DESC()
      :ORDER_BY("id"):ASC()
      :to_prepare()
    assert.equal("SELECT * FROM user WHERE (id > ?) ORDER BY user DESC, id ASC", sql)
    assert.equal(2, id)
  end)

  it("supports multi-table queries with LIMIT", function()
    local sql = sqlBuilder("SELECT * FROM user AS u, book AS b")
      :WHERE("b.user_id = u.id")
      :LIMIT(1, 10)
      :to_sql()
    assert.equal("SELECT * FROM user AS u, book AS b WHERE (b.user_id = u.id) LIMIT 10 OFFSET 1", sql)
  end)

  it("single-argument LIMIT means the first N rows", function()
    local sql = sqlBuilder("SELECT * FROM user"):LIMIT(10):to_sql()
    assert.equal("SELECT * FROM user LIMIT 10", sql)
  end)

  it("zero offset renders without OFFSET", function()
    local sql = sqlBuilder("SELECT * FROM user"):LIMIT(0, 10):to_sql()
    assert.equal("SELECT * FROM user LIMIT 10", sql)
  end)

  it("nests OR groups", function()
    local sql = sqlBuilder("SELECT * FROM user")
      :WHERE("id > ?", 1):WHERE("name != ?", "admin")
      :OR(sqlBuilder():WHERE("name = ?", "user_1"):WHERE("name = ?", "user_2")
        :OR(sqlBuilder():WHERE("ct = ?", 0)))
      :to_sql()
    assert.equal(
      "SELECT * FROM user WHERE (id > 1 AND name != 'admin') OR (name = 'user_1' AND name = 'user_2') OR (ct = 0)",
      sql)
  end)

  it("prepares nested OR groups with ordered params", function()
    local sql, a, b, c, d, e = sqlBuilder("SELECT * FROM user")
      :WHERE("id > ?", 1):WHERE("name != ?", "admin")
      :OR(sqlBuilder():WHERE("name = ?", "user_1"):WHERE("name = ?", "user_2")
        :OR(sqlBuilder():WHERE("ct = ?", 0)))
      :to_prepare()
    assert.equal("SELECT * FROM user WHERE (id > ? AND name != ?) OR (name = ? AND name = ?) OR (ct = ?)", sql)
    assert.equal(1, a)
    assert.equal("admin", b)
    assert.equal("user_1", c)
    assert.equal("user_2", d)
    assert.equal(0, e)
  end)

  it("renders GROUP BY and HAVING", function()
    local sql = sqlBuilder("SELECT status, COUNT(*) FROM user")
      :GROUP_BY("status")
      :HAVING("COUNT(*) > ?", 5)
      :to_sql()
    assert.equal("SELECT status, COUNT(*) FROM user GROUP BY status HAVING COUNT(*) > 5", sql)
  end)

  it("renders FOR UPDATE", function()
    local sql = sqlBuilder("SELECT * FROM user"):FOR_UPDATE():to_sql()
    assert.equal("SELECT * FROM user FOR UPDATE", sql)
  end)

  it("renders PROCEDURE", function()
    local sql = sqlBuilder("SELECT * FROM user"):PROCEDURE("analyse()"):to_sql()
    assert.equal("SELECT * FROM user PROCEDURE analyse()", sql)
  end)

  it("defaults ORDER to ASC", function()
    local sql = sqlBuilder("SELECT * FROM user"):ORDER_BY("name"):to_sql()
    assert.equal("SELECT * FROM user ORDER BY name ASC", sql)
  end)

  it("passes a WHERE condition without params through untouched", function()
    local sql = sqlBuilder("SELECT * FROM user"):WHERE("b.user_id = u.id"):to_sql()
    assert.equal("SELECT * FROM user WHERE (b.user_id = u.id)", sql)
  end)
end)
