return {
	"Saghen/blink.cmp",
	opts = {
		completion = {
			ghost_text = {
				enabled = false,
			},
		},
		sources = {
			default = { "lsp", "path", "snippets", "buffer", "obsidian-tasks" },
			providers = {
				["obsidian-tasks"] = {
					module = "obsidian-tasks.cmp.source",
					name = "ObsidianTasks",
				},
			},
		},
	},
}
