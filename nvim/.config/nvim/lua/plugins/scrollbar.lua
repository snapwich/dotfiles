return {
  "dstein64/nvim-scrollview",
  dependencies = {
    "lewis6991/gitsigns.nvim",
  },
  config = function()
    -- Enable gitsigns integration from contrib
    require("scrollview.contrib.gitsigns").setup()
  end,
}
