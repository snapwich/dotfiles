vim.g.root_spec = { "cwd" }
vim.opt.winbar = "%=%m %f"
vim.opt.clipboard = "unnamedplus" -- use + by default

local function in_tmux()
  return vim.env.TMUX ~= nil and vim.fn.executable("tmux") == 1
end

-- join lines preserving newlines (Neovim passes a list)
local function lines_to_string(lines)
  return table.concat(lines, "\n")
end

-- OSC52 copy + mirror into tmux buffer (shared across panes)
local function osc52_and_tmux_copy(reg)
  local osc52 = require("vim.ui.clipboard.osc52").copy(reg)
  return function(lines, regtype)
    -- 1) system clipboard via OSC52 (through tmux → outer terminal)
    pcall(osc52, lines, regtype)

    -- 2) also store in tmux's top buffer so other tmux panes/sessions can paste
    if in_tmux() then
      -- replace the top buffer content
      -- (use `set-buffer` so we don't create many tmux buffers)
      local text = lines_to_string(lines)
      -- Use `--` to stop option parsing in case text starts with dashes
      vim.fn.system({ "tmux", "set-buffer", "--", text })
      -- optional: also copy to tmux's external clipboard integration
      -- if you prefer: vim.fn.system({ "tmux", "set-buffer", "-w", "--", text })
    end
  end
end

-- Paste: prefer tmux buffer (fast), fallback to local register (non-blocking)
local function tmux_or_local_paste(reg)
  return function()
    if in_tmux() then
      local out = vim.fn.systemlist({ "tmux", "save-buffer", "-" })
      if vim.v.shell_error == 0 and #out > 0 then
        -- keep whatever register type user had (char/line/block)
        return out, vim.fn.getregtype(reg)
      end
    end
    -- fallback: local (never triggers OSC52 query)
    return vim.fn.split(vim.fn.getreg(reg), "\n"), vim.fn.getregtype(reg)
  end
end

vim.g.clipboard = {
  name = "osc52+tmux (no-query paste)",
  copy = {
    ["+"] = osc52_and_tmux_copy("+"),
    ["*"] = osc52_and_tmux_copy("*"),
  },
  paste = {
    ["+"] = tmux_or_local_paste("+"),
    ["*"] = tmux_or_local_paste("*"),
  },
}
