local SQLBuilder = require "lua_SQLBuilder"
local sqlBuilder = SQLBuilder.SQLBuilder
local SELECT = SQLBuilder.SELECT
local UPDATE = SQLBuilder.UPDATE
local INSERT = SQLBuilder.INSERT
local DELETE = SQLBuilder.DELETE


-- SqlBuilder对象，是最基础的通用sql构造器，
-- SQLbuilder提供构建sql语句最基础的接口[WHERE, OR, ORDER_BY, DESC, ASC, GROUP_BY, HAVING, LIMIT, FOR_UPDATE, PROCEDURE]
-- 你可以使用该构造器构造出任意sql语句,使用to_sql，提取构建的sql字符串
local sql = sqlBuilder("SELECT * FROM user"):WHERE("id > ?", 2):
        ORDER_BY("user"):DESC():ORDER_BY("id"):ASC():to_sql()
assert(sql == "SELECT * FROM user WHERE (id > 2) ORDER BY user DESC, id ASC")

-- SqlBuilder同时支持生成prepare语句，避免注入问题
local sql, id = sqlBuilder("SELECT * FROM user"):WHERE("id > ?", 2):
        ORDER_BY("user"):DESC():ORDER_BY("id"):ASC():to_prepare()
print(sql, id)
assert(sql == "SELECT * FROM user WHERE (id > ?) ORDER BY user DESC, id ASC" and id == 2)

-- 比起使用ORM, 使用SqlBuilder生成复杂sql查询更具有优势，以下是多表查询的简单例子
sql = sqlBuilder("SELECT * FROM user AS u, book AS b"):WHERE("b.user_id = u.id"):LIMIT(1,10):to_sql()
print(sql)
assert(sql == "SELECT * FROM user AS u, book AS b WHERE (b.user_id = u.id) LIMIT 1, 10")

-- 对于需要使用OR的情况，需要构建额外的SqlBuilder对象(不在接口内部自动构建的原因是为了增加构造sql的灵活性)
local sql = sqlBuilder("SELECT * FROM user"):
              WHERE("id > ?", 1):WHERE("name != ?", 'admin'):
              OR(sqlBuilder():WHERE("name = ?", 'user_1'):WHERE("name = ?", "user_2"):
              OR(sqlBuilder():WHERE("ct = ?", 0))):
              to_sql()
print(sql)
assert(sql == "SELECT * FROM user WHERE (id > 1 AND name != 'admin') OR (name = 'user_1' AND name = 'user_2') OR (ct = 0)")

-- prepare模式面对复杂查询仍能表现良好
local sql, id, name1, name2, name3, ct = sqlBuilder("SELECT * FROM user"):
              WHERE("id > ?", 1):WHERE("name != ?", 'admin'): --
              OR(sqlBuilder():WHERE("name = ?", 'user_1'):WHERE("name = ?", "user_2"):
              OR(sqlBuilder():WHERE("ct = ?", 0))):
              to_prepare()
assert(sql == "SELECT * FROM user WHERE (id > ? AND name != ?) OR (name = ? AND name = ?) OR (ct = ?)")
assert(id == 1 and name1 =='admin' and name2 == "user_1" and name3 == "user_2" and ct == 0)

--- 此外，SqlBuilder库还提供了SELECT，UPDATE，INSERT，DELETE对象，这些对象都是继承自sqlBuilder，但提供额外的接口方便更简单的编写sql语句
--- SELECT 提供了 QUERY 接口简化查询语句编写, 但需要注意，QUERY接口生成的sql查询语句是无序的，在使用prepare模式下需要特别留意！
-- 同时 SELECT 提供了PAGE 和 PER 接口，让翻页查询更直观
local sql = SELECT("*"):FROM("book"):QUERY({user_id=1, status=1}):
        PAGE(10):PER(2):to_sql()
