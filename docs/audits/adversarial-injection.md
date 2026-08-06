# 对抗性注入审计报告 — LuaSQLBuilder (D:/lua/lua_SQLBuilder)

**审计方式**：只读。本机无 Lua 解释器（CI 在 Ubuntu 上跑 Lua 5.1–5.4），因此将 `dialect.lua` / `utils.lua` / `sql_comp/WHERE.lua` / `UPDATE.lua` / `INSERT.lua` / `json.lua` 的转义逻辑做了 1:1 字节级移植仿真（`escape_mysql`、`escape_ansi`、`json.encode`、`render_value`、`render_inline`、`Make_JsonQuery`、`quote_ident`），逐条生成实际 SQL 输出后按目标 DB 语义判定。转义函数全部是确定性字符映射循环，移植可精确复现 Lua 输出（仿真产物：`.pi-subagents/artifacts/work/sqli_stdout.txt`，369 行）。
审计范围：mysql / mariadb / postgres / sqlite / ansi（另及 mssql/oracle/duckdb/clickhouse 的共享路径）。payload 集：单引号、双引号、反斜杠、`--`、`#`、`/* */`、NUL、`\n`、CRLF、Unicode 引号（U+2018/2019/FF07）、`%n`、分号多语句、SLEEP(5)、CONCAT、大小写混淆、GBK 宽字节（`\xbf\x27`、`\xbf\x5c`）、`\u0027`、`\x27`、`' OR '1'='1`。

---

## Review（总体结论）

值转义主干（WHERE 标量、IN 列表、INSERT VALUES/DATA 字符串与表值、JSON 查询值）在默认字符集下是安全的；但存在 **1 个可直接利用的 CRITICAL 注入**（table→JSON 值不经 SQL 转义）、4 个 HIGH（JSON 路径 key、标识符引号突破、mysql 多字节字符集绕过、原始拼接位置）、3 个 MEDIUM、1 个 LOW，以及 to_sql/to_prepare 不一致问题。

### Correct（已验证安全，含证据）

- WHERE 标量参数（`sql_comp/WHERE.lua:render_scalar`）：`O'Brien` → ansi `'O''Brien'`、mysql `'O\'Brien'`，四方言均不能逃出字面量。`\u0027`/`\x27` 在 mysql 被 `\\` 化（`\\u0027` → MySQL 解析为字面 `\u0027`，不产生引号）；ansi 方言反斜杠为字面量。**`\u0027` 不构成绕过**。
- WHERE IN 列表（`render_inline` table 分支）：逐元素转义 → `IN (1, '...')` 安全。
- INSERT VALUES / DATA 表值：先 `json.encode` 预编码、再经 `render_value` 的**字符串**分支转义 → `'{"k":"O''Reilly"}'` 安全（与既有集成测试 `spec/integration/injection_spec.lua` 一致，该测试只覆盖了 INSERT/WHERE 两条路径）。
- JSON 查询字符串**值**：`Make_JsonQuery` 以 `= ?` 参数绑定，安全。
- 注释（`--`/`#`/`/* */`）、换行、CRLF、分号、SLEEP/CONCAT/大小写混淆：一旦进入字符串字面量即为纯数据，不构成注入。
- `%n` 格式串：库内 `string.format` 的格式串全部是常量，用户值只作为 `%s` 参数传入，`%n` 不被解释。
- postgres/sqlite 的 ON CONFLICT upsert：只渲染 `col = EXCLUDED.col`，不渲染用户值，安全。
- `PAGE`/`PER`：`tonumber` + assert，安全。
- Unicode 弯引号/全角引号（U+2018/U+2019/U+FF07）：不是任何方言的字符串定界符，安全。

---

## 漏洞清单（按严重度排序）

### CRITICAL-1 — `render_value` 的 table→JSON 分支不做 SQL 转义（UPDATE SET / mysql upsert 值注入）

