local SQLBuilder = require "lua_SQLBuilder.SQLBuilder"
local SELECT = require "lua_SQLBuilder.SELECT"
local UPDATE = require "lua_SQLBuilder.UPDATE"
local INSERT = require "lua_SQLBuilder.INSERT"
local DELETE = require "lua_SQLBuilder.DELETE"

return {
    SQLBuilder = SQLBuilder,
    SELECT = SELECT,
    UPDATE = UPDATE,
    INSERT = INSERT,
    DELETE = DELETE,
}