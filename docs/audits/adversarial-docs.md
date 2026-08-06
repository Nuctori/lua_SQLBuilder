# 文档-行为一致性审计（adversarial-docs）

审计对象：`readme.md`（EN）、`README_zh-CN.md`（ZH） vs 实际代码行为
执行环境：Lua 5.4.8（C:\msys64\ucrt64\bin\lua5.4.exe），仓库 `D:/lua/lua_SQLBuilder`
方法：逐条执行两版 README 中的每个代码示例并比对注释输出；核对 dialect.lua 预设表；运行 `lua spec/run.lua` 验证测试命令。
仓库无 `plan.md` / `progress.md`（find 无结果）；本审计只读，未修改仓库任何文件。

---

## 一、不一致清单（按严重度排序）

### F1 [doc, medium] EN readme.md:58-60 — QUERY 分页示例输出与 ansi 默认行为不符（且与 ZH 版不一致）
- 文档代码（未声明方言）：
  ```lua
  local sql = sqlbuilder.SELECT("*"):FROM("book"):QUERY({ user_id = 1, status = 1 })
    :PAGE(2):PER(10):to_sql()
  -- SELECT * FROM book WHERE (`status` = 1 AND `user_id` = 1) LIMIT 10 OFFSET 10
  ```
- 期望（EN 注释）：反引号标识符（mysql 风格）
- 实际运行：`SELECT * FROM book WHERE ("status" = 1 AND "user_id" = 1) LIMIT 10 OFFSET 10`（ansi 默认双引号；`LIMIT 10 OFFSET 10` 正确）
- ZH 版 README_zh-CN.md:49-51 同段代码注释为双引号 `("status" = 1 AND "user_id" = 1)`，与实际一致。
- 结论：EN 版注释是旧的 mysql 默认时代的残留。EN/ZH 两版注释互相矛盾。
- 建议：**改文档**——EN 注释改为双引号（与 ZH 一致）；或给代码加 `{ dialect = "mysql" }`。

### F2 [doc, medium] EN readme.md:26 — Features 声称默认方言是 MySQL，与正文和代码矛盾
- 原文：`- **Multi-dialect**: MySQL (default), PostgreSQL, SQLite — ...`
- 实际：dialect.lua:23 `M.default = "ansi"`，readme.md:109-110 自己也写 "the default is `ansi`"（ZH:19 同样）。EN 文档内部自相矛盾。
- 建议：**改文档**——去掉 "(default)" 或改为 "ansi (default)"。

### F3 [doc, medium] EN readme.md:88 / ZH README_zh-CN.md:78 — INSERT + ON_DUPLICATE_KEY_UPDATE 示例在默认 ansi 下直接报错
- 文档代码（未声明方言）：
  ```lua
  sqlbuilder.INSERT("user"):DATA({ id = 1, name = "n" }):ON_DUPLICATE_KEY_UPDATE({ score = 1 })
  ```
- 实际运行：`error: dialect 'ansi' has no upsert support (use mysql/mariadb/postgres/sqlite)`（INSERT.lua:102，to_sql 时抛出）。
- 文档自身规则（"未声明方言不输出任何方言特性"）与该示例矛盾；两版 README 均有此问题。
- 建议：**改文档**——给示例加 `{ dialect = "mysql" }` 或在注释中说明需要 mysql/mariadb 方言。（代码行为正确：ANSI 无单语句 upsert。）

### F4 [code, high] utils.lua `Make_JsonQuery` 顶层键未排序 → 输出跨进程不确定，破坏 README 确定性承诺，并导致单元测试 flaky
- 位置：lua_SQLBuilder/utils.lua `Make_JsonQuery` 顶层 `for tName, tType in pairs(query) do`（未排序；递归层是排序的）。
- 证据：
  - 同一多键 JSON 查询 `QUERY({ json = { star = 5, tags = { "x" } } })`（clickhouse 方言）在 6 个独立进程中交替输出 `star` 在前 / `tags` 在前（Lua 5.4 随机哈希种子 → `pairs()` 顺序跨进程不稳定）。
  - `spec/unit/dialect_spec.lua:77` 硬编码断言了一种顺序 → 本机 `lua spec/run.lua` 连续 5 次运行均失败：`226 passed, 1 failed, 4 pending`（FAIL clickhouse: backticks, backslash escape, JSONExtractString, ANSI limit；expected tags-first vs actual star-first，行 77）。
  - README 声称 "Deterministic: table-style inputs are key-sorted; repeated renders are byte-identical"（readme.md:30-32 / ZH:22-24）——多键 JSON 查询表不满足"按键排序"。
  - 审计测试 spec/audit/invariants_spec.lua 只用单键 JSON（`json = { star = 5 }`），同一进程内比较，未覆盖此缺口。
- 建议：**改代码**——`Make_JsonQuery` 顶层循环先 `sort_keys`（与递归层一致）；文档承诺在先，代码修正后 README 声明成立。同时解决 flaky 测试。

### F5 [doc, low] ZH README_zh-CN.md:20 — 内置预设列表不全
- 原文：`内置预设：ansi / mysql / mariadb / postgres / sqlite / mssql`
- 实际：dialect.lua 有 9 个预设：ansi / mysql / mariadb / postgres / sqlite / mssql / **oracle / duckdb / clickhouse**。
- EN readme.md:113 只写 "Built-in presets (verified in CI for mysql/postgres/sqlite)"，未枚举，无冲突。
- 建议：**改文档**——补全列表或改为 "包括"。

