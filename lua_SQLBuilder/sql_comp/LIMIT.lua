local class = require "lua_SQLBuilder.class"
local LIMIT = class("LIMIT")
local fmt = string.format

function LIMIT:ctor()
    self.limit = {}
end

function LIMIT:add(p1, p2)
    local offset
    local count
    if p1 and not p2 then
        offset = 0
        count = p1
    else
        offset = p1
        count = p2
    end
    self.limit = {offset or "", count}
end

function LIMIT:to_sql()
    return table.concat(self.limit, ", ")
end


return LIMIT