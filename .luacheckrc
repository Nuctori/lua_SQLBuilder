-- luacheck configuration
-- https://github.com/lunarmodules/luacheck

-- lua51 std plus the 5.3+ table.unpack alias (guarded via `table.unpack or unpack`)
std = "lua51+table.unpack"

-- Bust globals used by spec files (busted provides them at runtime)
files["spec/"] = {
  std = "lua51+table.unpack",
  globals = {
    "describe", "it", "pending", "setup", "teardown",
    "before_each", "after_each", "assert",
  },
}

files["lua_SQLBuilder/"] = {
  std = "lua51+table.unpack",
}

-- The vendored json fallback prints on require by design
files["lua_SQLBuilder/json.lua"] = {
  std = "lua51+table.unpack",
  globals = {
    "print",
  },
}
