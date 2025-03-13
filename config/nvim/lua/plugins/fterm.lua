return {
    "numToStr/FTerm.nvim",
    config = function()
        require 'FTerm'.setup({
            border     = 'rounded',
            dimensions = {
                height = 0.8,
                width = 0.8,
            },
        })
        -- Example keybindings
        vim.keymap.set('n', '<A-i>', '<CMD>lua require("FTerm").toggle()<CR>', { desc = "Toggle Terminal: Terminal 1" })
        vim.keymap.set('t', '<A-i>', '<C-\\><C-n><CMD>lua require("FTerm").toggle()<CR>',
            { desc = "Toggle Terminal: Terminal 1" })

        local fterm = require("FTerm")

        local fterm2 = fterm:new({
            ft = 'FTerm2', -- You can also override the default filetype, if you want
            cmd = os.getenv('SHELL'),
            dimensions = {
                height = 0.8,
                width = 0.8
            }
        })

        vim.keymap.set('n', '<A-e>', function() fterm2:toggle() end, { desc = "Toggle Terminal: Terminal 2" })
        vim.keymap.set('t', '<A-e>', function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, true, true), 'n', false)
            fterm2:toggle()
        end, { desc = "Toggle Terminal: Terminal 2" })
    end

}
