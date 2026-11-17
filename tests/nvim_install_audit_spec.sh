#!/usr/bin/env bash
# Test audit failure detection without network access or the user's Neovim config.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat >"$work/fixture.lua" <<'LUA'
local case = vim.env.AUDIT_CASE
local registry_ready = false
local plugin = { _ = { installed = true, tasks = {} } }
package.loaded["lazy.core.config"] = { plugins = { fixture = plugin } }
package.loaded.lazy = {
    restore = function() end,
    load = function()
        plugin._.loaded = true
        if case == "config-error" then vim.notify("fixture config failed", vim.log.levels.ERROR) end
    end,
}
if case == "build-error" then
    plugin._.tasks = { { has_errors = function() return true end } }
end
package.loaded["mason-tool-installer"] = { setup = function() end }
package.loaded["plugins.mason-tool-installer"] = {
    config = function()
        local tools = case == "duplicate-tool" and { "fixture-alias", "fixture" } or { "fixture-alias" }
        require("mason-tool-installer").setup({ ensure_installed = tools })
    end,
}
package.loaded["mason-lspconfig.mappings"] = {
    get_mason_map = function()
        assert(registry_ready, "Aliases requested before registry refresh")
        return { lspconfig_to_package = { ["fixture-alias"] = "fixture" } } end,
}
package.loaded["mason-nvim-dap.mappings.source"] = { nvim_dap_to_package = {} }
package.loaded["mason-registry"] = {
    refresh = function(callback)
        registry_ready = true
        callback(case ~= "registry-error")
    end,
    has_package = function(name) return name == "fixture" end,
    get_package = function()
        return { is_installed = function() return case ~= "missing-tool" end }
    end,
}
-- Simulate a successful command even when a package failed to install.
vim.api.nvim_create_user_command("MasonToolsInstallSync", function() end, {})
dofile(vim.env.AUDIT_SCRIPT)
if case == "startup-error" then vim.notify("fixture startup failed", vim.log.levels.ERROR) end
if case == "handled-error" then
    -- Same pattern as Dadbod's optional icon cleanup: silent! leaves v:errmsg.
    vim.cmd("silent! call remove({}, 'collapsed')")
    assert(vim.v.errmsg:match("E716:"))
end
if case == "replaced-notify" then
    vim.notify = function() end
    vim.api.nvim_err_writeln("fixture unhandled error without an E-code")
end
if case == "async-error" then
    vim.schedule(function() error("fixture asynchronous failure") end)
end
if case == "reported-error" then
    vim.api.nvim_echo({ { "E999: fixture unhandled error", "ErrorMsg" } }, true, {})
end
dotfiles_install_audit()
LUA
run_case() {
    local case=$1 stage=$2 expected=$3 status=0
    AUDIT_CASE="$case" NVIM_AUDIT_STAGE="$stage" AUDIT_SCRIPT="$root/tests/nvim_install_audit.lua" \
        nvim --headless -u NONE -i NONE "+luafile $work/fixture.lua" >"$work/$case.log" 2>&1 || status=$?
    if [[ $status != "$expected" ]]; then
        printf 'FAIL %s: expected %s, got %s\n' "$case" "$expected" "$status"
        tail -30 "$work/$case.log"
        exit 1
    fi
    printf 'PASS %s\n' "$case"
}
run_case plugins-ok plugins 0
run_case mason-ok mason 0
run_case registry-error mason 1
run_case missing-tool mason 1
run_case duplicate-tool mason 1
run_case handled-error plugins 0
run_case reported-error plugins 1
run_case replaced-notify plugins 1
run_case async-error plugins 1
run_case startup-error plugins 1
run_case config-error plugins 1
run_case build-error plugins 1
