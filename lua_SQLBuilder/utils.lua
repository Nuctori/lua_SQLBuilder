local SQLUtils = {}
local fmt = string.format
local dialect_mod = require "lua_SQLBuilder.dialect"

-- Lazy json: the base builder loads with zero JSON dependency; the json
-- module (cjson in production, vendored json.lua otherwise) is only required
-- when a value actually needs encoding.
local json
local function get_json()
  if not json then
    json = require "lua_SQLBuilder.json"
  end
  return json
end

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
        -- JSON 先编码再转义：表值里的引号必须经方言转义（CRITICAL-1）
        return fmt("'%s'", dialect.escape_string(get_json().encode(v)))
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
        -- 数字键是数组下标（JSON 数组）：Lua 1-based → JSON 0-based，渲染 [N]
        -- 且不加点号分隔（$.tags[0]，P1）
        local is_index = tonumber(k) ~= nil
        local segment = is_index and fmt("[%d]", tonumber(k) - 1) or tostring(k)
        local path
        if fatherPath == "" then
            path = segment
        elseif is_index then
            path = fatherPath .. segment
        else
            path = fatherPath .. "." .. segment
        end
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
                func(subk, v[subk], path, funcs)
            end
        elseif typeOfv == "boolean" then
            -- 存在性检查：方言差异（clickhouse 缺键返回 '' 而非 NULL，P2）
            local expr = dialect.json_path(tableName, path)
            if dialect.name == "clickhouse" then
                if v then
                    funcs[#funcs + 1] = { fmt("%s != ''", expr) }
                else
                    funcs[#funcs + 1] = { fmt("%s = ''", expr) }
                end
            elseif v then
                funcs[#funcs + 1] = { fmt("%s IS NOT NULL", expr) }
            else
                funcs[#funcs + 1] = { fmt("%s IS NULL", expr) }
            end
        end
    end
    local funcs = {}
    local keys = {}
    for tName in pairs(query) do
        keys[#keys + 1] = tName
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, tName in ipairs(keys) do
        func(tName, query[tName], "", funcs)
    end
    return funcs
end

return SQLUtils
