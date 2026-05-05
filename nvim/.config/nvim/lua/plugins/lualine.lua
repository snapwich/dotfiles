return {
	"nvim-lualine/lualine.nvim",
	opts = function(_, opts)
		table.insert(opts.sections.lualine_x, 1, {
			function()
				if not (Obsidian and Obsidian.workspace) then
					return ""
				end
				return "󰠮 " .. Obsidian.workspace.name
			end,
		})
		vim.api.nvim_create_autocmd("User", {
			pattern = "ObsidianWorkpspaceSet",
			callback = function()
				vim.cmd("redrawstatus")
			end,
		})
	end,
}
