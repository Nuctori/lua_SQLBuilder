
local class = require "lua_SQLBuilder.class"
local sqlBuilder = require "lua_SQLBuilder.SQLBuilder"
---@class UPDATE : sqlBuilder
local UPDATE = class("UPDATE", sqlBuilder)
local table_format = require "utils".table_format

local json = require "lua_SQLBuilder.json"
local fmt = string.format
local tconcat = table.concat
local tsort = table.sort

function UPDATE:ctor(tableName)
    self.tableName = tableName
    self.setData = {}
    self.setDataTable = {}
    self.page = nil
    self.per = nil
    self.init(self)
end

function UPDATE:TableOperator()
    local t_concat = {}
    for _, v in ipairs(self.setData) do
        local field, val = v[1], v[2]
        if val then
            if type(val) == "userdata" then
                val = "NULL"
            end
            t_concat[#t_concat + 1] = string.gsub(field, "?", tostring(val), 1)
        else
            t_concat[#t_concat + 1] = field
        end
    end
    local setDataStr = fmt("%s", table.concat(t_concat, ", "))
    local setDataTStr = table_format(self.setDataTable, ", ")
    local setStr = setDataStr .. setDataTStr
    if setDataStr ~= "" and setDataTStr ~= "" then
        setStr = fmt("%s, %s", setDataStr, setDataTStr)
    end
    return fmt("UPDATE %s SET %s", self.tableName, setStr)
end

function UPDATE:PrepareTableOperator()
    local list = {}
    for k, v in pairs(self.setDataTable) do
      list[#list+1] = {k, v}
    end

    tsort(list)
    local prepareSetField = {}
    local prepareSetData = {}
    for idx, item in ipairs(list) do
        if type(item[2]) == "table" then
            if json then
                item[2] = json.encode(item[2])
            end
        end
        prepareSetField[#prepareSetField + 1] = fmt("%s = ?", item[1])
        prepareSetData[#prepareSetData + 1] = item[2]
    end
    for _, v in ipairs(self.setData) do
        local field, val = v[1], v[2]
        if val ~= nil then
            prepareSetField[#prepareSetField + 1] = fmt("%s = ?", field)
            prepareSetData[#prepareSetData + 1] = val
        else
            prepareSetField[#prepareSetField + 1] = fmt("%s?", field)
            prepareSetData[#prepareSetData + 1] = ""
        end
    end
    return fmt("UPDATE %s SET %s", self.tableName, tconcat(prepareSetField, ", ")), prepareSetData
end

function UPDATE:SET(setData, param)
    if type(setData) == "table" then
        self.setDataTable = setData
    else
        assert(type(setData) == "string", "setData must table or string:"..type(setData))
        self.setData[#self.setData + 1] = {setData, param}
    end

    return self
end

return UPDATE