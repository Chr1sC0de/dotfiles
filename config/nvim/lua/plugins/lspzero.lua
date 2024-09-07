return {
    "VonHeikemen/lsp-zero.nvim",
    branch = "v4.x",
    dependencies = {
        "williamboman/mason.nvim",
        "williamboman/mason-lspconfig.nvim",
        "hrsh7th/cmp-nvim-lsp",
        "hrsh7th/nvim-cmp",
    },
    config = function()
        local lsp_zero = require("lsp-zero")
        local lsp_attach = function(_, bufnr)
            local opts = { buffer = bufnr }
            vim.keymap.set("n", "K", "<cmd>lua vim.lsp.buf.hover()<cr>", opts)
            vim.keymap.set("n", "gd", "<cmd>lua vim.lsp.buf.definition()<cr>", opts)
            vim.keymap.set("n", "gD", "<cmd>lua vim.lsp.buf.declaration()<cr>", opts)
            vim.keymap.set("n", "gi", "<cmd>lua vim.lsp.buf.implementation()<cr>", opts)
            vim.keymap.set("n", "go", "<cmd>lua vim.lsp.buf.type_definition()<cr>", opts)
            vim.keymap.set("n", "gr", "<cmd>lua vim.lsp.buf.references()<cr>", opts)
            vim.keymap.set("n", "gs", "<cmd>lua vim.lsp.buf.signature_help()<cr>", opts)
            vim.keymap.set("n", "<F2>", "<cmd>lua vim.lsp.buf.rename()<cr>", opts)
            vim.keymap.set("n", "<c-a-l>", "<cmd>lua vim.lsp.buf.format({async = true})<cr>", opts)
            vim.keymap.set("n", "<F4>", "<cmd>lua vim.lsp.buf.code_action()<cr>", opts)
        end
        local capabilities = require("cmp_nvim_lsp").default_capabilities()

        lsp_zero.extend_lspconfig({
            sign_text = true,
            lsp_attach = lsp_attach,
            capabilities = capabilities
        })

        require("mason").setup({
            ui = {
                border = "rounded"
            }
        })

        -- list out the configurations for each lsp
        local lspconfigs = {
            ruff = { filetypes = { "python" } },
            pyright = {
                filetypes = { "python" },
                settings = {
                    pyright = {
                        -- Using Ruff's import organizer
                        disableOrganizeImports = true,
                    },
                    python = {
                        analysis = {
                            -- Ignore all files for analysis to exclusively use Ruff for linting
                            ignore = { '*' },
                        },
                    },
                }
            },
            tailwindcss = {
                filetypes = {
                    "aspnetcorerazor", "astro", "astro-markdown", "blade",
                    "clojure", "django-html", "htmldjango", "edge", "eelixir",
                    "elixir", "ejs", "erb", "eruby", "gohtml", "gohtmltmpl", "haml",
                    "handlebars", "hbs", "html", "htmlangular", "html-eex", "heex",
                    "jade", "leaf", "liquid", "mdx", "mustache", "njk",
                    "nunjucks", "php", "razor", "slim", "twig", "css", "less",
                    "postcss", "sass", "scss", "stylus", "sugarss", "javascript", "javascriptreact",
                    "reason", "rescript", "typescript", "typescriptreact", "vue", "svelte", "templ"
                }
            },
            markdown_oxide = {
                capabilities = vim.tbl_deep_extend(
                    'force',
                    capabilities,
                    {
                        workspace = {
                            didChangeWatchedFiles = {
                                dynamicRegistration = true,
                            },
                        },
                    }
                ),
            },
        }

        require("mason-lspconfig").setup({
            handlers = {
                function(server_name)
                    local setup

                    if server_name == "tsserver" then
                        server_name = "ts_ls"
                    end
                    if lspconfigs[server_name] == nil then
                        setup = {}
                    else
                        setup = lspconfigs[server_name]
                    end
                    require("lspconfig")[server_name].setup(setup)
                end
            }
        })

        -- Autocompletion config
        local cmp = require("cmp")
        local cmp_action = lsp_zero.cmp_action()

        cmp.setup({
            sources = {
                { name = "nvim_lsp" },
            },
            mapping = cmp.mapping.preset.insert({
                -- `Enter` key to confirm completion
                ["<CR>"] = cmp.mapping.confirm({ select = false }),

                -- Ctrl+Space to trigger completion menu
                ["<C-Space>"] = cmp.mapping.complete(),

                -- Navigate between snippet placeholder
                ["<C-f>"] = cmp_action.vim_snippet_jump_forward(),
                ["<C-b>"] = cmp_action.vim_snippet_jump_backward(),

                -- Scroll up and down in the completion documentation
                ["<C-u>"] = cmp.mapping.scroll_docs(-4),
                ["<C-d>"] = cmp.mapping.scroll_docs(4),
            }),
            snippet = {
                expand = function(args)
                    vim.snippet.expand(args.body)
                end,
            },
        })
    end
}
