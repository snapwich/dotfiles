local workspaces = vim.tbl_filter(function(ws)
	return vim.fn.isdirectory(vim.fn.expand(ws.path)) == 1
end, {
	{
		name = "notes",
		path = "~/vaults/notes",
	},
	{
		name = "_dev-notes",
		path = "/home/dev/repos/obsidian-tasks.nvim/default/tests/fixtures/vault",
	},
	{
		name = "work-notes",
		path = "~/vaults/work-notes",
		overrides = {
			daily_notes = {
				workdays_only = true,
			},
		},
	},
})

local default_workspace = vim.env.OBSIDIAN_WORKSPACE
if default_workspace then
	for i, ws in ipairs(workspaces) do
		if ws.name == default_workspace then
			table.remove(workspaces, i)
			table.insert(workspaces, 1, ws)
			break
		end
	end
end

local function apply_default_workspace()
	if not default_workspace then
		return
	end
	for _, ws in ipairs(Obsidian.workspaces or {}) do
		if ws.name == default_workspace then
			require("obsidian.workspace").set(ws)
			return
		end
	end
end

local function run_for_all_vaults(label, build_script)
	local datetime = os.date("%Y-%m-%d %H:%M:%S")
	local targets = vim.tbl_filter(function(ws)
		return not vim.startswith(ws.name, "_")
	end, workspaces)
	local total = #targets
	local results = {}
	for _, ws in ipairs(targets) do
		local vault_root = vim.fn.fnamemodify(vim.fn.expand(ws.path), ":p"):gsub("/$", "")
		local script = build_script(vault_root, datetime)
		vim.system({ "sh", "-c", script }, { text = true }, function(out)
			vim.schedule(function()
				results[#results + 1] = {
					name = ws.name,
					ok = out.code == 0,
					stderr = out.stderr or "",
					stdout = out.stdout or "",
				}
				if #results < total then
					return
				end
				local failures = vim.tbl_filter(function(r)
					return not r.ok
				end, results)
				if #failures == 0 then
					vim.notify(string.format("%s complete (%d vaults)", label, total), vim.log.levels.INFO)
				else
					local lines = { label .. " failed:" }
					for _, r in ipairs(failures) do
						lines[#lines + 1] = string.format("[%s] %s%s", r.name, r.stderr, r.stdout)
					end
					vim.notify(table.concat(lines, "\n"), vim.log.levels.ERROR)
				end
			end)
		end)
	end
end

local function search_aliases()
	local search = require("obsidian.search")
	local api = require("obsidian.api")
	local dir = api.resolve_workspace_dir()
	search.find_notes_async("", function(notes)
		---@type obsidian.PickerEntry[]
		local entries = {}
		for _, note in ipairs(notes) do
			if note.aliases and #note.aliases > 0 then
				local stat = note.path and vim.uv.fs_stat(tostring(note.path))
				local mtime = stat and stat.mtime.sec or 0
				local rel = note.path and note.path:vault_relative_path() or ""
				local folder = vim.fn.fnamemodify(rel, ":h")
				local aliases_str = table.concat(note.aliases, ", ")
				local text = folder ~= "." and string.format("%s/%s", folder, aliases_str) or aliases_str
				entries[#entries + 1] = {
					value = { path = note.path, line = 1 },
					text = text,
					ordinal = aliases_str,
					filename = tostring(note.path),
					_mtime = mtime,
				}
			end
		end
		table.sort(entries, function(a, b)
			return a._mtime > b._mtime
		end)
		if vim.tbl_isempty(entries) then
			vim.notify("No aliases found", vim.log.levels.WARN)
			return
		end
		vim.schedule(function()
			Obsidian.picker.pick(entries, {
				prompt_title = "Aliases",
				format_item = function(entry)
					return entry.text or ""
				end,
			})
		end)
	end, { dir = dir })
end

local function vault_sync_all()
	run_for_all_vaults("Vault sync", function(vault_root, datetime)
		local message = string.format("vault backup: %s", datetime)
		return table.concat({
			string.format("git -C %q add -A", vault_root),
			string.format(
				"{ git -C %q diff --cached --quiet || git -C %q commit -m %q; }",
				vault_root,
				vault_root,
				message
			),
			string.format("git -C %q pull --rebase", vault_root),
			string.format("git -C %q push", vault_root),
		}, " && ")
	end)
end

return {
	"obsidian-nvim/obsidian.nvim",
	version = "*",
	lazy = false,
	cond = #workspaces > 0,
	opts = {
		legacy_commands = false,
		workspaces = workspaces,
		notes_subdir = "inbox",
		new_notes_location = "notes_subdir",
		ui = { enable = false },
		daily_notes = {
			folder = "daily",
			workdays_only = false,
		},
		checkbox = {
			order = { " ", "x" },
		},
	},
	config = function(_, opts)
		require("obsidian").setup(opts)
		apply_default_workspace()

		-- Make ripgrep follow symlinks so cross-vault symlinked dirs are indexed
		local search = require("obsidian.search")
		for _, fn in ipairs({ "build_find_cmd", "build_search_cmd" }) do
			local orig = search[fn]
			search[fn] = function(...)
				local cmd = orig(...)
				table.insert(cmd, 2, "-L")
				return cmd
			end
		end

		-- Prevent Path:resolve() from following symlinks out of the vault
		local Path = require("obsidian.path")
		local orig_resolve = Path.resolve
		Path.resolve = function(self, ropts)
			local resolved = orig_resolve(self, ropts)
			local ws_root = tostring(Obsidian.workspace and Obsidian.workspace.root or "")
			if ws_root ~= "" and not tostring(resolved):find(ws_root, 1, true) then
				local abs = vim.fn.fnamemodify(tostring(self), ":p")
				if abs:find(ws_root, 1, true) then
					return Path.new(abs)
				end
			end
			return resolved
		end
	end,
	cmd = { "Obsidian" },
	keys = {
		{ "<leader>on", "<cmd>Obsidian new<cr>", desc = "New note" },
		{ "<leader>od", "<cmd>Obsidian dailies<cr>", desc = "Daily note picker" },
		{ "<leader>ot", "<cmd>Obsidian today<cr>", desc = "Daily Today" },
		{ "<leader>oy", "<cmd>Obsidian yesterday<cr>", desc = "Daily Yesterday" },
		{ "<leader>oo", "<cmd>Obsidian tomorrow<cr>", desc = "Daily Tomorrow" },
		{ "<leader>os", "<cmd>Obsidian search<cr>", desc = "Search Note Contents" },
		{ "<leader>of", "<cmd>Obsidian quick_switch<cr>", desc = "Search Note Names" },
		{ "<leader>og", "<cmd>Obsidian tags<cr>", desc = "Search Tags" },
		{ "<leader>oa", search_aliases, desc = "Search Aliases" },
		{ "<leader>ob", "<cmd>Obsidian backlinks<cr>", desc = "Show Backlinks" },
		{ "<leader>ol", "<cmd>Obsidian links<cr>", desc = "Show Links in document" },
		{ "<leader>oc", "<cmd>Obsidian toc<cr>", desc = "Table of Contents" },
		{ "<leader>ov", "<cmd>Obsidian follow_link vsplit_force<cr>", desc = "Follow link with Vertical Split" },
		{ "<leader>oh", "<cmd>Obsidian follow_link hsplit_force<cr>", desc = "Follow link with Horizontal Split" },
		{ "<leader>ow", "<cmd>Obsidian workspace<cr>", desc = "Switch Workspace" },
		{ "<leader>op", vault_sync_all, desc = "Vault sync (pull/push all)" },
	},
}
