local SQLUtils = {}
local fmt = string.format
local json = require "lua_SQLBuilder.json"
local dialect_mod = require "lua_SQLBuilder.dialect"

-- MySQL-flavored escape map (also the historical quote_to_str behavior).
local escape_map = {
    ['\0'] = "\\0",
    ['\b'] = "\\b",
    ['\n'] = "\\n",
    ['\r'] = "\\r",
    ['\t'] = "\\t",
    ['\26'] = "\\Z",
    ['\\'] = "\\\\",
    ["'"] = "\\'",
    ['"'] = '\\"',
}

function SQLUtils.quote_to_str (sql)
    -- Loop-based escaping: a gsub pattern containing a NUL byte (\0) breaks
    -- Lua 5.1's pattern parser (C-string scan stops at NUL).
    local out = {}
    for i = 1, #sql do
        local c = sql:sub(i, i)
        out[#out + 1] = escape_map[c] or c
    end
    return table.concat(out)
end

function SQLUtils.clear_table(t)
    local new_tab = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            v = SQLUtils.clear_table(v)
        elseif type(v) == "string" then
            v = SQLUtils.quote_to_str(v)
        end
        if type(k) == "string" then
            k = SQLUtils.quote_to_str(k)
        end
        new_tab[k] = v
    end
    return new_tab
end

--- Render a literal value for inline SQL (to_sql mode).
-- Strings are single-quoted with dialect-aware escaping; NULLs and userdata
-- become NULL; tables are JSON-encoded.
---@param v any
---@param dialect table|nil 方言配置（默认 mysql）
function SQLUtils.render_value(v, dialect)
    dialect = dialect or dialect_mod.resolve()
    if v == nil then
        return "NULL"
    end
    local t = type(v)
    if t == "string" then
        return fmt("'%s'", dialect.escape_string(v))
    end
    if t == "table" then
        return fmt("'%s'", json.encode(v))
    end
    if t == "boolean" or t == "number" then
        return tostring(v)
    end
    if t == "userdata" then
        return "NULL"
    end
    error("unsupported value type: " .. t)
end

---生成 json 查询条件（按方言渲染 JSON 路径算子）
---@param tableName string JSON 列名
---@param query table 匹配模式（标量/嵌套/boolean）
---@param dialect table|nil 方言配置（默认取模块默认）
---@return table @{sql, param} 列表；boolean 分支为 {sql}（无参数）
function SQLUtils.Make_JsonQuery(tableName, query, dialect)
    dialect = dialect or dialect_mod.resolve()
    local function func(k, v, fatherPath, funcs)
        -- 数字键是数组下标（JSON 数组），渲染为 [N] 段
        local segment = k
        if tonumber(k) then
            segment = fmt("[%d]", tonumber(k))
        end
        local path = fatherPath .. segment
        local typeOfv = type(v)
        if typeOfv == "string" then
            funcs[#funcs + 1] = { fmt("%s = ?", dialect.json_path(tableName, path)), v }
        elseif typeOfv == "number" then
            funcs[#funcs + 1] = { fmt("%s = ?", dialect.json_path(tableName, path)), tostring(v) }
        elseif typeOfv == "table" then
            local keys = {}
            for subk in pairs(v) do
                keys[#keys + 1] = subk
            end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, subk in ipairs(keys) do
                func(subk, v[subk], path .. ".", funcs)
            end
        elseif typeOfv == "boolean" then
            -- 方言感知的 IS (NOT) NULL；返回 {sql} 对（无参数）
            local expr = dialect.json_path(tableName, path)
            if v then
                funcs[#funcs + 1] = { fmt("%s IS NOT NULL", expr) }
            else
                funcs[#funcs + 1] = { fmt("%s IS NULL", expr) }
            end
        end
    end
    local funcs = {}
    for tName, tType in pairs(query) do
        func(tName, tType, "", funcs)
    end
    return funcs
end

return SQLUtils
