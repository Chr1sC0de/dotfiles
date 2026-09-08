local install_root = vim.fn.stdpath("data") .. "/tandem"

return {
	"Chr1sC0de/tandem.nvim",
	-- Updated together after the cross-repository integration suite passes.
	commit = "99f740e17a65e7d1a6ed6b528c894613d8f756e3",
	lazy = false,
	enabled = not vim.g.vscode,
	build = function()
		if vim.fn.executable("cargo") ~= 1 then
			error("Tandem requires Cargo. Install Rust, then run :Lazy build tandem.nvim")
		end
		local result = vim.system({
			"cargo", "install", "--locked", "--force",
			"--git", "https://github.com/Chr1sC0de/tandem",
			"--rev", "1b30de8709a320879efa8e6c498cab6f14508b10",
			"--root", install_root, "tandem-cli",
		}, { text = true }):wait()
		if result.code ~= 0 then
			error("Tandem CLI build failed: " .. (result.stderr or result.stdout or "unknown error"))
		end
	end,
	opts = { command = install_root .. "/bin/tandem" },
}
