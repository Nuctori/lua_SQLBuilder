-- Local zero-dependency test runner.
-- Usage:  lua spec/run.lua [dir1 dir2 ...]
-- Default dirs: spec/unit spec/production spec/integration
-- DB gating for integration is env-based (LUA_SQLBUILDER_DB, default sqlite).

package.path = "./?.lua;./?/init.lua;" .. package.path

local minibusted = require "spec.helpers.minibusted"

local dirs = { ... }
if #dirs == 0 then
  dirs = { "spec/unit", "spec/production", "spec/integration" }
end

local ok = minibusted.run(dirs)
os.exit(ok and 0 or 1)
