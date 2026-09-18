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
  local cwd = vim.fn.getcwd()
  for _, ws in ipairs(Obsidian.workspaces or {}) do
    if vim.startswith(cwd, tostring(ws.root)) then
      return
    end
  end
  for _, ws in ipairs(Obsidian.workspaces or {}) do
    if ws.name == default_workspace then
      require("obsidian.workspace").set(ws)
      return
    end
  end
end

-- Git must never block: `vim.system` gives it no tty, so an ssh passphrase or
-- credential prompt would hang the sync forever with nothing reported. The
-- transports need their own deadlines too -- `vim.system`'s timeout kills git
-- but the callback still waits on the stdio pipes, which a stuck grandchild
-- (ssh) keeps open.
local git_env = {
  GIT_TERMINAL_PROMPT = "0",
  GIT_ASKPASS = "",
  SSH_ASKPASS = "",
  GIT_SSH_COMMAND = "ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3",
  GIT_HTTP_LOW_SPEED_LIMIT = "1000",
  GIT_HTTP_LOW_SPEED_TIME = "30",
}

-- Backstop for a git process that hangs without network I/O.
local command_timeout = 60000

-- Lint output (lint-staged, markdownlint) carries ANSI colors and carriage
-- returns that make a notification unreadable.
local function clean_output(output)
  return (output or "")
      :gsub("\27%[[%d;]*[A-Za-z]", "")
      :gsub("\r", "\n")
      :gsub("\n\n+", "\n")
      :gsub("^%s+", "")
      :gsub("%s+$", "")
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
    vim.system(cmd.args, { text = true, env = git_env, timeout = command_timeout }, function(out)
      prev_code = out.code
      if out.code ~= 0 and not cmd.ignore_failure then
        -- Name the subcommand only ("commit", "push"): the full argv would drag
        -- the commit message into the notification.
        local what = cmd.args[2] == "-C" and cmd.args[4] or cmd.args[2]
        local detail = clean_output((out.stderr or "") .. (out.stdout or ""))
        if out.code == 124 then
          detail = string.format("timed out after %ds\n%s", command_timeout / 1000, detail)
        end
        on_done(false, string.format("`git %s` failed\n%s", what, detail))
        return
      end
      step()
    end)
  end
  step()
end

-- Failures are reported as soon as they happen, per vault: waiting for every
-- vault would hide an error behind a slow (or dead) remote. Long output stays
-- readable in the notification history (`<leader>sna`, `<leader>n`).
local function notify_failure(label, name, output)
  vim.notify(string.format("%s failed [%s]\n%s", label, name, output), vim.log.levels.ERROR, {
    title = label,
  })
end

