local workspaces = vim.tbl_filter(function(ws)
  return vim.fn.isdirectory(vim.fn.expand(ws.path)) == 1
end, {
  {
    name = "notes",
    path = "~/vaults/notes",
  },
  {
    name = "work-notes",
    path = "~/vaults/work-notes",
    overrides = {
      daily_notes = {
        workdays_only = true,
      },
    },
  },
})

local function run_for_all_vaults(label, build_script)
  local datetime = os.date("%Y-%m-%d %H:%M:%S")
  local total = #workspaces
  local results = {}
  for _, ws in ipairs(workspaces) do
    local vault_root = vim.fn.fnamemodify(vim.fn.expand(ws.path), ":p"):gsub("/$", "")
    local script = build_script(vault_root, datetime)
    vim.system({ "sh", "-c", script }, { text = true }, function(out)
      vim.schedule(function()
        results[#results + 1] = {
          name = ws.name,
          ok = out.code == 0,
          stderr = out.stderr or "",
          stdout = out.stdout or "",
        }
        if #results < total then
          return
        end
        local failures = vim.tbl_filter(function(r)
          return not r.ok
        end, results)
        if #failures == 0 then
          vim.notify(string.format("%s complete (%d vaults)", label, total), vim.log.levels.INFO)
        else
          local lines = { label .. " failed:" }
          for _, r in ipairs(failures) do
            lines[#lines + 1] = string.format("[%s] %s%s", r.name, r.stderr, r.stdout)
          end
          vim.notify(table.concat(lines, "\n"), vim.log.levels.ERROR)
        end
      end)
    end)
  end
end

local function vault_push_all()
  run_for_all_vaults("Vault push", function(vault_root, datetime)
    local message = string.format("vault backup: %s", datetime)
    return table.concat({
      string.format("git -C %q add -A", vault_root),
      string.format(
        "{ git -C %q diff --cached --quiet || git -C %q commit -m %q; }",
        vault_root,
        vault_root,
        message
      ),
      string.format("git -C %q push", vault_root),
    }, " && ")
  end)
end

local function vault_pull_all()
  run_for_all_vaults("Vault pull", function(vault_root)
    return string.format("git -C %q pull", vault_root)
  end)
end

return {
  "obsidian-nvim/obsidian.nvim",
  version = "*",
  lazy = false,
  cond = #workspaces > 0,
  opts = {
    legacy_commands = false,
    workspaces = workspaces,
    notes_subdir = "inbox",
    new_notes_location = "notes_subdir",
    ui = { enable = false },
    daily_notes = {
      folder = "daily",
      workdays_only = false,
    },
  },
  cmd = { "Obsidian" },
  keys = {
    { "<leader>on", "<cmd>Obsidian new<cr>",                      desc = "New note" },
    { "<leader>ot", "<cmd>Obsidian today<cr>",                    desc = "Daily Today" },
    { "<leader>oy", "<cmd>Obsidian yesterday<cr>",                desc = "Daily Yesterday" },
    { "<leader>os", "<cmd>Obsidian search<cr>",                   desc = "Search Note Contents" },
    { "<leader>of", "<cmd>Obsidian quick_switch<cr>",             desc = "Search Note Names" },
    { "<leader>oa", "<cmd>Obsidian tags<cr>",                     desc = "Search Tags" },
    { "<leader>ob", "<cmd>Obsidian backlinks<cr>",                desc = "Show Backlinks" },
    { "<leader>ol", "<cmd>Obsidian links<cr>",                    desc = "Show Links in document" },
    { "<leader>oc", "<cmd>Obsidian toc<cr>",                      desc = "Table of Contents" },
    { "<leader>ov", "<cmd>Obsidian follow_link vsplit_force<cr>", desc = "Follow link with Vertical Split" },
    { "<leader>oh", "<cmd>Obsidian follow_link hsplit_force<cr>", desc = "Follow link with Horizontal Split" },
    { "<leader>ow", "<cmd>Obsidian workspace<cr>",                desc = "Switch Workspace" },
    { "<leader>op", vault_pull_all,                               desc = "Vault pull all from remote" },
    { "<leader>oP", vault_push_all,                               desc = "Vault push all (add, commit, push)" },
  },
}
