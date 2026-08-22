local data_dir = vim.fn.stdpath("data")

vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.opt.runtimepath:prepend(data_dir .. "/lazy/oil.nvim")

local spec = dofile(vim.fn.getcwd() .. "/config/nvim/lua/plugins/oil.lua")
spec.config()

local config = require("oil.config")
local preview_mapping = config.keymaps["<C-p>"]

assert(config.float.preview_split == "right", "floating Oil previews should open on the right")
assert(type(preview_mapping) == "table", "Oil preview should have explicit split options")
assert(preview_mapping[1] == "actions.preview", "<C-p> should run Oil's preview action")
assert(preview_mapping.opts.vertical == true, "Oil preview should use a vertical split")
assert(preview_mapping.opts.split == "belowright", "Oil preview should open to the right")
assert(type(config.keymaps.gd.callback) == "function", "file detail toggle should remain configured")
assert(config.win_options.winbar == "%!v:lua.get_oil_winbar()", "primary Oil options should survive setup")

print("oil_preview_layout_test.lua: ok")
