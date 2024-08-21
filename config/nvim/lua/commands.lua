-- run formatting on save

local languages = { "lua", "python", "markdown", "bash", "sh" }
local route = {}

for _, language in pairs(languages) do
    route[language] = function()
        vim.lsp.buf.format { async = false }
    end
end

vim.api.nvim_create_autocmd("BufWritePre", {
    callback = function()
        local command = route[vim.bo.filetype]
        if (command ~= nil) then
            command()
        end
    end
})
