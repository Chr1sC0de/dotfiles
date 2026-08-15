return {
	"Vigemus/iron.nvim",
	enabled = not vim.g.vscode,
	config = function()
		local iron = require("iron.core")
		local lowlevel = require("iron.lowlevel")
		local marks = require("iron.marks")
		local view = require("iron.view")
		local common = require("iron.fts.common")
		local native = {
			send_line = iron.send_line,
			send_mark = iron.send_mark,
			send_until_cursor = iron.send_until_cursor,
		}

		local function position_leq(a_row, a_col, b_row, b_col)
			return a_row < b_row or (a_row == b_row and a_col <= b_col)
		end

		local function contains_range(sr, sc, er, ec, rs, rc, re, rec)
			return position_leq(sr, sc, rs, rc) and position_leq(re, rec, er, ec)
		end

		local function injected_filetype(range)
			local ok, parser = pcall(vim.treesitter.get_parser, 0)
			if not ok or not parser then
				return nil
			end

			parser:parse()
			local language_tree = parser:language_for_range(range)
			local language = language_tree:lang()
			if language == vim.bo.filetype then
				return nil
			end

			-- A LanguageTree may contain several disjoint injected regions. Only
			-- route when the complete action range belongs to one of them.
			local inside_region = false
			for _, region in pairs(language_tree:included_regions()) do
				for _, included_range in ipairs(region) do
					if contains_range(
						included_range[1], included_range[2], included_range[4], included_range[5],
						range[1], range[2], range[3], range[4]
					) then
						inside_region = true
						break
					end
				end
				if inside_region then
					break
				end
			end
			if not inside_region then
				return nil
			end

			local has_repl, repl = pcall(lowlevel.get_repl_def, language)
			if not has_repl or not repl then
				return nil
			end
			return language
		end

		local function send_range(range, data)
			local filetype = injected_filetype(range)
			if not filetype then
				return false
			end
			iron.send(filetype, data)
			return true
		end

		local function send_line()
			local row = vim.api.nvim_win_get_cursor(0)[1] - 1
			local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
			if line == "" then
				return
			end
			if send_range({ row, 0, row, #line }, line) then
				marks.set({ from_line = row, from_col = 0, to_line = row, to_col = #line - 1 })
			else
				native.send_line()
			end
		end

		local function send_visual()
			local data = iron.mark_visual()
			local range = marks.get()
			if data and range and send_range({ range.from_line, range.from_col, range.to_line, range.to_col + 1 }, data) then
				return
			end
			iron.send(nil, data)
		end

		local function send_mark()
			local range = marks.get()
			if not range then
				return
			end
			local text = vim.api.nvim_buf_get_text(0, range.from_line, range.from_col, range.to_line, range.to_col + 1, {})
			if not send_range({ range.from_line, range.from_col, range.to_line, range.to_col + 1 }, text) then
			native.send_mark()
			end
		end

		local function send_until_cursor()
			local row = vim.api.nvim_win_get_cursor(0)[1] - 1
			local lines = vim.api.nvim_buf_get_lines(0, 0, row + 1, false)
			local last_line = lines[#lines] or ""
			if send_range({ 0, 0, row, #last_line }, lines) then
				marks.set({ from_line = 0, from_col = 0, to_line = row, to_col = #last_line - 1 })
			else
				native.send_until_cursor()
			end
		end

		local function send_motion(mtype)
			local data = iron.mark_motion(mtype)
			local range = marks.get()
			if not (data and range and send_range({ range.from_line, range.from_col, range.to_line, range.to_col + 1 }, data)) then
				iron.send(nil, data)
			end
		end

		iron.setup({
			config = {
				-- Whether a repl should be discarded or not
				scratch_repl = true,
				-- Your repl definitions come here
				repl_definition = {
					sh = {
						-- Can be a table or a function that
						-- returns a table (see below)
						command = { "bash" },
					},
					bash = {
						-- Can be a table or a function that
						-- returns a table (see below)
						command = { "bash" },
					},
					python = {
						command = { "python" }, -- or { "ipython", "--no-autoindent" }
						format = common.bracketed_paste_python,
						block_dividers = { "# %%", "#%%" },
						env = { PYTHON_BASIC_REPL = "1" }, --this is needed for python3.13 and up.
					},
				},
				-- set the file type of the newly created repl to ft
				-- bufnr is the buffer id of the REPL and ft is the filetype of the
				-- language being used for the REPL.
				repl_filetype = function(bufnr, ft)
					return ft
					-- or return a string name such as the following
					-- return "iron"
				end,
				-- Send selections to the DAP repl if an nvim-dap session is running.
				dap_integration = true,
				-- How the repl window will be displayed
				-- See below for more information
				-- repl_open_cmd = view.split.vertical.botright("25%"),
				-- repl_open_cmd can also be an array-style table so that multiple
				-- repl_open_commands can be given.
				-- When repl_open_cmd is given as a table, the first command given will
				-- be the command that `IronRepl` initially toggles.
				-- Moreover, when repl_open_cmd is a table, each key will automatically
				-- be available as a keymap (see `keymaps` below) with the names
				-- toggle_repl_with_cmd_1, ..., toggle_repl_with_cmd_k
				-- For example,
				--
				repl_open_cmd = {
					view.split.vertical.rightbelow("%40"),
					view.split.rightbelow("%25"),
				},
			},
			-- Iron doesn't set keymaps by default anymore.
			-- You can set them here or manually add keymaps to the functions in iron.core
			keymaps = {
				toggle_repl = "<space>rr", -- toggles the repl open and closed.
				-- If repl_open_command is a table as above, then the following keymaps are
				-- available
				toggle_repl_with_cmd_1 = "<space>rv",
				toggle_repl_with_cmd_2 = "<space>rs",
				restart_repl = "<space>rR", -- calls `IronRestart` to restart the repl
				send_motion = "<space>sc",
				visual_send = "<space>sc",
				send_file = "<space>sf",
				send_line = "<space>sl",
				send_paragraph = "<space>sp",
				send_until_cursor = "<space>su",
				send_mark = "<space>sm",
				send_code_block = "<space>sb",
				send_code_block_and_move = "<space>sn",
				mark_motion = "<space>mc",
				mark_visual = "<space>mc",
				remove_mark = "<space>md",
				cr = "<space>s<cr>",
				interrupt = "<space>s<space>",
				exit = "<space>sq",
				clear = "<space>il",
			},
			-- If the highlight is on, you can change how it looks
			-- For the available options, check nvim_set_hl
			highlight = {
				italic = true,
			},
			ignore_blank_lines = true, -- ignore blank lines when sending visual select lines
		})

		-- Route only actions whose complete source range belongs to one injected
		-- language. Patching these public helpers also covers Iron's paragraph and
		-- code-block implementations, which delegate to visual_send/send_mark.
		iron.visual_send = send_visual
		iron.send_mark = send_mark
		iron.send_motion = send_motion

		vim.keymap.set("n", "<space>sl", send_line, { silent = true, desc = "iron_repl_send_line" })
		vim.keymap.set("v", "<space>sc", send_visual, { silent = true, desc = "iron_repl_visual_send" })
		vim.keymap.set("n", "<space>su", send_until_cursor, { silent = true, desc = "iron_repl_send_until_cursor" })
		vim.keymap.set("n", "<space>sm", send_mark, { silent = true, desc = "iron_repl_send_mark" })
		vim.keymap.set("n", "<space>sc", function() iron.run_motion("send_motion") end,
			{ silent = true, desc = "iron_repl_send_motion" })

		-- iron also has a list of commands, see :h iron-commands for all available commands
		vim.keymap.set("n", "<space>rf", "<cmd>IronFocus<cr>", { desc = "iron_repl_focus" })
		vim.keymap.set("n", "<space>rh", "<cmd>IronHide<cr>", { desc = "iron_repl_hide" })
	end,
}
