return {
  "mtrajano/tssorter.nvim",
  version = "*",
  opts = {
    sortables = {
      javascript = {
        imports = {
          node = "import_statement",
        },
        named_imports = {
          node = "import_specifier",
        },
        exports = {
          node = "export_statement",
        },
        object_properties = {
          node = "pair",
        },
      },
      typescript = {
        imports = {
          node = "import_statement",
        },
        named_imports = {
          node = "import_specifier",
        },
        exports = {
          node = "export_statement",
        },
        object_properties = {
          node = "pair",
        },
      },
      typescriptreact = {
        imports = {
          node = "import_statement",
        },
        named_imports = {
          node = "import_specifier",
        },
        exports = {
          node = "export_statement",
        },
        jsx_attributes = {
          node = "jsx_attribute",
        },
        object_properties = {
          node = "pair",
        },
      },
      javascriptreact = {
        imports = {
          node = "import_statement",
        },
        named_imports = {
          node = "import_specifier",
        },
        exports = {
          node = "export_statement",
        },
        jsx_attributes = {
          node = "jsx_attribute",
        },
        object_properties = {
          node = "pair",
        },
      },
    },
  },
}
