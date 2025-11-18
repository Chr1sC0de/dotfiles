return {
	"nvim-telescope/telescope.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons",
		"nvim-telescope/telescope-fzf-native.nvim",
		"nvim-telescope/telescope-dap.nvim"

	},
	config = function()
		require("telescope").setup({
			extensions = {
				fzf = {
					fuzzy = true,    -- false will only do exact matching
					override_generic_sorter = true, -- override the generic sorter
					override_file_sorter = true, -- override the file sorter
					case_mode = "smart_case", -- or "ignore_case" or "respect_case"
					-- the default case_mode is "smart_case"
				},
			},
		})
		local extensions = require("telescope").extensions.menufacture
		local builtin = require("telescope.builtin")
		local actions = require("telescope.actions")
		local action_state = require("telescope.actions.state")

		vim.keymap.set("n", "<leader>ff", extensions.find_files, { desc = "Telescope: find files" })

		vim.keymap.set("n", "<leader>fT", builtin.treesitter, { desc = "Telescope: treesitter" })

		vim.keymap.set("n", "<leader>fs", extensions.grep_string, { desc = "Telescope: grep string" })

		vim.keymap.set("n", "<leader>fg", extensions.live_grep, { desc = "Telescope: live grep" })

		vim.keymap.set(
			"n",
			"<leader>fbb",
			builtin.current_buffer_fuzzy_find,
			{ desc = "Telescope: search inside the current open buffer" }
		)

		vim.keymap.set("n", "<leader>ld", builtin.lsp_document_symbols, { desc = "Telescope: lsp document symbols" })

		vim.keymap.set(
			"n",
			"<leader>lw",
			builtin.lsp_dynamic_workspace_symbols,
			{ desc = "Telescope: dynamic workspace lsp symbols" }
		)

		vim.keymap.set(
			"n",
			"<leader>lr",
			builtin.lsp_references,
			{ desc = "Telescope: search for references for symbol under cursor" }
		)

		vim.keymap.set("n", "<leader>lic", builtin.lsp_incoming_calls, { desc = "Telescope: lsp incoming calls" })

		vim.keymap.set("n", "<leader>fmm", builtin.marks, { desc = "Telescope: search marks" })

		vim.keymap.set("n", "gd", builtin.lsp_definitions, { desc = "Telescope: definitions", noremap = true })

		vim.keymap.set(
			"n",
			"<leader>lim",
			builtin.lsp_implementations,
			{ desc = "Telescope: lsp implementations", noremap = true }
		)

		vim.keymap.set("n", "<leader>fbd", function()
			builtin.diagnostics({ bufnr = 0 })
		end, { desc = "Telescope: list diagnostics" })
		vim.keymap.set("n", "<leader>fad", builtin.diagnostics, { desc = "Telescope: list diagnostics" })

		vim.keymap.set("n", "<leader>fk", ":Telescope keymaps<cr>", { desc = "Telescope: search keymaps" })

		-- git stuff
		vim.keymap.set(
			"n",
			"<leader>gk",
			builtin.git_bcommits,
			{ desc = "Telescope: buffer commits with diff preview and checks them out on <cr>" }
		)
		vim.keymap.set("n", "<leader>gK", builtin.git_commits, {
			desc =
			"Telescope: list git commits with diff preview checkout: <cr>, reset mixed: <c-r>m, reset soft: <c-r>s, reset hard: <c-s>h",
		})
		vim.keymap.set("n", "<leader>gs", builtin.git_status, { desc = "Telescope: git status" })
		vim.keymap.set("n", "<leader>gS", builtin.git_stash, { desc = "Telescope: git stash" })
		vim.keymap.set("n", "<leader>gf", extensions.git_files, { desc = "Telescope: git files" })
		vim.keymap.set("n", "<leader>gb", builtin.git_branches, {
			desc =
			"Telescope: git branch Lists all branches with log preview, checkout action <cr>, track action <C-t>, rebase action<C-r>, create action <C-a>, switch action <C-s>, delete action <C-d> and merge action <C-y>",
		})

		buffer_searcher = function()
			builtin.buffers({
				sort_mru = true,
				ignore_current_buffer = true,
				show_all_buffers = true,
				attach_mappings = function(prompt_bufnr, map)
					local refresh_buffer_searcher = function()
						actions.close(prompt_bufnr)
						vim.schedule(function()
							buffer_searcher()
							vim.api.nvim_feedkeys(
								vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
								"n",
								false
							)
						end)
					end

					local delete_buf = function()
						local selection = action_state.get_selected_entry()
						vim.api.nvim_buf_delete(selection.bufnr, { force = true })
						refresh_buffer_searcher()
					end

					local delete_multiple_buf = function()
						local picker = action_state.get_current_picker(prompt_bufnr)
						local selection = picker:get_multi_selection()
						for _, entry in ipairs(selection) do
							vim.api.nvim_buf_delete(entry.bufnr, { force = true })
						end
						refresh_buffer_searcher()
					end

					map("n", "dd", delete_buf)
					map("n", "<C-d>", delete_multiple_buf)
					map("i", "<C-d>", delete_multiple_buf)

					return true
				end,
			})
		end

		vim.keymap.set("n", "<leader>fob", buffer_searcher, { desc = "Telescope: search buffers" })

		require("telescope").load_extension("fzf")

		-- Keymap to trigger the Telescope man_pages with the custom action
		vim.keymap.set("n", "<leader>fmp", function()
			builtin.man_pages({
				attach_mappings = function(_, map)
					local function open_man_fullscreen(prompt_bufnr)
						local entry = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						vim.cmd("tabnew")
						vim.cmd("Man " .. entry.value)
						vim.cmd("only")
					end
					map("i", "<CR>", open_man_fullscreen)
					map("n", "<CR>", open_man_fullscreen)
					return true
				end,
				previewer = true, -- Optional: disable preview window
			})
		end, { desc = "Telescope: search man pages in fullscreen" })

		-- Keymap to trigger the Telescope help tags with the custom action
		-- vim.keymap.set("n", "<leader>fht", builtin.help_tags, { desc = "Telescope: search help tags" })
		vim.keymap.set("n", "<leader>fht", function()
			builtin.help_tags({
				attach_mappings = function(_, map)
					local function open_help_tags_fullscreen(prompt_bufnr)
						local entry = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						vim.cmd("tabnew")
						vim.cmd("help " .. entry.value)
						vim.cmd("only")
					end
					map("i", "<CR>", open_help_tags_fullscreen)
					map("n", "<CR>", open_help_tags_fullscreen)
					return true
				end,
				previewer = true, -- Optional: disable preview window
			})
		end, { desc = "Telescope: search help tags" })
		-- plugins
		require('telescope').load_extension('dap')
	end,
}
