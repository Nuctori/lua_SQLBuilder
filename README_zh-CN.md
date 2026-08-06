# lua_SQLBuilder

零依赖的 Lua SQL 构造库，支持 Lua 5.1–5.4 与 LuaJIT，多方言（MySQL / PostgreSQL / SQLite / SQL Server / 标准 ANSI），并在真实数据库上通过 CI 验证。

```lua
local sqlbuilder = require "lua_SQLBuilder"

local sql = sqlbuilder.SQLBuilder("SELECT * FROM user")
  :WHERE("id > ?", 2)
  :ORDER_BY("user"):DESC()
  :ORDER_BY("id"):ASC()
  :to_sql()
-- SELECT * FROM user WHERE (id > 2) ORDER BY user DESC, id ASC
```

## 特性

- **链式构造**：`WHERE` / `OR` / `ORDER BY` / `GROUP BY` / `HAVING` / `LIMIT` / `FOR UPDATE`，以及 `SELECT` / `UPDATE` / `INSERT` / `DELETE` 辅助对象（`QUERY`、`SET`、`DATA`、`COLS`、`VALUES`、upsert）。
- **两种输出模式**：`to_sql()` 内联渲染（含方言感知的字符串转义）；`to_prepare()` 返回占位符 SQL 与绑定参数，交给驱动执行，天然防注入。
- **方言即配置**：默认 `ansi`（标准 SQL），声明方言后才启用对应特性（反引号、`->>`、`ON DUPLICATE` 等）。内置预设：ansi / mysql / mariadb / postgres / sqlite / mssql。
- **确定性输出**：表型输入按键排序；重复渲染字节级一致（由交叉审计不变量锁定）。
- **真实验证**：CI 对六个真实数据库跑同一套集成测试——MySQL 8、PostgreSQL 16、SQLite、DuckDB、ClickHouse（HTTP 接口）与 Oracle 23c free——覆盖 Lua 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT。

## 安装

LuaRocks（发布 tag 后）：

```
luarocks install lua_SQLBuilder
```

或直接 vendor `lua_SQLBuilder/` 目录并加入 `package.path`。

## 快速开始

### 预处理（推荐）

```lua
local sql, id = sqlbuilder.SQLBuilder("SELECT * FROM user")
  :WHERE("id > ?", 2)
  :to_prepare()
-- sql: SELECT * FROM user WHERE (id > ?)
-- id:  2
```

### SELECT + QUERY + 分页

```lua
local sql = sqlbuilder.SELECT("*"):FROM("book"):QUERY({ user_id = 1, status = 1 })
  :PAGE(2):PER(10):to_sql()
-- SELECT * FROM book WHERE ("status" = 1 AND "user_id" = 1) LIMIT 10 OFFSET 10
```

`QUERY` 接受标量、布尔、`userdata`（→ `IS NULL`）与表值；表值是 JSON 路径查询：

```lua
local sql = sqlbuilder.SELECT("*", { dialect = "mysql" }):FROM("book")
  :QUERY({ user_id = 1, json = { star = 5 } }):to_sql()
-- SELECT * FROM book WHERE (`json`->>'$.star' = '5' AND `user_id` = 1)
```

### OR 分组

嵌套 OR 需要显式子构造器（保持构造灵活性）：

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
sqlbuilder.INSERT("user"):DATA({ id = 1, name = "n" })
sqlbuilder.DELETE("user"):QUERY({ id = 1 })
```

Upsert 是方言特性——需声明方言（默认 `ansi` 无单语句 upsert）：

```lua
-- mysql / mariadb
sqlbuilder.INSERT("likes", { dialect = "mysql" })
  :DATA({ user_id = 1, like_count = 1 })
  :ON_DUPLICATE_KEY_UPDATE({ like_count = 1 })

-- postgres / sqlite / duckdb：需冲突目标列
local b = sqlbuilder.INSERT("likes", { dialect = "postgres" })
  :DATA({ user_id = 1, like_count = 1 })
  :ON_DUPLICATE_KEY_UPDATE({ like_count = 1 }, "user_id")
-- INSERT INTO likes ("like_count", "user_id") VALUES (1, 1)
--   ON CONFLICT ("user_id") DO UPDATE SET "like_count" = EXCLUDED."like_count"
```

## 方言配置

方言是**配置**——默认 `ansi`（标准 SQL），未声明方言不输出任何方言特性。按构造器声明（尾参 options 表）或设置模块默认：

```lua
local sqlbuilder = require "lua_SQLBuilder"

-- 按实例声明：启用该方言的特性（反引号、->> 等）
sqlbuilder.SELECT("*", { dialect = "mysql" }):FROM("user"):QUERY({ id = 1 })
-- SELECT * FROM user WHERE (`id` = 1)

