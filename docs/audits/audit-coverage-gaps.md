# lua_SQLBuilder 单元测试覆盖缺口独立审计报告

- 审计日期: (current run)
- 审计对象: `lua_SQLBuilder/` 全部库文件 + `spec/unit/*` + `spec/audit/invariants_spec.lua` + `spec/production/curd_spec.lua`
- 基线: `lua5.4 spec/run.lua` → **96 passed, 0 failed, 14 pending**（integration 因本地无驱动跳过，与 CI 门控一致）
- 方法: 逐文件通读 + 探针脚本实证验证每个可疑分支（所有行为结论均经实际执行确认，非推断）
- 行号基于当前 HEAD (7f6ee03)

---

## 1. 未被任何测试覆盖的公开 API / 方法 / 分支

### 1.1 完全零覆盖的公开方法

| 方法 | 位置 | 现状 |
| --- | --- | --- |
| `SQLBuilder:Dialect()` | SQLBuilder.lua:52 | 返回 `self._dialect.name`，无任何测试调用 |
| `SQLBuilder:PrepareTableOperator()` | SQLBuilder.lua:57 | base 直接返回 `TableOperator()`，无直接测试（仅经 `to_prepare` 间接） |
| `init.set_default_dialect / get_default_dialect` | init.lua:26-31 | 零测试（探针确认可用；错误名触发 `assert`） |
| `dialect.set_default / get_default / resolve` 错误路径 | dialect.lua:97-105 | 零测试（`resolve("oracle")` 抛错路径未覆盖） |
| `utils.quote_to_str` | utils.lua:20 | 零测试（探针: `a'b\c` → `a\'b\\c`） |
| `utils.clear_table` | utils.lua:26 | 零测试（递归转义；不改原表） |
| `utils.ORM_warpper` | utils.lua:40 | 零测试（防注入装饰器，探针验证会转义字符串参数） |
| `utils.table_format` | utils.lua:83 | 零测试 |
| `utils.Make_Query` | utils.lua:102 | 零测试（`Make_Query({a="x"})` → `` `a`='x' ``） |
| `utils.SortTable` | utils.lua:112 | 零测试 |
| `json.encode/decode` | json.lua | 库内仅用 encode（INSERT DATA/UPDATE 表模式/render_value）；`decode` 全库死代码，零测试 |
| `class(name, super)` | class.lua | 仅间接覆盖；继承、`__cname`、默认 ctor 无直接测试 |

### 1.2 有间接覆盖但关键分支未覆盖的方法

**SQLBuilder**

- `ORDER_BY(fieldName, sortType)` 两参形式 (SQLBuilder.lua:65-68): 所有测试只用单参。**实证：`ORDER_BY("id","DESC")` 输出 `ORDER BY id ASC, DESC ASC`** —— `sortType` 被 `ORDER:add` (sql_comp/ORDER.lua:9-12) 当作另一列追加，两参形式实际是坏的，且零测试。
- `DESC(isDesc)/ASC(isAsc)` 显式实参: 只测了无参默认。`DESC(false)`/`ASC(false)`/`ASC()` 未测。
- `HAVING` 的 `to_prepare` 路径 (SQLBuilder.lua:146): **prepare 模式用 `_having:to_sql()`，参数不进 params，字符串参数被内联成带引号字面量**。测试只覆盖 `to_sql`。实证：`HAVING("COUNT(*) > ?", 5):to_prepare()` → SQL 内联 `COUNT(*) > 5`，返回 params=nil。
- `LIMIT` 无参/字符串/零 count (LIMIT.lua:26-36): 只测了 (10)、(1,10)、(0,10)。实证：`LIMIT()` → 空；`LIMIT("x",10)` → `LIMIT 10 OFFSET x`（非法 SQL 无校验）；`LIMIT(10,0)` → `LIMIT 0 OFFSET 10`。
- `PROCEDURE` prepare 路径 + 非 string 断言 (SQLBuilder.lua:106-111): 只测了 to_sql。实证：`PROCEDURE(1)` 抛 assert；procedure 内 `?` 保持字面量不进 params。
- `FOR_UPDATE` 的 prepare 路径: 未测。
- `to_sql` 组合全栈（WHERE+GROUP+HAVING+ORDER+LIMIT+FOR_UPDATE 同时）: 未测（探针验证可组合）。

**SELECT**

