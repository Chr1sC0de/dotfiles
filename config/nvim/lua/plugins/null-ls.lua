local augroup = vim.api.nvim_create_augroup("LspFormatting", {})
return {
    "nvimtools/none-ls.nvim",
    requires = { "nvim-lua/plenary.nvim" },
    config = function()
        local none_ls = require("null-ls")
        none_ls.setup({
            sources = {
                none_ls.builtins.formatting.markdownlint,
                none_ls.builtins.formatting.prettierd,
            },
            on_attach = function(client, bufnr)
                if client.supports_method("textDocument/formatting") then
                    vim.api.nvim_clear_autocmds(
                        {
                            group = augroup,
                            buffer = bufnr
                        }
                    )
                    vim.api.nvim_create_autocmd("BufWritePre", {
                        group = augroup,
                        buffer = bufnr,
                        callback = function()
                            vim.lsp.buf.format({ bufnr = bufnr })
                        end
                    })
                end
            end
        })
    end
}
