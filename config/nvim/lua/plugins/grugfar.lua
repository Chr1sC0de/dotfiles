return {
    'MagicDuck/grug-far.nvim',
    opts = { headerMaxWidth = 80 },
    lazy = false,
    cmd = "GrugFar",
    config = function()
        -- optional setup call to override plugin options
        -- alternatively you can set options with vim.g.grug_far = { ... }
        require('grug-far').setup({});
        vim.keymap.set({ "n", "v" }, "<leader>sr", function()
            local grug = require("grug-far")
            local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
            grug.with_visual_selection({
                transient = true,
                prefills = {
                    filesFilter = ext and ext ~= "" and "*." .. ext or nil,
                },
            })
        end, { desc = "GrugFar: Search and Replace" })
    end,
}
