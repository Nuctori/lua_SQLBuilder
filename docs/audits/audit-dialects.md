# 方言实现交叉审计报告 — oracle / duckdb / clickhouse（含全部 9 预设）

审计对象：`D:/lua/lua_SQLBuilder`（Lua SQL 构造库，方言为配置表 `lua_SQLBuilder/dialect.lua`）
审计方式：源码核对 + Lua 5.4.6 实际执行（`lua spec/run.lua` 与 `lua -e`/脚本渲染核对）+ SQLite json1 真实执行验证。
只读审计，未修改任何仓库文件（git working tree clean @ 126a9ca）。

---

## 结论速览

- 9 预设 × 5 字段（quote_ident / json_path / escape_string / render_limit / upsert）结构完整；invariant 审计矩阵（9 方言 × 5 API）全覆盖且本地通过：**235 passed / 0 failed / 4 pending**（pending 为本地缺驱动跳过的 integration 用例）。
- **P1【高危】** JSON 数组路径渲染为 `$.key.[N]`（方括号前多点号）——SQLite json1 实测报错，影响 ansi/mysql/mariadb/sqlite/mssql/oracle/duckdb 7 个 `$` 路径方言。
- **P2【中高危】** ClickHouse 布尔 JSON 查询 `IS NULL`/`IS NOT NULL` 语义失效。
- 其余为中/低危与观察项（P3–P8）。

---

## P1【高危】JSON 数组路径 `$.key.[N]`（点号+方括号）非法 — ansi/mysql/mariadb/sqlite/mssql/oracle/duckdb

位置：`lua_SQLBuilder/utils.lua:96`（`path = fatherPath .. segment`，父路径以 `.` 结尾）+ `lua_SQLBuilder/dialect.lua:110-133`（各 `json_path_*`）。
复现（Lua 5.4.6 实际渲染）：

```lua
SELECT("*", {dialect="sqlite"}):FROM("user"):QUERY({profile={tags={"x","y"}}}):to_sql()
-- => SELECT * FROM user WHERE (CAST(json_extract("profile", '$.tags.[0]') AS TEXT) = 'x'
--      AND CAST(json_extract("profile", '$.tags.[1]') AS TEXT) = 'y')
-- mysql: `profile`->>'$.tags.[0]'   oracle: JSON_VALUE("PROFILE", '$.tags.[0]')
-- mssql: JSON_VALUE([profile], '$.tags.[0]')   duckdb: json_extract_string("profile", '$.tags.[0]')
-- ansi:  "profile"->>'$.tags.[0]'   mariadb: 与 mysql 同形
```

SQLite json1 真实验证（本机 sqlite3 实测，本次审计复跑复现）：

```
json_extract('{"tags":["x","y"]}', '$.tags[0]')  --> x        （规范写法 OK）
json_extract('{"tags":["x","y"]}', '$.tags.[0]') --> Error: stepping, bad JSON path: '$.tags.[0]'
json_extract('[1,2]', '$[0]')                    --> 1        （顶层数组规范写法 OK）
json_extract('[1,2]', '$.[0]')                   --> Error: stepping, bad JSON path: '$.[0]'
json_extract('{"a":[{"b":1}]}', '$.a[0].b')      --> 1        （深层规范写法 OK）
json_extract('{"a":[{"b":1}]}', '$.a.[0].b')     --> Error: stepping, bad JSON path: '$.a.[0].b'
```

差异说明：所有标准 JSON path 方言（MySQL 5.7+/MariaDB、SQLite json1、SQL Server 2016+、Oracle 12c+、DuckDB）的规范形式是 `$.key[N]` / `$[N]` —— `.` 后必须跟成员名，`[` 是独立步。`.[` 拼写在 MySQL（`is_path_stop` 使 `[` 终止未引号 keyName → “Invalid JSON path expression” 或空键查找）、SQL Server、Oracle（SQL/JSON path 语法）、DuckDB 上均为解析错误或错误键查找，无法命中 `tags[0]`。
Postgres 与 ClickHouse 恰好正确（按 `.` 分段后把 `[N]` 拆成独立段/独立参数：`->'tags'->>0`、`JSONExtractString(col,'tags',0)`）——正是这种“两套解析方式”暴露了 7 个 `$` 方言与 2 个分段方言的跨方言不一致。
覆盖缺口：`spec/unit` 无 `$.k.[N]` 断言；`spec/integration/json_spec.lua` 只测标量/嵌套对象路径；fixtures 种了 `tags` 数组但从不查询 → CI 六库全部测不到。
修复建议：`Make_JsonQuery` 仅对象键段间加 `.`（产出 `key[N]`），`json_path_postgres`/`json_path_clickhouse` 对每段做 `^(.*)%[(%d+)%]$` 拆分尾部下标；integration json_spec 增加数组查询用例（全方言）。

