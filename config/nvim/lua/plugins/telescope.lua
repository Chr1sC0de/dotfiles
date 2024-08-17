return {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.8",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
        require("telescope").setup({})
        local extensions = require('telescope').extensions.menufacture
        local builtin = require("telescope.builtin")
        vim.keymap.set("n", "<leader>ff", extensions.find_files, { desc = "Telescope: find files" })
        vim.keymap.set("n", "<leader>ft", builtin.treesitter, { desc = "Telescope: treesitter" })
        vim.keymap.set("n", "<leader>fs", extensions.grep_string, { desc = "Telescope: grep string" })
        vim.keymap.set("n", "<leader>fg", extensions.live_grep, { desc = "Telescope: live grep" })
        vim.keymap.set("n", "<leader>fB", builtin.buffers, { desc = "Telescope: search buffers" })
        vim.keymap.set("n", "<leader>fb", builtin.current_buffer_fuzzy_find,
            { desc = "Telescope: search inside the current open buffer" })
        vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Telescope: search help tags" })
        vim.keymap.set("n", "<leader>fm", builtin.marks, { desc = "Telescope: search marks" })
        vim.keymap.set("n", "<leader>fk", ":Telescope keymaps<cr>", { desc = "Telescope: search keymaps" })
        -- git stuff
        vim.keymap.set("n", "<leader>gk", builtin.git_bcommits,
            { desc = "Telescope: buffer commits with diff preview and checks them out on <cr>" })
        vim.keymap.set("n", "<leader>gK", builtin.git_commits,
            {
                desc =
                "Telescope: list git commits with diff preview checkout: <cr>, reset mixed: <c-r>m, reset soft: <c-r>s, reset hard: <c-s>h"
            })
        vim.keymap.set("n", "<leader>gs", builtin.git_status, { desc = "Telescope: git status" })
        vim.keymap.set("n", "<leader>gS", builtin.git_stash, { desc = "Telescope: git stash" })
        vim.keymap.set("n", "<leader>gb", builtin.git_branches,
            {
                desc =
                "Telescope: git branch Lists all branches with log preview, checkout action <cr>, track action <C-t>, rebase action<C-r>, create action <C-a>, switch action <C-s>, delete action <C-d> and merge action <C-y>"
            })
    end
}
