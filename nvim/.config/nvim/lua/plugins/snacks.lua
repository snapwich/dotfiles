local custom_pickers = {}

function custom_pickers.grep_quickfix()
  local qflist = vim.fn.getqflist()
  local files = {}
  local seen = {}
  for _, item in ipairs(qflist) do
    local bufnr = item.bufnr
    if bufnr and bufnr > 0 then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" and not seen[name] then
        seen[name] = true
        files[#files + 1] = name
      end
    end
  end
  if #files == 0 then
    vim.notify("Quickfix list is empty", vim.log.levels.WARN)
    return
  end
  Snacks.picker.grep({ dirs = files })
end

function custom_pickers.git_diff_origin_default()
  -- Query the remote directly for its default branch
  local output = vim.fn.system("git ls-remote --symref origin HEAD 2>/dev/null")
  local base = nil

  -- Parse: "ref: refs/heads/main	HEAD" -> "main"
  local match = output:match("ref: refs/heads/([^\t\n]+)")
  if match then
    base = match
  end

  -- Fallback: check for common branches locally
  if not base then
    vim.fn.system("git rev-parse --verify origin/main 2>/dev/null")
    if vim.v.shell_error == 0 then
      base = "main"
    else
      vim.fn.system("git rev-parse --verify origin/master 2>/dev/null")
      if vim.v.shell_error == 0 then
        base = "master"
      else
        vim.notify("Could not determine default branch for origin", vim.log.levels.ERROR)
        return
      end
    end
  end

  local git_root = Snacks.git.get_root()

  Snacks.picker.pick({
    source = "git_diff_origin_default",
    title = "Git branch changed files",
    preview = "file",
    finder = function(_, ctx)
      return require("snacks.picker.source.proc").proc(
        ctx:opts({
          cmd = "git",
          args = { "diff", "--name-only", ("origin/%s..."):format(base) },
          transform = function(item)
            item.cwd = git_root
            item.file = item.text
          end,
        }),
        ctx
      )
    end,
  })
end

-- Patch snacks' file rename to rename the buffer in place instead of swapping
-- in a fresh copy read from disk, which silently drops unsaved edits. Fixes the
-- explorer's `m`/move actions and <leader>fm, which all route through _rename.
-- See https://github.com/folke/snacks.nvim/discussions/2852
local function patch_rename()
  local rename = require("snacks.rename")
  function rename._rename(from, to)
    from = vim.fn.fnamemodify(from, ":p")
    to = vim.fn.fnamemodify(to, ":p")
    vim.fn.mkdir(vim.fs.dirname(to), "p")
    if vim.fn.rename(from, to) ~= 0 then
      Snacks.notify.error("Failed to rename file: `" .. from .. "`")
      return false
    end
    -- Only touch buffers if the file is actually open; renaming a closed file
    -- (e.g. from the explorer) must still report success so callers refresh.
    local from_buf = vim.fn.bufnr(from)
    if from_buf >= 0 then
      local to_buf = vim.fn.bufnr(to)
      if to_buf >= 0 and to_buf ~= from_buf then
        vim.api.nvim_buf_delete(to_buf, { force = true })
      end
      vim.api.nvim_buf_set_name(from_buf, to)
      vim.api.nvim_buf_call(from_buf, function()
        local mod = vim.bo.modified
        vim.cmd("edit! | undo") -- resync buffer<->file, then restore unsaved edits
        vim.bo.modified = mod
      end)
    end
    return true
  end
end

return {
  {
    "folke/snacks.nvim",
    init = function()
      vim.schedule(patch_rename) -- defer until snacks is loaded
    end,
    opts = {
      dashboard = {
        preset = {
          header = ""
        },
      },
      picker = {
        layout = {
          layout = {
            width = 0.95,
            height = 0.95,
          }
        },
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
            layout = {
              layout = {
                width = 40,
                height = 1,
                position = "right",
              },
            },
          },
          files = {
            hidden = true,
          }
        }
      },
      scroll = {
        enabled = false,
      },
    },
    keys = {
      { "<leader>gm", custom_pickers.git_diff_origin_default, desc = "Git branch changed files vs default branch" },
      { "<leader>sq", custom_pickers.grep_quickfix, desc = "Grep Quickfix List Files" }
    }
  },
}
