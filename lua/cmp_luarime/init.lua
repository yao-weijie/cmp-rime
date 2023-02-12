local source = {}
local config = {}
local async = require("plenary.async")
local fn = vim.fn
local cmp = require("cmp")
local rimeIME = require("cmp_luarime.rimeIME")
local utils = require("cmp_luarime.utils")
local rime_status = false
local key_offset
--
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
    mappings = {
        select_2 = ";", -- 分号
        select_3 = "'", -- 单引号
        page_down = ".",
        page_up = ",",
    },
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

    -- set keymap
    cmp.setup({
        -- TODO
        mapping = cmp.mapping.preset.insert({
            [";"] = cmp.mapping(function(fallback)
                return fallback()
            end),
            ["'"] = cmp.mapping(function(fallback)
                return fallback()
            end),

            ["."] = cmp.mapping(function(fallback)
                return fallback()
            end),
            [","] = cmp.mapping(function(fallback)
                return fallback()
            end),
        }),
    })
    vim.keymap.set({ "n", "i" }, "<C-g>", source.toggle, { desc = "toggle luarime" })

    -- cmp.event:on("menu_closed", function()
    --     -- vim.notify("menu closed")
    --     rimeIME:SessionCleanup(true)
    -- end)
    -- cmp.event:on("menu_opened", function()
    --     vim.notify("menu opened")
    -- end)
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

source.toggle = function()
    rime_status = not rime_status
    return rime_status
end
source.status = function()
    return rime_status
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
    enable = enable or rime_status

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
    return vim.split("qwertyuiopasdfghjklzxcvbnm", "")
end

local function callback_candidates(keys, params, rime_context, callback)
    local rime_candidates = rime_context.menu.candidates
    local menu_items = "" -- 用来调试查看的
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
        menu_items = menu_items .. item.label .. "\n"
        table.insert(cmp_items, item)
    end
    -- vim.notify(s)
    callback(cmp_items)
end

---Invoke completion (required).
---@param params cmp.SourceCompletionApiParams
---@param callback fun(response: lsp.CompletionResponse|nil)
function source:complete(params, callback)
    -- TODO 当光标前面有英文单词的时候, cmp 总是会自动匹配上,
    -- 怎么设计规则让插件从当前位置开始算起呢
    -- vim.notify("rime matched")
    local keys = string.sub(params.context.cursor_before_line, params.offset)

    if rimeIME.initialized then
        local session = rimeIME:SessionCreate()
        session:simulate(keys)
        local rime_context = session:Context()

        callback_candidates(keys, params, rime_context, callback)

        session:destroy()
    end
end

return source
