local augroup = vim.api.nvim_create_augroup("LspFormatting", {})

return {
    "nvimtools/none-ls.nvim",
    requires = { "nvim-lua/plenary.nvim" },
    config = function()
        local null_ls = require("null-ls")
        null_ls.setup({
            sources = {
                null_ls.builtins.formatting.markdownlint,
                null_ls.builtins.formatting.cbfmt,
                null_ls.builtins.formatting.prettierd,
                null_ls.builtins.formatting.djlint,
            },
        })
    end
}
