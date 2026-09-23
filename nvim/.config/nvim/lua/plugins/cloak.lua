return {
	"laytan/cloak.nvim",
	event = "BufReadPre",
	keys = {
		{ "<leader>uk", "<cmd>CloakPreviewLine<cr>", desc = "Toggle Cloak For Line" },
		{ "<leader>uK", "<cmd>CloakToggle<cr>", desc = "Toggle Cloak Globally" },
	},
	opts = {
		patterns = {
			{
				file_pattern = { ".env*", "*.env", "env.*" },
				cloak_pattern = "=.+",
				replace = nil,
			},
		},
	},
}
