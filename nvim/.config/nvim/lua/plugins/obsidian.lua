local workspaces = vim.tbl_filter(function(ws)
  return vim.fn.isdirectory(vim.fn.expand(ws.path)) == 1
end, {
  {
    name = "notes",
    path = "~/vaults/notes",
  },
  {
    name = "_dev-notes",
    path = "/home/dev/repos/obsidian-tasks.nvim/default/tests/fixtures/vault",
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

local default_workspace = vim.env.OBSIDIAN_WORKSPACE
if default_workspace then
  for i, ws in ipairs(workspaces) do
    if ws.name == default_workspace then
      table.remove(workspaces, i)
      table.insert(workspaces, 1, ws)
      break
    end
  end
end

local function apply_default_workspace()
  if not default_workspace then
    return
  end
  for _, ws in ipairs(Obsidian.workspaces or {}) do
    if ws.name == default_workspace then
      require("obsidian.workspace").set(ws)
      return
    end
  end
end

-- Run a list of argv commands sequentially (no shell, so it works on Windows).
-- Each command is { args = {...}, ignore_failure = bool, skip_if_prev_ok = bool }.
local function run_commands(commands, on_done)
  local idx = 0
  local prev_code = nil
  local function step()
    idx = idx + 1
    local cmd = commands[idx]
    if not cmd then
      on_done(true, "")
      return
    end
    if cmd.skip_if_prev_ok and prev_code == 0 then
      step()
      return
    end
    vim.system(cmd.args, { text = true }, function(out)
      prev_code = out.code
      if out.code ~= 0 and not cmd.ignore_failure then
        on_done(false, (out.stderr or "") .. (out.stdout or ""))
        return
      end
      step()
    end)
  end
  step()
end

local function run_for_all_vaults(label, build_commands)
  local datetime = os.date("%Y-%m-%d %H:%M:%S")
  local targets = vim.tbl_filter(function(ws)
    return not vim.startswith(ws.name, "_")
  end, workspaces)
  local total = #targets
  local results = {}
  for _, ws in ipairs(targets) do
    local vault_root = vim.fn.fnamemodify(vim.fn.expand(ws.path), ":p"):gsub("/$", "")
    run_commands(build_commands(vault_root, datetime), function(ok, output)
      vim.schedule(function()
        results[#results + 1] = { name = ws.name, ok = ok, output = output }
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
            lines[#lines + 1] = string.format("[%s] %s", r.name, r.output)
          end
          vim.notify(table.concat(lines, "\n"), vim.log.levels.ERROR)
        end
      end)
    end)
  end
end

local function search_aliases(opts)
  opts = opts or {}
  local filter = opts.filter
  local search = require("obsidian.search")
  local api = require("obsidian.api")
  local dir = api.resolve_workspace_dir()
  search.find_notes_async("", function(notes)
    ---@type obsidian.PickerEntry[]
    local entries = {}
    for _, note in ipairs(notes) do
      if note.aliases and #note.aliases > 0 and (not filter or filter(note)) then
        local stat = note.path and vim.uv.fs_stat(tostring(note.path))
        local mtime = stat and stat.mtime.sec or 0
        local rel = note.path and note.path:vault_relative_path() or ""
        local folder = vim.fn.fnamemodify(rel, ":h")
        local aliases_str = table.concat(note.aliases, ", ")
        local text = folder ~= "." and string.format("%s/%s", folder, aliases_str) or aliases_str
        entries[#entries + 1] = {
          value = { path = note.path, line = 1 },
          text = text,
          ordinal = aliases_str,
          filename = tostring(note.path),
          _mtime = mtime,
        }
      end
    end
    table.sort(entries, function(a, b)
      return a._mtime > b._mtime
    end)
    if vim.tbl_isempty(entries) then
      vim.notify("No aliases found", vim.log.levels.WARN)
      return
    end
    vim.schedule(function()
      Obsidian.picker.pick(entries, {
        prompt_title = opts.prompt_title or "Aliases",
        format_item = function(entry)
          return entry.text or ""
        end,
      })
    end)
  end, { dir = dir })
end

local function search_aliases_buffers()
  local open = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" then
        open[vim.fn.fnamemodify(name, ":p")] = true
      end
    end
  end
  search_aliases({
    prompt_title = "Aliases (Open Buffers)",
    filter = function(note)
      return note.path and open[vim.fn.fnamemodify(tostring(note.path), ":p")]
    end,
  })
end

local function all_dailies()
  local util = require("obsidian.util")
  local folder = Obsidian.opts.daily_notes.folder or ""
  local dir = vim.fs.joinpath(tostring(Obsidian.dir), folder)
  local alias_format = Obsidian.opts.daily_notes.alias_format or "%A %B %-d, %Y"

  ---@type obsidian.PickerEntry[]
  local entries = {}
  for name, type in vim.fs.dir(dir) do
    local stem = name:match("^(.+)%.md$")
    if type == "file" and stem then
      -- Default date_format is YYYY-MM-DD; derive the same alias `od` shows.
      local y, m, d = stem:match("(%d%d%d%d)-(%d%d)-(%d%d)")
      local text = stem
      if y then
        local ts = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
        text = tostring(util.format_date(ts, alias_format))
      end
      entries[#entries + 1] = { filename = vim.fs.joinpath(dir, name), text = text, _sort = stem }
    end
  end

  if vim.tbl_isempty(entries) then
    vim.notify("No daily notes found in " .. dir, vim.log.levels.WARN)
    return
  end

  -- Newest first (YYYY-MM-DD filenames sort lexically == chronologically).
  table.sort(entries, function(a, b)
    return a._sort > b._sort
  end)

  Obsidian.picker.pick(entries, { prompt_title = "All Dailies" })
end

local function vault_sync_all()
  run_for_all_vaults("Vault sync", function(vault_root, datetime)
    local message = string.format("vault backup: %s", datetime)
    return {
      { args = { "git", "-C", vault_root, "add", "-A" } },
      -- diff --cached --quiet exits nonzero when there are staged changes
      { args = { "git", "-C", vault_root, "diff", "--cached", "--quiet" }, ignore_failure = true },
      -- ...so skip the commit only when the diff found nothing (exit 0)
      { args = { "git", "-C", vault_root, "commit", "-m", message },       skip_if_prev_ok = true },
      { args = { "git", "-C", vault_root, "pull", "--rebase" } },
      { args = { "git", "-C", vault_root, "push" } },
    }
  end)
end

return {
  "obsidian-nvim/obsidian.nvim",
  enabled = true,
  -- dir = "/home/dev/repos/obsidian.nvim/default",
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
    templates = {
      folder = "templates",
    },
    checkbox = {
      order = { " ", "x" },
    },
  },
  config = function(_, opts)
    require("obsidian").setup(opts)
    apply_default_workspace()

    -- Make ripgrep follow symlinks so cross-vault symlinked dirs are indexed
    local search = require("obsidian.search")
    for _, fn in ipairs({ "build_find_cmd", "build_search_cmd" }) do
      local orig = search[fn]
      search[fn] = function(...)
        local cmd = orig(...)
        table.insert(cmd, 2, "-L")
        return cmd
      end
    end

    -- Prevent Path:resolve() from following symlinks out of the vault
    local Path = require("obsidian.path")
    local orig_resolve = Path.resolve
    Path.resolve = function(self, ropts)
      local resolved = orig_resolve(self, ropts)
      local ws_root = tostring(Obsidian.workspace and Obsidian.workspace.root or "")
      if ws_root ~= "" and not tostring(resolved):find(ws_root, 1, true) then
        local abs = vim.fn.fnamemodify(tostring(self), ":p")
        if abs:find(ws_root, 1, true) then
          return Path.new(abs)
        end
      end
      return resolved
    end
  end,
  cmd = { "Obsidian" },
  keys = {
    { "<leader>on", "<cmd>Obsidian new<cr>",                      desc = "New note" },
    { "<leader>oD", "<cmd>Obsidian dailies -30 0<cr>",            desc = "Daily note picker" },
    { "<leader>od", all_dailies,                                  desc = "All dailies" },
    { "<leader>ot", "<cmd>Obsidian today<cr>",                    desc = "Daily Today" },
    { "<leader>oy", "<cmd>Obsidian yesterday<cr>",                desc = "Daily Yesterday" },
    { "<leader>oo", "<cmd>Obsidian tomorrow<cr>",                 desc = "Daily Tomorrow" },
    { "<leader>os", "<cmd>Obsidian search<cr>",                   desc = "Search Note Contents" },
    { "<leader>of", "<cmd>Obsidian quick_switch<cr>",             desc = "Search Note Names" },
    { "<leader>og", "<cmd>Obsidian tags<cr>",                     desc = "Search Tags" },
    { "<leader>oa", search_aliases,                               desc = "Search Aliases" },
    { "<leader>ob", search_aliases_buffers,                       desc = "Search Aliases (Open Buffers)" },
    { "<leader>ok", "<cmd>Obsidian backlinks<cr>",                desc = "Show Backlinks" },
    { "<leader>ol", "<cmd>Obsidian links<cr>",                    desc = "Show Links in document" },
    { "<leader>oc", "<cmd>Obsidian toc<cr>",                      desc = "Table of Contents" },
    { "<leader>ov", "<cmd>Obsidian follow_link vsplit_force<cr>", desc = "Follow link with Vertical Split" },
    { "<leader>oh", "<cmd>Obsidian follow_link hsplit_force<cr>", desc = "Follow link with Horizontal Split" },
    { "<leader>ow", "<cmd>Obsidian workspace<cr>",                desc = "Switch Workspace" },
    { "<leader>op", vault_sync_all,                               desc = "Vault sync (pull/push all)" },
  },
}
