-- Bootstrap: project root on package.path (busted rewrites it on Lua 5.1)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Production-usage regression: the exact call shapes found in
-- fireBookStore-backend (vendored copy at lualib/sqlBuilder) so the library
-- never drifts away from how it is actually consumed.

local SQLBuilder = require "lua_SQLBuilder"

describe("production patterns", function()
  it("at_users.lua: WHERE id in ? with a table param", function()
    local userIds = { 1, 2, 3 }
    local sql = SQLBuilder.SELECT("id", "username", "nick")
      :FROM("users")
      :WHERE("id in ?", userIds)
      :to_sql()
    assert.equal("SELECT id, username, nick FROM users WHERE (id in (1,2,3))", sql)
  end)

  it("grass_group.lua: SELECT with QUERY on chapter", function()
    local sql = SQLBuilder.SELECT("*")
      :FROM("chapter")
      :QUERY({ book_id = 1, status = 1 })
      :to_sql()
    assert.equal("SELECT * FROM chapter WHERE (`book_id` = 1 AND `status` = 1)", sql)
  end)

  it("grass.lua / grass2.lua: INSERT DATA", function()
    local sql = SQLBuilder.INSERT("like"):DATA({
      user_id = 1,
      like = 1,
    }):to_sql()
    assert.equal("INSERT INTO like (`like`, `user_id`) VALUES (1, 1)", sql)
  end)

  it("curd.lua: generic CRUD upsert via DATA + ON_DUPLICATE", function()
    local args = { user_id = 1, like = 1 }
    local sql = SQLBuilder.INSERT("like")
      :DATA(args)
      :ON_DUPLICATE_KEY_UPDATE(args)
      :to_sql()
    assert.equal(
      "INSERT INTO like (`like`, `user_id`) VALUES (1, 1) ON DUPLICATE KEY UPDATE `like` = 1, `user_id` = 1",
      sql)
  end)

  it("curd.lua: DELETE via QUERY", function()
    local sql = SQLBuilder.DELETE("user"):QUERY({ id = 1 }):to_sql()
    assert.equal("DELETE FROM user WHERE (`id` = 1)", sql)
  end)

  it("init.lua demo: raw query strings pass through (unsafe by design, phase 2 adds escaping)", function()
    local sql = SQLBuilder.SELECT("*"):FROM("AAA"):QUERY({ a = 1 }):WHERE("' or 1='1"):to_sql()
    assert.equal("SELECT * FROM AAA WHERE (`a` = 1 AND ' or 1='1)", sql)
  end)
end)
