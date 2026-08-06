# 对抗性边界审计报告 — lua_SQLBuilder

- 审计对象: D:/lua/lua_SQLBuilder (HEAD = `b1e6e66`, 工作树干净)
- 运行环境: Lua 5.4.6 (`C:\Users\Nuctori\AppData\Local\Programs\Lua\bin\lua.exe`), sqlite3 3.50.6 (仅用于 JSON path 实证)
- 方式: 只读审计；测试脚本写在 gitignore 的 `.pi-subagents/artifacts/adversarial_test.lua`（不入库）；未修改任何仓库文件
- 基线: `lua spec/run.lua` → **226 passed, 1 failed, 4 pending**（1 个失败为测试自身期望陈旧，见 Note-3）

---

## 严重度排序问题清单

### HIGH-1: JSON 数组查询路径 `$.tags.[0]` 是非法 JSONPath（SQLite 实证，多方言受影响）
- 位置: `lua_SQLBuilder/utils.lua:92-95`（`segment = fmt("[%d]", tonumber(k)-1)` 与 `path = fatherPath .. segment` 拼出 `tags.[0]`）；`dialect.lua` 的 mysql/mariadb/sqlite/mssql/oracle/duckdb json_path 直接透传该串
- 复现:
  ```lua
  SELECT("*", {dialect="sqlite"}):FROM("user"):QUERY({json={tags={"x","y"}}}):to_sql()
  -- "…CAST(json_extract("json", '$.tags.[0]') AS TEXT) = 'x' AND … '$.tags.[1]' …"
  ```
- 实证: `sqlite3 ':memory:' "SELECT json_extract('{\"tags\":[\"x\",\"y\"]}', '\$.tags.[0]')"` → **`Error: stepping, bad JSON path: '$.tags.[0]'`**；`$.tags[0]` 正常返回。
- 期望: 数字索引段前不应带 `.`，正确渲染 `$.tags[0]` / `$.tags[1]`。postgres（`->'tags'->>0`）与 clickhouse（`JSONExtractString(...,'tags',0)`）自行分段所以正确，其余 6 方言全部产出坏路径。
- 注: commit b1e6e66 修了 1-based→0-based 偏移（`[N-1]`），但 `fatherPath .. "."` 的拼接未同步修复，属半成品修复。

### HIGH-2: NaN / ±inf 被静默渲染成非法 SQL 字面量
- 位置: `utils.lua:73-74`（render_value number 分支）、`sql_comp/WHERE.lua:21-22`、`UPDATE.lua:35-36`、`sql_comp/HAVING.lua:150-151` —— 全部直接 `tostring(v)`
- 复现:
  ```lua
  SQLBuilder("SELECT * FROM t"):WHERE("x = ?", 0/0):to_sql()        -- "x = -nan(ind)"
  SQLBuilder("SELECT * FROM t"):WHERE("x = ?", math.huge):to_sql()  -- "x = inf"
  UPDATE("t"):SET({x = -math.huge}):to_sql()                        -- SET "x" = -inf
  INSERT("t"):COLS("x"):VALUES({0/0}):to_sql()                      -- VALUES (-nan(ind))
  SELECT("*"):FROM("t"):QUERY({x = math.huge}):to_sql()             -- ("x" = inf)
  ```
- 期望: 非有限数值应显式报错（与 json.encode 的 `"unexpected number value"` 一致），或按方言渲染 `'NaN'::float8` 等合法形式。当前 to_sql 静默产出任何数据库都不认的 `inf`/`-nan(ind)` 字面量。
- 附加: `WHERE("x IN ?", {1, 0/0})` → `(1, -nan(ind))` 同源。

### HIGH-3: 稀疏数组 IN 列表被 ipairs 静默截断（数据丢失 + 占位符错位）
- 位置: `sql_comp/WHERE.lua:43-48`（to_sql）、`:84-90`（prepare）
- 复现:
  ```lua
  SQLBuilder("SELECT * FROM t"):WHERE("x IN ?", {1, nil, 3}):to_sql()
  -- "x IN (1)"       ← 3 个元素只剩 1 个，静默丢失
  SQLBuilder("SELECT * FROM t"):WHERE("x IN ?", {1, nil, 3}):to_prepare()
  -- "x IN (?)", param = 1   ← 用户给了 3 个值，只展开 1 个
  ```
- 期望: 遇 nil 空洞应显式报错（或文档明确禁止稀疏数组）。当前静默产出与用户意图不一致的 SQL 与参数集。

### HIGH-4: 空 IN 列表 → `x IN ()` 非法 SQL
- 位置: `sql_comp/WHERE.lua:43-48`（`table.concat(vals, ", ")` 为空 → `()`）
- 复现:
  ```lua
  SQLBuilder("SELECT * FROM t"):WHERE("x IN ?", {}):to_sql()      -- "x IN ()"
  SQLBuilder("SELECT * FROM t"):WHERE("x IN ?", {}):to_prepare()  -- "x IN ()", 0 params
  ```
