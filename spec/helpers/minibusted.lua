-- Minimal busted-compatible shim so the SAME spec files run either under
-- busted in CI or under a plain Lua interpreter locally (zero dependencies).
--
-- Supported subset: describe / it / before_each / pending / assert.
-- Tag-less: DB gating is env-based (see spec/helpers/db.lua).

local M = {}

-- busted-compatible assert: a callable table (like luassert) so both
-- `assert(cond)` and `assert.equal(a, b)` work under plain Lua 5.1-5.4.
local callable_assert = setmetatable({}, {
  __call = function(_, v, msg)
    if not v then
      error(msg or "assertion failed", 2)
    end
    return v, msg
  end,
})

function callable_assert.equal(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s\nexpected: %s\nactual:   %s",
      msg or "assertion failed", tostring(expected), tostring(actual)), 2)
  end
end

function callable_assert.has_error(fn, pattern)
  local ok, err = pcall(fn)
  if ok then
    error("expected function to raise an error", 2)
  end
  if pattern and not tostring(err):find(pattern, 1, true) then
    error(string.format("expected error matching %q, got: %s", pattern, tostring(err)), 2)
  end
end

assert = callable_assert

local failed = 0
local pending_count = 0
local passed = 0
local before_each_hooks = {}

local PENDING_SENTINEL = {}

--- Emulates busted's pending(): stops the current test as skipped.
function pending(msg)
  error({ [PENDING_SENTINEL] = true, msg = msg or "pending" })
end

--- Emulates busted's before_each(): run hooks before every `it`.
function before_each(fn)
  before_each_hooks[#before_each_hooks + 1] = fn
end

--- describe() runs its body immediately (busted runs setup eagerly too).
function describe(_, fn)
  fn()
end

function it(name, fn)
  local function run()
    for _, hook in ipairs(before_each_hooks) do
      hook()
    end
    fn()
  end
  local ok, err = xpcall(run, debug.traceback)
  if ok then
    passed = passed + 1
    print(string.format("  ok  %s", name))
  elseif type(err) == "table" and err[PENDING_SENTINEL] then
    pending_count = pending_count + 1
    print(string.format("  ~   %s  (pending: %s)", name, err.msg or ""))
  else
    failed = failed + 1
    print(string.format("  FAIL %s", name))
    print(err)
  end
end

--- Runs every `*_spec.lua` under the given directories.
function M.run(dirs)
  local start = os.time()
  for _, dir in ipairs(dirs or { "spec/unit", "spec/integration", "spec/production" }) do
    local p = io.popen(string.format('if exist "%s" (dir /b /s "%s\\*_spec.lua")', dir, dir))
    if p then
      for line in p:lines() do
        local lua_file = line:gsub("\\", "/")
        print(string.format("== %s", lua_file))
        local ok, err = xpcall(function()
          dofile(lua_file)
        end, debug.traceback)
        if not ok then
          failed = failed + 1
          print(string.format("  FAIL (file load) %s", lua_file))
          print(err)
        end
      end
      p:close()
    end
  end
  print(string.format("\n%d passed, %d failed, %d pending (%ds)",
    passed, failed, pending_count, os.time() - start))
  return failed == 0
end

return M
