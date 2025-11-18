return {
    'LukasPietzschmann/telescope-tabs',
    config = function()
        require('telescope').load_extension 'telescope-tabs'
        require('telescope-tabs').setup {}

        vim.keymap.set("n", "<leader>ft",
            function()
                require('telescope-tabs').list_tabs()
            end
            , { desc = "Telescope: tabs" })
    end,

    dependencies = { 'nvim-telescope/telescope.nvim' },
}
