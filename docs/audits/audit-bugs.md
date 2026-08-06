# lua_SQLBuilder 独立交叉审计 — bug 清单完整性与新 bug 挖掘

审计方式：通读 `lua_SQLBuilder/` 全部库代码 + `spec/unit/*`、`spec/audit/invariants_spec.lua`、`spec/production`、`spec/integration`、`usage.lua`，逐行静态追踪（本机无 Lua 解释器，无法实际运行；所有 Lua 语义结论基于 Lua 5.1–5.4 参考实现 lstrlib.c 与语言规范交叉核对）。CI 矩阵为 Lua 5.1/5.2/5.3/5.4/LuaJIT，结论对全矩阵成立。

---

## 第一部分：已知 bug 锁定验证（A1–A21）

### 已锁定且断言与代码行为一致的（pending 正确）

| ID | 代码位置 | 断言 | 验证结论 |
| --- | --- | --- | --- |
| A1 | `UPDATE.lua:65-66` — `fmt("%s = ?", field)` 对已含 `?` 的 field 再次拼接 | `known_bugs_spec.lua:35-42` | **仍在 bug 状态**：`SET("score = score + ?", 1)` → prepare 输出 `score = score + ? = ?`（3 个占位符 vs 2 个参数）。pending 锁定正确 ✓ |
| A2（已修复回归） | `utils.lua:153` string 分支返回 `{sql, v}` pair | `known_bugs_spec.lua:17-23` | 追踪输出 `SELECT * FROM user WHERE (`json`->>'$.foo' = ?)`，param `"bar"`。与断言**逐字符一致**，绿灯 ✓ |
| A3 | `utils.lua:162-164` boolean 分支 push 纯字符串 | `known_bugs_spec.lua:47-52` | `jsonSQL[1]` = 字符串首字符 → `WHERE("`")` 生成垃圾 SQL。pending 锁定正确 ✓ |
| A4 | `SELECT.lua:65` — `tostring(query)` 走 string 分支被引号包裹 | `known_bugs_spec.lua:53-58` | 当前输出 `('validate' = 'true')`（带引号），断言期望无引号。pending 锁定正确 ✓（**只锁了 true，false 同病，见缺口**） |
| A5 | `WHERE.lua:18` — `if param then`，false 落入 else | `known_bugs_spec.lua:59-64` | false 时输出字面 `?`。pending 锁定正确 ✓（**只锁了 WHERE，UPDATE SET / DELETE QUERY 未锁，见新 bug NB-3/NB-11**） |
| A6 | `ORDER.lua:desc` — `self.orders[#self.orders][2]` 对空表索引 nil | `known_bugs_spec.lua:65-70` | 无 ORDER_BY 时 `DESC()` 立即报错 `attempt to index a nil value`。pending 锁定正确 ✓ |
| A9（已修复回归） | `INSERT.lua:__getInsertValue` 每次新建数组，无副作用 | `known_bugs_spec.lua:25-31` | 两次 to_sql 输出一致，绿灯 ✓ |
| A10 | `INSERT.lua:DATA` — `values[1]` 覆盖但 `cols` 累加 | `known_bugs_spec.lua:79-84` | 二次 DATA：`cols` = a,b 而 value 只有 b → 列值错位。pending 锁定正确 ✓ |
| A19 | `WHERE.lua:24` — `param[i] = fmt("'%s'", pv)` 原地改写调用方表 | `invariants_spec.lua:122-125` | 当前会改写 `names[1]` → `'a'`，断言期望不动。pending 锁定正确 ✓ |
| A21 | `WHERE.lua:add` 只存 `{query, param}` 单个参数 | `known_bugs_spec.lua:85-90` | 2 个占位符只绑 1 个参数。pending 锁定正确 ✓ |

### 锁定有问题 / 缺口

- **A20 锁定已过期且自相冲突（P1）**：`known_bugs_spec.lua:71-77` 断言 prepare SQL 为**不带引号**的 `UPDATE user SET score = ? WHERE (id = ?)`，但：
  1. 代码中 `UPDATE.lua` 的 `sort_keys`（第 20-27 行）**已带 comparator**，A20 描述的 "tsort without comparator 崩溃" 早已修复 —— 锁定描述过期；
  2. 且现有**绿灯测试** `update_spec.lua:24-30` 期望**带引号** `UPDATE user SET \`score\` = ?, \`status\` = ?`。两条断言对同一行为要求相反，**phase 1 落地 A20 时必然互斥冲突**，fix 会破坏绿灯测试。
