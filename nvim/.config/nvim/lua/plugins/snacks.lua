return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        win = {
          input = {
            keys = {
              ["<PageUp>"] = { "preview_scroll_up", mode = { "n", "i" } },
              ["<PageDown>"] = { "preview_scroll_down", mode = { "n", "i" } },
            },
          },
        },
        sources = {
          explorer = {
            hidden = true,
            ignored = true,
          }
        }
      },
      scroll = {
        enabled = false,
      }
    },
  },
}
