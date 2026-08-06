local class = require "lua_SQLBuilder.class"
local WHERE = class("WHERE")
local fmt = string.format

function WHERE:ctor(dialect)
    self.conditions = {}
    self._dialect = dialect
end

function WHERE:add(query, param)
    self.conditions[#self.conditions + 1] = {query, param}
end

function WHERE:to_sql()
    local t_concat = {}
    for _, v in ipairs(self.conditions) do
        local query, param = v[1], v[2]
        if param then
            if type(param) == "string" then
                param = fmt("'%s'", param)
            elseif type(param) == "table" then
                for i, pv in ipairs(param) do
                    if type(pv) == "string" then
                        param[i] = fmt("'%s'", pv)
                    end
                end
                param = fmt("(%s)", table.concat(param, ","))
            elseif type(param) == "userdata" then
                param = "NULL"
            end
            t_concat[#t_concat + 1] = string.gsub(query, "?", function() return tostring(param) end, 1)
        else
            t_concat[#t_concat + 1] = query
        end
    end
    local toSql = fmt("%s", table.concat(t_concat, " AND "))
    if toSql and toSql ~= "" then
        toSql = fmt("(%s)", toSql)
    end
    return toSql
end

function WHERE:to_prepare()
    local t_concat = {}
    local params = {}
    for _, v in ipairs(self.conditions) do
        local query, param = v[1], v[2]
        t_concat[#t_concat + 1] = query
        params[#params + 1] = param
    end
    local toSql = fmt("%s", table.concat(t_concat, " AND "))
    if toSql and toSql ~= "" then
        toSql = fmt("(%s)", toSql)
    end
    return toSql, params
end

return WHERE