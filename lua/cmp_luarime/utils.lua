-- 本文件修改自https://github.com/zhaozg/rime_lua
local M = {}
local ffi = require("ffi")
local C = ffi.C

----------------------------------------------------------------------------------------------------------
-- 类型转换
--!help utilities
M.IsNULL = function(val)
    return val == nil
end
M.IsFalse = function(val)
    return val == C.False
end
M.IsEmpty = function(s)
    return s == nil or ffi.string(s) == ""
end

-- to c boolean
M.toBoolean = function(val)
    assert(val == C.True or val == C.False)
    return val ~= C.False
end
-- to lua bool
M.toBool = function(val)
    assert(type(val) == "boolean")
    return val and C.True or C.False
end
-- to lua string
M.toString = function(v, len)
    if type(v) == "cdata" then
        if v == nil then
            return nil
        else
            return ffi.string(v, len)
        end
    else
        return tostring(v)
    end
end

-- to c pointer
M.toPointer = function(s)
    return C.Cast("intptr_t", C.Cast("void*", s))
end
----------------------------------------------------------------------------------------------------------
-- 调试用
---@param menu table
M.show_menu = function(menu)


end

---@param composition table
M.show_composition = function(composition)


end

---param context table
M.show_context = function(context)

end

----------------------------------------------------------------------------------------------------------
M.on_message = function(context_object, session_id, message_type, message_value)
    local msg = string.format("[%s]: %s", M.toString(message_type), M.toString(message_value))
    vim.notify(msg, nil, { title = "cmp-luarime" })
end

M.find_hpath = function()
    local dirname = string.sub(debug.getinfo(1).source, 2, #"lua/cmp_luarime/rimeIME.lua" * -1)
    return dirname .. "/src/rime.h"
end

return M