- 期望: MySQL/PostgreSQL 均不接受 `IN ()`（语法错误）。应显式报错或提示空列表。当前静默产坏 SQL。

### HIGH-5: UPDATE 字符串表达式 SET 无参数时把 `?` 原样透传
- 位置: `UPDATE.lua:73-79`（to_sql `if #params > 0 … else field`）与 `:100-107`（prepare 同构）
- 复现:
  ```lua
  UPDATE("user"):SET("a = ?"):to_sql()      -- "UPDATE user SET a = ?"   ← 内联 SQL 里残留 ?（非法）
  UPDATE("u"):SET("a = ?"):WHERE("id = ?", 1):to_prepare()
  -- "UPDATE u SET a = ? WHERE (id = ?)"  + 仅 1 个参数 → 2 占位符对 1 参数，静默错位
  ```
- 期望: 与 WHERE 一致，缺参数应报 "missing parameter for placeholder 1"（NB-2 已为 WHERE 锁定该行为）。当前两种模式都静默错位。

### HIGH-6: INSERT 列数/行值数不校验（含 nil 空洞静默截断）
- 位置: `INSERT.lua:100-107`（TableOperator）、`:127-140`（VALUES 用 ipairs 存行）、`:24-42`（prepare）
- 复现:
  ```lua
  INSERT("user"):COLS("a","b"):VALUES({1}):to_sql()       -- "VALUES (1)"      2 列 1 值
  INSERT("user"):COLS("a","b"):VALUES({1,nil,3}):to_sql() -- "VALUES (1)"      第 3 值静默丢失
  INSERT("user"):COLS("a"):VALUES({1,2}):to_sql()         -- "VALUES (1, 2)"   1 列 2 值
  INSERT("user"):COLS("a","b"):to_sql()                   -- "VALUES "         悬空 VALUES
  INSERT("user"):VALUES({1}):to_sql()                     -- "() VALUES (1)"   空列名表
  INSERT("user"):DATA({c=3}):VALUES({1,2}):to_sql()       -- "(c) VALUES (3), (1, 2)" 列数不一致
  ```
- 期望: 列数 ≠ 行值数应报错。当前全部静默产坏 SQL；`VALUES` 中 nil 空洞行与 `DATA` 后追加 `VALUES`（列由 DATA 键决定）两种路径尤其危险。

### HIGH-7: JSON 查询的纯数字字符串键渲染出 `[-1]` 负索引
- 位置: `utils.lua:92-94`（`tonumber(k)` 对字符串键也命中，`tonumber("0")-1 = -1`）
- 复现:
  ```lua
  SELECT("*"):FROM("u"):QUERY({json={["0"]="a"}}):to_sql()
  -- mysql: "json"->>'$.[-1]' = 'a'      ← JSON 对象键 "0" 被当成数组下标，还减成 -1
  ```
- 期望: 数字键 1-based→0-based 只应作用于真正的数组索引；字符串数字键是 JSON 对象成员，应渲染为 `.0`（或 `$['0']`）。当前 `[-1]` 为非法路径（叠加 HIGH-1 的点号问题）。

### MED-1: 空/缺失子句构造器静默产出畸形 SQL
- 位置: `SELECT.lua:24-27`、`UPDATE.lua:70-85`、`DELETE.lua:16-18`、`INSERT.lua:100-107`
- 复现:
  ```lua
  SELECT():to_sql()                 -- "SELECT * FROM "            ← 无表名
  SELECT("*"):to_sql()              -- "SELECT * FROM "            ← 无 FROM
  SELECT({dialect="mysql"}):to_sql()-- "SELECT * FROM "            ← 仅 opts
  UPDATE("user"):to_sql()           -- "UPDATE user SET "          ← 悬空 SET
  UPDATE("user"):SET({}):to_sql()   -- "UPDATE user SET "
  DELETE():to_sql()                 -- "DELETE FROM nil"           ← "nil" 字面量
  ```
- 期望: 至少应校验表名/字段非空；DELETE 无表名渲染 `nil` 字符串是最刺眼的一种。

### MED-2: 查询文本字符串字面量内的 `?` 被当作占位符替换
- 位置: `sql_comp/WHERE.lua:29-31`（`count_placeholders` 数所有 `?`）、`:35-53`；`UPDATE.lua:44-54`
- 复现:
  ```lua
  SQLBuilder("SELECT * FROM t"):WHERE("name = 'a?b'", 42):to_sql()
  -- "name = 'a42b'"     ← 字面量 ? 被替换成参数，静默篡改 SQL
  UPDATE("u"):SET("name='a?b' AND x = ?", 1):to_prepare()
  -- 占位符计数 2 个，参数只 1 个 → 错位
  ```
