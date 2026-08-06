-- Bootstrap: project root on package.path (busted rewrites it on Lua 5.1)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Adversarial audit regression: findings from the injection / edge / API
-- adversarial reviews, locked as tests so they can never regress.

local sqlbuilder = require "lua_SQLBuilder"

describe("adversarial: injection hardening", function()
  it("CRITICAL-1: table values (JSON) are escaped inside the literal", function()
    -- UPDATE SET table value containing a quote must be escaped (was injectable)
    local sql = sqlbuilder.UPDATE("user", { dialect = "mysql" })
      :SET({ bio = { text = "x' OR 1=1 -- " } })
      :WHERE("id = ?", 1):to_sql()
    assert.equal("UPDATE user SET `bio` = '{\"text\":\"x\\' OR 1=1 -- \"}' WHERE (id = 1)", sql)
    -- ANSI: single quotes doubled
    local ansi = sqlbuilder.UPDATE("user"):SET({ bio = { text = "x' OR 1=1" } }):to_sql()
    assert.equal('UPDATE user SET "bio" = \'{"text":"x\'\' OR 1=1"}\'', ansi)
    -- mysql upsert value path (prepare mode too)
    local up = sqlbuilder.INSERT("likes", { dialect = "mysql" })
      :DATA({ user_id = 1, like_count = 1 })
      :ON_DUPLICATE_KEY_UPDATE({ note = { text = "a'b" } }):to_sql()
    assert.equal("INSERT INTO likes (`like_count`, `user_id`) VALUES (1, 1) "
      .. "ON DUPLICATE KEY UPDATE `note` = '{\"text\":\"a\\'b\"}'", up)
  end)

  it("quote_ident escapes the dialect delimiter (QUERY columns)", function()
    local sql = sqlbuilder.SELECT("*", { dialect = "mysql" }):FROM("user"):QUERY({ ["a`b"] = 1 }):to_sql()
    assert.equal("SELECT * FROM user WHERE (`a``b` = 1)", sql)
    local pg = sqlbuilder.SELECT("*", { dialect = "postgres" }):FROM("user"):QUERY({ ['a"b'] = 1 }):to_sql()
    assert.equal('SELECT * FROM user WHERE ("a""b" = 1)', pg)
  end)

  it("M5: LIMIT rejects non-numeric injection payloads", function()
    assert.has_error(function()
      sqlbuilder.SQLBuilder("SELECT * FROM user"):LIMIT(0, "10 OFFSET 5; DROP TABLE users--"):to_sql()
    end, "LIMIT count must be a non-negative number, got: 10 OFFSET 5; DROP TABLE users--")
    assert.has_error(function()
      sqlbuilder.SQLBuilder("SELECT * FROM user"):LIMIT("abc", 10):to_sql()
    end, "LIMIT offset must be a non-negative number, got: abc")
  end)
end)

describe("adversarial: state / consistency", function()
  it("M1: dialect config edits do not mutate existing builders (snapshot)", function()
    local dialect = require "lua_SQLBuilder.dialect"
    local b = sqlbuilder.SQLBuilder("SELECT * FROM user", { dialect = "mysql" })
      :WHERE("name = ?", "O'Brien")
    local before = b:to_sql()
    local saved = dialect.dialects.mysql.escape_string
    dialect.dialects.mysql.escape_string = function(s) return s end -- disable escaping
    local after = b:to_sql()
    dialect.dialects.mysql.escape_string = saved
    assert.equal(before, after, "existing builder must keep its dialect snapshot")
  end)

  it("M2: OR sub-builder with a different dialect is rejected", function()
    assert.has_error(function()
      sqlbuilder.SQLBuilder("SELECT * FROM user", { dialect = "postgres" })
        :OR(sqlbuilder.SQLBuilder("", { dialect = "mysql" }):WHERE("x = ?", 1))
        :to_sql()
    end, "OR sub-builder dialect 'mysql' does not match parent 'postgres'")
  end)

  it("M4: INSERT column/row width mismatch raises", function()
    assert.has_error(function()
      sqlbuilder.INSERT("user", { dialect = "mysql" }):COLS("id", "name"):VALUES({ 1 }):to_sql()
    end, "INSERT row width (1) does not match column count (2)")
  end)

  it("M3: UPDATE mixed SET modes render columns in one consistent order", function()
    local builder = sqlbuilder.UPDATE("user")
      :SET("note = ?", "x")
      :SET({ score = 1, name = "n" })
    local inline = builder:to_sql()
    local prepared = builder:to_prepare()
    -- both modes must place table-mode columns first (sorted)
    assert.equal('UPDATE user SET "name" = \'n\', "score" = 1, note = \'x\'', inline)
    assert.equal('UPDATE user SET "name" = ?, "score" = ?, note = ?', prepared)
  end)
end)

describe("adversarial: JSON query determinism", function()
  it("top-level JSON query keys are sorted (no pairs() flakiness)", function()
    local a = sqlbuilder.SELECT("*"):FROM("u"):QUERY({ z = 1, a = 2, m = 3 }):to_sql()
    local b = sqlbuilder.SELECT("*"):FROM("u"):QUERY({ z = 1, a = 2, m = 3 }):to_sql()
    assert.equal(a, b)
    assert.equal('SELECT * FROM u WHERE ("a" = 2 AND "m" = 3 AND "z" = 1)', a)
  end)
end)
