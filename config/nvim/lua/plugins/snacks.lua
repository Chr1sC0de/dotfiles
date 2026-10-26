return {
	"folke/snacks.nvim",
	enabled = not vim.g.vscode,
	lazy = false,
	priority = 1000,
	opts = {
		bigfile = { enabled = true },
		dashboard = { enabled = true },
		explorer = { enabled = true },
		indent = { enabled = true },
		input = { enabled = true },
		notifier = {
			enabled = true,
			timeout = 3000,
		},
		quickfile = { enabled = true },
		scope = { enabled = true },
		scroll = { enabled = false },
		statuscolumn = { enabled = false },
		words = { enabled = true },
		styles = {
			notification = {
				-- wo = { wrap = true } -- Wrap notifications
			},
		},
		picker = {
			enabled = true,
			ui_select = true,
			main = { current = true },
			layout = {
				layout = {
					width = 0.999,
					height = 0.999,
				},
			},
			sources = {
				select = {
					config = function(opts)
						local configure = opts.layout.config
						opts.layout.config = function(layout)
							layout = configure and configure(layout) or layout
							-- Snacks' item-count cap can produce fractional row counts.
							for _, box in ipairs(layout.layout) do
								if box.win == "list" and type(box.height) == "number" and box.height > 1 then
									box.height = math.floor(box.height)
								end
							end
							return layout
						end
					end,
				},
				explorer = {
					layout = {
						preset = "sidebar",
						preview = false,
						layout = {
							width = 32,
							min_width = 32,
							position = "left", -- or "right"
						},
					},
				},
				lines = {
					layout = {
						preset = "default",
						fullscreen = true,
						preview = true,
					},
				},
			},
		},
	},
	config = function(_, opts)
		require("snacks").setup(opts)
		require("config.snacks_pickers").setup()
	end,
}
