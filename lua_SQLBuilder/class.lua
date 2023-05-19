---@generic T
---@param name string
---@param super T?
---@return table
---@return T
local function class(name, super)
    local cls = {
        __super = super,
        __cname = name,
    }

    setmetatable(cls, {__index = super,
        __call = function(self, ...) return self.new(...) end})

    if cls.ctor then
        cls.ctor = function(self, ...) end
    end

    cls.__meta = {__index = cls}

    cls.new = function(...)
        local obj = setmetatable({}, cls.__meta)
        obj:ctor(...)
        return obj
    end
    return cls, super
end

return class