local class = require "lua_SQLBuilder.class"
local LIMIT = class("LIMIT")

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
    -- 数值校验：offset/count 必须是非负数字，防注入与非法 SQL（M5）
    if offset ~= nil and offset ~= "" then
        offset = tonumber(offset)
        assert(offset ~= nil and offset >= 0, "LIMIT offset must be a non-negative number, got: " .. tostring(p1))
    end
    if count ~= nil then
        count = tonumber(count)
        assert(count ~= nil and count >= 0, "LIMIT count must be a non-negative number, got: " .. tostring(count))
    end
    self.limit = { offset, count }
end

-- Rendering is dialect-specific ("count OFFSET offset" for mysql/pg/sqlite,
-- "OFFSET n ROWS FETCH NEXT m ROWS ONLY" for SQL Server).
function LIMIT:to_sql()
    local offset, count = self.limit[1], self.limit[2]
    if count == nil then
        return ""
    end
    return self._dialect.render_limit(offset, count)
end

return LIMIT
