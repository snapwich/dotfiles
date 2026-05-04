local workspaces = {
	{
		name = "notes",
		path = "~/vaults/notes",
	},
	{
		name = "work",
		path = "~/vaults/work",
		overrides = {
			daily_notes = {
				workdays_only = true,
			},
		},
	},
}

local function vault_sync()
	local file = vim.fn.expand("%:p")
	local vault_root
	for _, ws in ipairs(workspaces) do
		local ws_path = vim.fn.fnamemodify(vim.fn.expand(ws.path), ":p"):gsub("/$", "")
		if file == ws_path or vim.startswith(file, ws_path .. "/") then
			vault_root = ws_path
			break
		end
	end
	if not vault_root then
		vim.notify("Not in a vault buffer", vim.log.levels.WARN)
		return
	end
	local datetime = os.date("%Y-%m-%d %H:%M:%S")
	local message = string.format("vault sync %s", datetime)
	local script = table.concat({
		string.format("git -C %q add -A", vault_root),
		string.format("git -C %q commit -m %q", vault_root, message),
		string.format("git -C %q push", vault_root),
	}, " && ")
	vim.system({ "sh", "-c", script }, { text = true }, function(out)
		vim.schedule(function()
			if out.code == 0 then
				vim.notify("Vault synced: " .. datetime, vim.log.levels.INFO)
			else
				vim.notify("Vault sync failed:\n" .. (out.stderr or "") .. (out.stdout or ""), vim.log.levels.ERROR)
			end
		end)
	end)
end

return {
	"obsidian-nvim/obsidian.nvim",
	version = "*",
	ft = "markdown",
	opts = {
		legacy_commands = false,
		workspaces = workspaces,
		daily_notes = {
			folder = "daily",
			workdays_only = false,
		},
	},
	cmd = { "Obsidian" },
	keys = {
		{ "<leader>ot", "<cmd>Obsidian today<cr>", desc = "Daily Today" },
		{ "<leader>oy", "<cmd>Obsidian yesterday<cr>", desc = "Daily Yesterday" },
		{ "<leader>os", "<cmd>Obsidian search<cr>", desc = "Search Note Contents" },
		{ "<leader>of", "<cmd>Obsidian quick_switch<cr>", desc = "Search Note Names" },
		{ "<leader>oa", "<cmd>Obsidian tags<cr>", desc = "Search Tags" },
		{ "<leader>ob", "<cmd>Obsidian backlinks<cr>", desc = "Show Backlinks" },
		{ "<leader>ol", "<cmd>Obsidian links<cr>", desc = "Show Links in document" },
		{ "<leader>oc", "<cmd>Obsidian toc<cr>", desc = "Table of Contents" },
		{ "<leader>ov", "<cmd>Obsidian follow_link vsplit_force<cr>", desc = "Follow link with Vertical Split" },
		{ "<leader>oh", "<cmd>Obsidian follow_link hsplit_force<cr>", desc = "Follow link with Horizontal Split" },
		{ "<leader>op", vault_sync, desc = "Vault push sync commit (add, commit, push)" },
	},
}
