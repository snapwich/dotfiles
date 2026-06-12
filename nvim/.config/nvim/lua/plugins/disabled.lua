return {
  { "nvim-mini/mini.animate", enabled = false },
  -- Disable bufferline when running in Neovide
  { "akinsho/bufferline.nvim", cond = not vim.g.neovide },
}
