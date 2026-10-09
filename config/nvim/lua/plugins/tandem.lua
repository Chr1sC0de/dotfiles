local install_root = vim.fn.stdpath("data") .. "/tandem"

local function install_tandem()
	local result = vim.system({
		"cargo",
		"install",
		"--locked",
		"--force",
		"--git",
		"https://github.com/Chr1sC0de/tandem",
		"--rev",
		"6fafe49c779cc2ab219ffa55096e4624cb84c9d1",
		"--root",
		install_root,
		"tandem-cli",
	}, { text = true }):wait()
	if result.code ~= 0 then
		error("Tandem CLI build failed: " .. (result.stderr or result.stdout or "unknown error"))
	end
end

return {
	"Chr1sC0de/tandem.nvim",
	lazy = false,
	enabled = not vim.g.vscode,
	build = function()
		if vim.fn.executable("codex") == 1 then
			if vim.fn.executable("cargo") ~= 1 then
				error("Tandem requires Cargo. Install Rust, then run :Lazy build tandem.nvim")
			end
			install_tandem()
		end
	end,
	opts = { command = install_root .. "/bin/tandem" },
}
