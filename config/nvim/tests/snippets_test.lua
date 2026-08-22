local config_root = vim.fn.getcwd() .. "/config/nvim"
if vim.fn.isdirectory(config_root) == 0 then
	config_root = vim.fn.getcwd()
end

vim.opt.runtimepath:prepend(vim.fn.stdpath("data") .. "/lazy/blink.cmp")

local snippets_dir = config_root .. "/snippets"
local function decode_json(path)
	return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end

local package = decode_json(snippets_dir .. "/package.json")
local contribution = package.contributes.snippets[1]
assert(contribution.language == "jsonc", "personal snippets should target jsonc buffers")
assert(contribution.path == "./jsonc.json", "personal snippet manifest should reference jsonc.json")

local definitions = decode_json(snippets_dir .. "/jsonc.json")
local launch = definitions["Create a VS Code launch.json"]
local marimo = definitions["Debug marimo in edit mode"]
assert(launch.prefix == "launch-json", "launch.json snippet prefix should remain stable")
assert(marimo.prefix == "marimo-debug-edit", "marimo snippet prefix should remain stable")

local registry = require("blink.cmp.sources.snippets.default.registry").new({
	friendly_snippets = false,
	search_paths = { snippets_dir },
	global_snippets = {},
	extended_filetypes = {},
})

local by_prefix = {}
for _, snippet in ipairs(registry:get_snippets_for_ft("jsonc")) do
	by_prefix[snippet.prefix] = snippet
end

assert(by_prefix["launch-json"], "Blink should discover the launch.json snippet")
assert(by_prefix["marimo-debug-edit"], "Blink should discover the marimo debug snippet")
assert(#registry:get_snippets_for_ft("lua") == 0, "JSONC snippets should not leak into other filetypes")

local launch_body = table.concat(by_prefix["launch-json"].body, "\n")
local marimo_body = table.concat(by_prefix["marimo-debug-edit"].body, "\n")
assert(launch_body:find("\\$schema", 1, true), "the schema key must be escaped for snippet expansion")
assert(marimo_body:find("\\${file}", 1, true), "the DAP file variable must remain literal")
assert(marimo_body:find("\\${workspaceFolder}", 1, true), "the DAP workspace variable must remain literal")

local function expand_snippet(body)
	vim.bo.swapfile = false
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
	vim.cmd("startinsert")
	vim.snippet.expand(body)
	local expanded = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	if vim.snippet.active() then
		vim.snippet.stop()
	end
	return expanded
end

local expanded_launch = expand_snippet(launch_body)
assert(expanded_launch:find('"$schema"', 1, true), "launch.json expansion should contain a literal $schema key")

local expanded_marimo = expand_snippet(marimo_body)
assert(expanded_marimo:find('"${file}"', 1, true), "marimo expansion should contain a literal ${file}")
assert(
	expanded_marimo:find('"${workspaceFolder}"', 1, true),
	"marimo expansion should contain a literal ${workspaceFolder}"
)

local blink_spec = dofile(config_root .. "/lua/plugins/nvim-blink-cmp.lua")
local shown_with
blink_spec.opts.keymap["<A-s>"][1]({
	show = function(opts)
		shown_with = opts.providers
		return true
	end,
})
assert(vim.deep_equal(shown_with, { "snippets" }), "Alt-S should show only the snippets provider")
