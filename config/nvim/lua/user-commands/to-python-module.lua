vim.api.nvim_create_user_command("ToPythonModule", function()
	local line = vim.api.nvim_get_current_line()

	-- Trim whitespace.
	line = vim.trim(line)

	-- Remove surrounding quotes.
	line = line:gsub("^['\"]", ""):gsub("['\"]$", "")

	-- Normalise path separators.
	line = line:gsub("\\", "/")

	-- Remove ./ prefix.
	line = line:gsub("^%./", "")

	-- Remove common Python source roots.
	line = line:gsub("^src/", "")
	line = line:gsub("^lib/", "")

	-- Remove Python extension.
	line = line:gsub("%.py$", "")

	-- __init__.py represents the package itself.
	line = line:gsub("/__init__$", "")

	-- Convert path to Python module notation.
	line = line:gsub("/", ".")

	-- Replace the current line.
	vim.api.nvim_set_current_line(line)
end, {})
