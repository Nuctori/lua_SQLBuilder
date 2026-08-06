# 集成测试与 harness 交叉审计报告（lua_SQLBuilder）

范围：`spec/integration/roundtrip_spec.lua`、`spec/integration/json_spec.lua`、`spec/integration/upsert_spec.lua`、`spec/helpers/db.lua`、`spec/helpers/fixtures.lua`、`.github/workflows/ci.yml`，以及为核对断言而审阅的 SQL 生成层（`lua_SQLBuilder/dialect.lua`、`sql_comp/*.lua`、`utils.lua` 等）。

任务上下文文件 `plan.md` / `progress.md` 在仓库中不存在（无影响，已按实际文件审计）。

验证方法：本地 sqlite3 3.50.6 实测库生成 SQL；拉取并核对 lsqlite3（LuaDist）、pgmoon（v1.10.0/v1.17.0/master）、docker-library/mysql 8.0 entrypoint 源码。

---

## P0 — 阻断（对应 CI 作业必红）

### P0-1 [db.lua] pgmoon 不支持 `?` 占位符，PG 上全部 prepared-path 测试失败

- 位置：`spec/helpers/db.lua:149`（注释声称 “supports ? binding (converted to $n)”）——**该注释与实际行为不符**。
- 证据（已核对 pgmoon 源码，v1.10.0 与 v1.17.0/master 一致）：
  - pgmoon `query(sql, ...)` 带参数时走 `extended_query`，把**原始 SQL 原样放进 PostgreSQL Parse 消息**；`pgmoon/init.lua` 全文无任何 `?`→`$n` 转换（`grep "'?'"` 零命中），其自带测试与 README 全部使用 `$1` 占位符。
  - PostgreSQL 预编译语句只接受 `$n`，Parse 阶段遇到 `?` 直接报 “syntax error at or near '?'”。
- 受影响测试（PG 作业全部失败）：
  - `roundtrip_spec.lua:55-62`（parity）：`conn:query(prep_sql, p)` → pgmoon 返回 `nil,err` → 落入 P0-2 的误判 → `ipairs(nil)` 崩溃。
  - `roundtrip_spec.lua:90-98`（INSERT prepare）：`conn:exec(sql, unpack(row))` 静默“成功”（SQL 从未执行），后续 `SELECT ... WHERE id = 99` 为 0 行 → 断言 `"O'Brien"` 失败。
  - `json_spec.lua:55-65`（to_prepare parity）：同 parity 崩溃。
- 修正建议：在 pgmoon 连接层自行做 `?`→`$n` 的顺序替换（这些受控 SQL 无字符串字面量含 `?`，简单 `gsub` 即可；通用实现需跳过字符串字面量），或让 prepared SQL 直接生成 `$n`。

### P0-2 [db.lua] pgmoon 错误返回值是 `nil`，harness 却检查 `res == false`

- 位置：`spec/helpers/db.lua:177`（exec）、`spec/helpers/db.lua:185`（query）。
- 证据：pgmoon `receive_query_result` 对 SQL 错误/连接错误均 `return nil, err`（已核对源码）。Lua 中 `nil == false` 为 false → `conn:exec` 吞掉错误并返回 `true`；`conn:query` 走到 `ipairs(nil)`（db.lua:189）直接崩溃而非返回 `nil, err`。
- 修正建议：改为 `if not res then return nil, err end`，并在 `ipairs` 前防御 `type(res) == "table"`。
- 影响：与 P0-1 叠加放大；即使单独存在，也会掩盖 PG 侧真实 SQL 错误（fixtures 的 DDL/种子失败会被静默吞掉）。

### P0-3 [dialect.lua + json_spec.lua] SQLite JSON 数字等值断言错误（json_extract 类型亲和）