- `QUERY` 的 userdata 分支 (SELECT.lua:59-61): 零测试。实证：`QUERY({deleted=io.stderr})` → `` WHERE (`deleted` is NULL) ``。
- `QUERY` boolean 分支 (SELECT.lua:62-64): 仅 A4 pending（不执行）。实证：`QUERY({validate=true}):to_sql()` → `` WHERE (`validate` = 'true') ``（字符串带引号，A4 未修）；`false` → `'false'`。
- `QUERY({})` 空表 / nil 值: 空表 → 无 WHERE（探针验证）；`{a=nil}` 键不存在等价空表。
- `PAGE`/`PER` 边界 (SELECT.lua:73-84): 只测了正常值。实证：`PAGE(0):PER(10)` → `LIMIT 10 OFFSET -10`（非法）；`PAGE(nil)` 崩溃（算术）；`PER` 在 `PAGE` 前调用崩溃（`assert(self.page)`）；`PER(0)` → `LIMIT 0`；`PAGE("3")` 字符串 OK（未测）；`PAGE(1)` 单独 → `LIMIT 10`（默认 per=10，未测）。
- ctor 尾参 table 误判 (SELECT.lua:10-16): `SELECT("id", {1,2})` 会把最后字段当 opts 吞掉 → `SELECT id FROM t`（静默丢字段，零测试）。
- 空字段/空 FROM: `SELECT()` → `SELECT  FROM t`（双空格非法 SQL）；`FROM()` → `SELECT * FROM`。
- `fileds` 兼容别名: 未测（琐碎）。

**UPDATE**

- `TableOperator` 表模式各类型 (UPDATE.lua:30-48): 只测了 number/string。实证：boolean → `` `del` = false ``；nil 值 → 键被 pairs 跳过 → `UPDATE t SET`（空 SET 非法）；table 值 → `` `profile` = '{"k":1}' ``（内联 JSON）。
- `TableOperator` 字符串模式: userdata → NULL（实证）；nil param → 原样 `score = ?`（字面量）；多 `?` 只替换第一个（实证 `SET("a = ? AND b = ?", 1)` → `a = 1 AND b = ?`）。
- `PrepareTableOperator` 字符串模式 (UPDATE.lua:50-68): 仅 A1 pending（不执行）。实证：`SET("score = score + ?", 1)` prepare → `score = score + ? = ?`（**双占位符 bug 仍在**）；`SET("score = ?", nil)` prepare → `score = ??`；表模式 JSON 值 prepare → json 字符串作单参数绑定（未测）。
- `SET` 非 table/string 断言 (UPDATE.lua:79): 零测试（实证 `SET(42)` 抛 "setData must table or string"）。
- 未调用 SET: `UPDATE("t")` → `UPDATE t SET`（非法 SQL，零测试）。

**INSERT**

- `__getInsertValue` 各类型: 只测 number/string/table(经 DATA)。实证：boolean → `(1, true)`（MySQL 下 TRUE 兼容但未验证）；nil 值 → 行被压缩 `(1)`，列数不匹配（**静默产生错误 SQL**）；空 VALUES → `VALUES` 尾随空格。
- `__getPrepareInsertValue` boolean: 实证 `row2=true` 原样绑定（lsqlite3/pgmoon 等驱动对 boolean 绑定行为未验证，无集成测试）。
- 空表/无列: `INSERT("t")` → `INSERT INTO t () VALUES`。
- `COLS`/`VALUES` 类型断言 (INSERT.lua:115-129): 零测试（实证 `COLS(1)`、`VALUES("x")` 抛 assert）。
- `ON_DUPLICATE_KEY_UPDATE`: 只测了 mysql 单 key 字符串、postgres 字符串 conflict。实证未覆盖：conflictCols 为 table（输出 `ON CONFLICT ("a", "c")`，正常）；sqlite 方言（`excluded.` 引用）；空 update `{}` → 退化为普通 INSERT；update 值为 table（内联 JSON）。
- `DATA` + `COLS`/`VALUES` 混用: 未测（实证可按位置对齐生成，属隐性陷阱）。

**DELETE**

- `QUERY` 的 JSON 分支 (DELETE.lua:29-41): 零测试（实证 `` WHERE (`json`->>'$.k' = '1') `` 正常）。
- `QUERY` userdata: **实证 `` WHERE (`deleted` = NULL) `` —— 与 SELECT 的 `is NULL` 不一致，`= NULL` 在 SQL 中永不匹配**。
- `QUERY` boolean/空表: 未测。`{a=false}` → `` `a` = ? `` 字面量。
- `QUERY` 的 prepare 参数序: 未测（实证参数顺序正常）。

