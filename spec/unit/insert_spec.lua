-- Golden SQL tests for INSERT (mysql dialect by default).

local INSERT = require "lua_SQLBuilder".INSERT

describe("INSERT", function()
  it("COLS + VALUES", function()
    local sql = INSERT("user"):COLS("id", "name"):VALUES({ 1, "name1" }, { 2, "name2" }):to_sql()
    assert.equal("INSERT INTO user (`id`, `name`) VALUES (1, 'name1'), (2, 'name2')", sql)
  end)

  it("prepares COLS + VALUES with per-row params", function()
    local sql, data1, data2 = INSERT("user"):COLS("id", "name"):VALUES({ 1, "name1" }, { 2, "name2" }):to_prepare()
    assert.equal("INSERT INTO user (`id`, `name`) VALUES (?, ?), (?, ?)", sql)
    assert.equal(1, data1[1])
    assert.equal("name1", data1[2])
    assert.equal(2, data2[1])
    assert.equal("name2", data2[2])
  end)

  it("DATA sorts keys for deterministic output", function()
    local sql = INSERT("user"):DATA({ b = 2, a = 1, c = 3 }):to_sql()
    assert.equal("INSERT INTO user (`a`, `b`, `c`) VALUES (1, 2, 3)", sql)
  end)

  it("DATA renders JSON values", function()
    local sql = INSERT("user"):DATA({ id = 1, profile = { star = 5 } }):to_sql()
    assert.equal('INSERT INTO user (`id`, `profile`) VALUES (1, \'{"star":5}\')', sql)
  end)

  it("ON_DUPLICATE_KEY_UPDATE (mysql)", function()
    local sql = INSERT("likes"):DATA({ user_id = 1, like_count = 1 })
      :ON_DUPLICATE_KEY_UPDATE({ like_count = 1 })
      :to_sql()
    assert.equal(
      "INSERT INTO likes (`like_count`, `user_id`) VALUES (1, 1) ON DUPLICATE KEY UPDATE `like_count` = 1",
      sql)
  end)

  it("ON_DUPLICATE_KEY_UPDATE sorts update keys", function()
    local sql = INSERT("likes"):DATA({ user_id = 1, like_count = 1 })
      :ON_DUPLICATE_KEY_UPDATE({ z = 2, a = 1 })
      :to_sql()
    assert.equal(
      "INSERT INTO likes (`like_count`, `user_id`) VALUES (1, 1) ON DUPLICATE KEY UPDATE `a` = 1, `z` = 2",
      sql)
  end)

  it("renders upsert per dialect (postgres)", function()
    local sql = INSERT("likes", { dialect = "postgres" }):DATA({ user_id = 1, like_count = 1 })
      :ON_DUPLICATE_KEY_UPDATE({ like_count = 1 }, "user_id")
      :to_sql()
    assert.equal(
      'INSERT INTO likes ("like_count", "user_id") VALUES (1, 1) ON CONFLICT ("user_id") DO UPDATE SET "like_count" = EXCLUDED."like_count"',
      sql)
  end)

  it("requires conflict target on non-mysql dialects", function()
    assert.has_error(function()
      INSERT("likes", { dialect = "postgres" }):DATA({ user_id = 1, like_count = 1 })
        :ON_DUPLICATE_KEY_UPDATE({ like_count = 1 })
        :to_sql()
    end, "conflict")
  end)

  it("quotes COLS per dialect (postgres)", function()
    local sql = INSERT("user", { dialect = "postgres" }):COLS("id", "name"):VALUES({ 1, "x" }):to_sql()
    assert.equal('INSERT INTO user ("id", "name") VALUES (1, \'x\')', sql)
  end)
end)