- **A7 / A8 / A11–A18（共 10 个 ID）没有任何 spec 锁定**：`grep A7|A8|A11..A18` 全库仅命中审计脚本自身的 transcript。任务背景称"已知 bug 全部标记 pending"，与事实不符 —— 要么这些 ID 已被 phase-0b 静默修掉、要么从未锁过，需父会话核对 bug 清单原文。
- **B1（转义）锁只覆盖 WHERE to_sql 单值**：`invariants_spec.lua:156-158`。`UPDATE` string-mode to_sql、`HAVING`、`render_value`（INSERT/UPDATE table-mode）的字符串转义全部无锁（见 NB-5/NB-9）。

---

## 第二部分：新发现的 bug 候选清单（按严重度排序）

### P0 — 崩溃级

**NB-1 `%` 字符使 to_sql 崩溃或输出损坏（gsub 替换串转义）** — `WHERE.lua:31`、`UPDATE.lua:39`、`HAVING.lua:14`
`string.gsub(query, "?", tostring(param), 1)` 的替换串按 Lua 规则解释 `%`：`%n`=捕获引用、`%%`=字面 `%`，其余 `%x`（含串尾 `%`）在 Lua 5.1–5.4 全部抛 `invalid use of % in replacement string`。任何含 `%` 的字符串参数（LIKE 模式、百分比文本、URL）在 to_sql 模式直接崩溃：

```lua
local SQLBuilder = require "lua_SQLBuilder"
-- 崩溃: bad argument / "invalid use of % in replacement string"
local sql = SQLBuilder.SQLBuilder("SELECT * FROM user"):WHERE("name LIKE ?", "50%"):to_sql()
local sql2 = SQLBuilder.UPDATE("user"):SET("name = ?", "100%"):to_sql()
local sql3 = SQLBuilder.SQLBuilder("SELECT 1"):HAVING("COUNT(*) > ?", 0.5)  -- HAVING 无此路径但含%同样
-- 纯字符串参数进入 WHERE:to_sql 后先被包裹成 "'50%'" 再作为替换串 → % 后跟非数字非% → 必崩
```

`%1` 类参数（pattern 无捕获）在 5.1 产生垃圾/异常。to_prepare 模式无此问题（不走 gsub），故这是 **to_sql 独有** 且不在 A 清单与 B1 范围内的新崩溃。真实世界 LIKE 场景必踩。

**NB-2 to_prepare 参数错位：nil 参数留下空洞占位符** — `WHERE.lua:42-50`
`params[#params+1] = nil` 是无操作，占位符却保留；驱动按位置绑定 → 后续参数整体前移错绑：

```lua
local sql, p = SQLBuilder.SQLBuilder("SELECT * FROM user")
  :WHERE("a = ?", nil):WHERE("b = ?", 2):to_prepare()
-- sql = "... WHERE (a = ? AND b = ?)"，p == 2
-- 驱动把 2 绑到 a 上！b 无值 → 静默错绑（SELECT:QUERY({a=nil,b=2}) 同路径）
```

A5 只锁了 false；**nil 路径无人锁**。同族：`UPDATE("u"):SET({a=nil, b=1})` 经 `sort_keys`（pairs 含 nil 值键）→ `\`a\` = ?`无参数、`b=1` 绑到 a。

### P1 — 静默错误 SQL / 注入面

**NB-3 DELETE:QUERY 的 false 值 → to_sql 输出字面 `?`** — `DELETE.lua:40` → `WHERE.lua:18`
DELETE 不像 SELECT 有 boolean 分支，false 落入 `if param then` 的 else → 原样输出：

```lua
local sql = SQLBuilder.DELETE("user"):QUERY({ flag = false }):to_sql()
-- "DELETE FROM user WHERE (`flag` = ?)"  ← 成品 SQL 里带字面 ?，必报语法错误
```

A5 锁的是 `SQLBuilder:WHERE` 直调，**DELETE:QUERY 这个真实入口未锁**。

**NB-4 DELETE:QUERY 的 userdata → `= NULL`，与 SELECT 的 `is NULL` 不一致** — `DELETE.lua:39-40` vs `SELECT.lua:63`

```lua
local null = newproxy(true)  -- 或驱动返回的 NULL userdata
SELECT("*"):FROM("u"):QUERY({ deleted = null }):to_sql()  -- "`deleted` is NULL"   (正确语义)
DELETE("u"):QUERY({ deleted = null }):to_sql()            -- "`deleted` = NULL"   (恒不匹配，静默删不掉行)
```

**NB-5 HAVING 参数在 to_prepare 模式永远内联** — `HAVING.lua:10-15`
`HAVING:add` 在 add 时刻即 gsub 内联，`to_prepare` 不提取 HAVING 参数；prepare 模式里 HAVING 值仍以内联字面量出现（无占位符、无参数、无转义）：

