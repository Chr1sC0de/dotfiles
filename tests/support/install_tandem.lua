local spec = dofile("config/nvim/lua/plugins/tandem.lua")
assert(spec.enabled and spec.lazy == false)
spec.build()
assert(vim.fn.executable(spec.opts.command) == 1)
