-- Bootstrap: project root on package.path (busted rewrites it on Lua 5.1)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Golden SQL tests for SELECT (mysql dialect by default).

local SELECT = require "lua_SQLBuilder".SELECT

describe("SELECT", function()
  it("builds a plain query", function()
    local sql = SELECT("*"):FROM("book"):to_sql()
    assert.equal("SELECT * FROM book", sql)
  end)

  it("sorts QUERY keys for deterministic output", function()
    local sql = SELECT("*", { dialect = "mysql" }):FROM("book"):QUERY({ user_id = 1, status = 1 }):to_sql()
    assert.equal("SELECT * FROM book WHERE (`status` = 1 AND `user_id` = 1)", sql)
  end)

  it("combines QUERY with PAGE/PER pagination", function()
    local sql = SELECT("*", { dialect = "mysql" }):FROM("book")
      :QUERY({ user_id = 1, status = 1 }):PAGE(10):PER(2):to_sql()
    -- page 10, per 2 → offset (10-1)*2 = 18
    assert.equal("SELECT * FROM book WHERE (`status` = 1 AND `user_id` = 1) LIMIT 2 OFFSET 18", sql)
  end)

  it("renders JSON queries with the dialect operator", function()
    local sql = SELECT("*", { dialect = "mysql" }):FROM("book")
      :QUERY({ user_id = 1, status = 1, json = { star = 5 } }):to_sql()
    assert.equal(
      "SELECT * FROM book WHERE (`json`->>'$.star' = '5' AND `status` = 1 AND `user_id` = 1)",
      sql)
  end)

  it("supports FIELD additions", function()
    local sql = SELECT("id"):FIELD("name"):FROM("user"):to_sql()
    assert.equal("SELECT id, name FROM user", sql)
  end)

  it("supports multiple FROM tables", function()
    local sql = SELECT("*"):FROM("user", "book"):to_sql()
    assert.equal("SELECT * FROM user, book", sql)
  end)

  it("quotes identifiers per dialect (postgres)", function()
    local sql = SELECT("*", { dialect = "postgres" }):FROM("user"):QUERY({ id = 1, status = 1 }):to_sql()
    assert.equal('SELECT * FROM user WHERE ("id" = 1 AND "status" = 1)', sql)
  end)

  it("renders nested JSON paths per dialect (postgres)", function()
    local sql = SELECT("*", { dialect = "postgres" }):FROM("user"):QUERY({ json = { nested = { k = 1 } } }):to_sql()
    assert.equal('SELECT * FROM user WHERE ("json"->\'nested\'->>\'k\' = \'1\')', sql)
  end)

  it("quotes identifiers per dialect (sqlite)", function()
    local sql = SELECT("*", { dialect = "sqlite" }):FROM("user"):QUERY({ id = 1 }):to_sql()
    assert.equal('SELECT * FROM user WHERE ("id" = 1)', sql)
  end)

  it("renders JSON paths per dialect (sqlite)", function()
    local sql = SELECT("*", { dialect = "sqlite" }):FROM("user"):QUERY({ json = { star = 5 } }):to_sql()
    assert.equal('SELECT * FROM user WHERE (CAST(json_extract("json", \'$.star\') AS TEXT) = \'5\')', sql)
  end)
end)