- 期望: 字面量 `?` 无法转义是当前设计的已知局限；至少 prepare 模式应在参数不足时报错（WHERE 已报，UPDATE 不报）。to_sql 静默替换是实际数据损坏。

### MED-3: LIMIT 接受任意垃圾值
- 位置: `sql_comp/LIMIT.lua:9-30`（无任何类型/范围校验）
- 复现:
  ```lua
  SQLBuilder("SELECT * FROM t"):LIMIT(-1):to_sql()      -- "LIMIT -1"（MySQL/PG 非法）
  SQLBuilder("SELECT * FROM t"):LIMIT(0/0):to_sql()     -- "LIMIT -nan(ind)"
  SQLBuilder("SELECT * FROM t"):LIMIT("abc"):to_sql()   -- "LIMIT abc"（未加引号的垃圾）
  SQLBuilder("SELECT * FROM t"):LIMIT(1e308,1e308):to_sql() -- "LIMIT 1e+308 OFFSET 1e+308"
  ```
- 期望: 非负整数校验；`PAGE` 已有 `assert(page >= 1)` 先例，LIMIT 应同级别校验。

### MED-4: OR 子句在无前置 WHERE 时产出 `FROM t OR (...)` 非法 SQL
- 位置: `sql_comp/OR.lua:13-23`（只拦 ORDER/LIMIT/GROUP/HAVING，不校验主 builder 是否已有 WHERE）、`SQLBuilder.lua:132-133`
- 复现:
  ```lua
  SQLBuilder("SELECT * FROM t"):OR(SQLBuilder("", {dialect="ansi"}):WHERE("x = ?", 1)):to_sql()
  -- "SELECT * FROM t OR (x = 1)"    ← OR 悬空，SQL 语义非法
  ```
- 期望: 要么自动补 `WHERE 1=1` 前缀，要么报错提示 OR 需要前置 WHERE。

### MED-5: ANSI 系方言字符串参数中 NUL/控制字节原样进 SQL
- 位置: `dialect.lua:65-67`（`escape_ansi` 只加倍单引号）；mysql 的 `escape_mysql` 覆盖 `\0 \b \n \r \t \26 \\ '` 但 0x01-0x07/0x0B-0x0C/0x0E-0x19/0x1B-0x1F 仍原样
- 复现:
  ```lua
  SQLBuilder("SELECT * FROM t"):WHERE("x = ?", "a\0b"):to_sql()  -- 'a\0b'（原始 NUL 字节）
  SQLBuilder("SELECT * FROM t"):WHERE("x = ?", string.char(0,1,2,127,128,255)):to_sql()
  ```
- 期望: ANSI/PG/SQLite/MSSQL 字符串字面量内的 NUL 在多数驱动会被拒或截断；建议对控制字节显式转义或报错。MySQL 路径基本正确（`\0`→`\\0`），但非转义表字节同样未处理。

### MED-6: INSERT prepare 模式 boolean 参数类型漂移为字符串
- 位置: `INSERT.lua:30-35`（`if type(v) == "boolean" then row[i] = tostring(v)`）
- 复现: `INSERT("t"):COLS("f"):VALUES({false}):to_prepare()` → 参数为字符串 `"false"`；而 to_sql 内联渲染为 `false`，SELECT/UPDATE 的 prepare 则原样传 boolean。三种行为互不一致。
- 期望: prepare 参数应保留原始类型（boolean），或三处统一。

### MED-7: `SELECT({...})` 单表参数被当 opts 吞掉字段
- 位置: `SELECT.lua:12-15`（ctor 把末位 table 一律当 opts）
- 复现: `SELECT({"a","b"}):FROM("t"):to_sql()` → `"SELECT * FROM t"` —— 字段列表静默丢失。
- 期望: 当唯一参数是表且无 `dialect` 键时应按字段列表处理，或至少报错；当前静默退化为 `*`。

---

### NOTE-1: 额外参数静默丢弃
`WHERE("x = ?", 1, 2)` 两种模式都只取 1 个参数，多余 `2` 静默丢弃（无报错）。建议超参时报错。

### NOTE-2: `WHERE(nil)` 报错信息晦涩
`SQLBuilder(...):WHERE(nil):to_sql()` → `bad argument #1 to 'gsub' (string expected, got nil)`，非参数校验型错误。`SQLBuilder()` 空构造器 to_sql → `invalid value (nil) at index 1 in table for 'concat'`（TableOperator 返回 nil）。两者都是"会报错但信息对用户无意义"。

