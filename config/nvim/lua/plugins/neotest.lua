return {
    "nvim-neotest/neotest",
    dependencies = {
        "nvim-neotest/neotest-python",
        "nvim-neotest/nvim-nio",
        "nvim-lua/plenary.nvim",
        "antoinemadec/FixCursorHold.nvim",
        "nvim-treesitter/nvim-treesitter"
    },
    config = function()
        require("neotest").setup({
            adapters = {
                require("neotest-python")({
                    dap = { justMyCode = true },
                    runner = "pytest",
                    python = ".venv/bin/python"
                }),
            },
        })
        vim.keymap.set("n", "<leader>tn", function() require("neotest").run.run() end, { desc = "neotest: run nearest" })
        vim.keymap.set("n", "<leader>tf", function() require("neotest").run.run(vim.fn.expand("%")) end,
            { desc = "neotest: test file" })
        vim.keymap.set("n", "<leader>td", function() require("neotest").run.run({ strategy = "dap" }) end,
            { desc = "neotest: debug nearest test" })
        vim.keymap.set("n", "<leader>ts", function() require("neotest").run.stop() end,
            { desc = "neotest: stop the nearest test" })
        vim.keymap.set("n", "<leader>ta", function() require("neotest").run.attach() end,
            { desc = "neotest: attach the nearest test" })
        vim.keymap.set("n", "<leader>tp", function() require("neotest").output.open() end,
            { desc = "neotest: open test panel" })
    end
}
