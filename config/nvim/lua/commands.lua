-- run formatting on save

local autocmd_routing_table = {
    markdown = function()
        local name = vim.fn.expand('%:p')
        vim.cmd(":w")
        vim.cmd(":silent ! mdformat " .. name)
        vim.cmd("e!")
    end
}


vim.api.nvim_create_autocmd("BufWritePre", {
    callback = function()
        local filetype = vim.bo.filetype
        local command = autocmd_routing_table[filetype]
        if command == nil then
            vim.lsp.buf.format { async = false }
        else
            command()
        end
    end
})
