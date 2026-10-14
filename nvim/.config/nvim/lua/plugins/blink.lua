-- Text typed after an unclosed `[[` before the cursor, i.e. what obsidian-ls searches for.
local function ref_query(ctx)
  local query = ctx.line:sub(1, ctx.cursor[2]):match("%[%[([^%[%]]*)$")
  -- `#` and `^` switch obsidian-ls to heading/block search; leave those alone.
  if query and query ~= "" and not query:find("[#^|]") then
    return query
  end
end

-- First line in `path` that contains `query` (case-insensitive), as lnum, line, start, end.
local function find_match(path, query)
  local file = io.open(path, "r")
  if not file then
    return
  end
  local needle = query:lower()
  local lnum = 0
  for line in file:lines() do
    lnum = lnum + 1
    local s, e = line:lower():find(needle, 1, true)
    if s then
      file:close()
      return lnum, line, s, e
    end
  end
  file:close()
end

-- obsidian-ls only exposes the note path through the documentation markdown.
local function doc_path(item)
  local doc = type(item.documentation) == "table" and item.documentation.value or item.documentation
  return type(doc) == "string" and doc:match("%*%*path:%*%* `([^`]+)`") or nil
end

-- Show the line a contents-only match came from: a snippet in the menu and the
-- full line (match in bold) in the documentation popup.
local function annotate_match(item, path, query)
  local doc = type(item.documentation) == "table" and item.documentation.value or item.documentation
  local lnum, line, s, e = find_match(path, query)
  if not lnum then
    return
  end

  local prefix = (line:sub(1, s - 1):gsub("^[%s>%-%*#]+", ""))
  local lead = vim.fn.strchars(prefix)
  if lead > 10 then
    prefix = "…" .. vim.fn.strcharpart(prefix, lead - 10)
  end
  item.labelDetails = vim.tbl_extend("force", item.labelDetails or {}, { description = prefix .. line:sub(s) })

  local marked = line:sub(1, s - 1) .. "**" .. line:sub(s, e) .. "**" .. line:sub(e + 1)
  item.documentation = {
    kind = "markdown",
    value = ("%s\n--------\n**line %d:**\n%s"):format(doc, lnum, marked),
  }
end

return {
  "Saghen/blink.cmp",
  opts = {
    keymap = {
      preset = "super-tab",
    },
    completion = {
      ghost_text = {
        enabled = false,
      },
    },
    sources = {
      default = { "lsp", "path", "snippets", "buffer", "obsidian-tasks" },
      providers = {
        lsp = {
          -- obsidian-ls already filters `[[` refs by name *and* contents, but blink
          -- re-filters on filterText (the note id/alias), dropping contents-only
          -- matches. Append the query so those survive blink's fuzzy pass, show
          -- the matching line so it is clear why the note is listed, and insert
          -- the query as the link label, e.g. `[[1791999992-RORV|superfans]]`.
          transform_items = function(ctx, items)
            local query = ref_query(ctx)
            if not query then
              return items
            end
            local result, seen = {}, {}
            for _, item in ipairs(items) do
              local filter = item.filterText or item.label
              local path = item.client_name == "obsidian-ls"
                and not filter:lower():find(query:lower(), 1, true)
                and doc_path(item)
              if path then
                item.filterText = filter .. " " .. query
                annotate_match(item, path, query)
                local ok, note = pcall(require("obsidian.note").from_file, path)
                if ok and item.textEdit then
                  item.textEdit.newText = note:format_link({ label = query })
                end
              end
              -- A note with aliases yields one item per alias; after relabeling
              -- they all insert the same link, so keep only the first.
              local key = path and item.textEdit and item.textEdit.newText
              if not key or not seen[key] then
                if key then
                  seen[key] = true
                end
                result[#result + 1] = item
              end
            end
            return result
          end,
        },
        ["obsidian-tasks"] = {
          module = "obsidian-tasks.cmp.source",
          name = "ObsidianTasks",
        },
      },
    },
  },
}
