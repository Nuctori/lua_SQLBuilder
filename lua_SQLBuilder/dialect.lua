-- Dialect definitions as CONFIGURATION.
--
-- The default dialect is ANSI standard SQL: no dialect-specific features are
-- emitted unless a dialect is declared. Declare one per builder (trailing
-- options table) or set the module default:
--
--   sqlbuilder.set_default_dialect("mysql")             -- module-wide
--   SELECT("*", { dialect = "postgres" })               -- per-instance
--
-- Dialects are plain config tables; the built-in presets are conveniences
-- for the databases verified in CI. To use a database without a preset,
-- copy a close preset and adjust the fields:
--
--   local dialect = require "lua_SQLBuilder.dialect"
--   dialect.dialects.oracle = dialect.dialects.ansi  -- then tweak fields
--
-- Fields:
--   quote_ident       fn(name) -> quoted identifier
--   json_path         fn(table_name, path) -> JSON extract expression
--   escape_string     fn(s) -> string literal body (without quotes)
--   render_limit      fn(offset, count) -> LIMIT fragment
--   upsert            { keyword, needs_conflict, ref } or nil (unsupported)

local fmt = string.format

local M = {}

local DEFAULT = "ansi"
M.default = DEFAULT

-------------------------------------------------------------------------------
-- field defaults
-------------------------------------------------------------------------------

local function quote_ident_mysql(name)
  return fmt("`%s`", name:gsub("`", "``"))
end
local function quote_ident_ansi(name)
  return fmt('"%s"', name:gsub('"', '""'))
end
-- Oracle: unquoted DDL identifiers are stored UPPERCASE; quoted references
-- are case-sensitive, so we emit uppercase to match the stored names.
local function quote_ident_oracle(name)
  return fmt('"%s"', name:upper():gsub('"', '""'))
end
local function quote_ident_mssql(name)
  return fmt("[%s]", name:gsub("]", "]]"))
end

