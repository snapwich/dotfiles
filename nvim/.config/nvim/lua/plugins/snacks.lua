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

return {
  {
    "folke/snacks.nvim",
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
