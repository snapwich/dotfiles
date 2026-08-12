#!/usr/bin/env zsh
# Run `gwtmux -dwB` from the window menu (prefix + < > Worktree Done).
#
# Runs inside a display-popup so it does not type into the pane's program.
# gwtmux is a shell function, so the popup must be an interactive-capable
# zsh that sources it first.

# The popup's own TMUX_PANE is not a valid target. Use the pane that opened
# the menu so gwtmux renames or kills the right window.
if [[ -n "${GWTMUX_PANE:-}" ]]; then
	export TMUX_PANE="$GWTMUX_PANE"
fi

source "${HOME}/.local/share/gwtmux/gwtmux.sh"

gwtmux -dwB
rc=$?

# Keep the popup open on failure so the error stays readable.
if [[ $rc -ne 0 ]]; then
	print -n "\ngwtmux exited $rc -- press any key to close..."
	read -rsk1
fi

exit $rc
