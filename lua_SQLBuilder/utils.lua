local SQLUtils = {}
local fmt = string.format
local tsort = table.sort
local tconcat = table.concat
local unpack = table.unpack or unpack -- luacheck: ignore 143
local json = require "lua_SQLBuilder.json"
local dialect_mod = require "lua_SQLBuilder.dialect"

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
    return fmt("%s", string.gsub(sql, "[\0\b\n\r\t\26\\\'\"]", escape_map))
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

-- 入参转义防注入装饰器
function SQLUtils.ORM_warpper(ormFunc)
    return function (...)
        local params = {...}
        for i = 1, #params, 1 do
            local param = params[i]
            if type(param) == "string" then
                param = SQLUtils.quote_to_str(param)
            elseif type(param) == "table" then
                param = SQLUtils.clear_table(param)
            end

            params[i] = param
        end

        return ormFunc(unpack(params))
    end
end

--- Render a literal value for inline SQL (to_sql mode).
-- Strings/JSON are single-quoted; NULLs and userdata become NULL.
-- NOTE: does NOT escape yet — escaping is applied in phase 2.
function SQLUtils.render_value(v)
    if v == nil then
        return "NULL"
    end
    local t = type(v)
    if t == "string" then
        return fmt("'%s'", v)
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

function SQLUtils.table_format (tab, sep, sorts)
    assert(type(tab) == 'table', "Invalid table.")
    local list = {}
    for k, v in pairs(tab) do
      list[#list+1] = {k, v}
    end

    -- 根据key进行升序排列
    if sorts then
        tsort(list, sorts)
    end

    -- 开始合并数据
    for idx, item in ipairs(list) do
        if type(item[2]) == "table" then
            item[2] = json.encode(item[2])
        end
        if type(item[2]) == "string" then
            list[idx] = fmt("%s = '%s'", item[1], item[2])
        else
            list[idx] = fmt("%s = %s", item[1], item[2])
        end

    end
    return tconcat(list, sep)
end

---生成查询语句
---@param query any
function SQLUtils.Make_Query(query)
    assert(type(query) == 'table')
    local list = {}
    for k, v in pairs(query) do
      list[#list+1] = {k, v}
    end
    -- 开始合并数据
    for idx, item in ipairs(list) do
        if type(item[2]) == "string" then
            list[idx] = fmt("`%s`='%s'", item[1], item[2])
        elseif type(item[2]) == "boolean" then

        else

        end
    end
    return table.concat(list, " AND ")
end

function SQLUtils.SortTable(t)
    local sortTable = {}
    for k, v in pairs(t) do
        sortTable[#sortTable + 1] = {k,v}
    end
    table.sort(sortTable, function(a, b)
        return tostring(type(a)) < tostring(type(b))
    end)
    return sortTable
end

---comment 生成json查询语句（按方言渲染 JSON 路径算子）
---@param tableName string  JSON 列名
---@param query table     @用于匹配的模式
---@param dialect table|nil @方言配置（默认取模块默认）
---@return table @{sql, param} 列表；boolean 分支暂返回纯字符串（见 known_bugs A3，phase 1 修复）
function SQLUtils.Make_JsonQuery(tableName, query, dialect)
    dialect = dialect or dialect_mod.resolve()
    local function func(k, v, fatherPath, funcs)
        if tonumber(k) then
            k = fmt([["%s"]], k)
        end
        local typeOfv = type(v)
        if typeOfv == "string" then
            funcs[#funcs + 1] = { fmt("%s = ?", dialect.json_path(tableName, fatherPath .. k)), v }
        elseif typeOfv == "number" then
            funcs[#funcs + 1] = { fmt("%s = ?", dialect.json_path(tableName, fatherPath .. k)), tostring(v) }
        elseif typeOfv == "table" then
            for subk, subv in pairs(v) do
                func(subk, subv, k .. ".", funcs)
            end
        elseif typeOfv == "boolean" then
            -- KNOWN BUG A3: returns a bare string; callers index it as a pair.
            -- Fixed in phase 1 (see spec/unit/known_bugs_spec.lua).
            if v == true then
                funcs[#funcs + 1] = fmt("%s->>'$.%s' IS NOT NULL", tableName, fatherPath .. k)
            else
                funcs[#funcs + 1] = fmt("%s->>'$.%s' IS NULL", tableName, fatherPath .. k)
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
