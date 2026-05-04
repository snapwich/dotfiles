return {
	"obsidian-nvim/obsidian.nvim",
	version = "*",
	ft = "markdown",
	opts = {
		legacy_commands = false,
		workspaces = {
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
		},
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
	},
}