```lua
local sql, p = SQLBuilder.SQLBuilder("SELECT status, COUNT(*) FROM user")
  :GROUP_BY("status"):HAVING("COUNT(*) > ?", 5):to_prepare()
-- sql 含内联 "HAVING COUNT(*) > 5"，p == nil
-- 违背 prepare 模式契约；且 HAVING("x = ?", false/nil) 直接 gsub 报错（bad argument）
```

invariants 的 5 个 API × 3 方言矩阵**完全没覆盖 GROUP_BY/HAVING**，此行为从未被任何测试观测。

**NB-6 Make_JsonQuery 用 `pairs()` → 多键/嵌套 JSON 输出不确定** — `utils.lua:155,169`
顶层 `SELECT:QUERY` 用 `sort_keys` 保证确定性，但 JSON 子条件遍历是 `pairs()`（hash 序，LuaJIT 随机种子下跨进程可变），违反 invariants 自己声明的 determinism 契约；而 invariants 的 select 用例只用单键 `json = { star = 5 }`，**恰好测不到**：

```lua
local a = SELECT("*"):FROM("u"):QUERY({ j = { x = 1, y = 2, z = 3 } }):to_sql()
local b = SELECT("*"):FROM("u"):QUERY({ j = { x = 1, y = 2, z = 3 } }):to_sql()
-- a 与 b 中 j.x/j.y/j.z 条件顺序取决于 pairs 序，可不等 → determinism 不变量被破坏
```

**NB-7 JSON boolean 分支无视方言 + 数组下标路径错误** — `utils.lua:162-164`
boolean 分支硬编码裸 `tableName->>'$.path'`：表名不按方言加引号、路径不用 `dialect.json_path`，postgres/sqlite 下直接产出非法 SQL（postgres `->>` 不认 `$.` 语法）：

```lua
SELECT("*", { dialect = "postgres" }):FROM("u"):QUERY({ j = { flag = true } }):to_sql()
-- 输出: u->>'$.flag' IS NOT NULL  （应为 "j"->'flag' IS NOT NULL 或等价）
```

A3 的 pending 断言只锁 mysql 默认方言，**方言维度无人锁**。另：数组下标键 `tonumber(k)` → `$."0"` 路径对 sqlite `json_extract` / postgres 链式算子语义存疑（低置信，建议实测）。

**NB-8 OR 子构建器静默丢弃所有非 WHERE/OR 子句** — `OR.lua:17-27`
`collect_from` 只取 `_where` 与 `_or`，子构建器的 `ORDER_BY`/`LIMIT`/`GROUP_BY`/`HAVING`/`FOR_UPDATE`/`PROCEDURE` 被**静默吞掉**（无警告无报错）：

```lua
SQLBuilder.SQLBuilder("SELECT * FROM u"):OR(SQLBuilder.SQLBuilder():WHERE("x = ?", 1):LIMIT(5)):to_sql()
-- LIMIT 5 无影无踪
```

### P2 — 边缘/一致性

**NB-9 UPDATE string-mode to_sql 字符串值不加引号** — `UPDATE.lua:35-39`
string-mode 的 to_sql 对字符串值直接 `tostring(val)` gsub 内联，**不引号包裹**（对比：table-mode 走 `render_value` 引号包裹、WHERE 也引号包裹）：

```lua
UPDATE("user"):SET("name = ?", "Bob"):to_sql()
-- "UPDATE user SET name = Bob"  ← 语法错误/注入面，且与 WHERE/table-mode 行为不一致
```

**NB-10 UPDATE string-mode to_sql 的 false 参数 → 字面 `?`** — `UPDATE.lua:35` `if val then`
`SET("flag = ?", false)` → else 分支原样输出 field → `UPDATE user SET flag = ?`（成品 SQL 带 `?`）。A5 只锁 WHERE。

**NB-11 A20 锁定冲突**（详见第一部分）：fix 后与 `update_spec.lua` 绿灯断言互斥。

**NB-12 LIMIT/PAGE 边界** — `LIMIT.lua:14-27`、`SELECT.lua:71-77`

- `PAGE(0)` → `LIMIT(-per, per)` → 输出 `LIMIT per OFFSET -per`（非法 SQL，无 guard）；`PAGE(nil)` 直接算术报错。
- `LIMIT(0)` / `LIMIT(0, n)` 正确输出 `n` ✓；`LIMIT("10")` 字符串透传 ✓（无问题，仅记录）。

