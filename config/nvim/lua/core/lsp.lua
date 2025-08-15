vim.lsp.enable({
    -- "ty",
    -- "pyrefly",
    "basedpyright",
    "bashls",
    "docker_compose_language_service",
    "dockerls",
    "emmet_language_server",
    "eslint",
    "html",
    "jinja_lsp",
    "json_lsp",
    "lua_ls",
    "markdown_oxide",
    "ruff",
    "tailwindcss",
    "ts_ls",
    "htmx"
})

vim.lsp.config('lua_ls', {
    settings = {
        ['lua_ls'] = {
            root_markers = {
                ".git",
                ".luacheckrc",
                ".luarc.json",
                ".luarc.jsonc",
                ".stylua.toml",
                "selene.toml",
                "selene.yml",
                "stylua.toml",
            },
        },
    },
})
vim.lsp.config(
    'pyrefly', {
        filetypes = { "python" },
        settings = {
            python = {
                analysis = {
                    typeCheckingMode = "basic", -- or "strict"
                    autoImportCompletions = true
                }
            }
        }
    }
)

vim.lsp.config(
    'basedpyright', {
        filetypes = { "python" },
        settings = {
            basedpyright = {
                disableOrganizeImports = true,
                analysis = {
                    stubPath = os.getenv("HOME") .. "/Stubs"
                }
            },
            python = {
                analysis = {
                    ignore = { '*' },
                },
            },
        }
    }
)

vim.lsp.config(
    'jinja_lsp', {
        filetypes = { 'jinja', 'htmldjango' },
    }
)

vim.lsp.config(
    'html', {
        filetypes = { 'jinja', 'html', 'htmldjango' },
    }
)

vim.lsp.config(
    'tailwindcss', {
        filetypes = { 'jinja', 'html', 'htmldjango' },
    }
)

vim.diagnostic.config({
    -- virtual_lines = true,
    -- virtual_text = true,
    underline = true,
    update_in_insert = false,
    severity_sort = true,
    float = {
        border = "rounded",
        source = true,
    },
    signs = {
        text = {
            [vim.diagnostic.severity.ERROR] = "󰅚 ",
            [vim.diagnostic.severity.WARN] = "󰀪 ",
            [vim.diagnostic.severity.INFO] = "󰋽 ",
            [vim.diagnostic.severity.HINT] = "󰌶 ",
        },
        numhl = {
            [vim.diagnostic.severity.ERROR] = "ErrorMsg",
            [vim.diagnostic.severity.WARN] = "WarningMsg",
        },
    },
})
