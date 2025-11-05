vim.opt.winbar = "%=%m %f"

local function paste()
  return {
    vim.fn.split(vim.fn.getreg(""), "\n"),
    vim.fn.getregtype(""),
  }
end

local in_tmux = vim.env.TMUX ~= nil
local paste_fn = in_tmux and require("vim.ui.clipboard.osc52").paste("+") or paste

vim.g.clipboard = {
  name = "OSC 52",
  copy = {
    ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
    ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
  },
  paste = {
    ["+"] = paste_fn,
    ["*"] = paste_fn,
  },
}

vim.opt.clipboard:append { 'unnamed', 'unnamedplus' }
