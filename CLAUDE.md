# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code
in this repository.

## Repository Purpose

Personal dotfiles repository for managing application configurations across
machines using **GNU Stow**.

## Structure

Each top-level directory is a "stow package" that mirrors the structure it will
have in `$HOME`. Stow creates symlinks from the repo to the home directory.

**Example mapping:**

```plain
nvim/.config/nvim/lua/config/options.lua  →  ~/.config/nvim/lua/config/options.lua
zsh/.zprofile                             →  ~/.zprofile
git/.gitconfig                            →  ~/.gitconfig
```

## Working with Stow

```bash
# Install a package (creates symlinks in $HOME)
stow nvim

# Install multiple packages
stow zsh tmux git

# Install all packages
stow */

# Remove a package (removes symlinks)
stow -D nvim
```

## Making Changes

1. Edit files directly in the repository
2. Changes take effect immediately via symlinks
3. Commit to version control

## Notable Non-Standard Configurations

### Zsh Extensibility

The zsh configuration sources additional files from `~/.zprofile.d/`, allowing
environment-specific extensions (e.g., `n/` and `wsl/` packages add their own
zprofile.d files).

### Neovim Clipboard

The Neovim config (`nvim/.config/nvim/lua/config/options.lua`) uses a custom
clipboard integration that combines OSC52 (for SSH/remote clipboard) with tmux
buffer sharing. This is more complex than typical Neovim clipboard configs due
to the dual-sync mechanism.
