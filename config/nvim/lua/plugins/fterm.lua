return {
    "numToStr/FTerm.nvim",
    config = function()
        require 'FTerm'.setup({
            border     = 'rounded',
            dimensions = {
                height = 0.9,
                width = 0.9,
            },
        })
        -- Example keybindings
        vim.keymap.set('n', '<A-i>', '<CMD>lua require("FTerm").toggle()<CR>', { desc = "Toggle Terminal" })
        vim.keymap.set('t', '<A-i>', '<C-\\><C-n><CMD>lua require("FTerm").toggle()<CR>', { desc = "Toggle Terminal" })
    end

}
