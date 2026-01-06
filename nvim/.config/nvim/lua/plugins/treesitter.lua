return {
  "nvim-treesitter/nvim-treesitter-textobjects",
  opts = function(_, opts)
    if opts.move and opts.move.keys then
      -- these conflicts with jumpto-diffs
      opts.move.keys.goto_next_start["]c"] = nil
      opts.move.keys.goto_next_end["]C"] = nil
      opts.move.keys.goto_previous_start["[c"] = nil
      opts.move.keys.goto_previous_end["[C"] = nil
    end
    return opts
  end,
}
