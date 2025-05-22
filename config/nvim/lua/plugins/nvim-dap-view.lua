return {
    "igorlfs/nvim-dap-view",
    config = function()
        local dap = require("dap")

        require("dap-view.setup").setup({
            winbar = {
                show = true,
                -- You can add a "console" section to merge the terminal with the other views
                sections = { "watches", "scopes", "exceptions", "breakpoints", "threads", "repl" },
                -- Must be one of the sections declared above
                default_section = "watches",
                headers = {
                    breakpoints = "Breakpoints [B]",
                    scopes = "Scopes [S]",
                    exceptions = "Exceptions [E]",
                    watches = "Watches [W]",
                    threads = "Threads [T]",
                    repl = "REPL [R]",
                    console = "Console [C]",
                },
                controls = {
                    enabled = false,
                    position = "right",
                    buttons = {
                        "play",
                        "step_into",
                        "step_over",
                        "step_out",
                        "step_back",
                        "run_last",
                        "terminate",
                        "disconnect",
                    },
                    icons = {
                        pause = "",
                        play = "",
                        step_into = "",
                        step_over = "",
                        step_out = "",
                        step_back = "",
                        run_last = "",
                        terminate = "",
                        disconnect = "",
                    },
                    custom_buttons = {},
                },
            },
            windows = {
                height = 12,
                terminal = {
                    -- 'left'|'right'|'above'|'below': Terminal position in layout
                    position = "below",
                    -- List of debug adapters for which the terminal should be ALWAYS hidden
                    hide = { "debugpy", "neotest", "python", "neotest-python" },
                    -- Hide the terminal when starting a new session
                    start_hidden = true,
                },
            },
            -- Controls how to jump when selecting a breakpoint or navigating the stack
            switchbuf = "usetab",
        })

        dap.listeners.before.attach["dap-view-config"] = function()
            require("dap-view").open()
        end
        dap.listeners.before.launch["dap-view-config"] = function()
            require("dap-view").open()
        end
        dap.listeners.before.event_terminated["dap-view-config"] = function()
            require("dap-view").close()
        end
        dap.listeners.before.event_exited["dap-view-config"] = function()
            require("dap-view").close()
        end

        vim.keymap.set({ "n", "v" }, "<leader>de", function() require("dap-view").eval(nil, { enter = true }) end,
            { desc = "nvim-dap-view: evaluate" })
        vim.keymap.set({ "n", "v" }, "<leader>dt", function() require("dap-view").toggle() end,
            { desc = "nvim-dap-view: toggle" })
    end,

}
