vim.opt.relativenumber = false
vim.opt.list = false

vim.o.guifont = "FiraCode Nerd Font Mono:h10"

vim.api.nvim_create_autocmd("ModeChanged", {
  callback = function()
    local m               = vim.api.nvim_get_mode().mode
    local visual          = (m == "v" or m == "V" or m == "\22")
    local opend           = (m == "o" or (m:match("^no") ~= nil))
    vim.wo.relativenumber = visual or opend
  end,
})

local function paste()
  return {
    vim.fn.split(vim.fn.getreg(""), "\n"),
    vim.fn.getregtype(""),
  }
end

-- GUI clients (Neovide, etc.) have native system-clipboard access, so skip the
-- OSC52 terminal hack and let Neovim use its built-in provider.
if not vim.g.neovide then
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
end

vim.opt.clipboard:append { 'unnamed', 'unnamedplus' }