## P2【中高危】ClickHouse 布尔 JSON：`IS NULL`/`IS NOT NULL` 语义失效

位置：`utils.lua:113-117`（布尔分支拼接 `IS (NOT) NULL`）+ `dialect.lua:140-148`（json_path_clickhouse）。
复现（实际渲染）：

```lua
SELECT("*", {dialect="clickhouse"}):FROM("user"):QUERY({profile={flag=true}}):to_sql()
-- => SELECT * FROM user WHERE (JSONExtractString(`profile`, 'flag') IS NOT NULL)
SELECT("*", {dialect="clickhouse"}):FROM("user"):QUERY({profile={flag=false}}):to_sql()
-- => SELECT * FROM user WHERE (JSONExtractString(`profile`, 'flag') IS NULL)
```

差异说明：ClickHouse `JSONExtractString` 返回类型是不可空 String，键缺失时返回 `''`（绝不返回 NULL）。因此 `IS NULL` 恒假（`flag=false` 永不命中）、`IS NOT NULL` 恒真（`flag=true` 连缺键行都命中）——静默错误结果。其余方言（mysql `->>`、pg `->>`、sqlite json_extract、JSON_VALUE、json_extract_string）缺键均返回 NULL，presence 语义（known_bugs A3 记载的设计）在那些方言成立。integration json_spec 无布尔用例，CI 未覆盖。
修复建议：ClickHouse 布尔分支改渲染 `JSONHas(col,'key')`（或 `JSONExtractString(...) <> ''`），即布尔分支需按方言渲染而非公共拼接。

## P3【中危】JSON 路径键名零转义（全部方言）

位置：`utils.lua:90-96`（segment 直接取 Lua 键名）。
- 键含 `.`（如 `["a.b"]`）：被当作嵌套路径 `a.b`；INSERT 侧 json.encode 写字面键 `"a.b"` → 同一库写入的数据 QUERY 永远查不中；
- 键含 `'`：`'$.O'Brien'` 直接破坏 SQL 字面量（`$` 路径方言）；ClickHouse 的 `'a.b'` 也被 `gmatch("[^.]+")` 错拆；
- 字符串键 `"0"`（`tonumber("0")==0` 为假）按文本键处理，数值键 0/1 按下标处理，不一致。

## P4【低危】ClickHouse 复用 MySQL 转义表，字节 0x1A 渲染 `\Z` 为无效转义

位置：`dialect.lua:56`（`['\26'] = "\\Z"`）+ `dialect.lua:241`（clickhouse.escape_string = escape_mysql）。
复现（实测）：`escape_string("a\26b")` → `a\Zb`；`INSERT ... VALUES (1, 'a\Zb')`。ClickHouse 字符串转义不支持 `\Z`（未知转义丢弃反斜杠 → `'aZb'`），含 0x1A 字节的字符串静默损坏。map 其余条目（`\0 \b \n \r \t \\ \'`）均为 ClickHouse 合法转义。

## P5【观察】"ansi" 预设的 json_path 非 ANSI 标准

位置：`dialect.lua:126-129`。ansi 预设用 `->>'$.a'`（MySQL/PostgreSQL 事实语法），严格 ANSI SQL:2016 的 JSON_VALUE/JSON_QUERY 会拒绝。代码注释已声明是约定，但命名为 “ansi” 有误导性，建议文档注明。

## P6【观察】mssql 的 OFFSET/FETCH 依赖 ORDER BY；mariadb/mssql 无 CI 真库集成

- `dialect.lua:83-87` render_limit_mssql：SQL Server 要求 OFFSET/FETCH 前置 ORDER BY（无 ORDER BY 时报错）；Oracle 12c+ 不要求，CI oracle 分页用例已实测通过。
- CI（`.github/workflows/ci.yml`）真实数据库覆盖 6/9：mysql、postgres、sqlite、duckdb、clickhouse（HTTP）、oracle；mariadb、mssql 仅有预设无 CI job（与 readme.md:32-33、135 声明一致）。mariadb `->>` 需 10.2.3+、mssql OFFSET/FETCH 需 2012+，均未在真库验证。

## P7【观察】oracle upsert = nil，但 Oracle 23ai 已支持 ON CONFLICT

