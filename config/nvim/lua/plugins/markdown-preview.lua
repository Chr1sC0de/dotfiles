return -- install with yarn or npm
{
    "Carus11/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = "cd app && yarn install",
    init = function()
        vim.g.mkdp_filetypes = { "markdown" }
    end,
    ft = { "markdown" },

    config = function()
        vim.keymap.set("n", "<leader>mp", ":MarkdownPreview<cr>", { desc = "Markdown Preview: Start" })
        vim.keymap.set("n", "<leader>mx", ":MarkdownPreviewStop<cr>", { desc = "Markdown Preview: Stop" })
        vim.keymap.set("n", "<leader>mt", ":MarkdownPreviewToggle<cr>", { desc = "Markdown Preview: Toggle" })
    end

}