print(sql)
-- SELECT * FROM book WHERE (`status` = 1 AND `user_id` = 1) LIMIT 18, 2 ：unorder

--- QUERY 接口支持生成json查询语句(mysql5.7以上的特性)
local sql = SELECT("*"):FROM("book"):QUERY({user_id=1, status=1, json = {star = 5}}):
        PAGE(10):PER(2):to_sql()
print(sql)
-- SELECT * FROM book WHERE (`status` = 1 AND json->>'$.star' = 5 AND `user_id` = 1) LIMIT 18, 2

--- 使用QUERY接口依旧可以使用预处理，但查询参数返回顺序是无序的，需要注意！！
local sql, a, b, c, d, e = SELECT("*"):FROM("user"):QUERY({id=1, json={foo="bar", int=1, c={d=1}}, validate=true})
        :PAGE(10):PER(2):to_prepare()
print(sql, a, b, c, d, e)
-- SELECT * FROM user WHERE (`validate` = ? AND json->>'$.c.d' = ? AND json->>'$.int' = ? AND json->>'$.foo' = '?' AND `id` = ?) LIMIT 18, 2       true    1       1       bar     1

--- UPDATE只提供一个额外的SET接口，SET接口支持使用table模式和string模式,table 模式下，查询参数顺序是无序的
local sql = UPDATE("user"):SET({score=100, status="pass"}):WHERE("id = ?", 1):to_sql()
print(sql)
-- UPDATE user SET score = 100, status = 'pass' WHERE (id = 1)： unorder !

local sql = UPDATE("user"):SET("score = score + ?", 1):WHERE("id = ?", 1):to_sql()
assert(sql == "UPDATE user SET score = score + 1 WHERE (id = 1)")

local sql, score, status, id  = UPDATE("user"):SET("score = score + ?", 1):SET("status = ?", "pass"):WHERE("id = ?", 1):to_prepare()
assert(sql == "UPDATE user SET score = score + ? = ?, status = ? = ? WHERE (id = ?)")
assert(score == 1 and status == "pass" and id == 1)


--- INSERT 支持DATA 和 VALUES 两种插入方式
local sql = INSERT("user"):COLS("id", "name"):VALUES({1, 'name1'}, {2, 'name2'}):to_sql()
assert(sql == "INSERT INTO user (`id`, `name`) VALUES (1, 'name1'), (2, 'name2')")

local sql, data1, data2 = INSERT("user"):COLS("id", "name"):VALUES({1, 'name1'}, {2, 'name2'}):to_prepare()
assert(sql == "INSERT INTO user (`id`, `name`) VALUES (?, ?), (?, ?)")
print(data1[1], data1[2])
assert(data1[1] == 1 and data1[2] == "name1" and data2[1] == 2 and data2[2] == "name2")

--- INSERT 同时额外提供了“ON_DUPLICATE_KEY_UPDATE”接口
local sql = INSERT("like"):DATA({
    user_id = 1,
    like = 1,
}):ON_DUPLICATE_KEY_UPDATE({
    like = 1
}):to_sql()
print(sql)
-- INSERT INTO like (`like`, `user_id`) VALUES (1, 1) ON DUPLICATE KEY UPDATE `like` = 1: unorder

-- 使用DATA接口进行插入可以简化编写，但生成出来的SQL语句是无序的。
local sql = INSERT("user"):DATA({
    id = 1,
    name = 'name3'
}):to_sql()
print(sql)
-- INSERT INTO user (`id`, `name`) VALUES (1, 'name3'):  unorder !

-- DELETE 语句和SELECT 语句一样，额外提供了QUERY接口
local sql = DELETE("user"):QUERY({
    id = 1
}):to_sql()
print(sql)
-- DELETE FROM user WHERE (id = 1): unorder !

local sql, id = DELETE("user"):WHERE("id = ?", 1):to_prepare()
assert(sql == "DELETE FROM user WHERE (id = ?)" and id == 1)
print(sql, id)