#!/usr/bin/env bash
# Extend the built-in window menu (prefix + <) with extra items.
#
# tmux has no "append to menu" command, but the menu is only a normal key
# binding holding an inline display-menu command. This script reads that
# binding, appends items, and re-binds the key. The pristine default is
# cached in a user option so a config reload does not append twice.

set -eu

table=prefix
key='<'
cache='@default-window-menu'

default="$(tmux show-options -gqv "$cache")"

if [ -z "$default" ]; then
	default="$(
		tmux list-keys -T "$table" "$key" |
			sed -E "s/^bind-key[[:space:]]+-T[[:space:]]+${table}[[:space:]]+${key}[[:space:]]+//"
	)"
	tmux set-option -g "$cache" "$default"
fi

# Extra items: name, key shortcut, command. The whole menu must be one
# argument, so append to the default string instead of passing new words.
#
# gwtmux runs in a popup, not the pane: send-keys would type the command
# into whatever program owns the pane (a REPL, an editor, Claude Code).
# The popup has its own tty, so gwtmux can still prompt.
#
# Inside a popup, TMUX_PANE is the popup's own pane and is not a usable
# target, so the invoking pane is passed in GWTMUX_PANE and the wrapper
# exports it as TMUX_PANE for gwtmux's window lookups.
extra="'' 'Worktree Done' d { display-popup -E -d '#{pane_current_path}' -e 'GWTMUX_PANE=#{pane_id}' '~/.config/tmux/gwtmux-done.sh' }"

tmux bind-key -T "$table" "$key" "$default $extra"
