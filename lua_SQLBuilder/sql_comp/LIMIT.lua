local class = require "lua_SQLBuilder.class"
local LIMIT = class("LIMIT")
local fmt = string.format

function LIMIT:ctor(dialect)
    self.limit = {}
    self._dialect = dialect
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
    self.limit = { offset, count }
end

-- Portable rendering: "count OFFSET offset" (offset 0 → just "count").
-- Supported by MySQL >= 4.0.1, PostgreSQL, and SQLite; the MySQL-only
-- "offset, count" comma form is deliberately not used.
function LIMIT:to_sql()
    local offset, count = self.limit[1], self.limit[2]
    if count == nil then
        return ""
    end
    if offset == nil or offset == "" or tonumber(offset) == 0 then
        return tostring(count)
    end
    return fmt("%s OFFSET %s", count, offset)
end

return LIMIT
