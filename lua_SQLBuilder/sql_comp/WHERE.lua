local class = require "lua_SQLBuilder.class"
local WHERE = class("WHERE")
local fmt = string.format

function WHERE:ctor(dialect)
    self.conditions = {}
    self._dialect = dialect
end

---@param query string 带 ? 占位符的条件片段
---@param ... 与占位符一一对应的参数（table 参数在 IN 场景展开为值列表）
function WHERE:add(query, ...)
    self.conditions[#self.conditions + 1] = { query = query, params = { ... } }
end

-- 单个标量值的内联渲染（to_sql 模式；转义在 phase 2 统一接入）
local function render_scalar(v)
    local t = type(v)
    if t == "string" then
        return fmt("'%s'", v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "userdata" then
        return "NULL"
    end
    error("unsupported parameter type: " .. tostring(t), 3)
end

local function count_placeholders(query)
    return select(2, string.gsub(query, "%?", ""))
end

-- 内联替换：把 query 里的 ? 逐个替换为渲染后的参数。
-- table 参数按 IN 语义渲染为 (v1, v2, ...)。
local function render_inline(query, params)
    local i = 0
    local out = string.gsub(query, "%?", function()
        i = i + 1
        local p = params[i]
        if p == nil then
            error(fmt("missing parameter for placeholder %d in %q", i, query), 3)
        end
        if type(p) == "table" then
            local vals = {}
            for _, v in ipairs(p) do
                vals[#vals + 1] = render_scalar(v)
            end
            return fmt("(%s)", table.concat(vals, ", "))
        end
        return render_scalar(p)
    end)
    return out, i
end

function WHERE:to_sql()
    local t_concat = {}
    for _, cond in ipairs(self.conditions) do
        local query, params = cond.query, cond.params
        local ph_count = count_placeholders(query)
        if ph_count == 0 then
            -- 无占位符条件（如 JOIN 片段）原样透传
            t_concat[#t_concat + 1] = query
        else
            local rendered = render_inline(query, params)
            t_concat[#t_concat + 1] = rendered
        end
    end
    local toSql = table.concat(t_concat, " AND ")
    if toSql ~= "" then
        toSql = fmt("(%s)", toSql)
    end
    return toSql
end

-- prepare 模式：占位符保留（table 参数展开为多个 ?），参数平铺返回。
local function render_prepare(query, params, out)
    local i = 0
    local replaced = string.gsub(query, "%?", function()
        i = i + 1
        local p = params[i]
        if p == nil then
            error(fmt("missing parameter for placeholder %d in %q", i, query), 3)
        end
        if type(p) == "table" then
            local ph = {}
            for _, v in ipairs(p) do
                ph[#ph + 1] = "?"
                out[#out + 1] = v
            end
            return fmt("(%s)", table.concat(ph, ", "))
        end
        out[#out + 1] = p
        return "?"
    end)
    return replaced
end

function WHERE:to_prepare()
    local t_concat = {}
    local params = {}
    for _, cond in ipairs(self.conditions) do
        local query = cond.query
        local ph_count = count_placeholders(query)
        if ph_count == 0 then
            t_concat[#t_concat + 1] = query
        else
            t_concat[#t_concat + 1] = render_prepare(query, cond.params, params)
        end
    end
    local toSql = table.concat(t_concat, " AND ")
    if toSql ~= "" then
        toSql = fmt("(%s)", toSql)
    end
    return toSql, params
end

return WHERE
