-- Run in a separate Neovim process after Lazy's builds, so cached parser
-- libraries cannot hide missing or unloadable artifacts.
local provision = require("core.treesitter-install")
local languages = provision.languages()
provision.finish(languages)
local samples = {
	lua = "local x = 1\n",
	latex = "\\section{Hello}\n",
	regex = "[a-z]+",
	rust = "fn main() {}\n",
	go = "package main\nfunc main() {}\n",
	c = "int main(void) { return 0; }\n",
	r = "x <- 1\n",
	bash = "echo hello\n",
	python = "x = 1\n",
	markdown = "# Hello\n",
	markdown_inline = "hello *world*",
	json = '{"x":1}',
	yaml = "x: 1\n",
	tmux = "set -g mouse on\n",
	just = "hello:\n    echo hello\n",
	dap_repl = "hello\n",
	dockerfile = "FROM debian:13-slim\n",
	toml = "x = 1\n",
	query = "(identifier) @variable",
	sql = "SELECT 1;\n",
	duckdbsql = "SELECT 1;\n",
	jinja = "hello {{ name }}",
	jinja_inline = '# set a = "hello"\n',
	caddy = ':80 {\n respond "hello"\n}\n',
	mermaid = "flowchart TD\n A --> B\n",
}
local failures = {}
for _, language in ipairs(languages) do
	local ok, err = xpcall(function()
		assert(samples[language], "No parser fixture for " .. language)
		assert(vim.treesitter.language.add(language), "Cannot load parser " .. language)
		-- Use buffers: config injection directives inspect the buffer filename.
		local buffer = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buffer, "/tmp/dotfiles-parser-audit-" .. language)
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(samples[language], "\n", { plain = true }))
		local parser = vim.treesitter.get_parser(buffer, language)
		local trees = parser:parse(true)
		assert(trees and trees[1], "Parser produced no tree: " .. language)
		assert(not trees[1]:root():has_error(), "Fixture has parse errors: " .. language)
		-- Compile all query files, including installed plugin/config overrides.
		for _, kind in ipairs({ "highlights", "injections", "locals", "folds", "indents" }) do
			vim.treesitter.query.get(language, kind)
		end
		vim.api.nvim_buf_delete(buffer, { force = true })
		print("Verified Tree-sitter parser and queries: " .. language)
	end, debug.traceback)
	if not ok then
		table.insert(failures, language .. ": " .. tostring(err))
	end
end
assert(#failures == 0, table.concat(failures, "\n"))
