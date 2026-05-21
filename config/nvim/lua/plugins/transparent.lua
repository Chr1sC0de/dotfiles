return {
	"xiyaowong/transparent.nvim",
	enabled = not vim.g.vscode,
	config = function()
		-- Optional, you don't have to run setup.
		require("transparent").setup({
			-- table: default groups
			groups = {
				"Normal",
				"NormalNC",
				"Comment",
				"Constant",
				"Special",
				"Identifier",
				"Statement",
				"PreProc",
				"Type",
				"Underlined",
				"Todo",
				"String",
				"Function",
				"Conditional",
				"Repeat",
				"Operator",
				"Structure",
				"LineNr",
				"NonText",
				"SignColumn",
				"CursorLine",
				"CursorLineNr",
				"StatusLine",
				"StatusLineNC",
				"EndOfBuffer",
			},
			-- table: additional groups that should be cleared
			extra_groups = {
				"NormalFloat", -- plugins which have float panel such as Lazy, Mason, LspInfo
				"NvimTreeNormal", -- NvimTree
				"NeoTreeNormal", -- Neotree
			},
			-- table: groups you don't want to clear
			exclude_groups = {},
			-- function: code to be executed after highlight groups are cleared
			-- Also the user event "TransparentClear" will be triggered
			on_clear = function()
				local ok, border = pcall(vim.api.nvim_get_hl, 0, { name = "FloatBorder", link = false })
				local hl = { bg = "NONE" }
				if ok and border.fg then
					hl.fg = border.fg
				end

				for _, group in ipairs({ "SnacksPickerBorder", "SnacksPickerBoxBorder" }) do
					vim.api.nvim_set_hl(0, group, hl)
				end
			end,
		})
	end,
}
