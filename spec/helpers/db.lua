-- Uniform DB facade for integration tests.
--
-- The dialect under test is selected by env LUA_SQLBUILDER_DB
-- (default "sqlite"); credentials for mysql/postgres come from env,
-- matching the GitHub Actions services (see .github/workflows/ci.yml).
--
--   db.current()            → "sqlite" | "mysql" | "postgres"
--   db.connect()            → conn | nil, reason   (nil when driver missing)
--   conn:exec(sql, ...)     → true | nil, err       (bound params supported)
--   conn:query(sql, ...)    → rows | nil, err       (rows = array of {col=val})
--   conn:last_insert_id()   → number | nil
--   conn:close()
--
-- Results are normalized so assertions are dialect/driver independent:
-- numeric-looking strings become numbers, NULLs stay absent keys.

local db = {}

local unpack = table.unpack or unpack -- luacheck: ignore 143

local env = function(name, default) return os.getenv(name) or default end

db.current = function()
  return env("LUA_SQLBUILDER_DB", "sqlite")
end

-- Options table to bind builders to the dialect under test:
--   local SQLBuilder = require "lua_SQLBuilder"
--   SELECT("*", db.opts())
db.opts = function()
  return { dialect = db.current() }
end

-- Normalize a driver value for portable assertions.
local function normalize_value(v)
  if type(v) == "string" then
    local n = tonumber(v)
    if n and tostring(n) == v then
      return n
    end
  end
  return v
end

local function normalize_rows(names, raw_row)
  local out = {}
  for i, raw in ipairs(raw_row) do
    if raw ~= nil then
      out[names[i]] = normalize_value(raw)
    end
  end
  return out
end

-------------------------------------------------------------------------------
-- SQLite (lsqlite3)
-------------------------------------------------------------------------------

local function connect_sqlite()
  local ok, lsqlite3 = pcall(require, "lsqlite3")
  if not ok then
    return nil, "lsqlite3 not available"
  end
  local path = env("LUA_SQLBUILDER_SQLITE_PATH", "")
  local handle = (path ~= "") and lsqlite3.open(path) or lsqlite3.open_memory()
  if not handle then
    return nil, "lsqlite3 failed to open database"
  end

  local conn = {
    dialect = "sqlite",
    _db = handle,
  }

  function conn:exec(sql, ...)
    local n = select("#", ...)
    if n > 0 then
      local stmt = assert(self._db:prepare(sql))
      local args = { ... }
      -- bind_values(...) binds positionally in order (stmt:bind is index-based)
      local ok_bind, err = stmt:bind_values(unpack(args))
      if not ok_bind then
        stmt:finalize()
        return nil, err
      end
      local step = stmt:step()
      local ok_step = (step == lsqlite3.DONE or step == lsqlite3.ROW)
      stmt:finalize()
      return ok_step or nil, ok_step and nil or tostring(step)
    end
    local code, errmsg = self._db:exec(sql)
    return (code == 0) or nil, (code == 0) and nil or errmsg
  end

  function conn:query(sql, ...)
    local rows = {}
    local ok_q, iter = pcall(self._db.nrows, self._db, sql, ...)
    if not ok_q then
      return nil, iter
    end
    for row in iter do
      local normalized = {}
      for k, v in pairs(row) do
        normalized[k] = normalize_value(v)
      end
      rows[#rows + 1] = normalized
    end
    return rows
  end

  function conn:last_insert_id()
    return self._db:last_insert_rowid()
  end

  function conn:close()
    self._db:close()
  end

  return conn
end

-------------------------------------------------------------------------------
-- MySQL / PostgreSQL (LuaSQL 3.x)
-------------------------------------------------------------------------------

local function connect_luasql(driver, dsn_prefix)
  local ok, luasql_driver = pcall(require, "luasql." .. driver)
  if not ok then
    return nil, "luasql." .. driver .. " not available"
  end
  local factory = luasql_driver[driver]
  if not factory then
    return nil, "luasql." .. driver .. " has no factory"
  end
  local env_obj = factory()
  local host = env(dsn_prefix .. "_HOST", "127.0.0.1")
  local port = env(dsn_prefix .. "_PORT", driver == "mysql" and "3306" or "5432")
  local user = env(dsn_prefix .. "_USER", driver == "mysql" and "root" or "postgres")
  local password = env(dsn_prefix .. "_PASSWORD", driver == "mysql" and "root" or "postgres")
  local database = env(dsn_prefix .. "_DATABASE", "sqlbuilder_test")

  local handle, err = env_obj:connect(database, user, password, host, port)
  if not handle then
    env_obj:close()
    return nil, "connection failed: " .. tostring(err)
  end

  local conn = {
    dialect = driver,
    _conn = handle,
    _env = env_obj,
  }

  function conn:exec(sql, ...)
    local n = select("#", ...)
    local cursor, exec_err
    if n > 0 then
      cursor, exec_err = self._conn:execute(sql, ...)
    else
      cursor, exec_err = self._conn:execute(sql)
    end
    if not cursor then
      return nil, exec_err
    end
    if type(cursor) == "table" and cursor.close then
      cursor:close()
    end
    return true
  end

  function conn:query(sql, ...)
    local n = select("#", ...)
    local cursor, query_err
    if n > 0 then
      cursor, query_err = self._conn:execute(sql, ...)
    else
      cursor, query_err = self._conn:execute(sql)
    end
    if not cursor then
      return nil, query_err
    end
    local names = cursor:getcolnames()
    local rows = {}
    while true do
      local raw = cursor:fetch({}, "a")
      if not raw then break end
      rows[#rows + 1] = normalize_rows(names, raw)
    end
    cursor:close()
    return rows
  end

  function conn:last_insert_id()
    if driver == "mysql" then
      return self._conn:getlastautoid()
    end
    -- postgres: last sequence value in this session
    local ok_rows, rows = pcall(self.query, self, "SELECT LASTVAL() AS id")
    if ok_rows and rows and rows[1] then
      return rows[1].id
    end
    return nil
  end

  function conn:close()
    self._conn:close()
    self._env:close()
  end

  return conn
end

-------------------------------------------------------------------------------

local connections = {}

-- Connect (cached per dialect) or return nil, reason when the driver or
-- server is unavailable so specs can `pending()` gracefully.
function db.connect()
  local dialect = db.current()
  if connections[dialect] then
    return connections[dialect]
  end
  local conn, reason
  if dialect == "sqlite" then
    conn, reason = connect_sqlite()
  elseif dialect == "mysql" then
    conn, reason = connect_luasql("mysql", "MYSQL")
  elseif dialect == "postgres" then
    conn, reason = connect_luasql("postgres", "POSTGRES")
  else
    return nil, "unknown dialect: " .. dialect
  end
  if conn then
    connections[dialect] = conn
  end
  return conn, reason
end

function db.close_all()
  for _, conn in pairs(connections) do
    pcall(conn.close, conn)
  end
  connections = {}
end

return db
