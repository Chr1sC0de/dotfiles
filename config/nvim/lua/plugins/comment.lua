return {
    "LudoPinelli/comment-box.nvim",
    config = function()
        local opts = { noremap = true, silent = true }

        local function add_description(table, description)
            local output = {}
            for index, value in pairs(table) do
                output[index] = value
            end
            output["desc"] = description
        end

        vim.keymap.set({ "n", "v" }, "<Leader>cb", "<Cmd>CBccbox<CR>",
            add_description(opts, "comment-box: titles"))

        vim.keymap.set({ "n", "v" }, "<Leader>ct", "<Cmd>CBllline<CR>", add_description(opts, "comment-box: named parts"))

        vim.keymap.set("n", "<Leader>cl", "<Cmd>CBline<CR>", add_description(opts, "comment-box: simple line"))

        vim.keymap.set({ "n", "v" }, "<Leader>cm", "<Cmd>CBllbox14<CR>",
            add_description(opts, "comment-box: marked comments"))

        vim.keymap.set({ "n", "v" }, "<Leader>cd", "<Cmd>CBd<CR>", add_description(opts, "comment-box: remove box"))

        require('comment-box').setup({
            -- type of comments:
            --   - "line":  comment-box will always use line style comments
            --   - "block": comment-box will always use block style comments
            --   - "auto":  comment-box will use block line style comments if
            --              multiple lines are selected, line style comments
            --              otherwise
            comment_style = "line",
            doc_width = 100, -- width of the document
            box_width = 90,  -- width of the boxes
            borders = {      -- symbols used to draw a box
                top = "─",
                bottom = "─",
                left = "│",
                right = "│",
                top_left = "╭",
                top_right = "╮",
                bottom_left = "╰",
                bottom_right = "╯",
            },
            line_width = 80, -- width of the lines
            lines = {        -- symbols used to draw a line
                line = "─",
                line_start = "─",
                line_end = "─",
                title_left = "─",
                title_right = "─",
            },
            outer_blank_lines_above = false, -- insert a blank line above the box
            outer_blank_lines_below = false, -- insert a blank line below the box
            inner_blank_lines = false,       -- insert a blank line above and below the text
            line_blank_line_above = false,   -- insert a blank line above the line
            line_blank_line_below = false,   -- insert a blank line below the line
        })
    end
}