**sql_comp**

- `WHERE:to_sql` table-string 分支（变异 + A19）: 仅 pending。
- `WHERE:to_sql` userdata 分支 (WHERE.lua:28): 零测试（实证 → `NULL`）。
- `WHERE` falsy param (false) → 字面量 `?`（A5 未修）: 仅 pending。
- `WHERE:to_prepare` nil param / table param: 实证 table param 作为**单个 Lua table 参数**返回（`WHERE("id in ?", {1,2}):to_prepare()` → params={ {1,2} }），真实驱动无法绑定 table —— IN-clause prepare 场景仅 production 的 to_sql 有测试。
- `OR:to_sql` 空子构建器 / 子构建器无 WHERE（仅 GROUP）: 零测试（实证被静默丢弃）。
- `ORDER:desc` 非 boolean (ORDER.lua:15-19): 零测试（实证抛 assert）。
- `GROUP:add` 多参数/无参: 零测试（实证多参 → `GROUP BY a, b`）。
- `HAVING:add` nil/table param (HAVING.lua:10-16): 零测试。实证：nil → `gsub` 崩溃 "bad argument #3"；table → 字面量 `?` 保留。
- `LIMIT:add/to_sql` 字符串 offset、负值、count=0: 零测试。

**utils.Make_JsonQuery**

- 数字键（数组 JSON）: 零测试（实证 → `'$.arr."0"'`）。
- boolean 分支 (A3): 仅 pending；实证返回**裸字符串**（`tbl->>'$.flag' IS NOT NULL`），调用方 `jsonSQL[1]` 取到第一个字符 → 垃圾 SQL。
- 空 query `{}`: 零测试。
- postgres 路径含点键: 实证 `{["a.b"]=1}` 被 `gmatch("[^.]+")` 拆成 `->'a'->>'b'`（与 mysql/sqlite 的 `$.a.b` 语义不一致，潜在 bug）。

---

## 2. 与真实行为可能不符的 golden 断言

| # | 位置 | 断言 | 实证行为 | 判定 |
| --- | --- | --- | --- | --- |
| G1 | spec/unit/insert_spec.lua:46-49 "DATA renders JSON values" | `'{"star":5}'` | 单 key 目前稳定；但 `json.encode` 多 key 顺序**跨进程不稳定**（4 次运行出现 `{"z":1,"m":3,"a":2}` / `{"z":1,"a":2,"m":3}` / `{"m":3,"z":1,"a":2}`，Lua 5.4 随机哈希种子） | ⚠️ 未来多 key JSON golden 必 flaky；当前单 key 恰好安全 |
| G2 | spec/audit/invariants_spec.lua "determinism" | 同输入同输出 | 仅在**同进程内**成立（同种子）；跨进程/CI 重启后含 JSON 值的 INSERT/UPDATE 输出可能不同，断言强度超出实际保证 | ⚠️ 建议加跨进程验证或限定声明 |
| G3 | spec/unit/known_bugs_spec.lua A4/A5/A19/B1 | pending 期望 | 与当前行为不符是 pending 的本意；但注意 A4 的 `to_prepare` 已返回 `validate = ?`，仅 to_sql 未修 | ℹ️ 无问题，但修复时 A4 断言需同时覆盖 to_sql+prepare |
| G4 | spec/production/curd_spec.lua "init.lua demo: raw query strings pass through" | `AND ' or 1='1` 原样透传 | 与当前代码一致；B1 转义落地后此 golden 必须更新（测试注释已声明） | ℹ️ 已知 |
| G5 | usage.lua:51,57,63（项目文档，非测试） | `LIMIT 18, 2`、`json->>'$.star' = 5`、`= '?'` | 实际输出 `LIMIT 2 OFFSET 18`、`= '5'`（带引号）、A2 修复后为真占位符 | ❌ 文档与行为脱节，建议更新 |
| G6 | spec/unit/select_spec.lua "renders JSON queries..." | `'`json`->>'$.star' = '5'` | 与代码一致；但 `->>` 需要 MySQL ≥ 5.7.13/MariaDB ≥ 10.2.3，而 LIMIT 注释声称 MySQL ≥ 4.0.1 —— 方言版本声明不一致 | ⚠️ 文档级矛盾 |
| G7 | spec/unit/delete_spec.lua "QUERY builds a deterministic WHERE" | 仅数字等值 | 未覆盖 userdata：DELETE 实际产出 `` `deleted` = NULL ``（SQL 永不匹配，静默删 0 行）而 SELECT 产出 `is NULL` | ❌ 行为不一致，需加测试+修复 |
| G8 | spec/unit/sqlbuilder_spec.lua "nests OR groups" | `WHERE (id > 1 AND name != 'admin') OR (name = 'user_1' AND name = 'user_2') OR (ct = 0)` | 与代码一致（嵌套 OR 展平到同层） | ✅ 匹配 |
| G9 | spec/unit/update_spec.lua "SET string mode..." | `SET("score = score + ?", 1)` → `score = score + 1` | 与代码一致（单 `?` 时）；但同一代码路径多 `?` 时只替换第一个 | ℹ️ 单占位符断言对，多占位符场景缺失 |

