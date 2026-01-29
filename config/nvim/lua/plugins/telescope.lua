return {
	"nvim-telescope/telescope.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons",
		"nvim-telescope/telescope-fzf-native.nvim",
		"nvim-telescope/telescope-dap.nvim",
		"molecule-man/telescope-menufacture",
	},
	config = function()
		require("telescope").setup({
			extensions = {
				fzf = {
					fuzzy = true, -- false will only do exact matching
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
			desc = "Telescope: list git commits with diff preview checkout: <cr>, reset mixed: <c-r>m, reset soft: <c-r>s, reset hard: <c-s>h",
		})
		vim.keymap.set("n", "<leader>gs", builtin.git_status, { desc = "Telescope: git status" })
		vim.keymap.set("n", "<leader>gS", builtin.git_stash, { desc = "Telescope: git stash" })
		vim.keymap.set("n", "<leader>gf", extensions.git_files, { desc = "Telescope: git files" })
		vim.keymap.set("n", "<leader>gb", builtin.git_branches, {
			desc = "Telescope: git branch Lists all branches with log preview, checkout action <cr>, track action <C-t>, rebase action<C-r>, create action <C-a>, switch action <C-s>, delete action <C-d> and merge action <C-y>",
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

		vim.keymap.set("n", "<leader>fht", function()
			builtin.help_tags({
				attach_mappings = function(_, map)
					local function open_help_tags_fullscreen(prompt_bufnr)
						local entry = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
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
		require("telescope").load_extension("dap")

		-- code to search through only terminals
		local pickers = require("telescope.pickers")
		local finders = require("telescope.finders")
		local conf = require("telescope.config").values
		local previewers = require("telescope.previewers")
		local actions = require("telescope.actions")
		local action_state = require("telescope.actions.state")
		local uv = vim.loop

		---------------------------------------------------------------------
		-- BAT PREVIEWER (works with terminal buffers)
		---------------------------------------------------------------------
		local function terminal_preview()
			return previewers.new_buffer_previewer({
				title = "Terminal Output",
				define_preview = function(self, entry)
					if not entry or not entry.bufnr then
						return
					end

					local lines = vim.api.nvim_buf_get_lines(entry.bufnr, 0, -1, false)
					local max_lines = 200

					if #lines > max_lines then
						lines = vim.list_slice(lines, #lines - max_lines, #lines)
					end

					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
				end,
			})
		end

		---------------------------------------------------------------------
		-- DELETE TERMINAL BUFFER SAFELY
		---------------------------------------------------------------------
		local function delete_terminal_buffer(entry)
			local bufnr = entry.bufnr
			if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end

			-- Kill job if running
			local chan = vim.b[bufnr].terminal_job_id
			if chan then
				pcall(vim.fn.jobstop, chan)
			end

			-- Delete the buffer
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end

		---------------------------------------------------------------------
		-- MAIN TELESCOP PICKER
		---------------------------------------------------------------------
		local function open_terminal_picker()
			local terminal_bufs = {}
			local current = vim.api.nvim_get_current_buf()

			-- Collect terminal buffers except current
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if
					vim.api.nvim_buf_is_loaded(buf)
					and buf ~= current
					and vim.bo[buf].buftype == "terminal"
					and vim.startswith(vim.api.nvim_buf_get_name(buf), "term:")
				then
					table.insert(terminal_bufs, {
						bufnr = buf,
						name = vim.api.nvim_buf_get_name(buf),
					})
				end
			end

			pickers
				.new({}, {
					prompt_title = "Terminal Buffers",
					finder = finders.new_table({
						results = terminal_bufs,
						entry_maker = function(entry)
							local name = entry.name ~= "" and entry.name or ("term://" .. entry.bufnr)
							return {
								value = entry.bufnr,
								display = name,
								ordinal = name,
								bufnr = entry.bufnr,
							}
						end,
					}),
					sorter = conf.generic_sorter({}),
					previewer = terminal_preview(),

					attach_mappings = function(prompt_bufnr, map)
						-----------------------------------------------------------------
						-- OPEN BUFFER
						-----------------------------------------------------------------
						local function open_selection()
							local selection = action_state.get_selected_entry()
							actions.close(prompt_bufnr)
							vim.api.nvim_set_current_buf(selection.bufnr)
						end
						map("i", "<CR>", open_selection)
						map("n", "<CR>", open_selection)

						-----------------------------------------------------------------
						-- DELETE BUFFER (insert)
						-----------------------------------------------------------------
						map("i", "<C-d>", function()
							local entry = action_state.get_selected_entry()
							delete_terminal_buffer(entry)
							actions.close(prompt_bufnr)
							open_terminal_picker()
						end)

						-----------------------------------------------------------------
						-- DELETE BUFFER (normal)
						-----------------------------------------------------------------
						map("n", "dd", function()
							local entry = action_state.get_selected_entry()
							delete_terminal_buffer(entry)
							actions.close(prompt_bufnr)
							open_terminal_picker()
						end)

						return true
					end,
				})
				:find()
		end

		---------------------------------------------------------------------
		-- COMMAND
		---------------------------------------------------------------------
		vim.api.nvim_create_user_command("TelescopeTerminals", open_terminal_picker, {})
		vim.keymap.set("n", "<leader>fot", "<cmd>TelescopeTerminals<CR>")
	end,
}
