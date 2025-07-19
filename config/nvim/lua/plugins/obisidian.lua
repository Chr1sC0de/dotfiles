return {
    "epwalsh/obsidian.nvim",
    version = "*", -- recommended, use latest release instead of latest commit
    lazy = true,
    ft = "markdown",
    -- Replace the above line with this if you only want to load obsidian.nvim for markdown files in your vault:
    -- event = {
    --   -- If you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
    --   -- E.g. "BufReadPre " .. vim.fn.expand "~" .. "/my-vault/*.md"
    --   -- refer to `:h file-pattern` for more examples
    --   "BufReadPre path/to/my-vault/*.md",
    --   "BufNewFile path/to/my-vault/*.md",
    -- },
    dependencies = {
        -- Required.
        "nvim-lua/plenary.nvim",
        -- see below for full list of optional dependencies 👇
    },
    config = function()
        require("obsidian").setup(
            {
                workspaces = {
                    {
                        name = "personal",
                        path = "~/Documents/obsidian",
                    },
                },
                wiki_link_func = "use_alias_only",
                ui = { enable = true }
            }

        )
        vim.keymap.set("n", "<leader>ot", ":ObsidianTags<cr>", { desc = "Obsidian Tags" })
        vim.keymap.set("n", "<leader>on", ":ObsidianNew<cr>", { desc = "Obsidian New" })
        vim.keymap.set("n", "<leader>faa", ":ObsidianSearch #<cr>", { desc = "Obsidian Search headings" })
    end
}
