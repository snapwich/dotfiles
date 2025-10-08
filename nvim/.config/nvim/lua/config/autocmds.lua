vim.api.nvim_create_autocmd("FocusGained", {
  desc = "Reload files from disk when we focus vim",
  pattern = "*",
  command = "if getcmdwintype() == '' | checktime | endif",
})
vim.api.nvim_create_autocmd("BufEnter", {
  desc = "Every time we enter an unmodified buffer, check if it changed on disk",
  pattern = "*",
  command = "if &buftype == '' && !&modified && expand('%') != '' | exec 'checktime ' . expand('<abuf>') | endif",
})

-- lua/config/autocmds.lua

local grp = vim.api.nvim_create_augroup("AbsNumsInDiff", { clear = true })

local function sync_numbers_for_diff(win)
  win = win or 0
  if vim.wo[win].diff then
    -- Save the window's current settings once
    if not vim.w[win]._prev_number_opts then
      vim.w[win]._prev_number_opts = {
        number = vim.wo[win].number,
        relativenumber = vim.wo[win].relativenumber,
      }
    end
    -- Force absolute numbers in diff
    vim.wo[win].number = true
    vim.wo[win].relativenumber = false
  else
    -- Restore on diffoff/when leaving diff
    local prev = vim.w[win]._prev_number_opts
    if prev then
      vim.wo[win].number = prev.number
      vim.wo[win].relativenumber = prev.relativenumber
      vim.w[win]._prev_number_opts = nil
    end
  end
end

-- Apply when entering a window and when diff option toggles
vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
  group = grp,
  callback = function() sync_numbers_for_diff(0) end,
})

vim.api.nvim_create_autocmd("OptionSet", {
  group = grp,
  pattern = "diff",
  callback = function() sync_numbers_for_diff(0) end,
})