local function run_for_all_vaults(label, build_commands)
  local datetime = os.date("%Y-%m-%d %H:%M:%S")
  local targets = vim.tbl_filter(function(ws)
    return not vim.startswith(ws.name, "_")
  end, workspaces)
  local total = #targets
  local done = 0
  local failed = 0
  for _, ws in ipairs(targets) do
    local vault_root = vim.fn.fnamemodify(vim.fn.expand(ws.path), ":p"):gsub("/$", "")
    run_commands(build_commands(vault_root, datetime), function(ok, output)
      vim.schedule(function()
        done = done + 1
        if not ok then
          failed = failed + 1
          notify_failure(label, ws.name, output)
        end
        if done < total then
          return
        end
        if failed == 0 then
          vim.notify(string.format("%s complete (%d vaults)", label, total), vim.log.levels.INFO)
        else
          vim.notify(
            string.format("%s: %d of %d vaults failed", label, failed, total),
            vim.log.levels.WARN
          )
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

-- Deferred: obsidian.nvim isn't on the rtp yet while this spec is evaluated.
local function title_id(title, dir)
  return require("obsidian.builtin").title_id(title, dir)
end

-- A reference points at an existing source note; these are the candidates.
-- Books, articles and web pages all live together here — what distinguishes
-- them is their `tags`, not their folder.
local source_dirs = { "sources" }
local source_kinds = { book = true, article = true, web = true }

-- Cheap frontmatter read for picker labels. Scalars land on the table as-is;
-- `tags` and `aliases` keep their block-list items.
---@return table
local function frontmatter_info(path)
  local info = { tags = {}, aliases = {} }
  local ok, lines = pcall(vim.fn.readfile, path, "", 40)
  if not ok then
    return info
  end
  local key
  for i, line in ipairs(lines) do
    if i > 1 and line:match "^%-%-%-" then
      break -- end of the frontmatter block
    end
    local k, v = line:match "^([%w_-]+):%s*(.-)%s*$"
    if k then
      key = k
      v = v:gsub('^"(.*)"$', "%1")
      if v ~= "" and v ~= "[]" then
        info[k] = v
      end
    else
      local item = line:match "^%s*%-%s*(.-)%s*$"
      if item and (key == "tags" or key == "aliases") then
        table.insert(info[key], (item:gsub('^"(.*)"$', "%1")))
      end
    end
  end
  return info
end

-- Everything worth typing at the picker: author, year, the non-kind tags, the
-- url host and any alias. Snacks matches on the displayed text, so metadata
-- only becomes searchable by being part of the label.
---@return string label
local function source_label(info, stem)
  local kind
  local extra_tags = {}
  for _, tag in ipairs(info.tags) do
    if not kind and source_kinds[tag] then
      kind = tag
    else
      extra_tags[#extra_tags + 1] = tag
    end
  end

  local meta = {}
  local function add(value)
    if value and value ~= "" then
      meta[#meta + 1] = value
    end
  end
  add(info.author)
  add(info.year)
  vim.list_extend(meta, extra_tags)
  add(info.url and info.url:match "^%a+://([^/]+)")
  for _, alias in ipairs(info.aliases) do
    if alias:lower() ~= (info.title or stem):lower() then
      add(alias)
    end
  end

  local label = string.format("%s  (%s)", info.title or stem, kind or "source")
  if not vim.tbl_isempty(meta) then
    label = label .. "  · " .. table.concat(meta, " · ")
  end
  return label
end

---@return { stem: string, path: string, label: string }[]
local function source_notes()
  local out = {}
  for _, subdir in ipairs(source_dirs) do
    local dir = vim.fs.joinpath(tostring(Obsidian.dir), subdir)
    if vim.fn.isdirectory(dir) == 1 then
      for name, ftype in vim.fs.dir(dir) do
        local stem = name:match "^(.+)%.md$"
        if ftype == "file" and stem then
          local path = vim.fs.joinpath(dir, name)
          out[#out + 1] = {
            stem = stem,
            path = path,
            label = source_label(frontmatter_info(path), stem),
          }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    return a.stem < b.stem
  end)
  return out
end

-- `customlist` completion can only call a globally reachable function.
_G.obsidian_source_complete = function(arglead)
  local out = {}
  for _, note in ipairs(source_notes()) do
    if note.stem:lower():find(arglead:lower(), 1, true) then
      out[#out + 1] = note.stem
    end
  end
  return out
end

-- Set by `new_reference` below, which resolves the source asynchronously via
-- the picker; template substitutions themselves have to be synchronous.
local pending_source = nil

local function prompt_source()
  if pending_source then
    return pending_source
  end
  return require("obsidian.api").input("Source", {
    completion = "customlist,v:lua.obsidian_source_complete",
  }) or ""
end

--- The book/article the current buffer implies: itself when it is one, else
--- whatever a reference note's own `source:` points at.
---@return string|? stem
local function buffer_source_stem()
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == "" then
    return nil
  end

  local abs = vim.fn.fnamemodify(bufname, ":p")
  for _, subdir in ipairs(source_dirs) do
    local prefix = vim.fs.joinpath(tostring(Obsidian.dir), subdir) .. "/"
    if abs:sub(1, #prefix) == prefix then
      return vim.fn.fnamemodify(abs, ":t:r")
    end
  end

  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, 20, false)) do
    local link = line:match "^source:%s*\"?%[%[(.-)%]%]\"?%s*$"
    if link then
      return vim.split(link, "|")[1] -- drop any [[stem|Alias]] label
    end
  end
  return nil
end

---@param template string|obsidian.Path template name or path
---@param stem string|? source note stem, substituted for `{{source}}`
---@param id string|? note id/title, nil for the default zettel id
local function create_from_template(template, stem, id)
  pending_source = stem
  local ok, err = pcall(function()
    local note = require("obsidian.note").create { id = id, template = template }
    note:write()
    note:open { sync = true }
  end)
  pending_source = nil
  if not ok then
    vim.notify("Failed to create note: " .. tostring(err), vim.log.levels.ERROR)
  end
end

-- Pick a source note. Always offers the full list, but the source implied by
-- the current buffer floats to the top. `callback` gets the chosen stem; it is
-- never called when the pick is aborted.
---@param callback fun(stem: string)
local function pick_source(callback)
  local notes = source_notes()
  if vim.tbl_isempty(notes) then
    vim.notify("No notes in " .. table.concat(source_dirs, " or "), vim.log.levels.WARN)
    return
  end

  local inferred = buffer_source_stem()
  local ordered = {}
  for _, note in ipairs(notes) do
    if note.stem == inferred then
      table.insert(ordered, 1, note)
    else
      ordered[#ordered + 1] = note
    end
  end

  ---@type obsidian.PickerEntry[]
  local entries = {}
  for _, note in ipairs(ordered) do
    local label = note.stem == inferred and note.label .. "  ← current" or note.label
    entries[#entries + 1] = {
      filename = note.path,
      text = label,
      ordinal = label .. " " .. note.stem,
      user_data = note.stem,
    }
  end

  Obsidian.picker.pick(entries, {
    prompt_title = "Reference source",
    format_item = function(entry)
      return entry.text or ""
    end,
    callback = function(entry)
      if entry and entry.user_data then
        callback(entry.user_data)
      end
    end,
  })
end

local function new_reference()
  pick_source(function(stem)
    create_from_template("reference.md", stem)
  end)
end

---@return string|? body of the template, nil when it cannot be read
local function template_body(template)
  local ok, path =
      pcall(require("obsidian.templates").resolve_template, template, require("obsidian.api").templates_dir())
  if not ok then
    return nil
  end
  local read_ok, lines = pcall(vim.fn.readfile, tostring(path))
  return read_ok and table.concat(lines, "\n") or nil
end

---@param body string|?
---@param var string
local function template_uses(body, var)
  return body ~= nil and body:find("{{" .. var .. "}}", 1, true) ~= nil
end

-- `Obsidian new_from_template`, except a template with a `{{source}}` resolves
-- it through the source picker instead of a free-text input. The picker is
-- async and template substitution is not, so the source has to be settled
-- before the note is created.
local function new_from_template()
  local api = require "obsidian.api"
  local templates_dir = api.templates_dir()
  if not templates_dir then
    vim.notify("Templates folder is not defined or does not exist", vim.log.levels.ERROR)
    return
  end

  Obsidian.picker.find_files {
    prompt_title = "Templates",
    dir = templates_dir,
    no_default_mappings = true,
    callback = function(template)
      if not template or template == "" then
        return
      end

      local body = template_body(template)

      -- Only ask when the template renders it. A template without `{{title}}`
      -- (reference.md) takes the default zettel id, so the answer is discarded.
      local id
      if template_uses(body, "title") then
        id = api.input("Enter title or path (optional)", { completion = "file" })
        if not id then
          return -- aborted
        elseif id == "" then
          id = nil
        end
      end

      -- No sources in this vault: fall through so `prompt_source` asks for the
      -- value instead, rather than blocking note creation on an empty picker.
      if template_uses(body, "source") and not vim.tbl_isempty(source_notes()) then
        pick_source(function(stem)
          create_from_template(template, stem, id)
        end)
      else
        create_from_template(template, nil, id)
      end
    end,
  }
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
    -- Template bodies use only `{{var}}` so the same files render in the
    -- Obsidian desktop app too, via the Templater shims in `templater/`.
    -- Keep this in sync with FILENAME in the vault's `scripts/render.js`.
    templates = {
      folder = "templates",
      substitutions = { source = prompt_source },
      customizations = {
        -- Slug filenames (with -2/-3 collision suffixes) instead of zettel ids.
        book = { notes_subdir = "sources", note_id_func = title_id },
        article = { notes_subdir = "sources", note_id_func = title_id },
        web = { notes_subdir = "sources", note_id_func = title_id },
        talk = { notes_subdir = "sources", note_id_func = title_id },
        reference = { notes_subdir = "references" },
      },
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
    { "<leader>on", new_from_template,                            desc = "New note from template" },
    { "<leader>or", new_reference,                                desc = "New reference from book/article" },
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
