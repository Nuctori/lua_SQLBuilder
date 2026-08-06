local class = require "lua_SQLBuilder.class"
local sqlBuilder = require "lua_SQLBuilder.SQLBuilder"
---@class UPDATE : sqlBuilder
local UPDATE = class("UPDATE", sqlBuilder)

local json = require "lua_SQLBuilder.json"
local utils = require "lua_SQLBuilder.utils"
local render_value = utils.render_value
local fmt = string.format
local tconcat = table.concat

function UPDATE:ctor(tableName, opts)
    self.tableName = tableName
    self.setData = {}
    self.setDataTable = {}
    self.page = nil
    self.per = nil
    self.init(self, nil, opts)
end

local function sort_keys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

-- 标量内联渲染（与 WHERE 一致：字符串引号、数字/布尔裸、userdata 为 NULL）
local function render_scalar(v)
    local t = type(v)
    if t == "string" then
        return fmt("'%s'", v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "userdata" then
        return "NULL"
    end
    error("unsupported SET parameter type: " .. tostring(t), 3)
end

-- 把表达式里的 ? 逐个替换为内联值（函数替换，避免 % 解释）
local function render_inline_expr(expr, params)
    local i = 0
    return string.gsub(expr, "%?", function()
        i = i + 1
        local p = params[i]
        if p == nil then
            error(fmt("missing parameter for placeholder %d in %q", i, expr), 3)
        end
        return render_scalar(p)
    end)
end

-- prepare 模式：? 逐个保留为占位符，参数平铺
local function render_prepare_expr(expr, params, out)
    local i = 0
    return string.gsub(expr, "%?", function()
        i = i + 1
        local p = params[i]
        if p == nil then
            error(fmt("missing parameter for placeholder %d in %q", i, expr), 3)
        end
        out[#out + 1] = p
        return "?"
    end)
end

function UPDATE:TableOperator()
    local quote = self._dialect.quote_ident
    local sets = {}
    for _, v in ipairs(self.setData) do
        local field, params = v[1], v[2]
        if #params > 0 then
            sets[#sets + 1] = render_inline_expr(field, params)
        else
            sets[#sets + 1] = field
        end
    end
    for _, key in ipairs(sort_keys(self.setDataTable)) do
        sets[#sets + 1] = fmt("%s = %s", quote(key), render_value(self.setDataTable[key]))
    end
    return fmt("UPDATE %s SET %s", self.tableName, tconcat(sets, ", "))
end

function UPDATE:PrepareTableOperator()
    local quote = self._dialect.quote_ident
    local fields, params = {}, {}
    -- table mode: deterministic key order so prepare params are stable
    for _, key in ipairs(sort_keys(self.setDataTable)) do
        local val = self.setDataTable[key]
        if type(val) == "table" then
            val = json.encode(val)
        end
        fields[#fields + 1] = fmt("%s = ?", quote(key))
        params[#params + 1] = val
    end
    -- string mode: one ? per param, params flattened in order
    for _, v in ipairs(self.setData) do
        local field, expr_params = v[1], v[2]
        if #expr_params > 0 then
            fields[#fields + 1] = render_prepare_expr(field, expr_params, params)
        else
            fields[#fields + 1] = field
        end
    end
    return fmt("UPDATE %s SET %s", self.tableName, tconcat(fields, ", ")), params
end

---@param setData table|string 表模式（字段→值）或表达式（含 ? 占位符）
---@param ... 表达式模式的参数，与占位符一一对应
function UPDATE:SET(setData, ...)
    if type(setData) == "table" then
        self.setDataTable = setData
    else
        assert(type(setData) == "string", "setData must table or string:" .. type(setData))
        self.setData[#self.setData + 1] = { setData, { ... } }
    end
    return self
end

return UPDATE