`dialect.lua:227`：`upsert = nil`（MERGE 独立语句）。CI 镜像 gvenzl/oracle-free:23（23ai 支持 `INSERT ... ON CONFLICT DO UPDATE`）；保留 nil 对 12c–21c 可移植性稳妥，可作后续选项。另注意 fixture `profile VARCHAR2(4000)` 无 `IS JSON` 约束，真实数据含非 JSON 文本时 JSON_VALUE 抛 ORA-40441（MySQL JSON 列类型无此问题）。

## P8【观察】JSON 布尔 = presence 语义（README 未说明）

`QUERY({flag=true})` 匹配“键存在”的所有行（含 `{"flag":false}`）；`flag=false` 匹配“键缺失”的行 —— A3 记载的设计，但 README 未说明；且无法表达“flag 等于 false”。

---

## 核对无误的部分（证据）

- **quote_ident（9 方言）**：ansi/pg/sqlite/duckdb `"x"`+`""` 加倍；mysql/mariadb/clickhouse 反引号+`` `` `` 加倍；mssql `[x]`+`]]`；oracle 大写+加倍（`dialect.lua:43-46`，unquoted DDL 存大写 → `"USER"` 引用匹配，unit 断言通过）。
- **escape_string**：`escape_ansi`（`''` 加倍、反斜杠字面）对 pg（standard_conforming_strings=on）、sqlite、mssql、oracle、duckdb（standard-conforming strings）正确；`escape_mysql` 对 mysql/mariadb 正确（clickhouse 除 `\Z` 外正确，实测 `'O\'Brien'` 渲染合法）。
- **render_limit**：`count OFFSET offset`（mysql/pg/sqlite/duckdb/clickhouse 均合法，实测 `LIMIT 20 OFFSET 10`）；`OFFSET n ROWS FETCH NEXT m ROWS ONLY`（mssql/oracle 12c+ 合法，实测 `OFFSET 10 ROWS FETCH NEXT 20 ROWS ONLY`；`MakeLimitSql` 正确去除 LIMIT 关键字）；oracle 分页经 CI 真库验证。
- **upsert**：mysql `ON DUPLICATE KEY UPDATE`+字面值（needs_conflict=false 正确，实测）；pg `ON CONFLICT (col) DO UPDATE SET c = EXCLUDED.c`（EXCLUDED 大写正确）；sqlite/duckdb `excluded` 小写正确（DuckDB 官方写法，实测 duckdb 渲染 `ON CONFLICT ("user_id") DO UPDATE SET "like_count" = excluded."like_count"`）；CI 对 mysql/pg/sqlite/duckdb 真库 upsert 通过；oracle/clickhouse 无 upsert 时正确报错。
- **postgres 算子链**：`->'a'->0->>'b'` 合法（`->`/`->>` 接受整型下标），实测嵌套数组渲染正确。
- **oracle JSON_VALUE**：`JSON_VALUE("JSON", '$.star')` 12c+ 语法正确；路径键保持原样（Oracle JSON path 键区分大小写，与文档键一致）；列名大写引用与 unquoted DDL 匹配；`'O''Brien'` 转义正确。
- **duckdb**：`json_extract_string(col, '$.a[0].b')` 返回 VARCHAR、`ON CONFLICT ... excluded` 均为官方语法，CI 真库通过。
- **clickhouse JSONExtractString 参数化路径**：键列表 `'a','b'` + 数字下标 `0`（实测 `JSONExtractString(`profile`, 'a', 0, 'b')`）为 ClickHouse 合法写法，unit 断言通过。
- **invariant 审计矩阵**：`spec/audit/invariants_spec.lua` 覆盖 9 方言 × 5 API（base/select/update/insert/delete）的确定性 + to_sql/to_prepare 幂等性 + 无变更/转义/占位符对齐不变量 —— 本地全绿（235 passed / 0 failed / 4 pending，本次复跑复现）。

---

## 建议修复优先级

1. P1：规范化 JSON 路径为 `key[N]`，同步调整 pg/clickhouse 分段解析；新增 integration 数组用例锁回归。
2. P2：ClickHouse 布尔 JSON 分支改用 `JSONHas`。
3. P3：路径键方言感知转义（`.`,`[`,`]`,`'`,`\` 需引号包裹，如 MySQL `$."a.b"`、SQLite `$."a.b"`），或文档声明限制。
4. P4：ClickHouse 转义表移除 `\Z`（0x1A 改走其他表示）。
