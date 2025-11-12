return {
  "Bekaboo/dropbar.nvim",
  opts = {
    bar = {
      padding = {
        left = 1,
        right = 1,
      },
      sources = function()
        local sources = require("dropbar.sources")
        return {
          sources.path,
        }
      end,
    },
  },
  config = function(_, opts)
    require("dropbar").setup(opts)

    -- Hook to right-align the winbar
    vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "CursorMoved" }, {
      callback = function()
        local winbar = vim.wo.winbar
        if winbar ~= "" and not winbar:match("^%%=") then
          vim.wo.winbar = "%=" .. winbar -- Right align
          -- For center: vim.wo.winbar = "%=" .. winbar .. "%="
        end
      end,
    })

    local dropbar_api = require('dropbar.api')
    vim.keymap.set('n', '<Leader>;', dropbar_api.pick, { desc = 'Pick symbols in winbar' })
  end
}