- 位置：`lua_SQLBuilder/dialect.lua:30-33`（`json_path_sqlite` 渲染 `json_extract("profile", '$.star')`）；`spec/integration/json_spec.lua:28-33`（期望 2 行）、`:43-47`（期望 1 行）。
- 证据（sqlite 3.50.6 实测）：
  - `json_extract(profile,'$.star')` 对 JSON 数字 5 返回 **INTEGER 5**（`typeof`=integer）；库生成 SQL 为 `json_extract("profile", '$.star') = '5'`（Make_JsonQuery 用 `tostring(v)`，WHERE:to_sql 再包成字符串字面量）。
  - SQLite 对两个表达式比较**不套用亲和性**，按存储类排序 INTEGER < TEXT → `5 = '5'` 恒假 → **0 行**（实测确认）。
  - 实测修复验证：`CAST(json_extract(...) AS TEXT) = '5'` → 2 行；nested 同样 0→1 行。
  - `dialect.lua:24-25` 注释“equality is portable: the three databases all compare a JSON scalar to its text representation”对 SQLite 不成立。
- 连带：`json_spec.lua:50-52`（missing key 期望 0 行）在 SQLite 上“碰巧”通过（NULL 两边都不匹配）；`json_spec.lua:55-65` parity 在 SQLite 上**空洞地绿**（inline 与 prepared 均为 0 行）。
- 修正建议：`json_path_sqlite` 改为 `CAST(json_extract(%s, '$.%s') AS TEXT)`，与 MySQL `->>`、PG `->>` 的文本语义对齐（字符串/NULL 行为不变，实测通过）。

---

## P1 — 显著缺陷（语义/健壮性）

### P1-1 [db.lua] MySQL 结果行丢弃 NULL 列

- 位置：`spec/helpers/db.lua:273-278`：named fetch 后 `if v ~= nil then`。LuaSQL 以 nil 表示 NULL，行表中该键直接缺失 → “列为 NULL”与“列不存在”无法区分；`SELECT *` 时含 NULL 的行是稀疏表。
- 跨方言不一致（潜在陷阱）：carol 的 `profile` 在 MySQL/PG 上为 SQL NULL（键缺失），在 SQLite 上却是字符串 `'null'` —— 三方言三种“NULL”表示。当前断言未触及 profile，故不炸，但未来断言 NULL 时必踩。
- 修正建议：明确文档化契约，或改用 "a" 模式 + 显式 NULL 标记。

### P1-2 [db.lua] normalize_value 对所有字符串做数字强转

- 位置：`spec/helpers/db.lua:38-45`。`"100"`（文本列）会被转成数字 100，掩盖驱动类型差异；一旦未来种子数据出现形如 `"123"` 的文本值，断言静默错误。当前 fixtures 无此值。
- 修正建议：仅对已知数字型驱动类型（MySQL INT/DOUBLE、PG numeric）做归一化，而不是对所有 string。

### P1-3 [db.lua] last_insert_id 三方言语义不一致且会过期

- 位置：`spec/helpers/db.lua:200`（PG `SELECT LASTVAL()`）、`:288`（MySQL `getlastautoid`）、`:137`（SQLite `last_insert_rowid`）。
- PG `LASTVAL()` 返回**会话内最近一次任意序列的 nextval**，与插入行无关：显式 id 插入后返回的是种子期 chapter 序列的旧值；MySQL `getlastautoid` 对显式 id 插入返回 0/旧值。当前集成 spec 未调用，属潜伏陷阱。
- 修正建议：PG 用 `INSERT ... RETURNING id` 或 `currval(pg_get_serial_sequence(...))`。

### P1-4 [fixtures.lua] PG chapter 序列不被显式 id 种子推进

- 位置：`spec/helpers/fixtures.lua:29`（`id SERIAL PRIMARY KEY`）与 `:50-54`（显式插入 id=1,2,3）。
- MySQL AUTO_INCREMENT 与 SQLite AUTOINCREMENT 会随显式插入调整；**PG 序列不会**。任何未来“不指定 id 插入 chapter”的测试在 PG 上重复键（id=1），在另两方言正常。同时影响 P1-3 的 `LASTVAL()` 值。

---

