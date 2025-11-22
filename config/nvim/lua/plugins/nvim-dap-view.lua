return {
    "igorlfs/nvim-dap-view",
    config = function()
        local dap = require("dap")

        require("dap-view.setup").setup({
            windows = {
                height = 12,
                terminal = {
                    -- 'left'|'right'|'above'|'below': Terminal position in layout
                    position = "right",
                    -- List of debug adapters for which the terminal should be ALWAYS hidden
                    -- hide = { "debugpy", "neotest", "python", "neotest-python" },
                    -- Hide the terminal when starting a new session
                    -- start_hidden = true,
                },
            },
            -- Controls how to jump when selecting a breakpoint or navigating the stack
            switchbuf = "usetab",
        })

        -- dap.listeners.before.attach["dap-view-config"] = function()
        --     require("dap-view").open()
        -- end
        -- dap.listeners.before.launch["dap-view-config"] = function()
        --     require("dap-view").open()
        -- end
        -- dap.listeners.before.event_terminated["dap-view-config"] = function()
        --     require("dap-view").close()
        -- end
        -- dap.listeners.before.event_exited["dap-view-config"] = function()
        --     require("dap-view").close()
        -- end

        vim.keymap.set({ "n", "v" }, "<leader>de", function() require("dap-view").eval(nil, { enter = true }) end,
            { desc = "nvim-dap-view: evaluate" })
        vim.keymap.set({ "n", "v" }, "<leader>dt", function() require("dap-view").toggle() end,
            { desc = "nvim-dap-view: toggle" })
    end,

}
