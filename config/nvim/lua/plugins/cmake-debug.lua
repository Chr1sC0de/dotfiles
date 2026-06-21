return {
	"gergol/cmake-debugger.nvim",
	dependencies = {
		"mfussenegger/nvim-dap",
	},
	-- setup using default opts
	opts = { cmake_build_dir = "./out/Debug" },
}
