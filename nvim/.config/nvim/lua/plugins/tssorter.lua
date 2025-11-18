-- lua/plugins/tssorter.lua

-- shared flag used by all sortables' order_by
local ignore_case = true

-- lazy-load tshelper only when needed
local tshelper

local function default_order_by(node1, node2, ordinal1, ordinal2)
  tshelper = tshelper or require("tssorter.tshelper")

  -- (this is basically the plugin's default, with case toggle support)
  if ordinal1 and ordinal2 then
    if ignore_case then
      if type(ordinal1) == "string" then ordinal1 = ordinal1:lower() end
      if type(ordinal2) == "string" then ordinal2 = ordinal2:lower() end
    end

    if ordinal1 ~= ordinal2 then
      return ordinal1 < ordinal2
    end
  end

  local line1 = tshelper.get_text(node1)
  local line2 = tshelper.get_text(node2)

  if ignore_case then
    line1 = line1:lower()
    line2 = line2:lower()
  end

  return line1 < line2
end

return {
  "mtrajano/tssorter.nvim",
  version = "*",

  -- 1) keymaps live in the plugin spec
  keys = {
    {
      "<leader>cs",
      function()
        ignore_case = true
        require("tssorter").sort()
      end,
      desc = "Sort code (TSSort, case-insensitive)",
    },
    {
      "<leader>cS",
      function()
        ignore_case = false
        require("tssorter").sort()
      end,
      desc = "Sort code (TSSort, case-sensitive)",
    },
  },

  -- 2) wire the shared order_by into all sortables
  opts = {
    sortables = {
      javascript = {
        imports = {
          node = "import_statement",
          order_by = default_order_by,
        },
        named_imports = {
          node = "import_specifier",
          order_by = default_order_by,
        },
        exports = {
          node = "export_statement",
          order_by = default_order_by,
        },
        object_properties = {
          node = "pair",
          order_by = default_order_by,
        },
      },
      typescript = {
        imports = {
          node = "import_statement",
          order_by = default_order_by,
        },
        named_imports = {
          node = "import_specifier",
          order_by = default_order_by,
        },
        exports = {
          node = "export_statement",
          order_by = default_order_by,
        },
        object_properties = {
          node = "pair",
          order_by = default_order_by,
        },
        interface_properties = {
          node = "property_signature",
          order_by = default_order_by,
        },
        interface_methods = {
          node = "method_signature",
          order_by = default_order_by,
        },
        enum_members = {
          node = "enum_assignment", -- or "enum_member" depending on your TS grammar
          order_by = default_order_by,
        },
      },
      typescriptreact = {
        imports = {
          node = "import_statement",
          order_by = default_order_by,
        },
        named_imports = {
          node = "import_specifier",
          order_by = default_order_by,
        },
        exports = {
          node = "export_statement",
          order_by = default_order_by,
        },
        jsx_attributes = {
          node = "jsx_attribute",
          order_by = default_order_by,
        },
        object_properties = {
          node = "pair",
          order_by = default_order_by,
        },
        interface_properties = {
          node = "property_signature",
          order_by = default_order_by,
        },
        interface_methods = {
          node = "method_signature",
          order_by = default_order_by,
        },
        enum_members = {
          node = "enum_assignment",
          order_by = default_order_by,
        },
      },
      javascriptreact = {
        imports = {
          node = "import_statement",
          order_by = default_order_by,
        },
        named_imports = {
          node = "import_specifier",
          order_by = default_order_by,
        },
        exports = {
          node = "export_statement",
          order_by = default_order_by,
        },
        jsx_attributes = {
          node = "jsx_attribute",
          order_by = default_order_by,
        },
        object_properties = {
          node = "pair",
          order_by = default_order_by,
        },
      },
    },
  },
}
