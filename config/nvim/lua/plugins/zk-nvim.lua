return {
	"zk-org/zk-nvim",
	name = "zk",
	opts = {
		picker = "snacks_picker",
		lsp = {
			config = {
				name = "zk",
				cmd = { "zk", "lsp" },
				filetypes = { "markdown" },
			},
			auto_attach = {
				enabled = true,
			},
		},
		tags = {
			multi_select_strategy = "AND",
		},
		highlight = {
			additional_vim_regex_highlighting = { "markdown" },
		},
	},
}
