local M = {}
local ffi = require("ffi")
local C = ffi.C

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

M.toBoolean = function(val)
    assert(val == C.True or val == C.False)
    return val ~= C.False
end
M.toBool = function(val)
    assert(type(val) == "boolean")
    return val and C.True or C.False
end

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

M.toPointer = function(s)
    return C.Cast("intptr_t", C.Cast("void*", s))
end

M.on_message = function(context_object, session_id, message_type, message_value)
    local msg = string.format("[%s]: %s", M.toString(message_type), M.toString(message_value))
    vim.notify(msg, nil, { title = "cmp-luarime" })
end

M.find_hpath = function()
    local dirname = string.sub(debug.getinfo(1).source, 2, #"lua/cmp_luarime/rimeIME.lua" * -1)
    return dirname .. "/src/rime.h"
end

return M
