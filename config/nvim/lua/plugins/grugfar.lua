return {
    'MagicDuck/grug-far.nvim',
    opts = { headerMaxWidth = 80 },
    cmd = "GrugFar",
    config = function()
        -- optional setup call to override plugin options
        -- alternatively you can set options with vim.g.grug_far = { ... }
        require('grug-far').setup({
            -- options, see Configuration section below
            -- there are no required options atm
            -- engine = 'ripgrep' is default, but 'astgrep' or 'astgrep-rules' can
            -- be specified
        });
        vim.keymap.set({ "n", "v" }, "<leader>sr", function()
            local grug = require("grug-far")
            local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
            grug.grug_far({
                transient = true,
                prefills = {
                    filesFilter = ext and ext ~= "" and "*." .. ext or nil,
                },
            })
        end, { desc = "GrugFar: Search and Replace" })
    end,
}