**位置**：`lua_SQLBuilder/utils.lua:68-69`（`if t == "table" then return fmt("'%s'", get_json().encode(v))`，缺 `dialect.escape_string`）
**调用点**：`lua_SQLBuilder/UPDATE.lua:82`（`SET` 表模式 to_sql）、`lua_SQLBuilder/INSERT.lua:94`（mysql upsert，且 `INSERT.lua:124-131` 的 `PrepareTableOperator` 同样调用 `__renderUpsert` → **prepare 模式也注入**）
**受影响方言**：全部（UPDATE SET）；mysql/mariadb（upsert）。
**根因**：vendored `json.lua` 的 `encode_string` 只转义 `"`、`\` 和控制字符，**不转义单引号**（`json.lua` 中 `val:gsub('[%z\1-\31\\"]', escape_char)`）。JSON 文本里的 `'` 原样进入 `'...'` SQL 字面量。

**复现（实际生成 SQL）**：
```lua
local U = require("lua_SQLBuilder.UPDATE")
-- UPDATE SET 表模式（值里的单引号突破 JSON 与 SQL 双层字面量）
print(U("users", {dialect="sqlite"}):SET({bio = {text = "x' OR 1=1 -- "}}):WHERE("id = ?", 1):to_sql())
-- => UPDATE users SET "bio" = '{"text":"x' OR 1=1 -- "}' WHERE id = 1
--                                      ^ 字符串在此闭合，OR 1=1 -- 成为可执行 SQL

-- mysql ON DUPLICATE KEY UPDATE（to_sql 与 to_prepare 均注入）
local I = require("lua_SQLBuilder.INSERT")
print(I("users", {dialect="mysql"}):COLS("id"):VALUES({1}):ON_DUPLICATE_KEY_UPDATE({meta = {k = "'; DROP TABLE users; -- "}}):to_sql())
-- => INSERT INTO users (`id`) VALUES (1) ON DUPLICATE KEY UPDATE `meta` = '{"k":"'; DROP TABLE users; -- "}'
```
**判定**：四方言的 `semicolon_drop`/`sleep_fn`/`or_1_eq_1` 等全部 payload 均突破；`-- ` 注释吞掉尾部，多语句可执行 `DROP TABLE`。
**修复**：`render_value` table 分支改为 `return fmt("'%s'", dialect.escape_string(get_json().encode(v)))`；并注意与 to_prepare 的存储语义一致（prepare 绑定的是原始 JSON 文本）。更稳妥：文档明确 to_sql 内联模式仅限受信值，生产一律 to_prepare（但 upsert 表值两模式都要先修）。

---

### HIGH-2 — JSON 查询路径 key 注入（Make_JsonQuery，全方言）

**位置**：`lua_SQLBuilder/utils.lua:Make_JsonQuery`（path 原样拼接）→ `lua_SQLBuilder/dialect.lua` 各 `json_path_*`（mysql/ansi/sqlite/mssql/oracle/duckdb 用 `'$.%s'` 单引号包路径；postgres 用 `->'%s'`/`->>'%s'` 单引号包 key）。
**根因**：JSON 路径段不做转义，key 中的 `'` 直接闭合单引号字面量。
**复现**：`SELECT:QUERY({["profile' OR '1'='1"] = 1})` →
```
mysql    SELECT * FROM t WHERE `doc`->>'$.profile' OR '1'='1' = '1'
postgres SELECT * FROM t WHERE "doc"->>'profile' OR '1'='1' = '1'
sqlite   SELECT * FROM t WHERE CAST(json_extract("doc", '$.profile' OR '1'='1') AS TEXT) = '1'
```
**判定**：`OR '1'='1'` 使 WHERE 恒真 → 过滤条件绕过；mysql 路径下可继续扩展为任意语句。
**修复**：路径 key 白名单校验（`^[A-Za-z0-9_]+$`）或按方言对 `'` 加倍/拒绝；tableName 参数同样需要校验（见 HIGH-5）。

---

### HIGH-3 — 标识符引号突破（quote_ident 不转义引号字符）

**位置**：`lua_SQLBuilder/dialect.lua` `quote_ident_mysql`（`` `%s` ``）、`quote_ident_ansi`（`"%s"`）、`quote_ident_mssql`（`[%s]`）；消费点 `SELECT.lua:QUERY`/`DELETE.lua:QUERY`（field key）、`INSERT.lua:COLS`、`INSERT.lua:__renderUpsert` 的 conflictCols、`json_path_*` 的 tableName。
**复现**：`SELECT:QUERY({["name` OR 1=1 -- "] = 1})`（mysql）→
```
WHERE `name` OR 1=1 -- ` = '1'   -- `` `name` `` 真值 OR 1=1 → 条件恒真，过滤绕过
```
ansi/postgres/sqlite 用 `"name" OR 1=1 -- " = ?` 同理；mssql 用 `]`。
**判定**：标识符来自攻击者输入（动态过滤 API 的字段名）时构成注入。
**修复**：quote_ident 内对定界符转义（mysql `` ` ``→`` `` ``、ansi `"`→`""`、mssql `]`→`]]`），或对标识符做 `^[A-Za-z_][A-Za-z0-9_]*$` 校验。

