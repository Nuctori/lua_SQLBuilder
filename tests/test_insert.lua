local root = "/workspace/lua_SQLBuilder"
package.path = package.path
  .. ";" .. root .. "/?.lua"
  .. ";" .. root .. "/?/init.lua"

local SQLBuilder = require "lua_SQLBuilder"
local INSERT = SQLBuilder.INSERT

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s\nexpected: %s\nactual:   %s", label or "assertion failed", expected, actual))
  end
end

local function test_insert_data_sorted_keys()
  local sql = INSERT("user"):DATA({ b = 2, a = 1, c = 3 }):to_sql()
  local expected = "INSERT INTO user (`a`, `b`, `c`) VALUES (1, 2, 3)"
  assert_equal(sql, expected, "INSERT:DATA should sort keys for deterministic SQL")
end

local function run()
  test_insert_data_sorted_keys()
  print("ok - test_insert_data_sorted_keys")
end

run()
