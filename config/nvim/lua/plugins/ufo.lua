return {
    "kevinhwang91/nvim-ufo",
    dependencies = { "kevinhwang91/promise-async" },
    config = function()
        local ufo = require("ufo")
        vim.o.foldcolumn = "0" -- "0" is not bad
        vim.o.foldlevel = 99   -- Using ufo provider need a large value, feel free to decrease the value
        vim.o.foldlevelstart = 99
        vim.o.foldenable = true
        vim.keymap.set("n", "zR", ufo.openAllFolds, { desc = "ufo: open all fold" })
        vim.keymap.set("n", "zM", ufo.closeAllFolds, { desc = "ufo: close all folds" })
        ufo.setup({
            provider_selector = function(bufnr, filetype, buftype)
                return { "treesitter" }
            end
        })
    end
}