---

### HIGH-4 — mysql 反斜杠转义的 GBK/多字节字符集绕过（mysql/mariadb/clickhouse）

**位置**：`lua_SQLBuilder/dialect.lua:escape_mysql`（字符级 `\'` 转义，无字符集感知）。
**复现**：连接字符集为 GBK（或 GB2312/GB18030/BIG5）时，payload `\xbf\x27 OR 1=1 -- `（0xBF = GBK 首字节）：
```
转义后: \xbf\' OR 1=1 --    （字节：BF 5C 27 ...）
GBK 解析: 0xBF 0x5C 组成一个合法汉字 → 0x27 是未被转义的字符串终结符 → OR 1=1 -- 执行
```
**判定**：这是经典 `mysql_real_escape_string` 时代已被广泛利用的宽字节注入。库在 Lua 侧按字节转义，与连接字符集无关，无法自愈。UTF-8/utf8mb4 连接下 0xBF 是非法字节 → MySQL 报 1300 错误（DoS，非注入），所以**实际可利用性取决于部署字符集**；本项目面向中文市场，GBK 部署现实存在。INSERT VALUES/UPDATE/upsert/WHERE 所有值位置均受影响。
**修复**：无法在库内修复 —— 文档明确声明 to_sql 内联模式依赖连接字符集与 SQL_MODE；生产环境强制参数化（to_prepare 绑定值不受字符集影响）。如必须内联，连接需 `SET NAMES utf8mb4` 且校验值合法 UTF-8。

---

### HIGH-5 — 原始拼接位置：tableName / FROM / SELECT fields / ORDER BY / GROUP BY / PROCEDURE（by-design，审计列明）

**位置**：`SELECT.lua:25-27`（`SELECT %s FROM %s`，fields/froms 原样 concat）、`UPDATE.lua:84`、`DELETE.lua:14`、`INSERT.lua:102/124`（`INSERT INTO %s`）、`SQLBuilder.lua` ORDER_BY/GROUP_BY/PROCEDURE（原样透传）、`sql_comp/ORDER.lua:to_sql`、`sql_comp/GROUP.lua:to_sql`。
**复现**：
```
SELECT * FROM users WHERE 1=1; DROP TABLE users; --        （tableName = "users WHERE 1=1; DROP TABLE users; -- "）
SELECT * FROM t ORDER BY name DESC; DROP TABLE users; --   （ORDER_BY("name DESC; DROP TABLE users; -- ")）
SELECT * FROM t PROCEDURE CALL p(); DROP TABLE x; --       （PROCEDURE 原样）
```
**判定**：这些参数被 API 语义假定为开发人员提供的常量；一旦来自攻击者（动态表名/排序字段），即完整多语句注入。这是设计使然，但文档未给出任何警告。
**修复**：对 tableName/fields/order 增加标识符校验（`^[A-Za-z_][A-Za-z0-9_$.]*$`）或强制 quote_ident；PROCEDURE 文档标注"仅受信输入"。

---

### MEDIUM-6 — mysql `NO_BACKSLASH_ESCAPES` 模式不兼容

`escape_mysql` 用 `\'` 转义；该 SQL_MODE 下反斜杠是字面量，`'a\'` 中 `'` 直接终结字符串 → `OR 1=1 --` 成为代码。依赖服务器配置，库不可感知。修复：文档声明 + 推荐参数化。

### MEDIUM-7 — postgres `standard_conforming_strings=off` 时可绕过 ansi 转义

