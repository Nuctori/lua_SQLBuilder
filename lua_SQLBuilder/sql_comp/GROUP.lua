local class = require "lua_SQLBuilder.class"
local ORDER = class("ORDER")
local fmt = string.format

function ORDER:ctor(dialect)
    self.groups = {}
    self._dialect = dialect
end

function ORDER:add(...)
    for _, group in ipairs({...}) do
        self.groups[#self.groups + 1] = group
    end
end

function ORDER:to_sql()
    return table.concat(self.groups, ", ")
end


return ORDER