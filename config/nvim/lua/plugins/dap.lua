local get_pythonpath = function()
    local cwd = vim.fn.getcwd()
    if vim.fn.executable(cwd .. '/venv/bin/python') == 1 then
        return cwd .. '/venv/bin/python'
    elseif vim.fn.executable(cwd .. '/.venv/bin/python') == 1 then
        return cwd .. '/.venv/bin/python'
    else
        return 'python'
    end
end

local get_fastapi_library_name = function()
    local fastapi_entrypoint = os.getenv("NVIM_DAP_FASTAPI_ENTRYPOINT")
    local default_fastapi_entrypoint = "api_lib.main:app"
    if fastapi_entrypoint == nil then
        -- print("INFO: fastapi entrypoint not set, using default_fastapi_entrypoint= " .. default_fastapi_entrypoint)
        return default_fastapi_entrypoint
    end
    -- print("INFO: fastapi entrypoint set to = " .. fastapi_entrypoint)
    return fastapi_entrypoint
end

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
        vim.keymap.set('n', '<Leader>dr', function() require('dap').repl.open() end, { desc = "dap: open repl" })
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

        -- setup adapters
        dap.adapters.python = function(cb, config)
            if config.request == 'attach' then
                local port = (config.connect or config).port
                local host = (config.connect or config).host or '127.0.0.1'
                cb({
                    type = 'server',
                    port = assert(port, '`connect.port` is required for a python `attach` configuration'),
                    host = host,
                    options = {
                        source_filetype = 'python',
                    },
                })
            else
                cb({
                    type = 'executable',
                    -- use the debugpy installed by mason
                    command = vim.fn.stdpath("data") .. '/mason/packages/debugpy/venv/bin/python',
                    args = { '-m', 'debugpy.adapter' },
                    options = {
                        source_filetype = 'python',
                    },
                })
            end
        end

        dap.adapters.bashdb = {
            type = 'executable',
            command = vim.fn.stdpath("data") .. '/mason/packages/bash-debug-adapter/bash-debug-adapter',
            name = 'bashdb',
        }

        -- setup configuration
        dap.configurations.python = {
            {
                type = "python",
                request = "launch",
                name = "FastAPI",
                module = "uvicorn",
                args = {
                    get_fastapi_library_name(),
                    "--host",
                    "0.0.0.0",
                    "--port",
                    "8000",
                    "--ssl-keyfile",
                    "key.pem",
                    "--ssl-certfile",
                    "cert.pem",
                    "--reload"
                },
                subProcess = false,
                pythonPath = get_pythonpath()
            },
            {
                type = 'python',
                request = 'launch',
                name = "Launch file",
                -- Options below are for debugpy,
                -- see https://github.com/microsoft/debugpy/wiki/Debug-configuration-settings for supported options
                program = "${file}",
                pythonPath = get_pythonpath()
            },
        }

        dap.configurations.sh = {
            {
                type = 'bashdb',
                request = 'launch',
                name = "Launch file",
                showDebugOutput = true,
                pathBashdb = vim.fn.stdpath("data") .. '/mason/packages/bash-debug-adapter/extension/bashdb_dir/bashdb',
                pathBashdbLib = vim.fn.stdpath("data") .. '/mason/packages/bash-debug-adapter/extension/bashdb_dir',
                trace = true,
                file = "${file}",
                program = "${file}",
                cwd = '${workspaceFolder}',
                pathCat = "bat",
                pathBash = "/bin/bash",
                pathMkfifo = "mkfifo",
                pathPkill = "pkill",
                args = {},
                env = {},
                terminalKind = "integrated",
            }
        }
    end
}
