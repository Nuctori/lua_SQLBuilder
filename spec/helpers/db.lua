-- Uniform DB facade for integration tests.
--
-- The dialect under test is selected by env LUA_SQLBUILDER_DB
-- (default "sqlite"); credentials for mysql/postgres come from env,
-- matching the GitHub Actions services (see .github/workflows/ci.yml).
--
--   db.current()            → "sqlite" | "mysql" | "postgres"
--   db.connect()            → conn | nil, reason   (nil when driver missing)
--   conn:exec(sql, ...)     → true | nil, err       (bound params if supported)
--   conn:query(sql, ...)    → rows | nil, err       (rows = array of {col=val})
--   conn:last_insert_id()   → number | nil
--   conn.supports_params    → true when the driver can bind ? parameters
--   conn:close()
--
-- Driver note: LuaSQL (mysql/postgres) has NO parameter binding in the
-- released 2.x line, so param-bound execution is provided by lsqlite3 and
-- pgmoon only; mysql integration exercises to_sql (inline) execution and
-- string-level prepare validation (see spec/audit).

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

-- Inline SQL literal for fixture seeding (values are trusted constants).
local function literal(v)
  if v == nil then
    return "NULL"
  end
  local t = type(v)
  if t == "number" then
    return tostring(v)
  end
  if t == "boolean" then
    return v and "1" or "0"
  end
  return "'" .. tostring(v):gsub("'", "''") .. "'"
end

db.literal = literal

-------------------------------------------------------------------------------
-- SQLite (lsqlite3) — supports ? binding
-------------------------------------------------------------------------------

