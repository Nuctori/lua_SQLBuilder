# 文档-代码一致性审计报告（lua_SQLBuilder）

审计范围：readme.md / README_zh-CN.md 方言矩阵与示例、dialect.lua 实际配置、CI（.github/workflows/ci.yml）、CHANGELOG.md、rockspec、安全章节声明。
执行环境：Lua 5.4.6（`C:\Users\Nuctori\AppData\Local\Programs\Lua\bin\lua.exe`），`LUA_PATH="./?.lua;./?/init.lua;;"`。
注：plan.md / progress.md 不存在，未读取。

## 结论概览

- 9 预设方言矩阵的标识符/转义/upsert/LIMIT 列与 dialect.lua 实际配置**逐项一致**（唯 oracle 大写行为未在文档体现，见 #2）。
- 文档示例**除 EN JSON 示例外全部与 Lua 5.4.6 实际输出一致**（header、prepare、分页、OR、upsert、IN 列表、false/0、userdata→IS NULL）。
- 安全章节 4 项声明全部与代码行为一致（实测验证）。
- 主要不一致集中在：**CHANGELOG/rockspec 未收录新方言与新集成**、**EN 版 JSON 示例缺方言声明**、**oracle 大写标识符未文档化**、**两版 readme 内部"六库 CI"与脚注矛盾**。

## 不一致清单（位置 + 期望 vs 实际 + 处置）

### #1 [medium] readme.md EN 版 JSON 示例缺方言声明（示例输出与注释不符）
- 位置：readme.md:76-78
  ```lua
  local sql = sqlbuilder.SELECT("*"):FROM("book")
    :QUERY({ user_id = 1, json = { star = 5 } }):to_sql()
  -- SELECT * FROM book WHERE (`json`->>'$.star' = '5' AND `user_id` = 1)
  ```
- 期望（注释）：反引号标识符；实际（Lua 5.4.6 执行，默认 ansi）：`SELECT * FROM book WHERE ("json"->>'$.star' = '5' AND "user_id" = 1)`（双引号）。
- 对比：README_zh-CN.md:57-59 同一示例带 `{ dialect = "mysql" }`，输出与注释一致。EN 版漏了 `{ dialect = "mysql" }`。
- 处置：**改文档**（EN 示例补 `{ dialect = "mysql" }`，或注释改双引号）；同时消除 EN/ZH 不一致。

### #2 [medium] oracle 大写标识符未文档化
- 位置：readme.md 方言矩阵 oracle 行（`| oracle (12c+) | "x" | ...`）、README_zh-CN.md 同位置；两版 JSON 算子段 mssql/oracle 用 JSON_VALUE。
- 期望（文档）：oracle 标识符 `"x"`；实际（dialect.lua:36-39 `quote_ident_oracle` 执行 `name:upper()`）：`SELECT * FROM user WHERE ("ID" = 1)`、`JSON_VALUE("JSON", '$.star')`。即所有被引标识符转大写。
- 佐证：spec/unit/dialect_spec.lua:48-55 明确断言大写行为（golden：`"ID"`、`JSON_VALUE("JSON", ...)`），代码为有意设计（注释说明 Oracle 未加引号 DDL 存大写）。文档矩阵却写 `"x"`，未提大写转换。
- 处置：**改文档**（矩阵 oracle 行标注 UPPERCASE，如 `"X"`（大写），或在矩阵下加注）。

### #3 [medium] CHANGELOG 未收录新方言与新集成
- 位置：CHANGELOG.md [Unreleased] Added 首条 "Full CI matrix: Lua 5.1/5.2/5.3/5.4/LuaJIT against real SQLite, MySQL 8 and PostgreSQL 16"；全文无 oracle/duckdb/clickhouse。
- 期望：与 readme "CI runs the same integration suite against six real databases" 一致；实际：ci.yml 已有 integration-duckdb / integration-clickhouse / integration-oracle 任务，dialect.lua 已有 9 预设，unit 已有对应 golden。
- 处置：**改文档**（CHANGELOG 补 Added：oracle/duckdb/clickhouse 预设 + 三个真实库 CI 集成）。

### #4 [medium] rockspec 描述过时
- 位置：lua_SQLBuilder-0.2.0-1.rockspec description.summary "(MySQL / PostgreSQL / SQLite)"、detailed "Verified against real MySQL 8, PostgreSQL 16 and SQLite on CI"。
- 期望：与 readme 六库声明一致；实际：三库表述（模块清单未含新 dialect 文件——但方言均在 dialect.lua 内，无新增文件，此项仅描述过时）。
- 处置：**改文档**（rockspec summary/detailed 更新方言与 CI 清单）。

