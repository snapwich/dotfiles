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

-- `gc` quotes markdown instead of writing HTML comments: `<!-- -->` is useless
-- in notes, blockquotes are not. The builtin operator prefixes blank lines with
-- a bare `>` too, which keeps one quote from splitting in two.
--
-- Runs after $VIMRUNTIME/ftplugin/markdown.vim, which sets `<!-- %s -->`.
-- Other half of the override is lua/plugins/ts-comments.lua; both are needed.
-- Injected languages still win, so `gc` in a ```lua fence or the yaml
-- frontmatter is unaffected.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function(ev)
    vim.bo[ev.buf].commentstring = "> %s"
  end,
})

-- TS7 (`tsc --lsp`) drops every documentHighlight when the project path has an
-- `@`, which breaks `[[`/`]]` (Snacks.words). The server encodes `@` as `%40`
-- and then compares that string to the raw URI we sent. Send it encoded the
-- same way. Responses carry only ranges, so the request is all that needs it.
-- Remove once microsoft/TypeScript fixes tsc/internal/ls/documenthighlights.go.
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client or client.name ~= "tsc" then
      return
    end
    local request = client.request
    client.request = function(self, method, params, ...)
      if method == "textDocument/documentHighlight" and params and params.textDocument then
        params = vim.deepcopy(params)
        params.textDocument.uri = params.textDocument.uri:gsub("@", "%%40")
      end
      return request(self, method, params, ...)
    end
  end,
})
