# 对抗性 API/状态审计报告 — lua_SQLBuilder

审计日期：本报告基于 Lua 5.4.6（`C:\Users\Nuctori\AppData\Local\Programs\Lua\bin\lua.exe`）实际执行。
基线：`lua spec/run.lua` → 227 passed, 0 failed, 4 pending（integration 因缺 lsqlite3 驱动跳过）。

执行环境说明：任务要求读取的 `D:\lua\lua_SQLBuilder\plan.md` 与 `progress.md` 不存在（ENOENT），
审计直接基于源码（`lua_SQLBuilder/*.lua`）与现有 spec 契约进行。测试脚本置于系统临时目录，未修改仓库任何文件。

## 总判定

- **崩溃**：2 处（均为消息缺失的 `assert()`，属可误用 API 的 UX 问题；无文档化合理用法下的崩溃）。
- **静默状态污染**：2 处高危面 —— (a) 方言配置表字段级修改会**追溯污染已创建 builder** 的渲染输出（含关闭转义）；(b) OR 子对象方言不校验，单条 SQL 混用两种转义约定。
- **行为不一致**：3 处 —— UPDATE 混合 SET 模式 to_sql/to_prepare 列序不同；INSERT to_prepare 参数形态（按行 table）与其他 builder（平铺标量）不同；quote_ident/json_path 快照（eager）与 escape_string/render_limit/upsert 活引用（lazy）并存。
- 无 blocker 级问题；文档化正常用法全部通过。

---

## Medium（中危）

### M1. 方言配置表字段级修改追溯污染已创建 builder（静默状态污染 + 安全面）
位置：`lua_SQLBuilder/dialect.lua`（`M.dialects` 导出可变表、`resolve()` L257、`set_default()` L262）；`lua_SQLBuilder/SQLBuilder.lua:44`（构造时 resolve 拿到的是**同一张 config 表引用**）。

复现（Lua 5.4 实测）：
```lua
local dialect = require "lua_SQLBuilder.dialect"
local b = sqlbuilder.SQLBuilder("SELECT 1", { dialect = "mysql" }):WHERE("name = ?", "O'Brien")
print(b:to_sql())   -- SELECT 1 WHERE (name = 'O\'Brien')     正常
dialect.dialects.mysql.escape_string = function(s) return s end  -- 关闭转义
print(b:to_sql())   -- SELECT 1 WHERE (name = 'O'Brien')       已创建 builder 输出被追溯改写，注入面重现
```
同样：
- `dialect.dialects.postgres.upsert = nil` → 已创建的 postgres INSERT builder 后续 `to_sql()` 直接抛 "dialect 'postgres' has no upsert support"（原本合法的 builder 开始崩溃）。
- `dialect.dialects.mssql.render_limit = ...` → 已创建 builder 的 LIMIT 渲染被改写。

且**快照语义不一致**：`quote_ident` / `json_path` 在调用点（QUERY/DATA 时）立即渲染进条件字符串（eager，改表不影响旧 builder），而 `escape_string` / `render_limit` / `upsert` 在渲染点（to_sql/to_prepare 时）活读取（lazy，改表追溯生效）。同一次配置修改对部分子句生效、部分不生效，行为最难预测。
另：整体替换 preset 表（`dialect.dialects.mysql = {...}`）对旧 builder 无影响（旧引用保留），仅新 builder 生效——与字段级修改行为不对称。

建议：构造时深拷贝 config 表（或按渲染点统一固化）；至少文档明确「builder 构造后修改 preset 字段会追溯生效，且 eager/lazy 字段行为不同」；字段级修改属文档化扩展点（header 注释明示），故定级 medium 而非 high。

### M2. OR 子对象方言不校验，单条 SQL 混用两种转义约定（静默不一致 + 注入面）
位置：`lua_SQLBuilder/sql_comp/OR.lua:18-31`（`OR:add` 只检查子句种类，不检查 `sqlBuilder._dialect`）；渲染时子对象用**自己的方言**转义参数。

