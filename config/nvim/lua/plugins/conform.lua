return {
    'stevearc/conform.nvim',
    opts = {},
    event = { "BufReadPre", "BufNewFile" },
    config = function()
        require("conform").setup({
            formatters_by_ft = {
                python = { "ruff", lsp_forma = "fallback" },

            },
            format_on_save = {
                lsp_fallback = true,
                async = false,
                timeout_ms = 1000,
            },
        })
        vim.keymap.set({ "n", "v" }, "<leader>mp", function()
            require("conform").format({
                lsp_fallback = true,
                async = false,
                timeout_ms = 1000,
            })
        end, { desc = "Format file or range (in visual mode)" })
    end
}
