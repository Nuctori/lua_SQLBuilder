-- Spec bootstrap: make `require` resolve the project root regardless of the
-- working directory busted is launched from.
--
-- Used by CI via `busted --helper=spec/helpers/init.lua` and by the local
-- zero-dependency runner (spec/run.lua).

local root = (function()
  local src = debug.getinfo(1, "S").source
  -- source is like "@spec/helpers/init.lua" or "@D:\lua\lua_SQLBuilder\spec\..."
  local path = src:sub(2)
  path = path:gsub("\\", "/")
  path = path:gsub("/spec/helpers/init.lua$", "")
  return path
end)()

package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

return { root = root }
