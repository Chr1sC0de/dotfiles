vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.keymap.set("n", "<c-s>", ":w<cr>", { desc = "Save file" })
vim.keymap.set("n", "<c-z>", "u", { desc = "Undo" })

-- setup a toggle for the virtual edit command
TOGGLE_VIRTUALEDIT = false
vim.opt.virtualedit = nil
vim.keymap.set("n", "<leader>ve", function()
    if TOGGLE_VIRTUALEDIT then
        print("setting virtualedit=nil")
        vim.opt.virtualedit = nil
        TOGGLE_VIRTUALEDIT = true
    else
        print("setting virtualedit=all")
        vim.opt.virtualedit = "all"
        TOGGLE_VIRTUALEDIT = true
    end
end, { desc = "Toggle virtualedit mode from nil <-> all" })
