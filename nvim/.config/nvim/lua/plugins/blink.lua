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
        ["obsidian-tasks"] = {
          module = "obsidian-tasks.cmp.source",
          name = "ObsidianTasks",
        },
      },
    },
  },
}
