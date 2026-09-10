-- statusline
return {
	"nvim-lualine/lualine.nvim",
	event = "VeryLazy",
	enabled = not vim.g.vscode,
	init = function()
		vim.g.lualine_laststatus = vim.o.laststatus
		if vim.fn.argc(-1) > 0 then
			-- set an empty statusline till lualine loads
			vim.o.statusline = " "
		else
			-- hide the statusline on the starter page
			vim.o.laststatus = 0
		end
	end,
	config = function()
		local repositories = {}
		local function refresh()
			require("lualine").refresh({ place = { "statusline" } })
		end

		local function repo_name()
			local cwd = vim.fn.getcwd()
			if repositories[cwd] then
				return repositories[cwd].name
			end

			local entry = { name = "", pending = true }
			repositories[cwd] = entry
			local ok = pcall(
				vim.system,
				{ "git", "worktree", "list", "--porcelain", "-z" },
				{ cwd = cwd },
				function(result)
					vim.schedule(function()
						entry.pending = false
						if result.code == 0 then
							-- Git lists the main worktree first, even from a linked worktree.
							local root = (result.stdout or ""):match("^worktree (.-)%z")
							if root then
								entry.name = vim.fs.basename(root):gsub("%c", " "):gsub("%%", "%%%%")
							end
						end
						refresh()
					end)
				end
			)
			if not ok then
				entry.pending = false
			end
			return entry.name
		end

		vim.api.nvim_create_autocmd({ "DirChanged", "FocusGained" }, {
			group = vim.api.nvim_create_augroup("LualineRepositoryName", { clear = true }),
			callback = function()
				for cwd, entry in pairs(repositories) do
					-- Keep in-flight queries so redraws cannot start duplicate processes.
					if not entry.pending then
						repositories[cwd] = nil
					end
				end
				refresh()
			end,
		})

		require("lualine").setup({
			options = {
				icons_enabled = true,
				theme = "catppuccin-nvim",
				component_separators = { left = "", right = "" },
				section_separators = { left = "", right = "" },
				globalstatus = vim.o.laststatus == 3,
				disabled_filetypes = { statusline = { "dashboard", "alpha", "ministarter" } },
				ignore_focus = {},
				always_divide_middle = true,
				refresh = {
					statusline = 1000,
					tabline = 1000,
					winbar = 1000,
				},
			},
			sections = {
				lualine_a = { "mode" },
				lualine_b = { repo_name, "branch", "diff", "diagnostics" },
				lualine_c = { { "filename", path = 1, file_status = true } },
				lualine_x = { "encoding", "fileformat", "filetype" },
				lualine_y = { "progress" },
				lualine_z = { "location" },
			},
			inactive_sections = {
				lualine_a = {},
				lualine_b = {},
				lualine_c = { "filename" },
				lualine_x = { "location" },
				lualine_y = {},
				lualine_z = {},
			},
			tabline = {},
			winbar = {},
			inactive_winbar = {},
			extensions = { "neo-tree", "lazy" },
		})
	end,
}