### #5 [medium] 两版 readme 内部矛盾：六库 CI 声明 vs 矩阵脚注
- 位置：readme.md:30-33（"Verified: CI runs the same integration suite against six real databases…"）与 readme.md:135（"Built-in presets (verified in CI for mysql/postgres/sqlite; the rest are configuration per the database documentation)"）；README_zh-CN.md 同构。
- 实际：ci.yml 六个库都有 integration 任务（oracle 为 best-effort 安装、仅 5.4；clickhouse 仅 5.1/5.4；duckdb 5.1-5.4）。脚注 "其余按文档配置" 与六库验证声明矛盾。
- 处置：**改文档**（更新脚注，如 "verified in CI for mysql/postgres/sqlite/duckdb/clickhouse/oracle；oracle/clickhouse 覆盖的 Lua 版本较少"）。

### #6 [low-medium] "six databases on Lua 5.1/5.2/5.3/5.4/LuaJIT" 夸大 CI 矩阵
- 位置：readme.md:33-34、README_zh-CN.md 特性段（"覆盖 Lua 5.1 / 5.2 / 5.3 / 5.4 / LuaJIT"）。
- 实际（ci.yml）：oracle 仅 Lua 5.4；clickhouse 仅 5.1/5.4；duckdb/sqlite/mysql/postgres 为 5.1–5.4（无 LuaJIT）；LuaJIT 只跑 unit/audit/production。字面理解"六库全矩阵"不成立。
- 处置：**改文档**（按库注明 Lua 版本覆盖，或将 LuaJIT 限定于单元测试）。

### #7 [low] ZH readme 特性/导语遗漏新方言
- 位置：README_zh-CN.md:3（"多方言（MySQL / PostgreSQL / SQLite / SQL Server / 标准 ANSI）"）、:20（"内置预设：ansi / mysql / mariadb / postgres / sqlite / mssql"）。
- 期望：与矩阵（9 预设）及 EN 版一致；实际：缺 oracle / duckdb / clickhouse。
- 处置：**改文档**。

### #8 [low] EN 自定义方言示例用内置预设做"无预设"示例
- 位置：readme.md:141-143 `dialect.dialects.oracle = dialect.dialects.ansi`。
- 问题：引导语为 "For a database **without** a preset"，示例却原地覆盖**内置** oracle 预设（进程内破坏该预设行为）；ZH 版用 db2（正确示范）。EN/ZH 不一致。
- 处置：**改文档**（EN 示例改用 db2，与 ZH 对齐）。

### #9 [low] init.lua 注释过时（代码注释，非用户文档）
- 位置：lua_SQLBuilder/init.lua:20 `-- Supported: "mysql" (default), "postgres", "sqlite".`
- 实际：默认方言为 ansi，支持 9 个预设（dialect.lua M.default = "ansi"）。
- 处置：**改代码注释**（更新为 "ansi (default)" + 完整列表）。

### #10 [info] 版本编排：tag 与 CHANGELOG 不匹配
- 位置：readme.md:38 "LuaRocks (once a release is tagged)"；rockspec tag v0.2.0；CHANGELOG 无 [0.2.0] 章节。
- 实际：git tag v0.2.0 已存在（2026-08-06，commit acf78f0），但落后 HEAD 25 个提交（全部新方言/CI 工作均在 tag 之后）；CHANGELOG 新方言内容仍挂在 [Unreleased]。
- 处置：**文档编排**（重打/前移 v0.2.0 tag，或 CHANGELOG 补 [0.2.0] 章节；readme 措辞更新）。

### #11 [info] 仓库根残留 Windows 文件 `nul`
- 位置：D:\lua\lua_SQLBuilder\nul（34 字节，GBK 错误消息内容，未跟踪）。
- 处置：非文档问题，建议删除（git status 不显示，属本地残留）。

## 核验通过项（逐项实测）