真实 DB 行为风险（无集成测试佐证的 golden 面）：

- INSERT/VALUES/UPDATE 表模式的 **boolean 参数**在 prepare 模式原样绑定（探针 `row2=true`），lsqlite3/LuaSQL/pgmoon 对 boolean 绑定支持未验证。
- `WHERE("id in ?", {...}):to_prepare()` 把 **table 整体作为单个绑定参数**，真实驱动会绑定失败；生产用例（at_users.lua）只走 to_sql。

---

## 3. 每个构建器缺失的边缘用例（已实证）

- **SQLBuilder**: `WHERE("x = ?")` 无参 → 字面量 `?`；`WHERE("a=? AND b=?", 1)` 只替换第一个；多条件 + OR 参数序（main WHERE → OR → 追加 WHERE，实证 `(a=? AND c=?) OR (b=?)` 参数 1,3,2）无文档/测试。
- **SELECT**: `PAGE(0/-1/nil/字符串)`、`PER` 先于 `PAGE`、`PAGE` 单独默认 per=10、`QUERY` 空表/userdata/boolean、尾参 table 误判、空字段。
- **UPDATE**: 无 SET、SET 表模式 nil/boolean/table 值、字符串模式 nil param/multi-`?`/userdata、`SET` 非 string/table、prepare 字符串模式（A1 双占位符仍坏）。
- **INSERT**: 空 VALUES/无 COLS、VALUES 行内 nil（行压缩列数错位）、boolean 值、`COLS`/`VALUES` 类型断言、upsert 的 sqlite/conflict table/空 update/table 值、DATA+VALUES 混用。
- **DELETE**: `QUERY` JSON/空表/boolean/userdata（`= NULL` 陷阱）、prepare 参数序。
- **组合调用**: 全栈 to_sql 未测（实证可组合）；`OR` 子构建器无 WHERE；`GROUP_BY` 多列；`PROCEDURE`+`LIMIT` 顺序。

---

## 4. 优先级排序建议（P0=高价值缺失 / P1=建议 / P2=可选）

### P0 — 高价值缺失（公开 API 上可触达的真实 bug，零测试）

1. **`ORDER_BY(field, sortType)` 两参形式损坏**（SQLBuilder.lua:65 / sql_comp/ORDER.lua:9）
   实证输出 `ORDER BY id ASC, DESC ASC`。建议测试：`ORDER_BY("id","DESC")` 期望 `ORDER BY id DESC`（修复 ORDER:add 忽略 sortType 或去掉两参签名）+ 回归。
2. **`to_prepare` + `HAVING` 参数丢失**（SQLBuilder.lua:146）
   prepare 模式 HAVING 参数被内联、不返回。建议测试：`GROUP_BY:HAVING("COUNT(*) > ?", 5):to_prepare()` 断言与 WHERE 相同的占位符/参数对齐契约；字符串参数必须进 params 而非内联。
3. **UPDATE 字符串模式 prepare 双占位符（A1 仍坏）**（UPDATE.lua:50-68）
   实证 `score = score + ? = ?`。建议测试：现有 A1 pending 翻转 + 多 SET 与 WHERE 参数序 `SET("score=score+?",1):SET("status=?", "pass"):WHERE("id=?",1)` 断言 SQL 与参数一一对应。
