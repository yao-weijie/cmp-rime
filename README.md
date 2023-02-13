# cmp-luarime

## default config

```lua
require('cmp_luarime').setup({
    -- windows用户需要指定libri
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
})
```

## mapping

```lua
require('cmp').setup({
      sources = {
        { name = "luarime" },
        ...
      }

    mapping = cmp.mapping.preset.insert({
        ["<C-space>"] = require("cmp_luarime").mappings.toggle_menu,
        ["<Space>"] = require("cmp_luarime").mappings.space_commit,
        ["<CR>"] = require("cmp_luarime").mappings.confirm,
        ...
    })
})

vim.keymap.set({ "n", "i" }, "<C-g>", require("cmp_luarime").mappings.toggle, { desc = "toggle rime" })
```
