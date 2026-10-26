local M = {}

function M.cache_path()
	return vim.fn.stdpath("state") .. "/opencode/model-catalog.json"
end

local function cached()
	local ok, entries = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(M.cache_path()), "\n"))
	end)
	if not ok or type(entries) ~= "table" then return {} end
	local result = {}
	for _, entry in ipairs(entries) do
		if type(entry) == "table" and type(entry.model) == "string" and type(entry.label) == "string" then
			table.insert(result, { model = entry.model, label = entry.label })
		end
	end
	return result
end

local function save(entries)
	local path = M.cache_path()
	local temporary = path .. ".tmp." .. vim.fn.getpid()
	pcall(function()
		vim.fn.mkdir(vim.fs.dirname(path), "p", 448)
		if vim.fn.writefile({ vim.json.encode(entries) }, temporary) == 0 then
			vim.uv.fs_rename(temporary, path)
		end
	end)
	pcall(vim.fn.delete, temporary)
end

-- Persist only public labels/IDs, never the API model settings (which may carry
-- provider credentials). Discovery uses the CLI's service authentication.
function M.fetch(callback)
	local cancelled = false
	local process = vim.system({ "opencode", "api", "get", "/api/model" }, { text = true, timeout = 10000 },
		vim.schedule_wrap(function(result)
			if cancelled then return end
			local ok, response = pcall(vim.json.decode, result.stdout or "")
			local models = ok and type(response) == "table" and response.data
			if result.code ~= 0 or type(models) ~= "table" then
				local fallback = cached()
				callback(fallback, #fallback > 0 and "cached" or "unavailable", "OpenCode model discovery failed")
				return
			end
			local choices = {}
			for _, model in ipairs(models) do
				if model.enabled ~= false and model.status ~= "deprecated" and type(model.providerID) == "string" and type(model.id) == "string" then
					local id = model.providerID .. "/" .. model.id
					table.insert(choices, { model = id, label = (model.name or model.id) .. " (" .. id .. ")" })
					for _, variant in ipairs(model.variants or {}) do
						table.insert(choices, { model = id .. "#" .. variant.id, label = id .. "#" .. variant.id })
					end
				end
			end
			save(choices)
			callback(choices, "live")
		end))
	return function() cancelled = true; process:kill(15) end
end

return M
