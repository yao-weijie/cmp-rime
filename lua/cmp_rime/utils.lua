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
---@param composition table
M.fmt_composition = function(composition)
    if not composition then
        return ""
    end

    local preedit = composition.preedit
    if not preedit then
        return ""
    end

    local s = ""
    -- length, cursor_pos, sel_start, sel_end
    s = s .. composition.preedit .. "\n"
    -- s = s .. composition.cursor_pos .. "\n"
    -- s = s .. composition.sel_start .. "\n"
    -- s = s .. composition.sel_end .. "\n"

    return s
end

---@param menu table
M.fmt_menu = function(menu)
    local s = ""
    s = s .. string.format("page: %d\n", menu.page_no)
    for i, cdt in ipairs(menu.candidates) do
        local comment = cdt.comment and cdt.comment or ""
        s = s .. string.format("%d. %s %s \n", i, cdt.text, comment)
    end

    return s
end

---param context table
M.fmt_context = function(context)
    if not context then
        return "context is nil\n"
    end

    local s = ""
    if context.composition then
        s = s .. M.fmt_composition(context.composition)
        s = s .. M.fmt_menu(context.menu)
    else
        s = "(not composing)\n"
    end
    return s
end

----------------------------------------------------------------------------------------------------------
M.on_message = function(context_object, session_id, message_type, message_value)
    local msg = string.format("[%s]: %s", M.toString(message_type), M.toString(message_value))
    vim.notify(msg, nil, { title = "cmp-rime" })
end

M.find_hpath = function()
    local dirname = string.sub(debug.getinfo(1).source, 2, #"lua/cmp_rime/rimeIME.lua" * -1)
    return dirname .. "/src/rime.h"
end

return M