local mysql_escape_map = {
  ['\0'] = "\\0",
  ['\b'] = "\\b",
  ['\n'] = "\\n",
  ['\r'] = "\\r",
  ['\t'] = "\\t",
  ['\26'] = "\\Z",
  ['\\'] = "\\\\",
  ["'"] = "\\'",
}
local function escape_mysql(s)
  local out = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    out[#out + 1] = mysql_escape_map[c] or c
  end
  return table.concat(out)
end
-- ANSI standard (PostgreSQL with standard_conforming_strings=on, SQLite,
-- SQL Server): single quotes are doubled, backslash is literal.
local function escape_ansi(s)
  return s:gsub("'", "''")
end

-- "count OFFSET offset" (offset 0 -> just "count"); ANSI + MySQL >= 4.0.1,
-- MariaDB, PostgreSQL and SQLite.
local function render_limit_ansi(offset, count)
  if offset == nil or offset == "" or tonumber(offset) == 0 then
    return tostring(count)
  end
  return fmt("%s OFFSET %s", count, offset)
end
-- SQL Server / Oracle 12c+: OFFSET/FETCH after ORDER BY.
local function render_limit_mssql(offset, count)
  local offset_n = (offset == nil or offset == "" or tonumber(offset) == 0) and 0 or offset
  return fmt("OFFSET %s ROWS FETCH NEXT %s ROWS ONLY", offset_n, count)
end

-- Path segments: text keys arrive as "a" / "b", array indices as "[0]".
-- MySQL/MariaDB accept the "$.a[0].b" JSON-path spelling with backticks.
local function json_path_mysql(table_name, path)
  return fmt("%s->>'$.%s'", quote_ident_mysql(table_name), path)
end
-- ANSI preset: same JSON-path spelling, double-quoted identifiers.
local function json_path_jsonpath(table_name, path)
  return fmt("%s->>'$.%s'", quote_ident_ansi(table_name), path)
end
local function json_path_sqlite(table_name, path)
  -- json_extract works on every sqlite >= 3.9; CAST AS TEXT makes equality
  -- with the string form portable (sqlite applies no affinity between
  -- expression results).
  return fmt("CAST(json_extract(%s, '$.%s') AS TEXT)", quote_ident_ansi(table_name), path)
end
-- PostgreSQL ->> does not accept "$.a.b"; translate to an operator chain:
-- json->'a'->0->>'b' (text keys ->'k', array indices ->N).
local function json_path_postgres(table_name, path)
  local parts = {}
  for part in path:gmatch("[^.]+") do
    parts[#parts + 1] = part
  end
  local expr = quote_ident_ansi(table_name)
  for i = 1, #parts - 1 do
    local idx = parts[i]:match("^%[(%d+)%]$")
    if idx then
      expr = fmt("%s->%s", expr, idx)
    else
      expr = fmt("%s->'%s'", expr, parts[i])
    end
  end
  local last = parts[#parts]
  local last_idx = last:match("^%[(%d+)%]$")
  if last_idx then
    return fmt("%s->>%s", expr, last_idx)
  end
  return fmt("%s->>'%s'", expr, last)
end
-- SQL Server: JSON_VALUE(column, '$.a[0].b')
local function json_path_mssql(table_name, path)
  return fmt("JSON_VALUE(%s, '$.%s')", quote_ident_mssql(table_name), path)
end
-- Oracle 12c+: JSON_VALUE(column, '$.a[0].b') — UPPERCASE identifiers
local function json_path_oracle(table_name, path)
  return fmt("JSON_VALUE(%s, '$.%s')", quote_ident_oracle(table_name), path)
end
-- DuckDB: json_extract_string(column, '$.a[0].b') returns VARCHAR
local function json_path_duckdb(table_name, path)
  return fmt("json_extract_string(%s, '$.%s')", quote_ident_ansi(table_name), path)
end
-- ClickHouse: JSONExtractString(column, 'a', 0, 'b') — comma-separated key
-- list, numeric args are array indices.
local function json_path_clickhouse(table_name, path)
  local args = {}
  for part in path:gmatch("[^.]+") do
    local idx = part:match("^%[(%d+)%]$")
    if idx then
      args[#args + 1] = idx
    else
      args[#args + 1] = "'" .. part .. "'"
    end
  end
  return fmt("JSONExtractString(%s, %s)", quote_ident_mysql(table_name), table.concat(args, ", "))
end

local upsert_mysql = {
  keyword = "ON DUPLICATE KEY UPDATE",
  needs_conflict = false,
}
local upsert_pg = {
  keyword = "ON CONFLICT DO UPDATE",
  needs_conflict = true,
  ref = "EXCLUDED",
}
local upsert_sqlite = {
  keyword = "ON CONFLICT DO UPDATE",
  needs_conflict = true,
  ref = "excluded",
}

-------------------------------------------------------------------------------
-- presets (plain configuration tables)
-------------------------------------------------------------------------------

local dialects = {
  ansi = {
    name = "ansi",
    quote_ident = quote_ident_ansi,
    json_path = json_path_jsonpath,
    escape_string = escape_ansi,
    render_limit = render_limit_ansi,
    upsert = nil, -- no single-statement upsert in ANSI
  },
  mysql = {
    name = "mysql",
    quote_ident = quote_ident_mysql,
    json_path = json_path_mysql,
    escape_string = escape_mysql,
    render_limit = render_limit_ansi,
    upsert = upsert_mysql,
  },
  mariadb = {
    name = "mariadb",
    quote_ident = quote_ident_mysql,
    json_path = json_path_mysql,
    escape_string = escape_mysql,
    render_limit = render_limit_ansi,
    upsert = upsert_mysql,
  },
  postgres = {
    name = "postgres",
    quote_ident = quote_ident_ansi,
    json_path = json_path_postgres,
    escape_string = escape_ansi,
    render_limit = render_limit_ansi,
    upsert = upsert_pg,
  },
  sqlite = {
    name = "sqlite",
    quote_ident = quote_ident_ansi,
    json_path = json_path_sqlite,
    escape_string = escape_ansi,
    render_limit = render_limit_ansi,
    upsert = upsert_sqlite,
  },
  mssql = {
    name = "mssql",
    quote_ident = quote_ident_mssql,
    json_path = json_path_mssql,
    escape_string = escape_ansi,
    render_limit = render_limit_mssql,
    upsert = nil,
  },
  oracle = {
    name = "oracle",
    quote_ident = quote_ident_oracle,
    json_path = json_path_oracle,
    escape_string = escape_ansi,
    render_limit = render_limit_mssql, -- Oracle 12c+ OFFSET/FETCH
    upsert = nil, -- MERGE is a standalone statement
  },
  duckdb = {
    name = "duckdb",
    quote_ident = quote_ident_ansi,
    json_path = json_path_duckdb,
    escape_string = escape_ansi,
    render_limit = render_limit_ansi,
    upsert = upsert_sqlite, -- ON CONFLICT ... DO UPDATE, excluded ref
  },
  clickhouse = {
    name = "clickhouse",
    quote_ident = quote_ident_mysql, -- backticks
    json_path = json_path_clickhouse,
    escape_string = escape_mysql, -- backslash style
    render_limit = render_limit_ansi,
    upsert = nil, -- table engines (ReplacingMergeTree) handle dedup
  },
}

M.dialects = dialects

-------------------------------------------------------------------------------
-- resolution
-------------------------------------------------------------------------------

local default_name = DEFAULT

--- Resolve a dialect name (or nil → the module default) to its config table.
function M.resolve(name)
  if name == nil then
    name = default_name
  end
  local dialect = dialects[name]
  if not dialect then
    error("unknown dialect: " .. tostring(name) ..
      " (built-ins: ansi, mysql, mariadb, postgres, sqlite, mssql, oracle, duckdb, clickhouse)", 2)
  end
  return dialect
end

--- Snapshot a dialect config: builders copy the fields at construction time,
-- so later edits to `dialect.dialects.<name>` do not mutate existing
-- builders (predictable behavior, adversarial audit M1).
function M.snapshot(name)
  local d = M.resolve(name)
  local copy = {}
  for k, v in pairs(d) do
    copy[k] = v
  end
  return copy
end

function M.set_default(name)
  assert(dialects[name], "unknown dialect: " .. tostring(name))
  default_name = name
end

function M.get_default()
  return default_name
end

return M
