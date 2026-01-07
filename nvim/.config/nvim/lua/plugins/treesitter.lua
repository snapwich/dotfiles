return {
  "nvim-treesitter/nvim-treesitter-textobjects",
  opts = function(_, opts)
    if opts.move and opts.move.keys then
      -- disable [c ]c for diffview jumpto-diffs
      opts.move.keys.goto_next_start["]c"] = nil
      opts.move.keys.goto_previous_start["[c"] = nil
      -- remap [C ]C to prev/next class start
      opts.move.keys.goto_previous_start["[C"] = "@class.outer"
      opts.move.keys.goto_next_start["]C"] = "@class.outer"
    end
    return opts
  end,
}
