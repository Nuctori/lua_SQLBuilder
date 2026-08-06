-- Bootstrap: project root on package.path (busted rewrites it on Lua 5.1)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Direct tests for utils pure functions (audit gap: zero coverage before).

local utils = require "lua_SQLBuilder.utils"

describe("utils.quote_to_str", function()
  it("escapes quotes and backslashes", function()
    assert.equal("a\\'b\\\\c", utils.quote_to_str("a'b\\c"))
  end)

  it("escapes control characters", function()
    assert.equal("x\\0y\\nz", utils.quote_to_str("x\0y\nz"))
  end)
end)

describe("utils.clear_table", function()
  it("recursively escapes string values and keys without mutating input", function()
    local t = { name = "O'Brien", nested = { note = "a\\b" } }
    local out = utils.clear_table(t)
    assert.equal("O\\'Brien", out.name)
    assert.equal("a\\\\b", out.nested.note)
    assert.equal("O'Brien", t.name)
  end)
end)

describe("utils.render_value", function()
  it("quotes strings and JSON-encodes tables", function()
    assert.equal("'x'", utils.render_value("x"))
    assert.equal("1", utils.render_value(1))
    assert.equal("NULL", utils.render_value(nil))
    assert.equal("'{\"k\":1}'", utils.render_value({ k = 1 }))
  end)

  it("errors on unsupported types", function()
    assert.has_error(function()
      utils.render_value(print)
    end, "unsupported value type: function")
  end)
end)

describe("utils.Make_JsonQuery", function()
  it("returns {sql, param} pairs for scalars with string params", function()
    local out = utils.Make_JsonQuery("profile", { star = 5 })
    assert.equal(1, #out)
    assert.equal("`profile`->>'$.star' = ?", out[1][1])
    assert.equal("5", out[1][2])
  end)

  it("handles nested paths", function()
    local out = utils.Make_JsonQuery("profile", { nested = { k = "x" } })
    assert.equal("`profile`->>'$.nested.k' = ?", out[1][1])
    assert.equal("x", out[1][2])
  end)

  it("renders per dialect (postgres operator chain)", function()
    local dialect = require "lua_SQLBuilder.dialect".resolve("postgres")
    local out = utils.Make_JsonQuery("profile", { nested = { k = 1 } }, dialect)
    assert.equal('"profile"->\'nested\'->>\'k\' = ?', out[1][1])
  end)
end)