-- 模块级默认
sqlbuilder.set_default_dialect("postgres")
```

内置预设（`mysql`/`postgres`/`sqlite` 在 CI 真实验证；其余按数据库文档配置）：

| 方言 | 标识符 | 转义 | upsert | LIMIT |
| ------ | -------- | ------ | -------- | ------- |
| `ansi`（默认） | `"x"` | `''` 翻倍 | — | `LIMIT n OFFSET m` |
| `mysql` / `mariadb` | `` `x` `` | 反斜杠 | `ON DUPLICATE KEY UPDATE` | `LIMIT n OFFSET m` |
| `postgres` | `"x"` | `''` 翻倍 | `ON CONFLICT ... DO UPDATE` | `LIMIT n OFFSET m` |
| `sqlite` | `"x"` | `''` 翻倍 | `ON CONFLICT ... DO UPDATE` | `LIMIT n OFFSET m` |
| `mssql` | `[x]` | `''` 翻倍 | — | `OFFSET n ROWS FETCH NEXT m ROWS ONLY` |
| `oracle`（12c+） | `"x"` | `''` 翻倍 | — | `OFFSET n ROWS FETCH NEXT m ROWS ONLY` |
| `duckdb` | `"x"` | `''` 翻倍 | `ON CONFLICT ... DO UPDATE` | `LIMIT n OFFSET m` |
| `clickhouse` | `` `x` `` | 反斜杠 | — | `LIMIT n OFFSET m` |

JSON 算子：mysql/mariadb/ansi 用 `->>`；sqlite 用 `json_extract` + `CAST AS TEXT`；postgres 用 `->`/`->>` 链；mssql/oracle 用 `JSON_VALUE`；duckdb 用 `json_extract_string`；clickhouse 用 `JSONExtractString`。

没有预设的数据库：复制相近预设并调整字段（它们是纯配置：`quote_ident`、`json_path`、`escape_string`、`render_limit`、`upsert`）：

```lua
local dialect = require "lua_SQLBuilder.dialect"
dialect.dialects.db2 = dialect.dialects.ansi  -- 以未内置的数据库为例
sqlbuilder.set_default_dialect("db2")
```

## 参数语义

- `?` 占位符与参数按位置一一对应；数量不匹配直接报错（不再静默产出坏 SQL）。
- 表参数按 IN 语义展开：`WHERE("id in ?", {1,2,3})` 内联渲染 `id in (1, 2, 3)`，prepare 模式展开为 `id in (?, ?, ?)` 三个参数。
- `false` 与 `0` 是合法参数值（渲染为字面量）。
- 无占位符的原始片段（如 JOIN 条件）原样透传——它们是可信 SQL，**不做转义**。

## 安全

- `to_prepare()` 通过驱动绑定参数——推荐路径。
- `to_sql()` 按方言转义字符串值（MySQL/ClickHouse 反斜杠风格；PostgreSQL/SQLite/SQL Server/Oracle/DuckDB 单引号翻倍），**含 JSON 编码的表值**，内联 SQL 对参数值防注入；标识符按方言加引号并转义定界符。
- **可信片段边界**（by design，对抗性审计验证）：你传入的原始片段原样渲染、**不转义**——无占位符的 `WHERE`/`HAVING`/`OR` 查询串、`FROM`/`FIELD` 参数（可含别名/表达式）、`ORDER BY`/`GROUP BY` 参数、`PROCEDURE`。不要把不可信文本拼进其中。
- **反斜杠转义方言**（mysql/clickhouse）继承多字节字符集经典隐患（如 GBK `\xbf\x27`）：连接使用 `utf8mb4`/`utf8`，不可信输入优先 `to_prepare()`。
- 值来自用户输入时一律使用 `to_prepare()`。

## 测试

```
# 零依赖本地 runner（只需一个 Lua 解释器）
lua spec/run.lua

# busted（CI 使用）
busted --helper=spec/helpers/init.lua spec/unit spec/audit spec/production
LUA_SQLBUILDER_DB=sqlite busted --helper=spec/helpers/init.lua spec/integration
```

- `spec/unit` — 每个构造器 × 方言的 golden SQL
- `spec/audit` — 交叉审计不变量（确定性、幂等、参数对齐、转义往返、不改调用方输入）
- `spec/integration` — 对真实数据库执行生成的 SQL（方言由 `LUA_SQLBUILDER_DB` 选择）
- `spec/production` — 真实项目调用形态回归

## 许可证

MIT — 见 [LICENSE](LICENSE)。
