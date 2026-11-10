local M = {}

function M.cache_path(id)
	return vim.fn.stdpath("state") .. "/opencode/" .. (id == "pi" and "pi-" or "") .. "model-catalog.json"
end

local function cached(id)
	local ok, entries = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(M.cache_path(id)), "\n"))
	end)
	if not ok or type(entries) ~= "table" then
		return {}
	end
	local result = {}
	for _, entry in ipairs(entries) do
		if type(entry) == "table" and type(entry.model) == "string" and type(entry.label) == "string" then
			table.insert(result, { model = entry.model, label = entry.label })
		end
	end
	return result
end

local function save(entries, id)
	local path = M.cache_path(id)
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
function M.fetch(callback, id)
	id = id or require("agents.selection").get()
	local cancelled = false
	local command = id == "pi" and { "pi", "--offline", "--list-models" } or { "opencode", "api", "get", "/api/model" }
	local process = vim.system(
		command,
		{ text = true, timeout = 10000 },
		vim.schedule_wrap(function(result)
			if cancelled then
				return
			end
			if id == "pi" and result.code == 0 then
				local choices = {}
				for line in (result.stdout or ""):gmatch("[^\r\n]+") do
					local provider, model = line:match("^(%S+)%s+(%S+)%s+")
					if provider and provider ~= "provider" then
						local model_id = provider .. "/" .. model
						table.insert(choices, { model = model_id, label = model_id })
					end
				end
				if #choices > 0 then
					save(choices, id)
					callback(choices, "live")
					return
				end
			end
			local ok, response = pcall(vim.json.decode, result.stdout or "")
			local models = id ~= "pi" and ok and type(response) == "table" and response.data
			if result.code ~= 0 or type(models) ~= "table" then
				local fallback = cached(id)
				callback(fallback, #fallback > 0 and "cached" or "unavailable", id .. " model discovery failed")
				return
			end
			local choices = {}
			for _, model in ipairs(models) do
				if
					model.enabled ~= false
					and model.status ~= "deprecated"
					and type(model.providerID) == "string"
					and type(model.id) == "string"
				then
					local id = model.providerID .. "/" .. model.id
					table.insert(choices, { model = id, label = (model.name or model.id) .. " (" .. id .. ")" })
					for _, variant in ipairs(model.variants or {}) do
						table.insert(choices, { model = id .. "#" .. variant.id, label = id .. "#" .. variant.id })
					end
				end
			end
			save(choices, id)
			callback(choices, "live")
		end)
	)
	return function()
		cancelled = true
		process:kill(15)
	end
end

return M
