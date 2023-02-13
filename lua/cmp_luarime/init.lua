local source = {}
local config = {}
local fn = vim.fn
local cmp = require("cmp")
_RIME_IME = require("cmp_luarime.rimeIME")
local utils = require("cmp_luarime.utils")
local view = require("cmp.view")
local core = require("cmp.core")

local K_BackSpace = 0xff08
local K_PgUp = 0xff55
local K_PgDn = 0xff56

local rime_enabled = false
local contex_before_cursor = ""
local length_before_cursor = 0
local curr_key_sequence = ""
local last_key_sequence = ""
local real_offset = nil
local curr_cursor_pos = { row = fn.col("."), col = fn.col(".") }
local last_cursor_pos = { row = fn.col("."), col = fn.col(".") }
local crawling_move = true

local defaults = {
    sopath = "librime.so",
    traits = {
        shared_data_dir = "/usr/share/rime-data",
        user_data_dir = fn.expand("~/.local/share/cmp-luarime"),
        log_dir = "/tmp/cmp-luarime",
    },
    enable = {
        global = false,
        comment = true,
    },
    -- TODO
    max_candidates = 5,
}

local traits = {
    distribution_name = "Rime",
    distribution_code_name = "Rime",
    distribution_version = "0.1",
    app_name = "rime.cmp-luarime",
    min_log_level = 2,
}

source.new = function()
    local self = setmetatable({}, { __index = source })
    self.config = config
    setmetatable(config, { __index = defaults })
    return self
end

source.setup = function(opts)
    opts = opts or {}
    local new_config = vim.tbl_deep_extend("keep", opts, defaults)
    setmetatable(config, { __index = new_config })

    if not _RIME_IME.initialized then
        local hpath = utils.find_hpath()
        _RIME_IME(hpath, new_config.sopath)

        local traits_opts = vim.tbl_deep_extend("keep", traits, new_config.traits)
        _RIME_IME:initialize(traits_opts, false, utils.on_message)
    end
end

local function update_cursor_prefix()
    if not rime_enabled then
        return
    end

    last_cursor_pos = {
        row = curr_cursor_pos.row,
        col = curr_cursor_pos.col,
    }
    last_cursor_pos = curr_cursor_pos

    curr_cursor_pos = {
        row = fn.line("."),
        col = fn.col("."),
    }

    if
        math.abs(curr_cursor_pos.col - last_cursor_pos.col) == 1
        or math.abs(curr_cursor_pos.row - curr_cursor_pos.row) == 0
    then
        crawling_move = true
    end

    local line = vim.api.nvim_get_current_line()
    local line_before_cursor = string.sub(line, 1, curr_cursor_pos.col - 1)
    local word_before_cursor = string.match(line_before_cursor, "%l+$")
    if word_before_cursor then
        length_before_cursor = #word_before_cursor
    else
        length_before_cursor = 0
    end
end

local function clean_session()
    _RIME_IME.session:destroy()
    _RIME_IME.session = nil
end

vim.api.nvim_create_autocmd("InsertEnter", {
    callback = function()
        update_cursor_prefix()
    end,
})
-- excuted before match source pattern
vim.api.nvim_create_autocmd("CursorMovedI", {
    callback = function()
        update_cursor_prefix()
        if not crawling_move then
            _RIME_IME.session:destroy()
            _RIME_IME.session = nil
        end
    end,
})

