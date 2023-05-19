local SQLUtils = {}
local fmt = string.format
local tsort = table.sort
local tconcat = table.concat
local json = require "lua_SQLBuilder.json"

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

        return ormFunc(table.unpack(params))
    end
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


---comment 生成json查询语句
---@param query table    @用于匹配的模式
---@return boolean, string @是否成功, 错误信息
function SQLUtils.Make_JsonQuery(tableName, query)
    local function func(k, v, fatherPath, funcs)
        if tonumber(k) then
            k = fmt([["%s"]], k)
        end
        local typeOfv = type(v)
        if typeOfv == "string" then
          funcs[#funcs + 1] = {fmt("%s->>'$.%s' = '?'", tableName, fatherPath..k), v}
        elseif typeOfv == "number" then
          funcs[#funcs + 1] = {fmt("%s->>'$.%s' = ?", tableName, fatherPath..k), v}
        elseif typeOfv == "table" then
          for subk, subv in pairs(v) do
              local sqlStr = func(subk, subv, k..".", funcs)
              if sqlStr then
                  funcs[#funcs + 1] = sqlStr
              end
          end
        elseif typeOfv == "boolean" then
            if v == true then
                funcs[#funcs + 1] = fmt("%s->>'$.%s' IS NOT NULL",tableName, fatherPath..k)
            else
                funcs[#funcs + 1] = fmt("%s->>'$.%s' IS NULL",tableName, fatherPath..k)
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