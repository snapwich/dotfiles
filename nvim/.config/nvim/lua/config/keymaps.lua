local snacks = require "snacks"

vim.keymap.set("n", "<leader>cs", "<cmd>TSSort<cr>", { desc = "Sort code (TSSort)" })

vim.keymap.set({ 'n', 'v' }, 'x', '"_x')
vim.keymap.set({ 'n', 'v' }, 'd', '"_d')
vim.keymap.set({ 'n', 'v' }, 'c', '"_c')

vim.keymap.set('n', '<leader>yp', function()
  local abs_path = vim.fn.expand('%:p')
  local root_dir = vim.fn.getcwd()
  local rel_path = vim.fn.fnamemodify(abs_path, ':.' .. root_dir)
  local linenum = vim.fn.line('.')
  local result = string.format('%s:%d', rel_path, linenum)
  vim.fn.setreg('+', result)
  vim.notify('Copied: ' .. result)
end, { desc = 'Copy relative file path:line to clipboard' })

vim.keymap.set('n', '<leader>yP', function()
  local filepath = vim.fn.expand('%:p')
  local linenum = vim.fn.line('.')
  local result = string.format('%s:%d', filepath, linenum)
  vim.fn.setreg('+', result)
  vim.notify('Copied: ' .. result)
end, { desc = 'Copy absolute file path:line number to clipboard' })

vim.keymap.set('n', '<leader>tt', function()
  snacks.terminal('zsh')
end, { desc = 'Terminal zsh' })

vim.keymap.set('n', '<leader>tk', function()
  snacks.terminal('k9s')
end, { desc = 'Terminal k9s' })
