return {
    "mfussenegger/nvim-dap",
    config = function()
        local dap = require("dap")
        -- set the keymaps
        vim.keymap.set('n', '<F5>', function() require('dap').continue() end, { desc = "dap: continue" })
        vim.keymap.set('n', '<F10>', function() require('dap').step_over() end, { desc = "dap: step over" })
        vim.keymap.set('n', '<F11>', function() require('dap').step_into() end, { desc = "dap: step into" })
        vim.keymap.set('n', '<F12>', function() require('dap').step_out() end, { desc = "dap: step out" })
        vim.keymap.set('n', '<F9>', function() require('dap').toggle_breakpoint() end,
            { desc = "dap: toggle break point" })
        vim.keymap.set('n', '<Leader>B', function() require('dap').set_breakpoint() end, { desc = "dap: set breakpoint" })
        vim.keymap.set('n', '<Leader>lp',
            function() require('dap').set_breakpoint(nil, nil, vim.fn.input('Log point message: ')) end)
        vim.keymap.set('n', '<Leader>dr', function() require('dap').repl.toggle() end, { desc = "dap: open toggle" })
        vim.keymap.set('n', '<Leader>dl', function() require('dap').run_last() end, { desc = "dap: run last" })
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
        -- setup the dap configurations per use case

        local python_config = require("dap-conf.python")
        local bash_config = require("dap-conf.bash")
        local lua_config = require("dap-conf.lua")

        dap.adapters.python = python_config.adapter
        dap.configurations.python = python_config.configuration

        dap.adapters.bashdb = bash_config.adapter
        dap.configurations.sh = bash_config.configuration

        dap.adapters["local-lua"] = lua_config.adapter
        dap.configurations.lua = lua_config.configuration
    end
}