复现（实测）：
```lua
local sub = sqlbuilder.SQLBuilder("", { dialect = "mysql" }):WHERE("email = ?", "O'Brien")
sqlbuilder.SQLBuilder("SELECT * FROM user", { dialect = "postgres" })
  :WHERE("name = ?", "O'Brien"):OR(sub):to_sql()
-- 输出: SELECT * FROM user WHERE (name = 'O''Brien') OR (email = 'O\'Brien')
```
postgres（standard_conforming_strings=on）不解释 `\` 转义 → `'O\'Brien'` 中 `\` 为字面量、`'` 提前闭合 → 语法错误或注入。反向（mysql 父 + postgres 子）`''` 在 MySQL 中恰好也合法，掩盖了问题。父子方言同源时无感知风险；异源时静默产出目标库无法正确解析的 SQL。

建议：`OR:add` 校验子 builder 方言与父一致（`self._dialect == sub._dialect` 或同名），不一致即报错。

### M3. UPDATE 混合 SET 模式下 to_sql 与 to_prepare 列序/参数序不一致
位置：`lua_SQLBuilder/UPDATE.lua` —— `TableOperator()`（L48-62：先 string 模式 `self.setData`，后 table 模式 `setDataTable`）vs `PrepareTableOperator()`（L64-83：先 table 模式，后 string 模式）。

复现（实测）：
```lua
local b = UPDATE("user", { dialect = "mysql" }):SET("a = a + ?", 1):SET({ b = 2 })
b:to_sql()      -- UPDATE user SET a = a + 1, `b` = 2
b:to_prepare()  -- UPDATE user SET `b` = ?, a = a + ?   （参数顺序也随之翻转为 2,1）
```
同一 builder 两种渲染模式的 SET 列顺序不同（调用顺序反向不变：to_sql 恒 string→table，to_prepare 恒 table→string）。SET 列序语义上通常无碍，但对输出稳定性/快照比对（如缓存、日志）是不一致源。

建议：统一两种模式的拼接顺序；或至少文档说明。

### M4. INSERT 列数/行宽不校验，静默产出畸形 SQL
位置：`lua_SQLBuilder/INSERT.lua` —— `COLS()` L140、`VALUES()` L147、`DATA()` L156 均不校验行宽与列数匹配。

复现（实测）：
```lua
INSERT("user"):COLS("id","name"):VALUES({1}):to_sql()
-- INSERT INTO user ("id", "name") VALUES (1)            -- 列2行1，静默
INSERT("user"):DATA({a=1}):COLS("b"):VALUES({2}):to_sql()
-- INSERT INTO user ("a", "b") VALUES (1), (2)           -- DATA 后追加 VALUES 行宽错位
INSERT("user"):COLS("id","name"):VALUES({1,"n"}):DATA({x=9}):VALUES({2,"m"}):to_sql()
-- INSERT INTO user ("x") VALUES (9), (2, 'm')           -- 行2有2值对1列
```
均不崩溃、不报错，产出执行期必然失败的 SQL。`DATA` 会重置 cols/values（NB-14 已锁），但其后再混 `COLS`/`VALUES` 即破坏对齐。

建议：`to_sql`/`to_prepare` 渲染时校验每行 `#row == #cols`，不等即报错。

### M5. LIMIT/PAGE 参数无数值校验且原样拼入 SQL（两种模式都内联，注入面）
位置：`lua_SQLBuilder/sql_comp/LIMIT.lua`（`add` 原样存 p1/p2）；`dialect.lua` `render_limit_ansi`/`render_limit_mssql`（L62-75 仅 `tonumber(offset)==0` 判断，count 不经数值校验直接拼）；`SELECT.lua` `PAGE`（L78：`tonumber` 后仅 `>=1` 断言，允许小数）。

复现（实测）：
```lua
SELECT("*"):FROM("t"):LIMIT(-1, 10):to_sql()      -- LIMIT 10 OFFSET -1
SELECT("*"):FROM("t"):LIMIT("abc", 10):to_sql()   -- LIMIT 10 OFFSET abc
SELECT("*"):FROM("t"):PAGE(1.5):to_sql()          -- LIMIT 10 OFFSET 5.0
SELECT("*"):FROM("u"):LIMIT(0, "10 OFFSET 5; DROP TABLE users--"):to_prepare()
-- SELECT * FROM u LIMIT 10 OFFSET 5; DROP TABLE users--    to_sql 与 to_prepare 均原样内联
```
LIMIT 值（尤其 count）为攻击者可控时是直接注入面，且 **prepare 模式同样不参数化** LIMIT 段（与 WHERE/UPDATE 的参数化策略不一致）。

