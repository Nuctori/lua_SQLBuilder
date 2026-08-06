# lua_SQLBuilder

A dependency-free SQL statement builder for Lua 5.1–5.4 and LuaJIT, with
multi-dialect support (MySQL, PostgreSQL, SQLite) and real-database CI
verification.

```lua
local sqlbuilder = require "lua_SQLBuilder"

local sql = sqlbuilder.SQLBuilder("SELECT * FROM user")
  :WHERE("id > ?", 2)
  :ORDER_BY("user"):DESC()
  :ORDER_BY("id"):ASC()
  :to_sql()
-- SELECT * FROM user WHERE (id > 2) ORDER BY user DESC, id ASC
```

## Features

- **Chainable builders**: `WHERE` / `OR` / `ORDER BY` / `GROUP BY` / `HAVING` /
  `LIMIT` / `FOR UPDATE` plus `SELECT` / `UPDATE` / `INSERT` / `DELETE` helpers
  (`QUERY`, `SET`, `DATA`, `COLS`, `VALUES`, upsert).
- **Two output modes**: `to_sql()` renders inline SQL with dialect-aware string
  escaping; `to_prepare()` returns placeholder SQL plus bound parameters for
  injection-safe execution by your driver.
- **Multi-dialect**: MySQL (default), PostgreSQL, SQLite — identifier quoting,
  JSON path operators, upsert syntax and string escaping adapt automatically.
- **Deterministic**: table-style inputs are key-sorted; repeated renders are
  byte-identical (locked by cross-audit invariants).
- **Verified**: CI runs the same suite against real MySQL 8, PostgreSQL 16 and
  SQLite on Lua 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT.

## Installation

LuaRocks (once a release is tagged):

```
luarocks install lua_SQLBuilder
```

Or vendor the `lua_SQLBuilder/` directory and add it to `package.path`.

## Quick start

### Prepared statements (recommended)

```lua
local sql, id = sqlbuilder.SQLBuilder("SELECT * FROM user")
  :WHERE("id > ?", 2)
  :to_prepare()
-- sql: SELECT * FROM user WHERE (id > ?)
-- id:  2
```

### SELECT with QUERY and pagination

```lua
local sql = sqlbuilder.SELECT("*"):FROM("book"):QUERY({ user_id = 1, status = 1 })
  :PAGE(2):PER(10):to_sql()
-- SELECT * FROM book WHERE (`status` = 1 AND `user_id` = 1) LIMIT 10 OFFSET 10
```

`QUERY` accepts scalar, boolean, `userdata` (→ `IS NULL`) and table values;
a table value is a JSON-path query:

```lua
local sql = sqlbuilder.SELECT("*"):FROM("book")
  :QUERY({ user_id = 1, json = { star = 5 } }):to_sql()
-- SELECT * FROM book WHERE (`json`->>'$.star' = '5' AND `user_id` = 1)
```

### OR groups

Nested OR requires an explicit sub-builder (keeps construction flexible):

```lua
local sql = sqlbuilder.SQLBuilder("SELECT * FROM user")
  :WHERE("id > ?", 1)
  :OR(sqlbuilder.SQLBuilder(""):WHERE("name = ?", "user_1"))
  :to_sql()
-- SELECT * FROM user WHERE (id > 1) OR (name = 'user_1')
```

### UPDATE / INSERT / DELETE

```lua
sqlbuilder.UPDATE("user"):SET({ score = 100, status = "pass" }):WHERE("id = ?", 1)
sqlbuilder.INSERT("user"):DATA({ id = 1, name = "n" }):ON_DUPLICATE_KEY_UPDATE({ score = 1 })
sqlbuilder.DELETE("user"):QUERY({ id = 1 })
```

For PostgreSQL / SQLite, upserts need the conflict target:

```lua
local b = sqlbuilder.INSERT("likes", { dialect = "postgres" })
  :DATA({ user_id = 1, like_count = 1 })
  :ON_DUPLICATE_KEY_UPDATE({ like_count = 1 }, "user_id")
-- INSERT INTO likes ("like_count", "user_id") VALUES (1, 1)
--   ON CONFLICT ("user_id") DO UPDATE SET "like_count" = EXCLUDED."like_count"
```

## Dialects

Dialects are **configuration** — the default is `ansi` (standard SQL) and no
dialect-specific features are emitted unless one is declared. Declare per
builder (trailing options table) or set the module default:

```lua
local sqlbuilder = require "lua_SQLBuilder"

-- per-instance: declared dialect adds its features (backticks, ->>, ...)
sqlbuilder.SELECT("*", { dialect = "mysql" }):FROM("user"):QUERY({ id = 1 })
-- SELECT * FROM user WHERE (`id` = 1)

-- module-wide default
sqlbuilder.set_default_dialect("postgres")
```

Built-in presets (verified in CI for `mysql`/`postgres`/`sqlite`):

| dialect | identifiers | escaping | upsert | LIMIT |
|---------|-------------|----------|--------|-------|
| `ansi` (default) | `"x"` | `''` doubling | — | `LIMIT n OFFSET m` |
| `mysql` / `mariadb` | `` `x` `` | backslash | `ON DUPLICATE KEY UPDATE` | `LIMIT n OFFSET m` |
| `postgres` | `"x"` | `''` doubling | `ON CONFLICT ... DO UPDATE` | `LIMIT n OFFSET m` |
| `sqlite` | `"x"` | `''` doubling | `ON CONFLICT ... DO UPDATE` | `LIMIT n OFFSET m` |
| `mssql` | `[x]` | `''` doubling | — | `OFFSET n ROWS FETCH NEXT m ROWS ONLY` |

For a database without a preset, copy a close preset and adjust the fields
(they are plain config: `quote_ident`, `json_path`, `escape_string`,
`render_limit`, `upsert`):

```lua
local dialect = require "lua_SQLBuilder.dialect"
dialect.dialects.oracle = dialect.dialects.ansi  -- then tweak fields
sqlbuilder.set_default_dialect("oracle")
```

## Parameter semantics

- `?` placeholders are matched positionally with parameters. A mismatch raises
  an error instead of silently producing broken SQL.
- A table parameter expands as an IN list: `WHERE("id in ?", {1,2,3})` renders
  `id in (1, 2, 3)` inline, or `id in (?, ?, ?)` with three parameters in
  prepare mode.
- `false` and `0` are valid parameter values (rendered as literals).
- Raw query fragments without placeholders (e.g. join conditions) pass through
  untouched — they are trusted SQL and are **not** escaped.

## Security

- `to_prepare()` binds parameters through your driver — the recommended path.
- `to_sql()` escapes string values per dialect (MySQL backslash style;
  PostgreSQL/SQLite single-quote doubling) so inline SQL is injection-safe
  for values. Identifiers are quoted per dialect.
- Raw query fragments you pass in (the `query` string itself) are rendered
  verbatim; never interpolate untrusted text into them.

## Testing

```
# zero-dependency local runner (needs only a Lua interpreter)
lua spec/run.lua

# busted (CI uses this)
busted --helper=spec/helpers/init.lua spec/unit spec/audit spec/production
LUA_SQLBUILDER_DB=sqlite busted --helper=spec/helpers/init.lua spec/integration
```

- `spec/unit` — golden SQL for every builder × dialect
- `spec/audit` — cross-audit invariants (determinism, idempotency, param
  alignment, escaping round-trip, no input mutation)
- `spec/integration` — executes generated SQL against real databases
  (dialect selected by `LUA_SQLBUILDER_DB`)
- `spec/production` — regression for real-world usage patterns

## License

MIT — see [LICENSE](LICENSE).