### F6 [doc, low] EN readme.md:137-143 / ZH:126 — "没有预设的数据库"示例用了 oracle，但 oracle 已有预设
- 示例 `dialect.dialects.oracle = dialect.dialects.ansi` 能运行（已验证），但会**静默覆盖**代码中已有的真 oracle 预设（render_limit_mssql + json_path_oracle）。
- 建议：**改文档**——改用确实不存在的方言名（如 db2），或注明 oracle/duckdb/clickhouse 已有预设。

### F7 [code-comment, low] init.lua:16 — 过期注释
- `-- Supported: "mysql" (default), "postgres", "sqlite".` 实际默认是 ansi，支持 9 种。
- 建议：**改注释**。

### F8 [code-message, low] INSERT.lua:102 — 错误消息的方言清单不完整
- `(use mysql/mariadb/postgres/sqlite)`：mssql 也是内置预设且无 upsert 却没列出；duckdb 有 upsert 也没列出。
- 建议：**改错误消息**（可改为 `(use mysql/mariadb/postgres/sqlite/duckdb)` 或引用 resolve 的内置清单）。

### F9 [trivial] spec/run.lua:4 — 头注释与默认目录不符
- 注释 `Default dirs: spec/unit spec/production spec/integration`，代码默认实际含 `spec/audit`。
- 建议：**改注释**。

---

## 二、已验证为真的声明（PASS）

| 声明 | 证据 |
|---|---|
| 默认方言 ansi（两版 README Dialects 节） | dialect.lua:23；`get_default_dialect()` → "ansi" |
| `set_default_dialect` / `get_default_dialect` 存在且生效 | init.lua:22-28；设置 postgres 后新构造器用双引号；未知名 assert 报错 |
| 按实例 `{ dialect = "mysql" }` 覆盖默认 | SELECT 输出 `` (`id` = 1) `` ✓ |
| 方言矩阵表 6 行 × 4 字段全对 | quote_ident：ansi/pg/sqlite `"x"`、mysql/mariadb 反引号、mssql `[x]`；escape_string：ansi 系 `''` 翻倍、mysql 反斜杠（含 \0\b\n\r\t\Z）；render_limit：`LIMIT n OFFSET m`、mssql `OFFSET n ROWS FETCH NEXT m ROWS ONLY`（offset=0 时输出 `OFFSET 0 ROWS...`）；upsert：ansi/mssql=nil、mysql/mariadb=`ON DUPLICATE KEY UPDATE`、pg=`ON CONFLICT...EXCLUDED`、sqlite=`ON CONFLICT...excluded` —— 全部与 dialect.lua 逐项一致 |
| json_path 每方言存在 | mysql `->>'$.a.b'`、pg 操作符链 `"t"->'a'->>'b'`、sqlite `CAST(json_extract("t", '$.a.b') AS TEXT)`、mssql `JSON_VALUE([t], '$.a.b')`、ansi `"t"->>'$.a.b'` |
| 示例 1/2/3b/4/6/7 输出与注释一致 | 逐条运行 PASS（含 `WHERE (id > 2) ORDER BY user DESC, id ASC`、prepare `(id > ?)`+参数 2、pg upsert 全串、mysql JSON 路径 `'5'`） |
| 参数语义 | `?` 位置匹配、数量不匹配报错（`missing parameter for placeholder 2`）；IN 内联 `(1, 2, 3)`、prepare `(?, ?, ?)`+3 参数；`false`/`0` 渲染为字面量；无占位符片段原样透传（JOIN 示例） |
| 安全声明 | mysql `O\'Brien`、pg `O''Brien`；标识符按方言加引号；prepare 保留 `?` 绑定 |
| QUERY 值类型 | scalar ✓、boolean → `"active" = true` ✓、userdata → `"deleted_at" is NULL` ✓（io.tmpfile 实测）、table → JSON 路径 ✓ |
| `lua spec/run.lua` 可执行 | 运行成功但**间歇失败**（见 F4）：226 passed / 1 failed / 4 pending；integration 无驱动时优雅 pending（lsqlite3 缺失） |

## 三、命令可执行性

- `lua spec/run.lua` — ✅ 本机已执行（Lua 5.4.8）；但受 F4 flaky 影响当前退出码为 1。
- `busted --helper=spec/helpers/init.lua spec/unit spec/audit spec/production` — ⚠️ 本机未安装 busted，无法执行；命令与 `.github/workflows/ci.yml:49` 完全一致，CI 实际使用 → 可信但本地未验证。
- `LUA_SQLBUILDER_DB=sqlite busted --helper=spec/helpers/init.lua spec/integration` — ⚠️ 同上；与 ci.yml:72-74 一致；注意这是 POSIX 环境变量语法（CI/Ubuntu 场景），Windows cmd 下原样不可用。

## 四、EN/ZH 一致性

- 除 F1（EN 反引号 vs ZH 双引号）与 F2（EN 独有 "MySQL (default)" 声明）外，两版示例代码、输出注释、API 说明完全一致；F3 两版同病。
- 其余示例（1/2/3b/4/6/7）两版给出相同输出，且与实际一致。

## 五、建议汇总

- 改文档：F1、F2、F3、F5、F6（EN/ZH 同步修改）。
- 改代码：F4（utils.lua 顶层排序，顺带修复 flaky 测试与 README 确定性承诺）。
- 改注释/消息：F7、F8、F9。
