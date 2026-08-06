-- Bootstrap: ensure the project root is on package.path (works with busted on every Lua version, incl. 5.1 where busted rewrites the path)
package.path = "./?.lua;./?/init.lua;" .. package.path

-- Machine cross-audit: invariants that must hold across every public builder
-- API and every dialect. The audit runs on EVERY CI run; violations here mean
-- the library broke a behavioral contract, not just a golden string.
--
-- Known violations are marked `pending` with their bug id and flip to green
-- when fixed (same convention as spec/unit/known_bugs_spec.lua).

local SQLBuilder = require "lua_SQLBuilder"

local DIALECTS = { "mysql", "postgres", "sqlite" }

-- One representative builder per public API, bound to a dialect.
local function make_builder(api, dialect)
  local opts = { dialect = dialect }
  if api == "base" then
    return SQLBuilder.SQLBuilder("SELECT * FROM user", opts)
      :WHERE("id > ?", 2)
      :OR(SQLBuilder.SQLBuilder("", opts):WHERE("status = ?", 1))
      :ORDER_BY("name"):DESC()
      :LIMIT(10, 20)
  elseif api == "select" then
    return SQLBuilder.SELECT("*", opts)
      :FROM("book")
      :QUERY({ user_id = 1, status = 1, json = { star = 5 } })
      :PAGE(2):PER(10)
  elseif api == "update" then
    return SQLBuilder.UPDATE("user", opts)
      :SET({ score = 100, status = "pass" })
      :WHERE("id = ?", 1)
  elseif api == "insert" then
    return SQLBuilder.INSERT("user", opts)
      :COLS("id", "name", "status")
      :VALUES({ 1, "name1", 1 }, { 2, "name2", 0 })
  elseif api == "delete" then
    return SQLBuilder.DELETE("user", opts)
      :QUERY({ id = 1, status = 0 })
  end
  error("unknown api: " .. tostring(api))
end

local APIs = { "base", "select", "update", "insert", "delete" }

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

local function collect_all(f)
  return { f() }
end

describe("audit: determinism (same input, same output)", function()
  for _, dialect in ipairs(DIALECTS) do
    for _, api in ipairs(APIs) do
      it(api .. " on " .. dialect, function()
        local a = make_builder(api, dialect):to_sql()
        local b = make_builder(api, dialect):to_sql()
        assert.equal(a, b)
      end)
    end
  end
end)

describe("audit: idempotency (repeated calls do not change output)", function()
  for _, dialect in ipairs(DIALECTS) do
    for _, api in ipairs(APIs) do
      it(api .. " to_sql on " .. dialect, function()
        local builder = make_builder(api, dialect)
        assert.equal(builder:to_sql(), builder:to_sql())
      end)
      it(api .. " to_prepare on " .. dialect, function()
        local a = collect_all(function() return make_builder(api, dialect):to_prepare() end)
        local b = collect_all(function() return make_builder(api, dialect):to_prepare() end)
        assert.equal(a[1], b[1])
        assert.equal(#a, #b)
        for i = 2, #a do
          assert(deep_equal(a[i], b[i]), "param " .. i .. " differs on " .. api .. "/" .. dialect)
        end
      end)
    end
  end
end)

describe("audit: no mutation of caller tables", function()
  it("WHERE table param with numbers is untouched", function()
    local ids = { 1, 2, 3 }
    SQLBuilder.SQLBuilder("SELECT * FROM user"):WHERE("id in ?", ids):to_sql()
    assert.equal("1,2,3", table.concat(ids, ","))
  end)

  it("SELECT QUERY input is untouched", function()
    local query = { user_id = 1, status = 1 }
    SQLBuilder.SELECT("*"):FROM("book"):QUERY(query):to_sql()
    assert.equal(1, query.user_id)
    assert.equal(1, query.status)
  end)

  it("INSERT VALUES input is untouched", function()
    local row = { 1, "name1" }
    SQLBuilder.INSERT("user"):COLS("id", "name"):VALUES(row):to_sql()
    assert.equal("name1", row[2])
  end)

  it("A19 (pending): WHERE table param with strings is mutated", function()
    pending("A19 - fixed in phase 1")
    local names = { "a", "b" }
    SQLBuilder.SQLBuilder("SELECT * FROM user"):WHERE("name in ?", names):to_sql()
    assert.equal("a", names[1])
  end)
end)

describe("audit: placeholder/param alignment", function()
  it("scalar params align with placeholders", function()
    local sql, p1, p2 = SQLBuilder.SQLBuilder("SELECT * FROM user")
      :WHERE("a = ?", 1)
      :WHERE("b = ?", 2)
      :to_prepare()
    local _, count = sql:gsub("%?", "?")
    assert.equal(2, count)
    assert.equal(1, p1)
    assert.equal(2, p2)
  end)

  it("A1 (pending): UPDATE string-mode prepare misaligns placeholders", function()
    pending("A1 - fixed in phase 1")
    local sql = SQLBuilder.UPDATE("user"):SET("score = score + ?", 1):WHERE("id = ?", 1):to_prepare()
    local _, count = sql:gsub("%?", "?")
    assert.equal(2, count)
  end)
end)

describe("audit: escaping round-trip", function()
  it("prepare mode keeps quotes out of the SQL (driver escapes)", function()
    local sql = SQLBuilder.INSERT("user"):COLS("id", "name"):VALUES({ 1, "O'Brien" }):to_prepare()
    assert.equal("INSERT INTO user (`id`, `name`) VALUES (?, ?)", sql)
  end)

  it("B1 (pending): to_sql inline mode escapes string values", function()
    pending("B1 - fixed in phase 2 (unified escaping)")
    local sql = SQLBuilder.SQLBuilder("SELECT * FROM user"):WHERE("name = ?", "O'Brien"):to_sql()
    assert.equal("SELECT * FROM user WHERE (name = 'O''Brien')", sql)
  end)
end)
