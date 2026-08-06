-- Bootstrap: ensure the project root is on package.path (works with busted on every Lua version, incl. 5.1 where busted rewrites the path)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Golden SQL tests for UPDATE (mysql dialect by default).

local UPDATE = require "lua_SQLBuilder".UPDATE

describe("UPDATE", function()
  it("SET table mode sorts keys for deterministic output", function()
    local sql = UPDATE("user"):SET({ score = 100, status = "pass" }):WHERE("id = ?", 1):to_sql()
    assert.equal("UPDATE user SET `score` = 100, `status` = 'pass' WHERE (id = 1)", sql)
  end)

  it("SET string mode replaces the placeholder", function()
    local sql = UPDATE("user"):SET("score = score + ?", 1):WHERE("id = ?", 1):to_sql()
    assert.equal("UPDATE user SET score = score + 1 WHERE (id = 1)", sql)
  end)

  it("prepares table-mode SET with sorted params", function()
    local sql, score, status, id = UPDATE("user"):SET({ score = 100, status = "pass" }):WHERE("id = ?", 1):to_prepare()
    assert.equal("UPDATE user SET `score` = ?, `status` = ? WHERE (id = ?)", sql)
    assert.equal(100, score)
    assert.equal("pass", status)
    assert.equal(1, id)
  end)

  it("quotes SET keys per dialect (postgres)", function()
    local sql = UPDATE("user", { dialect = "postgres" }):SET({ score = 100 }):WHERE("id = ?", 1):to_sql()
    assert.equal('UPDATE user SET "score" = 100 WHERE (id = 1)', sql)
  end)
end)
