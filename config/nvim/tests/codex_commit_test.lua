vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")

local commit = require("codex.commit")

local function expect_valid(message)
	local valid, reason = commit.validate_fallback(message)
	assert(valid, message .. " should be valid: " .. tostring(reason))
end

local function expect_invalid(message)
	local valid = commit.validate_fallback(message)
	assert(not valid, message .. " should be invalid")
end

expect_valid("feat: add commit workflow")
expect_valid("fix(config/nvim): handle missing cz")
expect_valid("feat!: change the API")
expect_valid("refactor(config.nvim/tools): simplify runner")

expect_invalid("update: unsupported type")
expect_invalid("feat(bad@scope): invalid scope")
expect_invalid("feat: ")
expect_invalid("feat: description\nwith body")
expect_invalid("feat: description ")

print("codex_commit_test.lua: ok")