建议：`LIMIT:add` / `PAGE` 对 offset/count 强制 `tonumber` + `>=0` 校验；prepare 模式同样应校验（不能参数化的段必须类型验证）。

---

## Low（低危）

### L1. PER 在 PAGE 前 → 无消息断言崩溃
`lua_SQLBuilder/SELECT.lua:85` `assert(self.page)`（无消息）。
实测：`SELECT("*"):FROM("u"):PER(20)` → `SELECT.lua:85: assertion failed!`。建议补消息（如 "PER requires PAGE first"）。

### L2. PROCEDURE(nil) → 无消息断言崩溃
`lua_SQLBuilder/SQLBuilder.lua:124` `assert(type(procedure) == "string")`（无消息）。建议补消息。

### L3. SELECT 尾参 table 启发式吞掉字段表；UPDATE 表名无类型校验
- `lua_SQLBuilder/SELECT.lua:12-17`：`type(fields[#fields]) == "table"` 一律当 opts。
  实测：`SELECT({"a","b"}):FROM("u")` → `SELECT * FROM u`（字段静默丢失）；`SELECT("*", {1,2})` → 同上。传字段数组时静默吞掉。
- `lua_SQLBuilder/UPDATE.lua:15`：`UPDATE({ dialect = "mysql" })` → 实测输出 `UPDATE table: 00000... SET "a" = 1`（tableName 为 table 时静默拼地址进 SQL）。建议 ctor 校验 `tableName` 为 string。

### L4. OR:add 非 builder 参数 → 延迟到渲染时才崩溃且报错晦涩
`lua_SQLBuilder/sql_comp/OR.lua:26`：`OR("SELECT 2")` 不报错，`to_sql()` 时才崩 `attempt to index a nil value (field '_where')`。建议 `add` 入口校验参数带 `_where`/`_or`。

### L5. OR 子句守卫漏掉 FOR_UPDATE / PROCEDURE（静默丢弃）
`OR.lua:20` 守卫只查 `_order/_limit/_group/_having`。实测：OR 子对象 `:FOR_UPDATE()` 或 `:PROCEDURE("p()")` 静默丢弃、无报错——与注释宣称的「无用子句显式报错」策略不一致。建议把 `_forUpdate`/`_procedure` 纳入守卫。

### L6. WHERE 参数多于占位符时静默丢弃多余参数
`sql_comp/WHERE.lua:add` 存全量 params，渲染只消费占位符数。
实测：`WHERE("a = ?", 1, 2):to_prepare()` → `WHERE (a = ?)` 仅返回 1 个参数，第二个值 2 静默消失（数据丢失）。建议渲染时校验 `占位符数 == 参数数`。

### L7. INSERT to_prepare 参数形态与其他 builder 不一致；boolean 被字符串化
- `lua_SQLBuilder/INSERT.lua:__getPrepareInsertValue`（L11-25）：返回 `params = {行1, 行2, ...}`，即 to_prepare 的每个参数是**一行值的 table**；而 SELECT/UPDATE 返回**平铺标量**（实测对照：INSERT 2 行 → 3 个返回值，后两个是 table；UPDATE → 标量序列）。同一库两种契约，驱动绑定代码易踩坑。
- 同一函数内 `type(v)=="boolean"` 时 `row[i] = tostring(v)` —— prepare 模式下 boolean 变成字符串 `"true"/"false"`，而 WHERE/UPDATE 的 prepare 保留真实 boolean。跨组件类型处理不一致。

### L8. FOR_UPDATE 在 UPDATE/DELETE 上静默放行（方言非法 SQL）
`SQLBuilder.lua:FOR_UPDATE` 继承给 UPDATE/DELETE。实测：`UPDATE("user"):SET({a=1}):FOR_UPDATE()` → `UPDATE user SET "a" = 1 FOR UPDATE`（MySQL 中非法）；`DELETE(...):FOR_UPDATE()` 同理；`DELETE(...):LIMIT(0,5)` 也放行（仅 MySQL 合法）。建议按 builder 类型限制子句合法性。

### L9. dialect.default 导出字段是死代码；init.lua 文档过时
- `dialect.lua` 导出 `M.default = DEFAULT`，但 `resolve/set_default/get_default` 全部使用局部 `default_name`。实测 `dialect.default = "postgres"` 无任何效果——误导性 API 陷阱。
- `lua_SQLBuilder/init.lua:27-28` 注释 `Supported: "mysql" (default), "postgres", "sqlite"` —— 实际默认是 **ansi**，且已有 9 个预设（含 oracle/duckdb/clickhouse）。文档与实际不符。

