#!/usr/bin/env bash
# Sort the windows of a session by @priority: high, medium, low, then no
# priority. Windows with the same priority keep their order.
#
# Usage: priority-sort.sh <window-id>
#
# The window id selects the session. A window id is passed (not a session
# id) because run-shell gives the command to sh, and sh expands a '$1'
# session id as a positional parameter.

set -eu

session="$(tmux display-message -p -t "$1" '#{session_id}')"
active="$(tmux display-message -p -t "$session" '#{window_id}')"

# rank<TAB>index<TAB>id, sorted by rank, then by index for a stable order.
# The index list stays in index order: those are the slots to fill.
mapfile -t slots < <(tmux list-windows -t "$session" -F '#{window_index}')
mapfile -t wanted < <(
	tmux list-windows -t "$session" -F '#{?#{==:#{@priority},high},0,#{?#{==:#{@priority},medium},1,#{?#{==:#{@priority},low},2,3}}}	#{window_index}	#{window_id}' |
		sort -t "$(printf '\t')" -k1,1n -k2,2n |
		cut -f3
)

# Fill each slot with the window that belongs there. swap-window moves the
# window in that slot to where the wanted window was, so every slot before
# this one stays correct.
for i in "${!slots[@]}"; do
	current="$(tmux display-message -p -t "$session:${slots[$i]}" '#{window_id}')"
	if [ "$current" != "${wanted[$i]}" ]; then
		tmux swap-window -d -s "${wanted[$i]}" -t "$current"
	fi
done

# swap-window can change the current window, so go back to the one that was
# current. The client stays on the same window, at its new index.
tmux select-window -t "$active"
