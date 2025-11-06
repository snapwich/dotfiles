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
        interface_properties = {
          node = "property_signature",
        },
        interface_methods = {
          node = "method_signature",
        },
        enum_members = {
          node = "enum_assignment",
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
        interface_properties = {
          node = "property_signature",
        },
        interface_methods = {
          node = "method_signature",
        },
        enum_members = {
          node = "enum_assignment",
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