**NB-13 WHERE 表参数混入 boolean → table.concat 崩溃** — `WHERE.lua:21-27`
`WHERE("x in ?", {1, false})` → concat 遇 boolean 抛 `invalid value (boolean) at index 2`；`{1, nil, 3}` 被 ipairs 静默截断为 `(1)`；同一调用在 to_prepare 模式把整表当**单个**参数（1 占位符 vs N 值）——to_sql 与 to_prepare 语义分裂。

**NB-14 INSERT:DATA 与 COLS 混用 → 列值错位** — `INSERT.lua:96-110`
`COLS("id")` 后 `DATA({a=1})` → cols={id,a} 而 values 仅 1 值 → `INSERT ... (`id`,`a`) VALUES (1)` 列数不匹配；`DATA` 后再 `VALUES` 同理。无守卫。

**NB-15 SELECT() 空构造 → `SELECT  FROM`** — `SELECT.lua:14-20`
无参数构造输出 `"SELECT  FROM "`（双空格+空表名），无断言无默认。`SELECT:QUERY({k=nil})` 经 sort_keys 纳入 nil 值键 → 同 NB-2 错位。

---

## 第三部分：invariants_spec 覆盖矩阵核查

矩阵：`make_builder` 5 个 API（base/select/update/insert/delete）× 3 方言，全部为 to_sql + to_prepare + determinism + idempotency。

**已覆盖**：WHERE 标量参数、单层 OR、ORDER_BY+DESC、双参 LIMIT、SELECT QUERY（数值+单键 JSON 数值）、PAGE/PER、UPDATE table-mode SET、INSERT COLS+VALUES、DELETE QUERY 数值、方言引号/JSON 算子（单键）。

**缺失（建议补进 invariants）**：

1. **GROUP_BY / HAVING**（含 HAVING 参数 → NB-5 唯一能拦截它的地方）；
2. **to_sql ↔ to_prepare 一致性不变量**：`to_sql` 输出不得含 `?`；`to_prepare` 的 `?` 计数 == 参数计数（当前只有 WHERE 标量一例 + A1 一例，覆盖不到 NB-2/NB-3/NB-11/NB-13）；
3. **JSON 多键/嵌套键 determinism**（当前单键恰好掩盖 NB-6 的 pairs() 非确定性）；
4. **UPDATE string-mode SET**（NB-1/NB-9/NB-10 全在此路径）、**INSERT DATA / ON_DUPLICATE_KEY_UPDATE**、**FIELD / 多 FROM**、**ASC / FOR_UPDATE / PROCEDURE**、**boolean/userdata QUERY 值**（SELECT 与 DELETE 各自行为）、空构建器；
5. **to_prepare 幂等性测试实际测的是跨实例确定性**（`invariants_spec.lua:90-91` 两次 `make_builder(...)` 新建实例），**同一实例连续两次 to_prepare 的幂等未测**（to_sql 幂等在 `:86` 用同一 builder，正确）。

---

## 结论摘要

- 11 个已锁 ID 中 9 个锁定准确（A1/A3/A4/A5/A6/A10/A19/A21 pending 正确；A2/A9 回归绿灯正确）；**A20 锁定过期且与绿灯测试冲突**；**A7/A8/A11–A18 共 10 个 ID 完全无锁**。
- 新增 15 个候选 bug：P0 两个（`%` gsub 崩溃 NB-1、nil 参数 prepare 错位 NB-2），P1 六个（DELETE false→字面 `?`、DELETE userdata→`= NULL`、HAVING 永不 prepare、JSON pairs 非确定、JSON boolean 无视方言、OR 静默丢子句），P2 七个。
- 高价值修复建议：统一参数渲染（引号/转义/`%` 处理）到一个 renderer；JSON 遍历改 sort_keys；HAVING/GROUP 进 prepare 参数流；invariants 补"占位符==参数数"与 to_sql 无 `?` 两条全局不变量。

## 证据

- 逐行追踪的代码路径与 Lua 语义交叉核对（lstrlib.c `add_s` 对替换串 `%` 的判定，5.1–5.4 一致）。
- 关键引用：`WHERE.lua:18,31,42-50`、`UPDATE.lua:35,39,65-66`、`DELETE.lua:39-40`、`SELECT.lua:63,65`、`HAVING.lua:10-15`、`OR.lua:17-27`、`utils.lua:153,155,162-164,169`、`LIMIT.lua:20-27`、`INSERT.lua:96-110`、`known_bugs_spec.lua:71-77` vs `update_spec.lua:24-30`、`invariants_spec.lua:16-45,86,90-91`。
- 本机无 Lua 解释器（`lua`/`luajit`/`busted` 均不可用），未执行测试；全部结论为静态追踪。唯一不确定性标注见 NB-7 数组路径与 NB-1 中 `%1` 的具体 5.1 行为（崩 vs 垃圾输出），均属错误表现。
