return {
    "joshuavial/aider.nvim",
    config = function()
        require("aider").setup(
            {
                -- your configuration comes here
                -- if you don't want to use the default settings
                auto_manage_context = true, -- automatically manage buffer context
                default_bindings = false,   -- use default <leader>A keybindings
                debug = false,              -- enable debug logging
            }
        )
        vim.api.nvim_set_keymap('n', '<leader>Ao', ':AiderOpen<CR><C-w>l:close<CR>',
            { noremap = true, silent = true, desc = "Aider Open" })
        vim.api.nvim_set_keymap('n', '<leader>Am', ':AiderAddModifiedFiles<CR>',
            { noremap = true, silent = true, desc = "AiderAddModifiedFailes" })
    end

}
