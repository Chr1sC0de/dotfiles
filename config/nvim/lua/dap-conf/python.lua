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
    adapter = function(cb, config)
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
    end,
    configuration = {
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
            pythonPath = get_pythonpath(),
            repl_lang = "python"
        },
        {
            type = 'python',
            request = 'launch',
            name = "Launch file",
            -- Options below are for debugpy,
            -- see https://github.com/microsoft/debugpy/wiki/Debug-configuration-settings for supported options
            program = "${file}",
            pythonPath = get_pythonpath(),
            repl_lang = "python"
        },
    }
}
