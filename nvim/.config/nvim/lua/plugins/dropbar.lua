return {
  "Bekaboo/dropbar.nvim",
  opts = {
    bar = {
      -- show more filetypes than default
      enable = function(buf)
        local buftype = vim.bo[buf].buftype
        local filetype = vim.bo[buf].filetype
        if buftype ~= "" and buftype ~= "acwrite" then
          return false
        end
        if filetype == "help" then
          return false
        end
        return true
      end,
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
    sources = {
      path = {
        modified = function(sym)
          return sym:merge({
            icon = " " .. sym.icon,
            icon_hl = "DiagnosticWarn",
          })
        end,
      },
    },
  },
}
