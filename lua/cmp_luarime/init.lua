local source = {}
local config = {}
local fn = vim.fn
local cmp = require("cmp")
local rimeIME = require("cmp_luarime.rimeIME")
local utils = require("cmp_luarime.utils")
local rime_enabled = false
local cmp_cb

local defaults = {
    sopath = "librime.so",
    traits = {
        shared_data_dir = "/usr/share/rime-data",
        user_data_dir = fn.expand("~/.local/share/cmp-luarime"),
        log_dir = fn.expand("~/.local/share/cmp-luarime/log"),
    },
    enable = {
        global = false,
        comment = true,
        string = true,
    },
    -- TODO
    max_candidates = 5,
}

local traits = {
    distribution_name = "Rime",
    distribution_code_name = "Rime",
    distribution_version = "0.1",
    app_name = "cmp-luarime",
    min_log_level = 2, -- rime_log_level.ERROR, -- important!
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

    local hpath = utils.find_hpath()
    rimeIME(hpath, new_config.sopath)

    local traits_opts = vim.tbl_deep_extend("keep", traits, new_config.traits)
    rimeIME:initialize(traits_opts, false, utils.on_message)

    cmp.event:on("menu_closed", function()
        rimeIME:SessionCleanup(true)
    end)
    vim.api.nvim_create_autocmd("InsertLeave", {
        callback = function()
            rimeIME:SessionCleanup(true)
        end,
    })
    -- vim.api.nvim_create_autocmd("InsertEnter", {
    --     callback = function()
    --         key_offset = vim.fn.col(".")
    --     end,
    -- })
    vim.api.nvim_create_autocmd("ExitPre", {
        callback = function()
            rimeIME:finalize()
        end,
    })
end

--------------------------------------------------------------------------------
-- @return string
function source:get_debug_name()
    return "luarime"
end
-- TODO
source.mappings = {
    toggle_menu = cmp.mapping(function(fallback)
        if cmp.visible() then
            cmp.abort()
            if rimeIME.session or rimeIME.session:exist() then
                rimeIME.session:destroy()
            end
        else
            cmp.complete()
        end
    end),
    confirm = cmp.mapping(function(fallback)
        local selected_entry = cmp.core.view:get_selected_entry()
        if selected_entry and selected_entry.source.name == "luarime" then
            cmp.abort()
            vim.api.nvim_input(" ")
        elseif cmp.visible() then
            cmp.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = true })
        else
            fallback()
        end
    end),
    space_commit = cmp.mapping(function(fallback)
        local selected_entry = cmp.core.view:get_selected_entry()
        if selected_entry and selected_entry.source.name == "luarime" then
            -- TODO:连续提交
            cmp.confirm({ select = true })
            cmp.close()
        else
            fallback()
        end
    end),

    page_down = cmp.mapping(function(fallback)
        if cmp.visible() and rimeIME.session and rimeIME.session:exist() then
            rimeIME.session:PageDown()
            -- 刷新context?
        else
            fallback()
        end
    end),
    page_up = cmp.mapping(function(fallback)
        if cmp.visible() and rimeIME.session and rimeIME.session:exist() then
            rimeIME.session:PageUp()
        else
            fallback()
        end
    end),
    select_2 = cmp.mapping(function(fallback)
        if cmp.visible() and rimeIME.session and rimeIME.session:exist() then
            rimeIME.session:Select(2, false)
        else
            fallback()
        end
    end),
    select_3 = cmp.mapping(function(fallback)
        if cmp.visible() and rimeIME.session and rimeIME.session:exist() then
            rimeIME.session:Select(2, false)
        else
            fallback()
        end
    end),
    toggle = function()
        rime_enabled = not rime_enabled
        return rime_enabled
    end,
}

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
    if self.config.enable.string then
        enable = enable or context.in_syntax_group("String") or context.in_treesitter_capture("string")
    end

    -- 在其他地方手动控制
    enable = enable or rime_enabled

    return enable
end

---Return the keyword pattern for triggering completion (optional).
---If this is ommited, nvim-cmp will use a default keyword pattern. See |cmp-config.completion.keyword_pattern|.
---@return string
function source:get_keyword_pattern()
    -- vim 正则而非lua 的正则
    -- 如果知道前面有几个非输入在字符,那就可以指定一定数量?
    -- return [[\l\{2,}]]
    return [[\l\+]]
end
-- Return trigger characters for triggering completion. (Optional)
function source:get_trigger_characters()
    -- stylua: ignore start
    return { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", }
    -- stylua: ignore end
end

local function callback_candidates(keys, params, rime_context, callback)
    local rime_candidates = rime_context.menu.candidates
    local cmp_items = {}
    local cursor = params.context.cursor
    for idx, candidate in ipairs(rime_candidates) do
        local label = string.format("%d. %s", idx, candidate.text)
        local item = {
            label = label,
            filterText = keys,
            sortText = idx,
            kind = 1,
            preselect = idx == 1,
            textEdit = {
                newText = candidate.text,
                -- 参考自cmp-flypy.nvim
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
    callback(cmp_items)
end

local function get_candidates(...)
    local rime_context = rimeIME.session:Context()
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
    -- TODO 当光标前面有英文单词的时候, cmp 总是会自动匹配上,
    -- 怎么设计规则让插件从当前位置开始算起呢
    -- vim.notify("rime matched")
    local keys = string.sub(params.context.cursor_before_line, params.offset)
    cmp_cb = callback

    if rimeIME.initialized then
        -- rime正在连续输入中
        -- if rimeIME.session and rimeIME.session:exist() then
        --     -- 相比刚才增加还是减少了输入按键?
        --     callback()
        --     return
        -- else
        --     -- 开始输入,先不考虑前面有英文字符的情况
        --     -- 如果keys>1, 说明前面有英文字符,记录此时位置作为input起始位置
        --     rimeIME.session = rimeIME:SessionCreate()
        --     rimeIME.cmp = {
        --         keys = keys,
        --         callback = callback,
        --     }
        --     rimeIME.cmp_cb = callback
        --     rimeIME.session:simulate(keys)
        --     local rime_context = rimeIME.session:Context()
        --     callback_candidates(keys, params, rime_context, callback)
        --     -- callback(get_candidates(rimeIME, keys, params))
        -- end

        rimeIME.session = rimeIME:SessionCreate()
        local session = rimeIME:SessionCreate()
        session:simulate(keys)
        local rime_context = session:Context()
        callback_candidates(keys, params, rime_context, callback)
        session:destroy()
    end
end

return source