vim.api.nvim_create_autocmd({ "InsertLeave", "FocusLost" }, {
    callback = function()
        _RIME_IME:SessionCleanup(true)
        _RIME_IME.session = nil
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
    return "luarime"
end

local function callback_candidates(params)
    local keys = _RIME_IME.session:Input()
    local rime_candidates = _RIME_IME.session:Context().menu.candidates
    local cmp_items = {}
    local cursor = params.context.cursor
    for idx, candidate in ipairs(rime_candidates) do
        local label = string.format("%d. %s", idx, candidate.text)
        local item = {
            label = label,
            filterText = keys,
            sortText = keys,
            kind = 1,
            preselect = idx == 1,
            textEdit = {
                newText = candidate.text,
                range = {
                    start = {
                        line = cursor.line,
                        character = params.offset - 1,
                    },
                    ["end"] = {
                        line = cursor.line,
                        character = cursor.col,
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

    _RIME_IME.callback(cmp_items)
    if _CONFIG.auto_commit and #cmp_items == 1 then
        cmp.confirm({ select = true })
        cleanup_session()
        cmp.close()
    end
end

-- TODO
source.mapping = {
    toggle = function()
        rime_enabled = not rime_enabled
        update_cursor_prefix()
        return rime_enabled
    end,
    ---@param enable boolean
    set_enable = function(enable)
        rime_enabled = enable
    end,
    toggle_menu = cmp.mapping(function(fallback)
        if cmp.visible() then
            cmp.abort()
            if _RIME_IME.session then
                _RIME_IME.session:destroy()
                _RIME_IME.session = nil
            end
        else
            cmp.complete()
            if rime_enabled then
                update_cursor_prefix()
            end
        end
    end),
    confirm = cmp.mapping(function(fallback)
        local selected_entry = cmp.get_selected_entry()
        if selected_entry and selected_entry.source.name == "luarime" then
            cmp.abort()
            vim.api.nvim_input(" ")
            _RIME_IME.session:destroy()
            _RIME_IME.session = nil
        elseif cmp.visible() then
            cmp.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = true })
        else
            fallback()
        end
    end),
    space_commit = cmp.mapping(function(fallback)
        local selected_entry = cmp.core.view:get_selected_entry()
        if selected_entry and selected_entry.source.name == "luarime" then
            cmp.confirm({ select = true })
            if _RIME_IME.session:commit() then
                -- TODO:继续提交
            else
                cmp.close()
            end
        else
            fallback()
        end
    end),

    page_down = cmp.mapping(function(fallback)
        if cmp.visible() and rime_enabled and _RIME_IME.session then
            local entries = cmp.get_entries()
            for _, entry in ipairs(entries) do
                if entry.source.name == "luarime" then
                    _RIME_IME.session:process(K_PgDn, 0)
                    callback_candidates(_RIME_IME.cmp_params)
                    return
                end
            end
        else
            fallback()
        end
    end),
    page_up = cmp.mapping(function(fallback)
        if cmp.visible() and rime_enabled and _RIME_IME.session then
            local entries = cmp.get_entries()
            for _, entry in ipairs(entries) do
                if entry.source.name == "luarime" then
                    _RIME_IME.session:process(K_PgUp, 0)
                    callback_candidates(_RIME_IME.cmp_params)
                    return
                end
            end
        else
            fallback()
        end
    end),
}
for num = 1, 9 do
    source.mapping[tostring(num)] = cmp.mapping(function(fallback)
        if cmp.visible() and rime_enabled then
            local entries = cmp.get_entries()
            for _, entry in ipairs(entries) do
                if entry.source.name == "luarime" then
                    local rime_entries = entry.source.entries
                    if rime_entries[num] ~= nil then
                    -- TODO: 回调, 如果有未完成的词继续更新
                        cmp.core:confirm(rime_entries[num], {})
                        if _RIME_IME.session:commit() then
                            -- 
                        else
                            -- clean_session()
                        end
                    else
                        fallback()
                    end
                    return
                end
            end
        else
            fallback()
        end
    end)
end

source.status = function()
    return rime_enabled
end

---Return whether this source is available in the current context or not (optional).
---@return boolean
function source:is_available()
    if self.config.enable.global then
        return true
    end

    -- 在comment 或者string 中,按照配置总是开启或者总是关闭
    local context = require("cmp.config.context")
    local enable = false
    if self.config.enable.comment then
        print(self.config.enable.comment)
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



---Executed after the item was selected.
---@param completion_item lsp.CompletionItem
---@param callback fun(completion_item: lsp.CompletionItem|nil)
function source:execute(completion_item, callback)
    callback(completion_item)
end

---Invoke completion (required).
---@param params cmp.SourceCompletionApiParams
---@param callback fun(response: lsp.CompletionResponse|nil)
function source:complete(params, callback)
    local keys = string.sub(params.context.cursor_before_line, params.offset)

    if _RIME_IME.initialized then
--         real_offset = params.offset + length_before_cursor

        _RIME_IME.callback = callback
        _RIME_IME.session = _RIME_IME:SessionCreate()
        _RIME_IME.session:simulate(keys)
        _RIME_IME.cmp_params = params
        callback_candidates(params)
    end
end

return source