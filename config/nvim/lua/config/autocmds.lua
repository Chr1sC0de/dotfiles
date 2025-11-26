vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("lsp-attach", { clear = true }),
	callback = function(event)
		local map = function(keys, func, desc)
			vim.keymap.set("n", keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
		end

		-- defaults:
		-- https://neovim.io/doc/user/news-0.11.html#_defaults

		map("gl", vim.diagnostic.open_float, "Open Diagnostic Float")
		map("K", vim.lsp.buf.hover, "Hover Documentation")
		map("gr", vim.lsp.buf.type_definition, "Type Definition")
		map("gr", vim.lsp.buf.references, "References")
		map("gs", vim.lsp.buf.signature_help, "Signature Documentation")
		map("gD", vim.lsp.buf.declaration, "Goto Declaration")
		map("<leader>la", vim.lsp.buf.code_action, "Code Action")
		map("<F2>", vim.lsp.buf.rename, "Rename all references")
		map("<leader>v", "<cmd>vsplit | lua vim.lsp.buf.definition()<cr>", "Goto Definition in Vertical Split")

		local function client_supports_method(client, method, bufnr)
			if vim.fn.has("nvim-0.11") == 1 then
				return client:supports_method(method, bufnr)
			else
				return client.supports_method(method, { bufnr = bufnr })
			end
		end

		local client = vim.lsp.get_client_by_id(event.data.client_id)

		if
			client
			and client_supports_method(client, vim.lsp.protocol.Methods.textDocument_documentHighlight, event.buf)
		then
			local highlight_augroup = vim.api.nvim_create_augroup("lsp-highlight", { clear = false })

			-- When cursor stops moving: Highlights all instances of the symbol under the cursor
			-- When cursor moves: Clears the highlighting
			vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
				buffer = event.buf,
				group = highlight_augroup,
				callback = vim.lsp.buf.document_highlight,
			})
			vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
				buffer = event.buf,
				group = highlight_augroup,
				callback = vim.lsp.buf.clear_references,
			})

			-- When LSP detaches: Clears the highlighting
			vim.api.nvim_create_autocmd("LspDetach", {
				group = vim.api.nvim_create_augroup("lsp-detach", { clear = true }),
				callback = function(event2)
					vim.lsp.buf.clear_references()
					vim.api.nvim_clear_autocmds({ group = "lsp-highlight", buffer = event2.buf })
				end,
			})
		end
	end,
})


-----------------------------------------------------------
-- DBUI DRAWER MAPPINGS (FileType = dbui)
-----------------------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
	pattern = "dbui",
	callback = function(event)
		local opts = { buffer = event.buf }

		vim.keymap.set("n", "o", "<Plug>(DBUI_SelectLine)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Toggle/Open" }))

		vim.keymap.set("n", "<CR>", "<Plug>(DBUI_SelectLine)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Toggle/Open" }))

		vim.keymap.set("n", "<2-LeftMouse>", "<Plug>(DBUI_SelectLine)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Mouse Toggle/Open" }))

		vim.keymap.set("n", "S", "<Plug>(DBUI_SelectLineVsplit)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Open in vsplit" }))

		vim.keymap.set("n", "d", "<Plug>(DBUI_DeleteLine)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Delete buffer/query/connection" }))

		vim.keymap.set("n", "<C-]>", "<Plug>(DBUI_JumpToForeignKey)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Jump to foreign key" }))

		vim.keymap.set("n", "A", "<Plug>(DBUI_AddConnection)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Add connection" }))

		vim.keymap.set("n", "H", "<Plug>(DBUI_ToggleDetails)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Toggle connection detail notes" }))

		vim.keymap.set("n", "R", "<Plug>(DBUI_Redraw)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Refresh drawer" }))

		vim.keymap.set("n", "r", "<Plug>(DBUI_RenameLine)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Rename buffer/saved query/connection" }))

		vim.keymap.set("n", "?", "<Plug>(DBUI_Help)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Help menu" }))

		vim.keymap.set("n", "q", "<Plug>(DBUI_Quit)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Close drawer" }))

		vim.keymap.set("n", "<C-k>", "<Plug>(DBUI_GotoFirstSibling)",
			vim.tbl_extend("force", opts, { desc = "DBUI: First sibling" }))

		vim.keymap.set("n", "<C-j>", "<Plug>(DBUI_GotoLastSibling)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Last sibling" }))

		vim.keymap.set("n", "K", "<Plug>(DBUI_GotoPrevSibling)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Previous sibling" }))

		vim.keymap.set("n", "J", "<Plug>(DBUI_GotoNextSibling)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Next sibling" }))

		vim.keymap.set("n", "<C-p>", "<Plug>(DBUI_GotoParentNode)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Parent node" }))

		vim.keymap.set("n", "<C-n>", "<Plug>(DBUI_GotoChildNode)",
			vim.tbl_extend("force", opts, { desc = "DBUI: Child node" }))
	end,
})


-----------------------------------------------------------
-- SQL QUERY BUFFER MAPPINGS (FileType = sql)
-----------------------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
	pattern = "sql",
	callback = function(event)
		local opts = { buffer = event.buf }

		vim.keymap.set("n", "<Leader>S", "<Plug>(DBUI_ExecuteQuery)",
			vim.tbl_extend("force", opts, { desc = "DB: Execute SQL file" }))

		vim.keymap.set("v", "<Leader>S", "<Plug>(DBUI_ExecuteQuery)",
			vim.tbl_extend("force", opts, { desc = "DB: Execute selected SQL" }))

		vim.keymap.set("n", "<Leader>W", "<Plug>(DBUI_SaveQuery)",
			vim.tbl_extend("force", opts, { desc = "DB: Save SQL query" }))

		vim.keymap.set("n", "<Leader>E", "<Plug>(DBUI_EditBindParameters)",
			vim.tbl_extend("force", opts, { desc = "DB: Edit bind parameters" }))
	end,
})


-----------------------------------------------------------
-- DB RESULTS BUFFER MAPPINGS (FileType = dbout)
-----------------------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
	pattern = "dbout",
	callback = function(event)
		local opts = { buffer = event.buf }

		-- Operator pending mapping for cell values: yic, vic, cic…
		vim.keymap.set({ "o", "x" }, "ic", "<Plug>(vim-dadbod-ic)",
			vim.tbl_extend("force", opts, { desc = "DB: Inner cell value" }))

		vim.keymap.set("n", "<C-]>", "<Plug>(DBUI_JumpToForeignKey)",
			vim.tbl_extend("force", opts, { desc = "DB: Jump to foreign key record" }))

		vim.keymap.set("n", "<Leader>R", "<Plug>(DBUI_ToggleResultLayout)",
			vim.tbl_extend("force", opts, { desc = "DB: Toggle expanded result view" }))
	end,
})