## P2 — CI / 运维

### P2-1 [ci.yml] 每个 integration-servers 矩阵单元都启动两个数据库容器

- 位置：`.github/workflows/ci.yml:84-113`。`services:` 同时声明 mysql:8.0 与 postgres:16，因此 mysql 单元也会起 postgres 容器、postgres 单元也会起 mysql 容器（8 单元 × 2 容器）。各单元独立 runner 无端口冲突，功能不破，但浪费资源并扩大失败面。
- 修正建议：按 `matrix.db` 拆成两个 job，或各自独立的 services 块。

### P2-2 [ci.yml] rocks 未锁版本

- `luarocks install lsqlite3 / luasql-mysql / pgmoon / busted` 均取最新；pgmoon 占位符契约本身已是移动靶（见 P0-1）。建议锁定版本（如 pgmoon 1.17.0-1）保证可复现。

### P2-3 [roundtrip_spec.lua] OR 子构建器静默使用默认方言（mysql）

- 位置：`roundtrip_spec.lua:111` —— `SQLBuilder.SQLBuilder("")` 未传 opts，解析为默认方言 mysql。当前仅贡献方言无关的 WHERE，碰巧正确；未来子构建器使用方言相关方法会静默渲染 MySQL 语法。

---

## P3 — 备注

- `roundtrip_spec.lua:31-39` `eq_rows` 只遍历第一个表的键，第二张表的额外列不被检查（parity 校验偏弱）。
- lsqlite3 `db:exec` 返回契约：LuaDist 正源返回数字错误码（已核源码），`db.lua:88-89` 的 `code ~= 0` 与之一致；但个别 fork 返回布尔 `true` 会令所有无参 exec 报错——CI 装正源 rock，风险低。
- `lua_SQLBuilder/json.lua` require 时打印推荐提示（busted 输出噪声）。
- `spec/helpers/fixtures.lua:80-86` `fixtures.expected` 为死代码（全仓无引用）。

---

## 验证为正确的部分（证据）

- 全部 inline 路径期望在 sqlite 3.50.6 实测通过：`status=1`→ids 1,3,4；`name like '%a%'`→3 行；`id in (1,2)`→2 行；`LIMIT 2 OFFSET 2`→ids 3,4；`GROUP BY status HAVING COUNT(*)>1`→status=1,num=3；JSON 字符串等值→alice；carol 的 JSON `null` 在 `json_extract` 路径查询下等同 SQL NULL（实测 `IS NULL` 命中 carol）。
- MySQL 8 `->>`（返回 utf8mb4 文本、与字面量比较无 collation 冲突）与 PG jsonb `->>`（返回 text）使 number/string/nested 三个 JSON 断言的期望值对这两方言正确。
- fixtures 三方言 schema/种子一致：`db.literal` 单引号翻倍合法；MySQL JSON 列接受种子 JSON 串；mysql:8.0 官方镜像默认 `MYSQL_ROOT_HOST='%'`（已核 docker-library/mysql entrypoint 第 230 行 `file_env 'MYSQL_ROOT_HOST' '%'`），runner 经 127.0.0.1 TCP 以 root 连接可行；`ON CONFLICT (user_id)`/`ON DUPLICATE KEY UPDATE` upsert 语义三方言正确。
- lsqlite3 的 `?` 绑定、`last_insert_rowid`、`nrows` 迭代与 harness 用法吻合；lsqlite3 `db:exec` 数字返回契约与 `code ~= 0` 检查一致。

---

## 关键风险汇总（影响 CI 绿与否）

1. sqlite 集成作业：`json_spec` 数字等值 + nested 两个用例红（P0-3）。
2. postgres 集成作业：parity、INSERT prepare、JSON parity 三个用例红/崩溃（P0-1 + P0-2）。
3. mysql 作业：当前用例全部可通过（prepare 路径按设计 pending）。

（以上推断以“CI 已实际跑过这些作业”为前提；若 CI 从未跑绿，这些即为首次运行必现问题。）