local function connect_sqlite()
  local ok, lsqlite3 = pcall(require, "lsqlite3")
  if not ok then
    return nil, "lsqlite3 not available"
  end
  local handle = lsqlite3.open_memory()
  if not handle then
    return nil, "lsqlite3 failed to open database"
  end

  local conn = {
    dialect = "sqlite",
    supports_params = true,
    _db = handle,
  }

  function conn:exec(sql, ...)
    local n = select("#", ...)
    if n == 0 then
      local code, errmsg = self._db:exec(sql)
      if code ~= 0 then
        return nil, errmsg or tostring(code)
      end
      return true
    end
    -- Bound path, defensively: lsqlite3 versions differ on raise vs return.
    local ok_p, stmt, prep_err = pcall(self._db.prepare, self._db, sql)
    if not ok_p or not stmt then
      return nil, "prepare failed (" .. tostring(prep_err) .. "): " .. tostring(sql)
    end
    local args = { ... }
    local ok_b, bind_err = pcall(stmt.bind_values, stmt, unpack(args))
    if not ok_b then
      stmt:finalize()
      return nil, "bind failed: " .. tostring(bind_err)
    end
    if bind_err ~= nil and bind_err ~= 0 then
      stmt:finalize()
      return nil, "bind returned " .. tostring(bind_err)
    end
    local ok_s, step = pcall(stmt.step, stmt)
    if not ok_s then
      stmt:finalize()
      return nil, "step raised: " .. tostring(step)
    end
    stmt:finalize()
    if step == lsqlite3.DONE or step == lsqlite3.ROW then
      return true
    end
    return nil, "step returned " .. tostring(step)
  end

  function conn:query(sql, ...)
    -- nrows returns (iterator, state, control) for the generic for; wrap the
    -- whole loop so the triple survives and failures carry the SQL.
    local args = { ... }
    local rows = {}
    local ok_iter, iter_err = pcall(function()
      for row in self._db.nrows(self._db, sql, unpack(args)) do
        local normalized = {}
        for k, v in pairs(row) do
          normalized[k] = normalize_value(v)
        end
        rows[#rows + 1] = normalized
      end
    end)
    if not ok_iter then
      return nil, "query failed (" .. tostring(iter_err) .. "): " .. tostring(sql)
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
-- PostgreSQL (pgmoon) — pure Lua, supports ? binding (converted to $n)
-------------------------------------------------------------------------------

local function connect_pgmoon()
  local ok, pgmoon = pcall(require, "pgmoon")
  if not ok then
    return nil, "pgmoon not available"
  end
  local pg = pgmoon.new({
    host = env("POSTGRES_HOST", "127.0.0.1"),
    port = tonumber(env("POSTGRES_PORT", "5432")),
    user = env("POSTGRES_USER", "postgres"),
    password = env("POSTGRES_PASSWORD", "postgres"),
    database = env("POSTGRES_DATABASE", "sqlbuilder_test"),
  })
  local connected, conn_err = pg:connect()
  if not connected then
    return nil, "connection failed: " .. tostring(conn_err)
  end

  local conn = {
    dialect = "postgres",
    supports_params = true,
    _pg = pg,
  }

  -- PostgreSQL prepared statements use $n placeholders. pgmoon does not
  -- convert "?", so translate positionally (when params are present every
  -- "?" in the SQL is a placeholder; inline string literals with "?" never
  -- reach this path with params).
  local function pg_convert(sql, n)
    local i = 0
    local out = sql:gsub("%?", function()
      i = i + 1
      return "$" .. i
    end)
    if i ~= n then
      return nil, "placeholder count mismatch: " .. i .. " placeholders, " .. n .. " params"
    end
    return out
  end

  function conn:exec(sql, ...)
    local n = select("#", ...)
    if n > 0 then
      local converted, convert_err = pg_convert(sql, n)
      if not converted then
        return nil, convert_err
      end
      sql = converted
    end
    local res, err = self._pg:query(sql, ...)
    if not res then
      return nil, err
    end
    return true
  end

  function conn:query(sql, ...)
    local n = select("#", ...)
    if n > 0 then
      local converted, convert_err = pg_convert(sql, n)
      if not converted then
        return nil, convert_err
      end
      sql = converted
    end
    local res, err = self._pg:query(sql, ...)
    if not res then
      return nil, err
    end
    local rows = {}
    for _, row in ipairs(res) do
      local normalized = {}
      for k, v in pairs(row) do
        normalized[k] = normalize_value(v)
      end
      rows[#rows + 1] = normalized
    end
    return rows
  end

  function conn:last_insert_id()
    local ok_rows, rows = pcall(self.query, self, "SELECT LASTVAL() AS id")
    if ok_rows and rows and rows[1] then
      return rows[1].id
    end
    return nil
  end

  function conn:close()
    self._pg:close()
  end

  return conn
end

-------------------------------------------------------------------------------
-- MySQL (LuaSQL) — inline execution only (no ? binding in released 2.x)
-------------------------------------------------------------------------------

local function luas_driver_or(mod)
  -- luasql.mysql module exposes a .mysql factory (or the module may already
  -- be an environment object)
  return mod.mysql and mod.mysql() or mod
end

local function connect_luasql_mysql()
  local ok, luasql_driver = pcall(require, "luasql.mysql")
  if not ok then
    return nil, "luasql.mysql not available"
  end
  local env_obj = luas_driver_or(luasql_driver)
  local host = env("MYSQL_HOST", "127.0.0.1")
  local port = env("MYSQL_PORT", "3306")
  local user = env("MYSQL_USER", "root")
  local password = env("MYSQL_PASSWORD", "root")
  local database = env("MYSQL_DATABASE", "sqlbuilder_test")

  local handle, connect_err = env_obj:connect(database, user, password, host, port)
  if not handle then
    env_obj:close()
    return nil, "connection failed: " .. tostring(connect_err)
  end

  local conn = {
    dialect = "mysql",
    supports_params = false, -- LuaSQL 2.x cannot bind ? parameters
    _conn = handle,
    _env = env_obj,
  }

  function conn:exec(sql, ...)
    local n = select("#", ...)
    if n > 0 then
      return nil, "mysql driver (LuaSQL 2.x) does not support bound parameters"
    end
    local cursor, err = self._conn:execute(sql)
    if not cursor then
      return nil, err
    end
    if type(cursor) == "table" and cursor.close then
      cursor:close()
    end
    return true
  end

  function conn:query(sql)
    local cursor, query_err = self._conn:execute(sql)
    if not cursor then
      return nil, query_err
    end
    -- In LuaSQL-mysql, fetch mode 'a' returns rows keyed by column name
    -- ('n' is numeric indices, opposite of the generic manual)
    local rows = {}
    while true do
      local raw = cursor:fetch({}, "a")
      if not raw then break end
      local normalized = {}
      for k, v in pairs(raw) do
        if v ~= nil then
          normalized[k] = normalize_value(v)
        end
      end
      rows[#rows + 1] = normalized
    end
    cursor:close()
    return rows
  end

  function conn:last_insert_id()
    return self._conn:getlastautoid()
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
    conn, reason = connect_luasql_mysql()
  elseif dialect == "postgres" then
    conn, reason = connect_pgmoon()
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
