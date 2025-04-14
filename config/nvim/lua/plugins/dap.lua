return {
    "mfussenegger/nvim-dap",
    recommended = true,
    desc = "Debugging support. Requires language specific adapters to be configured. (see lang extras)",

    dependencies = {
        "rcarriga/nvim-dap-ui",
        -- python
        "mfussenegger/nvim-dap-python",
        -- virtual text for the debugger
        {
            "theHamsta/nvim-dap-virtual-text",
            opts = {},
        },
    },
    config = function()
        require("dapui").setup()
        local dap = require("dap")
        -- set the keymaps
        vim.keymap.set('n', '<F5>', function() dap.continue() end, { desc = "dap: continue" })
        vim.keymap.set('n', '<s-F5>', function() dap.terminate() end, { desc = "dap: terminate session" })
        vim.keymap.set('n', '<F10>', function() dap.step_over() end, { desc = "dap: step over" })
        vim.keymap.set('n', '<F11>', function() dap.step_into() end, { desc = "dap: step into" })
        vim.keymap.set('n', '<F12>', function() dap.step_out() end, { desc = "dap: step out" })
        vim.keymap.set('n', '<F9>', function() dap.toggle_breakpoint() end,
            { desc = "dap: toggle break point" })
        vim.keymap.set('n', '<Leader>B', function() dap.set_breakpoint() end, { desc = "dap: set breakpoint" })
        vim.keymap.set('n', '<Leader>lp',
            function() dap.set_breakpoint(nil, nil, vim.fn.input('Log point message: ')) end,
            { desc = "dap: set logpoint message" })
        vim.keymap.set('n', '<Leader>dr', function() dap.repl.toggle() end, { desc = "dap: open toggle" })
        vim.keymap.set('n', '<Leader>dl', function() dap.run_last() end, { desc = "dap: run last" })
        vim.keymap.set({ 'n', 'v' }, '<Leader>dh', function()
            require('dap.ui.widgets').hover()
        end, { desc = "dap: hover widgets" })
        vim.keymap.set({ 'n', 'v' }, '<Leader>dp', function()
            require('dap.ui.widgets').preview()
        end, { desc = "dap: preview widgets" })
        vim.keymap.set('n', '<Leader>df', function()
            local widgets = require('dap.ui.widgets')
            widgets.centered_float(widgets.frames)
        end, { desc = "dap: centered floats frames" })
        vim.keymap.set('n', '<Leader>ds', function()
            local widgets = require('dap.ui.widgets')
            widgets.centered_float(widgets.scopes)
        end, { desc = "dap: centered floats scopes" })

        vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, link = "Visual" })

        -- setup the dap configurations per use case
        local bash_config = require("dap-conf.bash")
        local lua_config = require("dap-conf.lua")

        require("dap-python").setup("uv")
        require('dap-python').test_runner = 'pytest'

        dap.adapters.bashdb = bash_config.adapter
        dap.configurations.sh = bash_config.configuration

        dap.adapters["local-lua"] = lua_config.adapter
        dap.configurations.lua = lua_config.configuration

        for name, sign in pairs(
            {
                Stopped             = { "󰁕 ", "DiagnosticWarn", "DapStoppedLine" },
                Breakpoint          = " ",
                BreakpointCondition = " ",
                BreakpointRejected  = { " ", "DiagnosticError" },
                LogPoint            = ".>",
            }
        ) do
            sign = type(sign) == "table" and sign or { sign }
            vim.fn.sign_define(
                "Dap" .. name,
                { text = sign[1], texthl = sign[2] or "DiagnosticInfo", linehl = sign[3], numhl = sign[3] }
            )
        end
    end
}
