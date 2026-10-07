#!/usr/bin/env bash
# Rank tmux panes by RSS (mem) or CPU% of all descendant processes.
# Pick one in fzf, jump to it or kill it.
#
# Usage: proc-tree.sh [mem|cpu] [--list]
#
# Keys inside fzf:
#   enter    switch to the pane
#   ctrl-x   kill the top offender PID (SIGTERM)
#   ctrl-k   kill the entire pane
#   ctrl-r   refresh
#   ctrl-t   toggle mem/cpu
set -euo pipefail

mode=mem
want_list=0
for arg in "$@"; do
  case "$arg" in
    mem|cpu) mode=$arg ;;
    --list)  want_list=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

list() {
  local tmp=/tmp/.tmux-proc-panes.$$
  tmux list-panes -a -F '#{pane_pid}	#{session_name}:#{window_index}.#{pane_index}	#{window_name}	#{pane_current_command}' > "$tmp"

  # Column 3 of ps output is either rss (KB) or %cpu depending on mode.
  local psfmt
  if [[ $mode == mem ]]; then psfmt='pid=,ppid=,rss=,comm='
  else                        psfmt='pid=,ppid=,%cpu=,comm='
  fi

  ps -axo "$psfmt" | awk -v panefile="$tmp" -v mode="$mode" '
  BEGIN {
    while ((getline line < panefile) > 0) {
      split(line, a, "\t")
      is_pane[a[1]] = 1
      LOC[a[1]]  = a[2]
      WIN[a[1]]  = a[3]
      PCMD[a[1]] = a[4]
    }
    close(panefile)
  }
  {
    i = ($1 == "" ? 2 : 1)
    pid=$i; ppid=$(i+1); val=$(i+2); comm=$(i+3)
    P[pid]=ppid; V[pid]=val; C[pid]=comm; ALL[pid]=1
  }
  END {
    for (pid in ALL) {
      p = pid; hops = 0
      while (p != "" && p != "0" && p != "1" && hops++ < 64) {
        if (p in is_pane) {
          TOTAL[p] += V[pid]
          COUNT[p] += 1
          if (V[pid]+0 > TOPV[p]+0) {
            TOPV[p] = V[pid]; TOPPID[p] = pid; TOPCMD[p] = C[pid]
          }
          break
        }
        if (!(p in P)) break
        p = P[p]
      }
    }
    for (p in TOTAL) {
      printf "%.3f\t%s\t%s\t%s\t%d\t%.3f\t%s\t%s\n", \
        TOTAL[p], LOC[p], WIN[p], PCMD[p], COUNT[p], TOPV[p], TOPPID[p], TOPCMD[p]
    }
  }' | sort -rn | awk -F'\t' -v mode="$mode" '
    function human_kb(kb,   u, i) {
      split("K M G T", u, " "); i=1
      while (kb >= 1024 && i < 4) { kb /= 1024; i++ }
      return sprintf("%6.1f%s", kb, u[i])
    }
    function fmt(v) {
      if (mode == "mem") return human_kb(v)
      return sprintf("%6.1f%%", v)
    }
    { printf "%s  %-14s  %-20s  %-10s  procs=%-3d  top=%s %s (pid %s)\n",
             fmt($1), $2, "["$3"]", $4, $5, fmt($6), $8, $7 }'

  rm -f "$tmp"
}

if (( want_list )); then list; exit 0; fi

self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
other=$([[ $mode == mem ]] && echo cpu || echo mem)
title=$([[ $mode == mem ]] && echo "TOTAL RSS" || echo "TOTAL CPU%")

choice=$(
  list | fzf \
    --ansi --no-sort --reverse \
    --header=$"$title   session:w.p    [window]              cmd         procs      top offender
enter=jump  C-x=kill PID  C-k=kill pane  C-r=refresh  C-t=switch to $other" \
    --preview-window=right:60%:wrap \
    --preview "loc=\$(echo {} | awk '{print \$2}'); tmux capture-pane -ep -t \$loc -S -200 2>/dev/null | tail -80" \
    --bind "ctrl-r:reload($self $mode --list)" \
    --expect=ctrl-x,ctrl-k,ctrl-t
) || exit 0

key=$(echo "$choice" | head -1)
line=$(echo "$choice" | sed -n '2p')
[[ -z $line ]] && exit 0

loc=$(echo "$line" | awk '{print $2}')
pid=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if ($i=="(pid") print $(i+1)}' | tr -d ')')

case "$key" in
  ctrl-x)
    [[ -n $pid ]] && kill "$pid" && tmux display-message "sent SIGTERM to $pid"
    ;;
  ctrl-k)
    tmux kill-pane -t "$loc" && tmux display-message "killed pane $loc"
    ;;
  ctrl-t)
    exec "$self" "$other"
    ;;
  *)
    sess=${loc%%:*}
    win=${loc%.*}
    tmux switch-client -t "$sess"
    tmux select-window -t "$win"
    tmux select-pane -t "$loc"
    ;;
esac
