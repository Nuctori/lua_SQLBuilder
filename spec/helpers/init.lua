-- Spec bootstrap: make `require` resolve the project root regardless of the
-- working directory busted is launched from.
--
-- Used by CI via `busted --helper=spec/helpers/init.lua` and by the local
-- zero-dependency runner (spec/run.lua).

local function project_root()
  local src = debug.getinfo(1, "S").source
  -- source is like "@spec/helpers/init.lua" (CI, relative) or
  -- "@D:\lua\lua_SQLBuilder\spec\helpers\init.lua" (local, absolute)
  local path = src:sub(2)
  path = path:gsub("\\", "/")
  path = path:gsub("/spec/helpers/init.lua$", "")
  if path == "" then
    path = "."
  end
  return path
end

local root = project_root()
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

return { root = root }
