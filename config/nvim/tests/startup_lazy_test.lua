vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
local schemas = 0
package.preload.schemastore = function()
	schemas = schemas + 1
	return {
		json = {
			schemas = function()
				return { { name = "json fixture" } }
			end,
		},
		yaml = {
			schemas = function()
				return { yaml = "fixture" }
			end,
		},
	}
end
package.loaded["blink.cmp"] = {
	get_lsp_capabilities = function(opts)
		return opts
	end,
}
local configs = {}
vim.lsp.config = function(name, opts)
	configs[name] = opts
end
vim.lsp.enable = function() end
require("core.lsp")
assert(schemas == 0, "Schema catalog must not load during startup")
local json = vim.deepcopy(configs.jsonls)
json.before_init({}, json)
assert(json.settings.json.schemas[1].name == "json fixture")
local yaml = vim.deepcopy(configs.yamlls)
yaml.before_init({}, yaml)
assert(yaml.settings.yaml.schemas.yaml == "fixture")
assert(schemas == 1, "Both servers share the cached catalog")
local spec = dofile("config/nvim/lua/plugins/diffbandit.lua")
assert(#spec.cmd >= 21 and #spec.keys == 2, "Keep command and keymap entry points")
assert(not package.loaded.diffbandit)
print("startup_lazy_test.lua: ok (deferred schema catalog, JSON/YAML settings, DiffBandit entry points)")