1. **方言矩阵 9 预设 × 4 列**：与 dialect.lua 全部一致（ansi/mysql/mariadb 反引号+反斜杠+ON DUPLICATE；postgres/sqlite/duckdb 双引号+''翻倍+ON CONFLICT；mssql [x]+OFFSET/FETCH；clickhouse 反引号+反斜杠+无 upsert；oracle LIMIT/转义/JSON 正确，仅大小写未注明见 #2）。duckdb upsert 用 `excluded` 小写 ref（继承 sqlite 预设），与 DuckDB 官方语法一致。
2. **JSON 算子段**：mysql/mariadb/ansi `->>`；sqlite `CAST(json_extract(...) AS TEXT)`；postgres `->`/`->>` 链；mssql/oracle `JSON_VALUE`；duckdb `json_extract_string`；clickhouse `JSONExtractString` —— 与 dialect.lua 一一对应。
3. **示例实测**（Lua 5.4.6）：header 示例、to_prepare、PAGE(2):PER(10)（ansi/mysql）、OR 分组、postgres upsert、IN 列表内联/prepare、false/0 字面量、userdata→`is NULL`、clickhouse JSONExtractString(`json`, 'star') —— 全部与注释一致（除 #1）。
4. **安全章节**：
   - 转义方言清单：mysql/clickhouse 反斜杠（`'O\'Brien'`），postgres/sqlite/mssql/oracle/duckdb/ansi 单引号翻倍（`'O''Brien'`）——实测一致；
   - JSON 编码表值转义：`QUERY({json={star="O'Brien"}})` 输出 `'O\'Brien'`（mysql）/`'O''Brien'`（ansi）——实测一致；
   - 标识符引号+定界符转义：mysql `` `weird``name` ``、ansi `"weird"name"→""`、mssql `]→]]`、oracle 大写+`""`——实测一致；
   - trusted-fragment boundary：FROM 原生串（含 JOIN 表达式）、无占位符 WHERE、ORDER BY、PROCEDURE 原样透传不转义——实测一致；GBK 反斜杠隐患声明与 escape_mysql 行为相符（不转义高字节）。
5. **测试**：`lua spec/run.lua spec/unit spec/audit spec/production` → 235 passed, 0 failed。oracle/duckdb/clickhouse 预设均有单元 golden 断言（spec/unit/dialect_spec.lua:45-92）。
6. **CI 声明**：ci.yml 确有 6 个库的 integration 任务（mysql:8.0、postgres:16、sqlite、duckdb v1.5.5、clickhouse 24.8 HTTP、oracle-free 23-slim），"Oracle 23c free / ClickHouse over HTTP" 表述属实（版本覆盖问题见 #6）。

## 处置汇总

- 改文档：11 项中 9 项（#1-#8 用户文档，#10 编排）；#9 改代码注释；#11 清理残留。
- 改代码：无（未发现代码与文档冲突且代码错误的情况；oracle 大写、clickhouse/duckdb 行为均被单元测试锁定为有意设计）。

---

## 复跑验证（revival run，2026-08-06）

仓库状态：HEAD=126a9ca（与首次审计一致），工作树干净，无代码变动；以下结论在二次会话中重新实证。

### 执行命令与结果
1. `lua spec/run.lua`（Lua 5.4.6，`LUA_PATH="./?.lua;./?/init.lua;;"`）→ **235 passed, 0 failed, 4 pending**（4 pending 为 integration 套件因本机无 lsqlite3 驱动跳过，CI 中由真实库覆盖）；exit 0。
2. `lua -e` 文档示例批（26 项断言）→ **25 PASS / 1 FAIL**：
   - PASS：header、to_prepare、分页(ansi/mysql)、ZH JSON 示例、OR 分组、postgres/duckdb upsert、oracle 引号/JSON/LIMIT、duckdb/clickhouse JSON、mssql LIMIT、ansi/mysql/clickhouse 字符串转义、JSON 表值转义、IN 列表、false/0、userdata→IS NULL、trusted-fragment 透传（FROM 表达式/原生 WHERE/ORDER BY/PROCEDURE）、标识符定界符转义（mysql 反引号翻倍、mssql `]]`）。
   - FAIL：仅 **EN JSON 示例按原文执行**（readme.md:76-78 无方言声明 → 实际 `"json"->>'$.star'` 双引号，注释为反引号）——即发现 #1，文档问题，代码正确。
3. 方言矩阵 EN/ZH 逐行 diff → 内容一致（仅译文措辞差异：`"x"`/反引号/`[x]`/`''`/`LIMIT n OFFSET m`/`OFFSET n ROWS FETCH NEXT m ROWS ONLY`/`ON DUPLICATE KEY UPDATE`/`ON CONFLICT ... DO UPDATE` 全部相同）。

### 结论
首次审计的 11 项发现全部复核成立，无新增、无撤销。处置建议不变：9 项改文档、1 项改代码注释（init.lua:20）、1 项仓库残留清理（`nul`）。
