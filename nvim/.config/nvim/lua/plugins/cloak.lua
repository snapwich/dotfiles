return {
  "laytan/cloak.nvim",
  event = "BufReadPre",
  keys = {
    { "<leader>uk", "<cmd>CloakToggle<cr>", desc = "Toggle Cloak" },
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
