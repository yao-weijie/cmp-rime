local source = {}
local fn = vim.fn
local cmp = require("cmp")
_RIME_IME = require("cmp_rime.rimeIME")
local utils = require("cmp_rime.utils")

-- https://developer.mozilla.org/zh-CN/docs/Web/API/UI_Events/Keyboard_event_key_values
local K_PgUp = 0xff55
local K_PgDn = 0xff56

local rime_enabled = false

local _CONFIG = {}
local defaults = {
    libpath = "librime.so",
    traits = {
        shared_data_dir = "/usr/share/rime-data",
        user_data_dir = fn.expand("~/.local/share/cmp-rime"),
        log_dir = "/tmp/cmp-rime",
    },
    enable = {
        global = false,
        comment = true,
    },
    auto_commit = false,
    number_select = 5,
}

local traits = {
    distribution_name = "Rime",
    distribution_code_name = "Rime",
    distribution_version = "0.1",
    app_name = "rime.cmp-rime",
    min_log_level = 2,
}

-- 简单粗暴
local function cleanup_session()
    if _RIME_IME.session then
        _RIME_IME:SessionCleanup(true)
    end
    _RIME_IME.session = nil
end

vim.api.nvim_create_autocmd({ "InsertLeave", "FocusLost" }, {
    callback = function()
        cleanup_session()
    end,
})
vim.api.nvim_create_autocmd("ExitPre", {
    callback = function()
        _RIME_IME:finalize()
    end,
})

--------------------------------------------------------------------------------
---@return string
function source:get_debug_name()
    return "rime"
end

local function get_pre_commit(context)
    local preedit = context.composition.preedit
    if preedit then
        local idx = string.find(context.composition.preedit, [[%a]])
        return string.sub(context.composition.preedit, 1, idx - 1)
    else
        return ""
    end
end

local function callback_candidates(opts)
    opts = opts or {}
    local params = opts.params or _RIME_IME.cmp_params
    local cursor = params.context.cursor
    local keys = opts.keys or _RIME_IME.session:Input() -- 原始输入
    local rime_context = _RIME_IME.session:Context()
    local rime_candidates = rime_context.menu.candidates
    local pre_commit = opts.pre_commit and get_pre_commit(rime_context) or ""
    local sep = pre_commit ~= "" and " " or ""
    local cmp_items = {}
    local label, spc

    for idx, candidate in ipairs(rime_candidates) do
        if idx == 1 then
            label = string.format("%s%s%d. %s", pre_commit, sep, idx, candidate.text)
        else
            -- 每个中文字符计算出来的长度是3!!
            spc = string.rep(" ", #pre_commit * 2 / 3)
            label = string.format("%s%s%d. %s", spc, sep, idx, candidate.text)
        end

        local item = {
            label = label,
            filterText = keys, -- 必须是英文字符
            sortText = candidate.text,
            kind = 1,
            preselect = idx == 1,
            textEdit = {
                newText = pre_commit .. candidate.text,
                range = {
                    start = {
                        line = cursor.line,
                        character = params.offset,
                    },
                    ["end"] = {
                        line = cursor.line,
                        character = cursor.col - 1,
                    },
                },
                insert = {
                    start = {
                        line = cursor.line,
                        character = cursor.character - (cursor.col - params.offset),
                    },
                    ["end"] = {
                        line = cursor.line,
                        character = cursor.character,
                    },
                },
            },
        }
        table.insert(cmp_items, item)
    end

    -- 唯一候选项自动上屏
    _RIME_IME.callback(cmp_items)
    if _CONFIG.auto_commit and #cmp_items == 1 then
        cmp.confirm({ select = true })
        cleanup_session()
        cmp.close()
    end
end

local function find_rime_entries(entries)
    for _, entry in ipairs(entries) do
        if entry.source.name == "rime" then
            return entry.source.entries
        end
    end
end

source.mapping = {
    toggle = function()
        if cmp.visible() and _RIME_IME.session then
            _RIME_IME.callback({})
            cmp.complete()
        end
        rime_enabled = not rime_enabled
        return rime_enabled
    end,
    toggle_menu = cmp.mapping(function(fallback)
        if cmp.visible() then
            cmp.abort()
            cleanup_session()
        else
            cmp.complete()
        end
    end),
    confirm = cmp.mapping(function(fallback)
        if not cmp.visible() then
            return fallback()
        end

        local selected_entry = cmp.get_selected_entry()
        if selected_entry and selected_entry.source.name == "rime" then
            cmp.abort()
            vim.api.nvim_input("<Space>")
            cleanup_session()
        elseif cmp.visible() then
            cmp.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = true })
        end
    end),
    space_commit = cmp.mapping(function(fallback)
        if not cmp.visible() then
            return fallback()
        end

        local selected_entry = cmp.core.view:get_selected_entry()
        if selected_entry and selected_entry.source.name == "rime" then
            if not _RIME_IME.session then
                return cmp.core:confirm(selected_entry, {})
            end

            -- 同步提交
            local num = tonumber(string.match(selected_entry.completion_item.label, [[(%d)]]))
            _RIME_IME.session:Select(num, false)
            if not _RIME_IME.session:Status().is_composing then
                cmp.core:confirm(selected_entry, {})
                _RIME_IME.session:commit()
                cleanup_session()
            else
                callback_candidates({
                    pre_commit = true,
                })
            end
        else
            return fallback()
        end
    end),

    page_down = cmp.mapping(function(fallback)
        if cmp.visible() and _RIME_IME.session then
            local rime_entries = find_rime_entries(cmp.get_entries())
            if rime_entries == nil then
                return fallback()
            end

            _RIME_IME.session:process(K_PgDn, 0)
            callback_candidates({
                pre_commit = true,
            })
        else
            fallback()
        end
    end),
    page_up = cmp.mapping(function(fallback)
        if cmp.visible() and _RIME_IME.session then
            local rime_entries = find_rime_entries(cmp.get_entries())
            if rime_entries == nil then
                return fallback()
            end

            _RIME_IME.session:process(K_PgUp, 0)
            callback_candidates({
                pre_commit = true,
            })
        else
            fallback()
        end
    end),

    -- TODO
    select_prev_item = cmp.mapping(function(fallback)
        if not cmp.visible() then
            return fallback()
        end

        cmp.select_prev_item({ behavior = cmp.SelectBehavior.Select })
    end),
    select_next_item = cmp.mapping(function(fallback)
        if not cmp.visible() then
            return fallback()
        end

        cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
    end),
}