### NOTE-3: 测试套件 1 个失败为陈旧期望
`spec/unit/dialect_spec.lua:76-79`（clickhouse 用例）期望 `tags` 在 `star` 之前输出，但实现按 `sort_keys` 字母序渲染 `star` 在前。库行为是确定性的（字母排序），失败的是测试自身期望顺序。修复测试期望即可。（审计前的 oracle 失败已在 b1e6e66 修复。）

### NOTE-4: PROCEDURE 中 `?` 在 prepare 模式无参数绑定
`PROCEDURE("CALL p(?)")` prepare → SQL 含 `?` 但无对应参数，驱动侧会错位。PROCEDURE 是裸 SQL 通道，建议文档注明 prepare 不处理其占位符。

### NOTE-5: FOR_UPDATE 允许出现在 UPDATE/INSERT 上
`UPDATE("u"):SET({a=1}):FOR_UPDATE():to_sql()` → `UPDATE u SET a = 1 FOR UPDATE`。无子句类型守卫（OR:add 有守卫先例）。低危。

### NOTE-6: `ORDER_BY(123)` 静默接受非字符串
→ `ORDER BY 123 ASC`。低危。

### NOTE-7: `PER` 先于 `PAGE` → `assertion failed!` 无消息
`SELECT("*"):FROM("t"):PER(5):to_sql()` 报错但无提示信息。低危。

### NOTE-8: mssql OFFSET/FETCH 依赖 ORDER BY
`LIMIT(10,20)` mssql → `OFFSET 10 ROWS FETCH NEXT 20 ROWS ONLY`（SQL Server 语法要求前置 ORDER BY）。属方言语义，DB 层报错，构建期无感知。

---

## 类别覆盖结果

| 类别 | 结果 |
|---|---|
| 1 异常值 | nil/false/0/±0/0.0/空串/10KB/Unicode/emoji/组合字符 均正常或干净报错；**NaN/huge/-huge 静默坏 SQL (HIGH-2)**；**NUL/二进制字节 ANSI 系未转义 (MED-5)**；1e308 → `1e+308`（合法字面量）；`-0`→`0`、`-0.0`→`-0.0`、`0.0`→`0.0` 均正常 |
| 2 空/缺失 | QUERY({}) 正常无 WHERE；**SELECT 无 FROM / UPDATE 无 SET / INSERT 无 VALUES / DELETE 无表名 全部静默畸形 (MED-1, HIGH-6)** |
| 3 结构 | 100+ 链、10 层 OR、1000 元素 IN、混合类型数组全部正常且对齐；**稀疏 IN 截断 (HIGH-3)**；5000 层 OR 无栈溢出（展平为单链）；10k IN 内存约 2.5MB 无异常 |
| 4 渲染一致性 | 占位符/参数对齐：标量、IN 展开、OR+HAVING 混合全部对齐（实测 ph=5 ↔ 5 参数；1000-IN ↔ 1000 参数）；重复渲染字节一致；**INSERT prepare 返回行表而非平铺 (MED-6 类型漂移)**；INSERT boolean 类型不一致 |
| 5 幂等与状态 | to_sql 重复、to_prepare 重复字节一致；to_sql 后加 WHERE 再 to_sql 正常累积；DATA 后 VALUES 列错位 (HIGH-6)；VALUES 后 DATA 重置（文档化 A10 行为） |

## 已确认的良好行为（含证据）
- 确定性：全 9 方言 × 5 API 重复渲染字节一致（`spec/audit/invariants_spec.lua` + 实测）。
- 占位符对齐：`WHERE("a = ? AND b IN ?", 1, {2,3}) + OR + HAVING` prepare → 5 占位符 5 参数顺序正确（SQLBuilder.lua:144-174 的收集顺序 WHERE→OR→HAVING 与 SQL 文本顺序一致）。
- 干净显式报错：`PAGE(-1)`/`PAGE("abc")`（SELECT.lua:77）、`ORDER_BY` 非法 sortType（SQLBuilder.lua:81）、`PROCEDURE(nil)`（:124）、OR 子对象携带 ORDER/LIMIT/GROUP/HAVING（OR.lua:19）、缺参数 WHERE（NB-2 已锁定）、json.encode NaN（`unexpected number value`）。
- NB-1 回归验证：`WHERE("name LIKE ?", "50%")` → `'50%'`（gsub 函数替换修复有效）。
- 深链/大表：5000 层 OR、5000 个 WHERE、10k IN 均无崩溃/内存异常。

## 运行记录
- `lua spec/run.lua` → 226 passed, 1 failed (stale clickhouse expectation), 4 pending
- 45+ 组对抗探针（.pi-subagents/artifacts/adversarial_test.lua）—— 全部输出已核对
- sqlite3 实证 JSON path 非法性
