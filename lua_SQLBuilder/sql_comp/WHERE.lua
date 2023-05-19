local class = require "lua_SQLBuilder.class"
local WHERE = class("WHERE")
local fmt = string.format

function WHERE:ctor()
    self.conditions = {}

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
                for i, v in ipairs(param) do
                    if type(v) == "string" then
                        param[i] = fmt("'%s'", v)
                    end
                end
                param = fmt("(%s)", table.concat(param, ","))
            elseif type(param) == "userdata" then
                param = "NULL"
            end
            t_concat[#t_concat + 1] = string.gsub(query, "?", tostring(param), 1)
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