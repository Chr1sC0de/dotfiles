return {
    adapter = {
        type = "executable",
        command = "node",
        args = {
            os.getenv("HOME") .. "/.local-lua-debugger-vscode/extension/debugAdapter.js"
        },
        enrich_config = function(config, on_config)
            if not config["extensionPath"] then
                local c = vim.deepcopy(config)
                -- 💀 If this is missing or wrong you'll see
                -- "module 'lldebugger' not found" errors in the dap-repl when trying to launch a debug session
                c.extensionPath = os.getenv("HOME") .. "/.local-lua-debugger-vscode/"
                on_config(c)
            else
                on_config(config)
            end
        end,
    },
    configuration = {
        {
            name = 'Launch File: Lua',
            type = 'local-lua',
            request = 'launch',
            cwd = '${workspaceFolder}',
            program = {
                lua = 'lua',
                file = '${file}',
            },
            verbose = true,
            args = {},
        },
    }
}