该模式下反斜杠是转义符：值 `\' OR 1=1 -- ` 经 `escape_ansi`（只加倍 `'`）→ `\'' OR 1=1 -- ` → `\`+`'` 被解析为转义引号、下一个 `'` 闭合字符串 → 注入。默认 ON 时安全；配置依赖。修复：文档声明 + 推荐参数化。

### MEDIUM-8 — `LIMIT()` 参数无类型校验

`SQLBuilder.lua:LIMIT` → `sql_comp/LIMIT.lua:add` 原样存储，`render_limit_ansi` 直接 `tostring`。`LIMIT("1; DROP TABLE users; -- ")` → `LIMIT 1; DROP TABLE users; --`。`PAGE/PER` 已 tonumber 校验，但裸 `LIMIT` 不校验。修复：`tonumber` + assert（与 PAGE 一致）。

### LOW-9 — ansi 方言 NUL 字节直通（解析截断 DoS）

`escape_ansi` 不处理 `\0`；postgres/sqlite 的 SQL 文本以 C 字符串解析，字面量内 NUL 会截断语句 → 语法错误/语句截断（不能注入，因 NUL 之后的内容被丢弃，但可造成 DoS/语义混乱）。mysql 已转义为 `\0`。修复：ansi 也转义 `\0` 或拒绝。

---

## to_sql vs to_prepare 不一致清单（判定标准 3）

1. **UPDATE SET 表值（JSON）**：to_sql 注入（CRITICAL-1）；to_prepare 绑定参数安全。**不一致且 to_sql 可注入**。
2. **mysql upsert 表值（JSON）**：to_sql 与 to_prepare 都走 `__renderUpsert` 内联渲染，**两模式均注入**（无 prepare 逃生通道，需直接修复）。
3. **UPDATE SET 布尔值**：to_sql 渲染 `= true`（字面量）；to_prepare 绑定 `"true"` 字符串——语义漂移（MySQL tinyint 接受，postgres boolean 列绑定字符串可能被驱动拒绝）。低危。
4. **INSERT prepare 布尔值**：`__getPrepareInsertValue` 把 boolean `tostring` 后作为参数绑定（`"true"`/`"false"` 字符串），与 to_sql 的 `true`/`false` 字面量不一致。低危。

## 其他 Note

- **WHERE/HAVING/OR 的 query 片段是原始 SQL 透传**（`sql_comp/WHERE.lua:add` 原样保存；0 占位符条件在 `to_sql`/`to_prepare` 中原样拼接）。这是全库风险面最大的 API：任何攻击者可影响的字符串被当作 query 参数传入即直接注入。文档应显著警告。
- 占位符计数是纯文本 `%?` 统计：query 字符串字面量内的 `?`（如 `name = '?'`）或 postgres 的 `??` 会造成占位符错位（参数被拼进字符串内部）。非注入，但属正确性隐患。
- `utils.lua` 的旧版 `escape_map`（含 `"` → `\"`）与 `dialect.lua` 的 `mysql_escape_map`（不含 `"`）不一致；两套转义并存，建议统一（`"` 在 `'...'` 语境下无利用价值，但消除分歧避免未来误用）。
- 现有测试缺口：`spec/integration/injection_spec.lua` 只覆盖 INSERT VALUES / WHERE 标量；`spec/unit/utils_spec.lua:33` 对 `render_value({k=1})` 只断言了无引号场景。**table→JSON 值（UPDATE SET / upsert）、JSON 路径 key、标识符引号、GBK 宽字节均无测试**。

---

## 建议修复优先级

1. `utils.lua:68-69` 一行修复（escape_string 包裹 JSON）→ 关闭 CRITICAL-1。
2. `Make_JsonQuery` 路径 key 校验 + `quote_ident` 转义定界符 → 关闭 HIGH-2/3。
3. 文档：to_sql 内联模式安全前提（连接字符集 utf8mb4、默认 SQL_MODE、参数来自受信源）；生产推荐 to_prepare。
4. `LIMIT` 加 tonumber 校验；ansi 转义 NUL。
5. 补注入回归测试覆盖上述路径。

## 验证命令

- `python .pi-subagents/artifacts/work/sqli_sim.py` → 通过（369 行生成 SQL，evidence 见 `sqli_stdout.txt`）
- `lua spec/run.lua` → 未运行（本机无 Lua；CI 在 Ubuntu 跑 Lua 5.1–5.4，转义逻辑为纯字节循环，移植仿真逐字节等价）