for num = 1, 9 do
    source.mapping[tostring(num)] = cmp.mapping(function(fallback)
        if not cmp.visible() or not rime_enabled then
            return fallback()
        end

        local rime_entries = find_rime_entries(cmp.get_entries())
        if rime_entries == nil or rime_entries[num] == nil then
            return fallback()
        end

        if not _RIME_IME.session then
            return cmp.core:confirm(rime_entries[num], {})
        end

        -- 和rime 同步提交
        _RIME_IME.session:Select(num, false)
        if not _RIME_IME.session:Status().is_composing then
            cmp.core:confirm(rime_entries[num], {})
            _RIME_IME.session:commit()
            cleanup_session()
        else
            callback_candidates({
                pre_commit = true,
            })
        end
    end)
end

source.status = function()
    return rime_enabled
end

---Return whether this source is available in the current context or not (optional).
---@return boolean
function source:is_available()
    if _CONFIG.enable.global then
        return true
    end

    -- 在comment中,按照配置总是开启或者总是关闭
    local context = require("cmp.config.context")
    local enable = false
    if _CONFIG.enable.comment then
        enable = enable or context.in_syntax_group("Comment") or context.in_treesitter_capture("comment")
    end

    -- 在其他地方手动控制
    enable = enable or rime_enabled

    return enable
end

---Return the keyword pattern for triggering completion (optional).
---If this is ommited, nvim-cmp will use a default keyword pattern. See |cmp-config.completion.keyword_pattern|.
---@return string
function source:get_keyword_pattern()
    return [[\l\+]]
end
-- Return trigger characters for triggering completion. (Optional)
function source:get_trigger_characters()
    -- stylua: ignore start
    return { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"}
    -- stylua: ignore end
end

---Invoke completion (required).
---@param params cmp.SourceCompletionApiParams
---@param callback fun(response: lsp.CompletionResponse|nil)
function source:complete(params, callback)
    -- TODO: real_offset
    local keys = string.sub(params.context.cursor_before_line, params.offset)

    if _RIME_IME.initialized then
        _RIME_IME.callback = callback
        -- TODO: 待优化
        _RIME_IME.session = _RIME_IME:SessionCreate()
        _RIME_IME.session:simulate(keys)
        _RIME_IME.cmp_params = params
        callback_candidates()
    end
end

source.setup = function(opts)
    opts = opts or {}
    _CONFIG = vim.tbl_deep_extend("keep", opts, defaults)

    if not _RIME_IME.initialized then
        _RIME_IME(utils.find_hpath(), _CONFIG.libpath)

        local traits_opts = vim.tbl_deep_extend("keep", traits, _CONFIG.traits)
        _RIME_IME:initialize(traits_opts, false, utils.on_message)
    end

    local num_sel = _CONFIG.number_select > 9 and 9 or _CONFIG.number_select
    for num = 1, num_sel do
        cmp.setup({
            mapping = cmp.mapping.preset.insert({
                [tostring(num)] = source.mapping[tostring(num)],
            }),
        })
    end
end

source.new = function()
    return setmetatable({}, { __index = source })
end

return source
