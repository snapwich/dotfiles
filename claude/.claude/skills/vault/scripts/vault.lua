-- Headless worker for the `vault` script. Run inside a full nvim config so
-- obsidian.nvim and obsidian-tasks.nvim are loaded:
--
--   VAULT_ROOT=… VAULT_ARGS='[json argv]' VAULT_OUT=file \
--     nvim --headless -n -c "luafile vault.lua"
--
-- Results go to VAULT_OUT (nvim's own stdout/stderr carry plugin noise).
-- Exit codes: 0 ok, 1 error, 2 refused (needs --force).

local ROOT = vim.fs.normalize(assert(os.getenv("VAULT_ROOT"), "VAULT_ROOT not set"))
local ARGS = vim.json.decode(os.getenv("VAULT_ARGS") or "[]")
local OUT = assert(os.getenv("VAULT_OUT"), "VAULT_OUT not set")

local out = {}
local function say(s)
  out[#out + 1] = s
end

local Refused = {}
local function fail(msg)
  error({ msg = msg }, 0)
end
local function refuse(msg)
  error({ msg = msg, refused = Refused }, 0)
end

-- ── args ──────────────────────────────────────────────────────────────────────

--- Split argv into flags and positionals. `--` ends flags.
local function parse_args(argv, bool_flags)
  local flags, pos = {}, {}
  local i = 1
  while i <= #argv do
    local a = argv[i]
    if a == "--" then
      for j = i + 1, #argv do
        pos[#pos + 1] = argv[j]
      end
      break
    end
    local name = a:match("^%-%-([%w-]+)$")
    if name then
      if bool_flags[name] then
        flags[name] = true
      else
        i = i + 1
        if argv[i] == nil then
          fail("--" .. name .. " needs a value")
        end
        flags[name] = argv[i]
      end
    else
      pos[#pos + 1] = a
    end
    i = i + 1
  end
  return flags, pos
end

-- ── files ─────────────────────────────────────────────────────────────────────

local function rel(abs)
  abs = vim.fs.normalize(abs)
  if abs:sub(1, #ROOT + 1) == ROOT .. "/" then
    return abs:sub(#ROOT + 2)
  end
  return abs
end

local function abs_path(p)
  if p:sub(1, 1) == "/" then
    return vim.fs.normalize(p)
  end
  return vim.fs.normalize(ROOT .. "/" .. p)
end

local function read(path)
  if vim.fn.filereadable(path) == 0 then
    fail("no such file: " .. rel(path))
  end
  return vim.fn.readfile(path)
end

local function write(path, lines)
  if vim.fn.writefile(lines, path) ~= 0 then
    fail("write failed: " .. rel(path))
  end
end

-- ── obsidian.nvim ─────────────────────────────────────────────────────────────

-- obsidian.nvim resolves daily notes against its CURRENT workspace, which comes
-- from OBSIDIAN_WORKSPACE / cwd, not from VAULT_ROOT. Always switch to ROOT so
-- a write can never land in a different vault.
local function use_workspace()
  if type(Obsidian) ~= "table" then
    fail("obsidian.nvim is not loaded")
  end
  local W = require("obsidian.workspace")
  local target
  for _, ws in ipairs(Obsidian.workspaces or {}) do
    if vim.fs.normalize(tostring(ws.root)) == ROOT then
      target = ws
    end
  end
  target = target or W.new({ name = vim.fs.basename(ROOT), path = ROOT })
  if not (Obsidian.workspace and vim.fs.normalize(tostring(Obsidian.workspace.root)) == ROOT) then
    W.set(target)
  end
  if vim.fs.normalize(tostring(Obsidian.dir)) ~= ROOT then
    fail("could not switch obsidian.nvim to " .. ROOT)
  end
end

local function parse_date(s)
  if s == nil or s == "today" then
    return os.time()
  end
  local y, m, d = s:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
  if not y then
    fail("date must be YYYY-MM-DD: " .. s)
  end
  return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

--- Path of the daily note for *date*; create it from the template when
--- *create* is set and it does not exist.
local function daily_path(date, create)
  use_workspace()
  local note = require("obsidian.daily").daily({ date = parse_date(date), dir = ROOT })
  local path = vim.fs.normalize(tostring(note.path))
  if path:sub(1, #ROOT + 1) ~= ROOT .. "/" then
    fail("daily note resolved outside the vault: " .. path)
  end
  local created = false
  if create and not note:exists() then
    note:write()
    created = true
  end
  return path, created
end

-- ── task lines ────────────────────────────────────────────────────────────────

local list_block = require("obsidian-tasks.util.list_block")
local md_structure = require("obsidian-tasks.util.md_structure")

local function indent_of(line)
  return line:match("^(%s*)")
end

--- Task text → list line(s). First positional is the task; any more are
--- child bullets under it. Text that is already a list item is kept as-is.
local function build_lines(texts, indent)
  if #texts == 0 then
    fail("missing task text")
  end
  local lines = {}
  for i, t in ipairs(texts) do
    t = vim.trim(t)
    local body
    if t:match("^[-*+] ") then
      body = t
    elseif i == 1 then
      body = "- [ ] " .. t
    else
      body = "- " .. t
    end
    lines[#lines + 1] = (i == 1 and indent or indent .. "  ") .. body
  end
  return lines
end

--- Resolve REF (`path:line`) + the --expect fragment to a 1-indexed line.
--- When the line moved, relocate it by a unique match in the same file.
local function resolve_ref(ref, expect)
  local p, n = (ref or ""):match("^(.-):(%d+)$")
  if not p then
    fail("ref must be path:line, got: " .. tostring(ref))
  end
  if not expect or expect == "" then
    fail("--expect TEXT is required with a ref")
  end
  local path = abs_path(p)
  local lines = read(path)
  local want = expect:lower()
  local function hit(i)
    return lines[i] and lines[i]:lower():find(want, 1, true) ~= nil
  end
  local lnum = tonumber(n)
  if not hit(lnum) then
    local found = {}
    for i = 1, #lines do
      if hit(i) then
        found[#found + 1] = i
      end
    end
    if #found ~= 1 then
      fail(
        string.format(
          "%s:%d does not contain %q (%d other matches in file)",
          rel(path),
          lnum,
          expect,
          #found
        )
      )
    end
    say(string.format("note: relocated %s:%d -> %s:%d", rel(path), lnum, rel(path), found[1]))
    lnum = found[1]
  end
  return path, lines, lnum
end

--- 1-indexed last line of the item at *lnum* and its subtree.
local function block_last(lines, lnum)
  return list_block.continuation_end(lines, lnum - 1, #indent_of(lines[lnum]))
end

local function heading_of(lines, lnum)
  local st = md_structure.scan(lines)
  for i = lnum, 1, -1 do
    local h = st.heading(i)
    if h then
      return h
    end
  end
end

local function report(verb, path, first, new_lines, where)
  for k, l in ipairs(new_lines) do
    if k == 1 or l:match("^%s*[-*+] ") then
      say(string.format("%-7s %s:%d  %s", k == 1 and verb or "", rel(path), first + k - 1, vim.trim(l)))
    end
  end
  if where then
    say("  in " .. where)
  end
end

local function insert(path, lines, at, new_lines)
  for k = #new_lines, 1, -1 do
    table.insert(lines, at + 1, new_lines[k])
  end
  write(path, lines)
end

-- ── commands ──────────────────────────────────────────────────────────────────

local cmds = {}

function cmds.info()
  local path = daily_path(nil, false)
  say("vault: " .. ROOT)
  say("today: " .. rel(path) .. (vim.fn.filereadable(path) == 1 and "" or " (not created yet)"))
  local dash = ROOT .. "/tasks.md"
  say("dashboard: " .. (vim.fn.filereadable(dash) == 1 and "tasks.md" or "(none)"))
end

--- Render a dashboard and print it with a source ref on each task row.
function cmds.tasks(argv)
  local flags = parse_args(argv, {})
  local dash = abs_path(flags.file or "tasks.md")
  read(dash)
  local render = require("obsidian-tasks.render")
  -- The first render starts an async vault walk; its callback re-renders. That
  -- re-render is the complete state, so wait for it.
  local done = false
  local orig = render.rerender_buffer
  render.rerender_buffer = function(...)
    local r = { orig(...) }
    done = true
    return unpack(r)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(dash))
  local buf = vim.api.nvim_get_current_buf()
  if not vim.wait(15000, function()
    return done
  end, 20) then
    say("warning: render did not finish in 15s; output may be partial")
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local meta = {}
  for _, block in ipairs(render._buffer_state[buf] or {}) do
    for lnum, m in pairs(block.line_map or {}) do
      meta[lnum] = m
    end
  end
  local headers = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    local row, d = m[2], m[4]
    if d.virt_lines and d.virt_lines_above then
      headers[row] = headers[row] or {}
      for _, vl in ipairs(d.virt_lines) do
        local s = {}
        for _, chunk in ipairs(vl) do
          s[#s + 1] = chunk[1]
        end
        local text = vim.trim(table.concat(s))
        if text ~= "" then
          table.insert(headers[row], text)
        end
      end
    end
  end

  local group_filter = flags.group and flags.group:lower()
  local match = flags.match and flags.match:lower()
  local st = md_structure.scan(lines)
  local in_group = group_filter == nil
  -- A group header prints only once a task under it prints.
  local pending
  for i, l in ipairs(lines) do
    local row = i - 1
    for _, h in ipairs(headers[row] or {}) do
      -- Skip query footers ("─ sorted: … │ N results ─").
      if not h:match("^─") then
        local name = h:gsub("^#+%s*", "")
        if group_filter then
          in_group = name:lower():find(group_filter, 1, true) ~= nil
        end
        pending = in_group and ("## " .. name) or nil
      end
    end
    local m = meta[row]
    if m and in_group then
      local text = l
      local stem = m.src_path and vim.fn.fnamemodify(m.src_path, ":t:r")
      text = text:gsub("%s*%[%[([^%]]-)%]%]$", function(link)
        if link:gsub("|.*", "") == stem then
          return ""
        end
      end)
      if not match or text:lower():find(match, 1, true) then
        if pending then
          say(pending)
          pending = nil
        end
        local ref = m.src_path and m.src_line and string.format("%s:%d", rel(m.src_path), m.src_line) or ""
        say(string.format("%-24s %s", ref, text))
      end
    elseif not m and not st.code[i] and st.heading(i) and not group_filter and not match then
      say("# " .. st.heading(i))
    end
  end
end

--- Add a task (plus optional child bullets).
function cmds.add(argv)
  local flags, texts = parse_args(argv, { ["no-heading"] = true })
  local modes = (flags.below and 1 or 0) + (flags.under and 1 or 0) + (flags.heading and 1 or 0)
    + (flags["no-heading"] and 1 or 0)
  if modes ~= 1 then
    fail("add needs exactly one of --below REF, --under REF, --heading H, --no-heading")
  end

  if flags.below or flags.under then
    local path, lines, lnum = resolve_ref(flags.below or flags.under, flags.expect)
    local anchor_indent = indent_of(lines[lnum])
    local indent = anchor_indent
    if flags.under then
      -- Match an existing child's indent, else two more spaces.
      local nxt = lines[lnum + 1]
      if nxt and nxt:match("^%s*[-*+] ") and #indent_of(nxt) > #anchor_indent then
        indent = indent_of(nxt)
      else
        indent = anchor_indent .. "  "
      end
    end
    local at = block_last(lines, lnum)
    local new_lines = build_lines(texts, indent)
    insert(path, lines, at, new_lines)
    report("added", path, at + 1, new_lines, heading_of(lines, at + 1) and ("## " .. heading_of(lines, at + 1)))
    return
  end

  local path, created = daily_path(flags.date, true)
  local lines = read(path)
  local new_lines = build_lines(texts, "")
  local heading = flags.heading
  local placement = require("obsidian-tasks.render.note_placement")
  local p = placement.place(lines, heading, 2, new_lines)
  for k = #p.lines_to_insert, 1, -1 do
    table.insert(lines, p.row + 1, p.lines_to_insert[k])
  end
  write(path, lines)
  -- Find where the task line landed.
  local first = p.row + 1
  for k, l in ipairs(p.lines_to_insert) do
    if l == new_lines[1] then
      first = p.row + k
      break
    end
  end
  local where = heading and ("## " .. heading .. (p.created_heading and " (new heading)" or "")) or "(no heading)"
  if created then
    where = where .. ", new daily note"
  end
  report("added", path, first, new_lines, where)
end

local STATUS = { done = "x", undone = " ", cancel = "-", start = "/" }

local function set_status(cmd, argv)
  local flags, pos = parse_args(argv, {})
  local path, lines, lnum = resolve_ref(pos[1], flags.expect)
  local l = lines[lnum]
  local pre, sym, post = l:match("^(%s*[-*+] %[)(.)(%].*)$")
  if not pre then
    fail(rel(path) .. ":" .. lnum .. " is not a task: " .. l)
  end
  lines[lnum] = pre .. STATUS[cmd] .. post
  if sym == STATUS[cmd] then
    say(string.format("unchanged %s:%d  %s", rel(path), lnum, vim.trim(l)))
    return
  end
  write(path, lines)
  report(cmd, path, lnum, { lines[lnum] }, heading_of(lines, lnum) and ("## " .. heading_of(lines, lnum)))
end

for name in pairs(STATUS) do
  cmds[name] = function(argv)
    set_status(name, argv)
  end
end

--- Replace a task's text, keeping its indent and status.
function cmds.set(argv)
  local flags, pos = parse_args(argv, {})
  local path, lines, lnum = resolve_ref(pos[1], flags.expect)
  local text = pos[2] and vim.trim(pos[2])
  if not text or text == "" then
    fail("set REF --expect T \"new text\"")
  end
  local pre = lines[lnum]:match("^(%s*[-*+] %[.%] )") or lines[lnum]:match("^(%s*[-*+] )")
  if not pre then
    fail(rel(path) .. ":" .. lnum .. " is not a list item")
  end
  local old = lines[lnum]
  lines[lnum] = pre .. text:gsub("^[-*+] %[.%] ", ""):gsub("^[-*+] ", "")
  write(path, lines)
  say(string.format("%-7s %s:%d  %s", "was", rel(path), lnum, vim.trim(old)))
  report("now", path, lnum, { lines[lnum] })
end

--- Delete a task and its subtree. Refuses a subtree without --force.
function cmds.delete(argv)
  local flags, pos = parse_args(argv, { force = true })
  local path, lines, lnum = resolve_ref(pos[1], flags.expect)
  local last = block_last(lines, lnum)
  local block = {}
  for i = lnum, last do
    block[#block + 1] = lines[i]
  end
  if #block > 1 and not flags.force then
    say(string.format("refused: %s:%d has %d line(s) under it:", rel(path), lnum, #block - 1))
    for _, l in ipairs(block) do
      say("  " .. l)
    end
    refuse("re-run with --force to delete all of them")
  end
  for _ = lnum, last do
    table.remove(lines, lnum)
  end
  write(path, lines)
  say(string.format("deleted %s:%d  %s%s", rel(path), lnum, vim.trim(block[1]), #block > 1 and
    string.format(" (+%d line(s) under it)", #block - 1) or ""))
end

--- Add prose under a heading of a daily note (end of that section).
function cmds.note(argv)
  local flags, texts = parse_args(argv, {})
  if #texts == 0 then
    fail("missing note text")
  end
  local path, created = daily_path(flags.date, true)
  local lines = read(path)
  local st = md_structure.scan(lines)
  local n = st.open_fence and st.open_fence - 1 or #lines
  local body = {}
  for _, t in ipairs(texts) do
    vim.list_extend(body, vim.split(t, "\n", { plain = true }))
  end

  local h_row
  if flags.heading then
    for i = 1, n do
      if st.heading(i) == flags.heading then
        h_row = i
      end
    end
  end
  local at, new_lines, where
  if flags.heading and not h_row then
    -- New section at the end of the note.
    at = n
    while at > st.body_start and list_block.is_blank(lines[at]) do
      at = at - 1
    end
    new_lines = vim.list_extend({ "", "## " .. flags.heading, "" }, body)
    where = "## " .. flags.heading .. " (new heading)"
  else
    local from = h_row or st.body_start
    local to = n
    for i = from + 1, n do
      if st.heading(i) then
        to = i - 1
        break
      end
    end
    at = to
    while at > from and list_block.is_blank(lines[at]) do
      at = at - 1
    end
    new_lines = vim.list_extend({ "" }, body)
    -- Keep a blank between the prose and a heading that follows directly.
    if lines[at + 1] ~= nil and not list_block.is_blank(lines[at + 1]) then
      table.insert(new_lines, "")
    end
    where = h_row and ("## " .. flags.heading) or "(no heading)"
  end
  insert(path, lines, at, new_lines)
  say(string.format("noted   %s:%d  %s%s", rel(path), at + 2, body[1], #body > 1 and " …" or ""))
  say("  in " .. where .. (created and ", new daily note" or ""))
end

--- Print a daily note (path + content). Never creates one.
function cmds.daily(argv)
  local flags = parse_args(argv, {})
  local path = daily_path(flags.date, false)
  if vim.fn.filereadable(path) == 0 then
    say(rel(path) .. " (does not exist)")
    return
  end
  say("== " .. rel(path))
  for i, l in ipairs(read(path)) do
    say(string.format("%4d  %s", i, l))
  end
end

-- ── main ──────────────────────────────────────────────────────────────────────

local function main()
  local cmd = table.remove(ARGS, 1)
  if not cmd or not cmds[cmd] then
    fail("unknown command: " .. tostring(cmd))
  end
  cmds[cmd](ARGS)
end

local ok, err = xpcall(main, function(e)
  if type(e) == "table" then
    return e
  end
  return { msg = debug.traceback(tostring(e), 2) }
end)
local code = 0
if not ok then
  say("error: " .. err.msg)
  code = err.refused == Refused and 2 or 1
end
vim.fn.writefile(out, OUT)
vim.cmd(code == 0 and "qa!" or ("cq " .. code))
