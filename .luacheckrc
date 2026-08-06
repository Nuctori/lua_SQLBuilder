-- luacheck configuration
-- https://github.com/lunarmodules/luacheck

std = "lua51"

-- Bust globals used by spec files (busted provides them at runtime)
files["spec/"] = {
  std = "lua51",
  globals = {
    "describe", "it", "pending", "setup", "teardown",
    "before_each", "after_each", "assert",
  },
}

files["lua_SQLBuilder/"] = {
  std = "lua51",
}

-- The vendored json fallback prints on require by design
files["lua_SQLBuilder/json.lua"] = {
  std = "lua51",
  globals = {
    "print",
  },
}
