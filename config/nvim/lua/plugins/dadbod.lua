return {
    'kristijanhusak/vim-dadbod-ui',
    lazy = false,
    dependencies = {
        { 'tpope/vim-dadbod',                     lazy = false },
        { 'kristijanhusak/vim-dadbod-completion', ft = { 'sql', 'mysql', 'plsql' }, lazy = false },
    },
    cmd = {
        'DBUI',
        'DBUIToggle',
        'DBUIAddConnection',
        'DBUIFindBuffer',
    },
    init = function()
        -- Your DBUI configuration
        vim.g.db_ui_use_nerd_fonts = 1
        vim.g.db_ui_execute_on_save = 0
    end,
    config = function()

    end
}
