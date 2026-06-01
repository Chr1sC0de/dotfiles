vim.keymap.set("n", "<leader>dl", function()
	require("osv").launch({ port = 8086, frozen_delay = 100 })
end, { noremap = true, desc = "dap: launch one small step neovim debugger, need to attach in separate instance" })
