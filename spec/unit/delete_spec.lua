-- Bootstrap: project root on package.path (busted rewrites it on Lua 5.1)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Golden SQL tests for DELETE (mysql dialect by default).

local DELETE = require "lua_SQLBuilder".DELETE

describe("DELETE", function()
  it("QUERY builds a deterministic WHERE", function()
    local sql = DELETE("user", { dialect = "mysql" }):QUERY({ id = 1, status = 0 }):to_sql()
    assert.equal("DELETE FROM user WHERE (`id` = 1 AND `status` = 0)", sql)
  end)

  it("prepares WHERE with params", function()
    local sql, id = DELETE("user", { dialect = "mysql" }):WHERE("id = ?", 1):to_prepare()
    assert.equal("DELETE FROM user WHERE (id = ?)", sql)
    assert.equal(1, id)
  end)

  it("quotes identifiers per dialect (postgres)", function()
    local sql = DELETE("user", { dialect = "postgres" }):QUERY({ id = 1 }):to_sql()
    assert.equal('DELETE FROM user WHERE ("id" = 1)', sql)
  end)
end)
