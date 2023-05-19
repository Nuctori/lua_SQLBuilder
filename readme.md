# SqlBuilder Library

The SqlBuilder library provides a flexible and convenient way to construct SQL statements in Lua. It offers a basic SQLBuilder object that provides interfaces to construct any SQL statement, including WHERE, OR, ORDER_BY, DESC, ASC, GROUP_BY, HAVING, LIMIT, FOR_UPDATE, and PROCEDURE. 

## Usage

### Basic Usage

To create an SQL statement, simply create an instance of the SQLBuilder object and start chaining methods to construct the query. The `to_sql()` method can be used to retrieve the constructed SQL statement as a string.

```lua
local SQLBuilder = require "sqlbuilder"
local sqlBuilder = SQLBuilder.SQLBuilder

local sql = sqlBuilder("SELECT * FROM user"):WHERE("id > ?", 2):ORDER_BY("user"):DESC():ORDER_BY("id"):ASC():to_sql()
```

### Prepared Statements

SqlBuilder supports prepared statements to avoid SQL injection problems. The `to_prepare()` method can be used to retrieve the SQL statement with placeholders and the associated parameters as a table.

```lua
local sql, id = sqlBuilder("SELECT * FROM user"):WHERE("id > ?", 2):ORDER_BY("user"):DESC():ORDER_BY("id"):ASC():to_prepare()
```

### Multi-Table Queries

SqlBuilder can be used to construct complex multi-table queries as well.

```lua
local sql = sqlBuilder("SELECT * FROM user AS u, book AS b"):WHERE("b.user_id = u.id"):LIMIT(1,10):to_sql()
```

### OR Queries

For OR queries, an additional SqlBuilder object needs to be created. This is not automatically created within the interface to add flexibility to the construction of SQL statements.

```lua
local sql = sqlBuilder("SELECT * FROM user"):
          WHERE("id > ?", 1):WHERE("name != ?", 'admin'):
          OR(sqlBuilder():WHERE("name = ?", 'user_1'):WHERE("name = ?", "user_2"):
          OR(sqlBuilder():WHERE("ct = ?", 0))):
          to_sql()
```

### SELECT, UPDATE, INSERT, and DELETE Objects

SqlBuilder provides SELECT, UPDATE, INSERT, and DELETE objects. These objects inherit from SqlBuilder but provide additional interfaces to create simpler SQL statements.

#### SELECT Object

The SELECT object provides the QUERY, PAGE, and PER interfaces to simplify the construction of SELECT statements.

```lua
local sql = SELECT("*"):FROM("book"):QUERY({user_id=1, status=1}):PAGE(10):PER(2):to_sql()
```

The QUERY interface also supports generating JSON queries for MySQL 5.7 and above.

```lua
local sql = SELECT("*"):FROM("book"):QUERY({user_id=1, status=1, json = {star = 5}}):PAGE(10):PER(2):to_sql()
```

#### UPDATE Object

The UPDATE object providesthe SET interface to simplify the construction of UPDATE statements. The SET interface supports both table and string modes. In table mode, the query parameters are unordered.

```lua
local sql = UPDATE("user"):SET({score=100, status="pass"}):WHERE("id = ?", 1):to_sql()
```

#### INSERT Object

The INSERT object provides the DATA and VALUES interfaces to simplify the construction of INSERT statements. The DATA interface generates unordered SQL statements.

```lua
local sql = INSERT("user"):COLS("id", "name"):VALUES({1, 'name1'}, {2, 'name2'}):to_sql()
```

The INSERT object also provides the ON_DUPLICATE_KEY_UPDATE interface.

```lua
local sql = INSERT("like"):DATA({
    user_id = 1,
    like = 1,
}):ON_DUPLICATE_KEY_UPDATE({
    like = 1
}):to_sql()
```

#### DELETE Object

The DELETE object provides the QUERY interface to simplify the construction of DELETE statements.

```lua
local sql = DELETE("user"):QUERY({
    id = 1
}):to_sql()
```
