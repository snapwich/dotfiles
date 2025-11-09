local custom_pickers = {}

function custom_pickers.git_diff_origin_default()
  -- Query the remote directly for its default branch
  local output = vim.fn.system("git ls-remote --symref origin HEAD 2>/dev/null")
  local base = "master" -- default fallback

  -- Parse: "ref: refs/heads/main	HEAD" -> "main"
  local match = output:match("ref: refs/heads/([^\t\n]+)")
  if match then
    base = match
  end

  local git_root = Snacks.git.get_root()

  Snacks.picker.pick({
    source = "git_diff_origin_default",
    title = "Git branch changed files",
    preview = "file",
    finder = function(opts, ctx)
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
      picker = {
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
      { "<leader>gm", custom_pickers.git_diff_origin_default, desc = "Git branch changed files vs default branch" }
    }
  },
}
