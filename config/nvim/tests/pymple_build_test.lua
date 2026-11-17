-- Run: nvim --headless -u NONE -i NONE -n -l config/nvim/tests/pymple_build_test.lua
local spec = dofile("config/nvim/lua/plugins/pymple.lua")
local executable, system = vim.fn.executable, vim.system
local missing, broken = nil, nil
local calls = {}
vim.fn.executable = function(binary)
	return binary == missing and 0 or 1
end
vim.system = function(argv)
	assert(argv[1] ~= "sudo" and argv[1] ~= "apt-get" and argv[1] ~= "cargo", "No installers in build hook")
	assert(argv[2] == "--version")
	table.insert(calls, argv[1])
	return {
		wait = function(_, timeout)
			assert(timeout == 10000)
			return { code = argv[1] == broken and 1 or 0, stderr = "fixture" }
		end,
	}
end
spec.build()
assert(#calls == 3)
for _, binary in ipairs(calls) do
	missing = binary
	local ok, err = pcall(spec.build)
	assert(not ok and err:find("Pymple requires " .. binary, 1, true))
end
missing, broken = nil, "gg"
local ok, err = pcall(spec.build)
assert(not ok and err:find("Pymple dependency failed: gg", 1, true))
vim.fn.executable, vim.system = executable, system
print("pymple_build_test.lua: ok (dependencies usable, missing, broken; no system installation)")