### L10. SELECT 无 FROM → 静默产出 `SELECT * FROM  WHERE ...`
`SELECT:TableOperator()`（L24-27）对空 `froms` 不做处理。实测 `SELECT("*"):QUERY({id=1}):to_sql()` → `SELECT * FROM  WHERE ("id" = 1)`（残留空格）。建议空 froms 时省略 "FROM " 或报错。

---

## Note（确定性行为，非缺陷但需知晓）

- **N1. WHERE 在 OR 之后调用仍并入 OR 前的 WHERE 组**：实测 `WHERE(a):OR(sub):WHERE(b)` → `WHERE (a = 1 AND b = 2) OR (c = 3)`。渲染恒为 WHERE→OR（`SQLBuilder.lua:to_sql`），调用顺序不改变输出，但用户若以为第二个 WHERE 出现在 OR 之后会被误导。语义确定，文档未说明。
- **N2. 最后调用者胜出语义**（均确定且无报错）：LIMIT 重复（`LIMIT.lua:add` 整体替换）、PAGE↔LIMIT 互相覆盖、SET 表模式重复整体替换（`UPDATE.lua:SET`：`SET({a,b}):SET({c})` → 仅 c）、ON_DUPLICATE 重复整体替换、DATA 重复重置（已由 A10/NB-14 锁定）。其中 SET 表模式「整体替换 vs 字符串模式追加」语义不对称。
- **N3. to_sql 中 SET 表模式恒排在字符串模式之后**：`SET("b=?",1):SET({a=1})` 与反向调用输出相同（`SET b = ..., "a" = ...`），与调用顺序无关。
- **N4. 同一 OR 子对象共享给多个父 builder 安全**：渲染只读子对象，实测 `p1:OR(shared)` + `p2:OR(shared)` 输出各自正确、互不污染。
- **N5. 方言快照语义不对称**（详见 M1）：`quote_ident`/`json_path` 调用点固化，`escape_string`/`render_limit`/`upsert` 渲染点活读。
- **N6. set_default_dialect 非法值均失败快且不破坏默认值**（实测 nil/数字/未知名 → 报错且原默认保留）；`opts.dialect` 非法值在构造时即抛错（fail-fast，好行为）。

---

## 确认正确的行为（证据）

- set_default_dialect 后**旧 builder 持有方言快照**：切换 mysql 后旧 ansi builder 的 `to_sql`/`Dialect()` 不变；多次切换（postgres→sqlite→mysql）均验证。
- `dialect.dialects.x` 新增 preset 立即被 `resolve`/`set_default_dialect` 识别；整体替换 preset 后新 builder 用新表、旧 builder 用旧表。
- 所有链式方法（SELECT/UPDATE/INSERT/DELETE/基础 builder 的 WHERE/OR/ORDER/GROUP/HAVING/LIMIT/FOR_UPDATE/PROCEDURE）均返回 self（实测 `==` 成立）。
- `TableOperator`/`PrepareTableOperator` 直接调用安全：SELECT/DELETE 继承基类实现返回头 SQL（无参数）；UPDATE 返回参数数组。
- `to_sql`/`to_prepare` 幂等（重复调用输出一致）；不修改调用方传入的 table（spec A9/A19 及实测复核）。
- WHERE 占位符多于参数 → 带占位符编号的清晰报错（`missing parameter for placeholder 2 in ...`）。
- OR 子对象携带 ORDER/LIMIT/GROUP/HAVING → 在 `OR:add` 调用点即抛清晰错误（错误定位到用户调用行）。
- 非法方言（`opts.dialect="nope"`、`set_default_dialect("oracle9")`）全部 fail-fast 且默认值不受污染。

---

## 建议优先级排序

1. M1 快照语义统一（深拷贝 config 或固化渲染点）——安全面，最高优先。
2. M2 OR 方言一致性校验。
3. M5 LIMIT/PAGE 数值校验（两模式统一）。
4. M4 INSERT 行宽校验；M3 UPDATE 双模式列序统一。
5. L1/L2 补 assert 消息；L4/L5 补入口校验与守卫完备性；L9 修文档/删死字段。