4. **`PAGE` 边界值**（SELECT.lua:73-84）
   实证 `PAGE(0)` → `LIMIT 10 OFFSET -10`、`PAGE(nil)` 崩溃、`PER` 前置于 `PAGE` 崩溃。建议测试：`PAGE(0)`/负数/非数字抛错或钳位到 ≥0；`PER` 独立调用抛错信息断言。
5. **falsy/nil 参数字面量 `?` 族**（WHERE.lua:14-26, SELECT.lua:62-64, DELETE.lua:29-41）
   实证 `WHERE("x=?", false)`、`QUERY({a=false})` → 字面量 `?`。建议测试：false/0/"" 参数在 to_sql 与 to_prepare 下的行为（A5 翻转 + DELETE/UPDATE 同族）。
6. **IN-clause prepare 绑定**（WHERE.lua:34-40）
   实证 `WHERE("id in ?", {1,2}):to_prepare()` 返回单 table 参数。建议测试：断言 prepare 参数形态（期望逐值展开或明确文档不支持）；至少加一条 `to_prepare` + IN 的防护性断言。

### P1 — 建议补充

1. **HAVING 的 nil/table 参数**（HAVING.lua:10-16）：`HAVING("x = ?")` 崩溃、`HAVING("x in ?", {1,2})` 字面量 `?` —— 与 WHERE 语义对齐测试。
2. **`DESC`/`ASC` 无 `ORDER_BY` 崩溃（A6）**：ORDER.lua:18 nil 索引；加错误路径测试。
3. **userdata 全链路**：WHERE→NULL、SELECT QUERY→`is NULL`、DELETE QUERY→`= NULL`（不一致，建议先加测试锁定差异再修复为 `is NULL`）、UPDATE SET→NULL、INSERT VALUES→NULL。
4. **UPDATE 表模式类型矩阵**：nil 值（当前静默丢列 → `UPDATE t SET` 非法 SQL）、boolean、table JSON、prepare JSON 参数形态。
5. **UPDATE 字符串模式**：nil param（to_sql 字面量 / prepare `??` 双问号）、多 `?` 只替换第一个、userdata→NULL。
6. **INSERT 空输入**：`INSERT("t")` / `VALUES()` / `COLS()` 空 → `INSERT INTO t () VALUES` 非法 SQL 错误路径；行内 nil 列数错位。
7. **INSERT upsert 方言矩阵**：sqlite `excluded.`、conflictCols table、空 update `{}`、update 值 table/boolean。
8. **DELETE QUERY 类型矩阵**：JSON、空表、boolean、userdata、prepare 参数序。
9. **LIMIT 边界**：`LIMIT()`、`LIMIT("x",10)`（`OFFSET x` 非法透传）、`LIMIT(10,0)`、负值。
10. **`QUERY`/`DATA`/`SET` 的 ctor 尾参 table 误判**：`SELECT("id", {1,2})` 吞字段。
11. **`set_default_dialect`/`get_default_dialect`/`resolve` 错误路径**（init.lua:26-31, dialect.lua:97-105）。
12. **`Make_JsonQuery` 直接单测**：数字键、空 query、默认方言、postgres 含点键拆解（语义不一致）。
13. **`utils` 全部纯函数**：quote_to_str / clear_table / ORM_warpper / table_format / Make_Query / SortTable / render_value 错误路径（function 类型）。
14. **`SELECT:QUERY` boolean 分支 to_prepare**：当前已返回 `= ?` + `"true"` 字符串参数，加绿测防止回归。

### P2 — 可选

 1. **json.lua**：decode 全库死代码但可作为工具测（roundtrip、错误路径）；encode 的 circular/sparse 错误路径。
 2. **class.lua**：继承链、`__cname`、默认 ctor、callable 语法 `class("X")(...)`。
 3. **组合调用**：全栈 to_sql/to_prepare 顺序 golden；`OR` 空子构建器；`PROCEDURE`+`LIMIT`。
 4. **`Dialect()` 访问器**、`fileds` 别名。
 5. **json.lua 模块加载副作用**：`require` 即向 stdout 打印 "We recommend using cjson..."（json.lua:1），影响测试输出整洁，建议测试/文档注明或改 warn。

---

## 5. 附注

- 所有探针验证已清理（未留在仓库）。
- 集成测试（spec/integration/*）本地因驱动缺失跳过，属预期门控；boolean 绑定、IN prepare 等"真实驱动行为"风险需在有驱动的 CI 上补集成用例。
- `progress.md`/`plan.md` 项目根不存在（任务描述路径不可用），审计未受影响。
