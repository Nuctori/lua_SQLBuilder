local class = require "lua_SQLBuilder.class"
local HAVING = class("HAVING")
local fmt = string.format

function HAVING:ctor(dialect)
    self.conditions = {}
    self._dialect = dialect
end

---@param query string 带 ? 占位符的条件片段
---@param ... 参数，与占位符一一对应
function HAVING:add(query, ...)
    self.conditions[#self.conditions + 1] = { query = query, params = { ... } }
end

local function count_placeholders(query)
    return select(2, string.gsub(query, "%?", ""))
end

local function render_scalar(dialect, v)
    local t = type(v)
    if t == "string" then
        return fmt("'%s'", dialect.escape_string(v))
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "userdata" then
        return "NULL"
    end
    error("unsupported HAVING parameter type: " .. tostring(t), 3)
end

function HAVING:to_sql()
    local t_concat = {}
    for _, cond in ipairs(self.conditions) do
        local query, params = cond.query, cond.params
        local ph_count = count_placeholders(query)
        if ph_count == 0 then
            t_concat[#t_concat + 1] = query
        else
            local i = 0
            t_concat[#t_concat + 1] = string.gsub(query, "%?", function()
                i = i + 1
                local p = params[i]
                if p == nil then
                    error(fmt("missing parameter for placeholder %d in %q", i, query), 3)
                end
                return render_scalar(self._dialect, p)
            end)
        end
    end
    return table.concat(t_concat, " AND ")
end

function HAVING:to_prepare()
    local t_concat = {}
    local params = {}
    for _, cond in ipairs(self.conditions) do
        local query = cond.query
        local ph_count = count_placeholders(query)
        if ph_count == 0 then
            t_concat[#t_concat + 1] = query
        else
            local i = 0
            t_concat[#t_concat + 1] = string.gsub(query, "%?", function()
                i = i + 1
                local p = cond.params[i]
                if p == nil then
                    error(fmt("missing parameter for placeholder %d in %q", i, query), 3)
                end
                params[#params + 1] = p
                return "?"
            end)
        end
    end
    return table.concat(t_concat, " AND "), params
end

return HAVING
