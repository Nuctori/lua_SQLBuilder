local class = require "lua_SQLBuilder.class"
local HAVING = class("HAVING")
local fmt = string.format

function HAVING:ctor()
    self.conditions = {}
end

function HAVING:add(query, param)
    if type(param) == "string" then
        param = fmt("'%s'", param)
    end
    self.conditions[#self.conditions + 1] = string.gsub(query, "?", param, 1)
end

function HAVING:to_sql()
    return table.concat(self.conditions, " AND ")
end


return HAVING