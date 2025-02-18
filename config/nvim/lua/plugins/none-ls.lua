local augroup = vim.api.nvim_create_augroup("LspFormatting", {})
return {
    "nvimtools/none-ls.nvim",
    requires = { "nvim-lua/plenary.nvim" },
    config = function()
        local none_ls = require("null-ls")
        none_ls.setup({
            sources = {
                none_ls.builtins.formatting.markdownlint,
                none_ls.builtins.formatting.cbfmt,
                none_ls.builtins.formatting.prettierd,
            },
        })
    end
}
