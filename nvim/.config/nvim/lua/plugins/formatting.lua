return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        markdown = { "markdownlint-cli2", "markdown-toc" },
        ["markdown.mdx"] = { "markdownlint-cli2", "markdown-toc" },
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- mason-lspconfig enables every installed server, and oxfmt claims
        -- markdown. Conform then falls back to it when no markdown formatter
        -- applies, and it joins tab-indented list lines into the paragraph.
        oxfmt = { enabled = false },
      },
    },
  },
}
