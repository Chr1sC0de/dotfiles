return {
    "rcarriga/nvim-dap-ui",
    commit = "bc81f8d3440aede116f821114547a476b082b319",
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    config = function()
        local dap = require("dap")
        local dapui = require("dapui")

        dap.listeners.before.attach.dapui_config = function()
            dapui.open()
        end
        dap.listeners.before.launch.dapui_config = function()
            dapui.open()
        end
        vim.keymap.set({ "n", "v" }, "<leader>de", function() dapui.eval(nil, { enter = true }) end,
            { desc = "dapui: evaluate" })
        vim.keymap.set({ "n", "v" }, "<leader>dt", function() dapui.toggle() end, { desc = "dapui: toggle" })
    end
}
