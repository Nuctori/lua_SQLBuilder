-- Dialect definitions: the small set of SQL differences between supported
-- databases (identifier quoting, JSON path operator, upsert syntax).
--
-- The library defaults to MySQL; pass { dialect = "postgres" | "sqlite" }
-- as the trailing options argument to any builder, or call
-- `sqlbuilder.set_default_dialect("postgres")` once at startup.

local fmt = string.format

local M = {}

local DEFAULT = "mysql"
M.default = DEFAULT

local function quote_ident_mysql(name)
  return fmt("`%s`", name)
end

local function quote_ident_ansi(name)
  return fmt('"%s"', name)
end

-- JSON scalar-equality expressions. Params are always bound/rendered as their
-- string form (see utils.Make_JsonQuery) so equality is portable: the three
-- databases all compare a JSON scalar to its text representation.
local function json_path_mysql(table_name, path)
  return fmt("%s->>'$.%s'", quote_ident_mysql(table_name), path)
end

local function json_path_sqlite(table_name, path)
  -- json_extract works on every sqlite >= 3.9. CAST AS TEXT makes equality
  -- with the string form portable: sqlite does not apply affinity to
  -- expression-to-expression comparisons, so json_extract(...) = '5'
  -- (INTEGER vs TEXT) would never match.
  return fmt("CAST(json_extract(%s, '$.%s') AS TEXT)", quote_ident_ansi(table_name), path)
end

-- PostgreSQL's ->> does not accept the "$.a.b" path syntax; translate the
-- path into an operator chain: json->'a'->'b'->>'c'.
local function json_path_postgres(table_name, path)
  local parts = {}
  for part in path:gmatch("[^.]+") do
    part = part:gsub('^"(.*)"$', "%1")
    parts[#parts + 1] = part
  end
  local expr = quote_ident_ansi(table_name)
  for i = 1, #parts - 1 do
    expr = fmt("%s->'%s'", expr, parts[i])
  end
  return fmt("%s->>'%s'", expr, parts[#parts])
end

local dialects = {
  mysql = {
    name = "mysql",
    quote_ident = quote_ident_mysql,
    json_path = json_path_mysql,
    upsert = {
      keyword = "ON DUPLICATE KEY UPDATE",
      needs_conflict = false,
    },
  },
  postgres = {
    name = "postgres",
    quote_ident = quote_ident_ansi,
    json_path = json_path_postgres,
    upsert = {
      keyword = "ON CONFLICT DO UPDATE",
      needs_conflict = true,
      ref = "EXCLUDED",
    },
  },
  sqlite = {
    name = "sqlite",
    quote_ident = quote_ident_ansi,
    json_path = json_path_sqlite,
    upsert = {
      keyword = "ON CONFLICT DO UPDATE",
      needs_conflict = true,
      ref = "excluded",
    },
  },
}

M.dialects = dialects

local default_name = DEFAULT

--- Resolve a dialect name (or nil → the module default) to its config table.
function M.resolve(name)
  if name == nil then
    name = default_name
  end
  local dialect = dialects[name]
  if not dialect then
    error("unknown dialect: " .. tostring(name) ..
      " (supported: mysql, postgres, sqlite)", 2)
  end
  return dialect
end

function M.set_default(name)
  assert(dialects[name], "unknown dialect: " .. tostring(name))
  default_name = name
end

function M.get_default()
  return default_name
end

return M
