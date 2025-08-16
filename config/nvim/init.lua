require "core.lazy"
require "core.lsp"

require "config.options"
require "config.autocmds"
require "config.keymaps"

local border_colors = "#85adf3"

-- Transparent floating window backgrounds
vim.api.nvim_set_hl(0, "NormalFloat", { fg = border_colors, bg = "none" })
vim.api.nvim_set_hl(0, "FloatBorder", { fg = border_colors, bg = "none" })

-- Optional: if your theme also uses FloatTitle or FloatFooter
vim.api.nvim_set_hl(0, "FloatTitle", { fg = border_colors, bg = "none" })
vim.api.nvim_set_hl(0, "FloatFooter", { fg = border_colors, bg = "none" })

vim.opt.signcolumn = "yes"
