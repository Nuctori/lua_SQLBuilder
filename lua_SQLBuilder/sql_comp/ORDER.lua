local class = require "lua_SQLBuilder.class"
local ORDER = class("ORDER")
local fmt = string.format

function ORDER:ctor()
    self.orders = {}
end

function ORDER:add(...)
    for _, order in ipairs({...}) do
        self.orders[#self.orders + 1] = {order, false}
    end
end

function ORDER:desc(boolean)
    boolean = boolean or false
    assert(type(boolean) == "boolean")
    self.orders[#self.orders][2] = boolean
end


function ORDER:to_sql()
    local orders = {}
    for _, v in ipairs(self.orders) do
        local order = v[1]
        local desc = v[2]
        orders[#orders + 1] = order..(desc and " DESC" or " ASC")
    end
    local sql = table.concat(orders, ", ")
    return sql
end


return ORDER