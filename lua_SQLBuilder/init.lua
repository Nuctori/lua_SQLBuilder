local SQLBuilder = require "lua_SQLBuilder.SQLBuilder"
local SELECT = require "lua_SQLBuilder.SELECT"
local UPDATE = require "lua_SQLBuilder.UPDATE"
local INSERT = require "lua_SQLBuilder.INSERT"
local DELETE = require "lua_SQLBuilder.DELETE"
local dialect = require "lua_SQLBuilder.dialect"

-- The default dialect is ANSI standard SQL (see dialect.lua); declare a
-- dialect per builder ({dialect=...}) or via set_default_dialect to enable
-- dialect-specific features.
local M = {
    SQLBuilder = SQLBuilder,
    SELECT = SELECT,
    UPDATE = UPDATE,
    INSERT = INSERT,
    DELETE = DELETE,
}

--- Set the default dialect for all future builders.
-- Supported: "ansi" (default), "mysql", "mariadb", "postgres", "sqlite",
-- "mssql", "oracle", "duckdb", "clickhouse".
-- Per-instance override: pass { dialect = "postgres" } as the trailing
-- options argument to any builder constructor.
function M.set_default_dialect(name)
    dialect.set_default(name)
end

function M.get_default_dialect()
    return dialect.get_default()
end

return M
