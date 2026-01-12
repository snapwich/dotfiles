local snacks = require "snacks"

-- prevent copy on delete
vim.keymap.set({ 'n', 'v' }, 'x', '"_x')
vim.keymap.set({ 'n', 'v' }, 'd', '"_d')
vim.keymap.set({ 'n', 'v' }, 'D', '"_D')
vim.keymap.set({ 'n', 'v' }, 'c', '"_c')
vim.keymap.set({ 'x' }, 'p', 'P')

vim.keymap.set({ 'n', 'v' }, 'q', '<nop>')
vim.keymap.set({ 'n', 'v' }, 'Q', '<nop>')

-- disable join command, it's useless
vim.keymap.set({ 'n', 'v' }, 'J', '<nop>')

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
  snacks.terminal('zsh -l')
end, { desc = 'Terminal zsh' })

vim.keymap.set('n', '<leader>tk', function()
  snacks.terminal('k9s')
end, { desc = 'Terminal k9s' })

vim.keymap.set('n', '<leader>we', function()
  local explorer_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ft = vim.bo[buf].filetype
    if ft == "snacks_picker_list" then
      explorer_win = win
      break
    end
  end
  if explorer_win and vim.api.nvim_get_current_win() ~= explorer_win then
    -- Explorer exists: jump to it
    vim.api.nvim_set_current_win(explorer_win)
  else
    -- No explorer (or already in it): toggle/open via Snacks.explorer()
    Snacks.explorer()
  end
end, { desc = 'Focus snacks explorer' })

vim.keymap.set('n', '<leader>wp', "<C-w>p", { desc = 'Previous window' })

vim.keymap.set('n', '<leader>b[', ":BufferLineMovePrev<CR>", { desc = "Move current buffer left" })
vim.keymap.set('n', '<leader>b]', ":BufferLineMoveNext<CR>", { desc = "Move current buffer right" })

vim.keymap.set('n', '<leader>cs', "<cmd>TSSortIgnoreCase true<cr><cmd>TSSort<cr>",
  { desc = "Sort code (TSSort, case-insensitive)" })
vim.keymap.set('n', '<leader>cS', "<cmd>TSSortIgnoreCase false<cr><cmd>TSSort<cr>",
  { desc = "Sort code (TSSort, case-sensitive)" })
