local source = {}
local cmp = require("cmp")
_RIME_IME = require("cmp_rime.rimeIME")
local utils = require("cmp_rime.utils")

-- https://developer.mozilla.org/zh-CN/docs/Web/API/UI_Events/Keyboard_event_key_values
local K_BS = 0xff08
local K_PgUp = 0xff55
local K_PgDn = 0xff56

local rime_enabled = false

local _CONFIG = {}
local defaults = {
    libpath = "librime.so",
    traits = {
        shared_data_dir = "/usr/share/rime-data",
        user_data_dir = vim.fn.expand("~/.local/share/cmp-rime"),
        log_dir = "/tmp/cmp-rime",
    },
    enable = {
        global = false,
        comment = true,
    },
    preselect = false,
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

vim.api.nvim_create_autocmd({ "FocusLost", "InsertLeave", "TermOpen" }, {
    callback = function()
        _RIME_IME:SessionCleanup(true)
    end,
})
vim.api.nvim_create_autocmd({ "VimLeave" }, {
    callback = function()
        _RIME_IME:SessionCleanup(true)
        _RIME_IME:finalize()
    end,
})

--------------------------------------------------------------------------------
---@return string
function source:get_debug_name()
    return "rime"
end

-- BUG 长句乱序词解析错误
local function callback_candidates(opts)
    local function get_pre_commit(context)
        local preedit = context.composition.preedit
        local preview = context.commit_text_preview

        for i = 1, math.min(#preedit, #preview) + 1 do
            if string.sub(preedit, 1, i) ~= string.sub(preview, 1, i) then
                return string.sub(preedit, 1, i - 1)
            end
        end
        return ""
    end

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

    if rime_context.menu.num_candidates == 0 then
        _RIME_IME.session:clear()
        _RIME_IME.callback({})
        return
    end

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
            preselect = _CONFIG.preselect and idx == 1 or false,
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
        _RIME_IME.session:commit()
        cmp.confirm({ select = true })
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
        if _RIME_IME.callback then
            _RIME_IME.callback({})
            _RIME_IME.session:clear()
        end

        rime_enabled = not rime_enabled
        return rime_enabled
    end,
    toggle_menu = cmp.mapping(function(fallback)
        if cmp.visible() then
            cmp.abort()
            _RIME_IME.session:clear()
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
            _RIME_IME.session:clear()
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
            if not _RIME_IME.session:exist() then
                return cmp.core:confirm(selected_entry, {})
            end

            local rime_entries = selected_entry.source.entries
            local num = selected_entry.id - rime_entries[1].id + 1

            -- 同步提交
            _RIME_IME.session:Select(num, false)
            if not _RIME_IME.session:Status().is_composing then
                cmp.core:confirm(selected_entry, {})
                _RIME_IME.session:commit()
                _RIME_IME.session:clear()
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
        if not cmp.visible() or not _RIME_IME.session:exist() or not _RIME_IME.session:Status().is_composing then
            return fallback()
        end

        local context = _RIME_IME.session:Context()
        if context and context.menu.is_last_page then
            return
        end

        _RIME_IME.session:process(K_PgDn, 0)
        callback_candidates({
            pre_commit = true,
        })
    end),
    page_up = cmp.mapping(function(fallback)
        if not cmp.visible() or not _RIME_IME.session:exist() or not _RIME_IME.session:Status().is_composing then
            return fallback()
        end

        local context = _RIME_IME.session:Context()
        if context and context.menu.page_no == 1 then
            return
        end

        _RIME_IME.session:process(K_PgUp, 0)
        callback_candidates({
            pre_commit = true,
        })
    end),

    select_prev_item = cmp.mapping(function(fallback)
        if not cmp.visible() then
            return fallback()
        end

        local entries = cmp.get_entries()
        local selected_entry = cmp.get_selected_entry()

        if not selected_entry then
            if entries[#entries].source.name == "rime" then
                return cmp.select_prev_item({ behavior = cmp.SelectBehavior.Select })
            else
                return cmp.select_prev_item()
            end
        end

        if selected_entry.id == entries[1].id then
            return cmp.select_prev_item()
        end

        for i = 2, #entries do
            if entries[i].id == selected_entry.id then
                if entries[i - 1].source.name == "rime" then
                    return cmp.select_prev_item({ behavior = cmp.SelectBehavior.Select })
                else
                    return cmp.select_prev_item()
                end
            end
        end
    end),
    select_next_item = cmp.mapping(function(fallback)
        if not cmp.visible() then
            return fallback()
        end

        local entries = cmp.get_entries()
        local selected_entry = cmp.get_selected_entry()

        if not selected_entry then
            if entries[1].source.name == "rime" then
                return cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
            else
                return cmp.select_next_item()
            end
        end

        if selected_entry.id == entries[#entries].id then
            return cmp.select_next_item()
        end

        for i = 1, #entries do
            if entries[i].id == selected_entry.id then
                if entries[i + 1].source.name == "rime" then
                    return cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
                else
                    return cmp.select_next_item()
                end
            end
        end
    end),
}

for num = 1, 9 do
    source.mapping[tostring(num)] = cmp.mapping(function(fallback)
        if not cmp.visible() then
            return fallback()
        end

        local rime_entries = find_rime_entries(cmp.get_entries())
        if rime_entries == nil or rime_entries[num] == nil then
            return fallback()
        end

        if not _RIME_IME.session:exist() then
            return cmp.core:confirm(rime_entries[num], {})
        end

        -- 和rime 同步提交
        _RIME_IME.session:Select(num, false)
        if not _RIME_IME.session:Status().is_composing then
            cmp.core:confirm(rime_entries[num], {})
            _RIME_IME.session:commit()
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

    local enable = false
    local context = require("cmp.config.context")
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
    if not _RIME_IME.initialized then
        return callback()
    end

    if not _RIME_IME.session:exist() then
        _RIME_IME.session = _RIME_IME:SessionCreate()
    end

    -- TODO: 两种方式可能要结合起来用才行
    local key_sequence = string.sub(params.context.cursor_before_line, params.offset)
    local key = params.completion_context.triggerCharacter or ""

    _RIME_IME.session:clear()
    _RIME_IME.session:simulate(key_sequence)
    -- 一次只传一个key 暂时不能回退
    -- _RIME_IME.session:simulate(key)
    _RIME_IME.callback = callback
    _RIME_IME.cmp_params = params
    callback_candidates()
end

source.setup = function(opts)
    opts = opts or {}
    _CONFIG = vim.tbl_deep_extend("keep", opts, defaults)

    if not _RIME_IME.initialized then
        _RIME_IME(utils.find_hpath(), _CONFIG.libpath)

        local traits_opts = vim.tbl_deep_extend("keep", traits, _CONFIG.traits)
        _RIME_IME:initialize(traits_opts, false, utils.on_message)
        _RIME_IME.session = _RIME_IME:SessionCreate()
    end

    local num_sel = math.min(_CONFIG.number_select, 9)
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
