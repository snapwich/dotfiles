#!/usr/bin/env bash
# Rank tmux panes by RSS (mem) or CPU% of all descendant processes.
# Pick one in fzf, jump to it or kill it.
#
# Processes are tied to a pane by walking up the ppid chain. If that fails
# (the process was reparented, e.g. its pane was closed), fall back to the
# TMUX / TMUX_PANE vars it inherited. Processes whose pane no longer exists
# are grouped in a "dead:%N" row.
#
# CPU% is sampled over a short interval (like top/htop), not the lifetime
# average that ps reports. Reads /proc, so Linux only.
#
# Usage: proc-tree.sh [mem|cpu] [--list]
#
# Keys inside fzf:
#   enter    switch to the pane
#   ctrl-x   kill the top offender PID (SIGTERM, SIGKILL after 2s), stay open
#   ctrl-k   kill the entire pane (dead pane: kill all its processes)
#   ctrl-r   refresh
#   ctrl-t   toggle mem/cpu
set -euo pipefail

mode=mem
want_list=0
preview_loc=
kill_line=
while (( $# )); do
  case "$1" in
    mem|cpu)     mode=$1 ;;
    --list)      want_list=1 ;;
    --preview)   preview_loc=$2; shift ;;
    --kill-line) kill_line=$2; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

sample_secs=0.5
hz=$(getconf CLK_TCK)
page_kb=$(( $(getconf PAGESIZE) / 1024 ))

# One line per process: pid ppid cpu_ticks rss_kb comm (tab separated).
snapshot() {
  { cat /proc/[0-9]*/stat 2>/dev/null || true; } | awk -v page_kb="$page_kb" '
  {
    # comm may contain spaces or parens; it ends at the last ")".
    s = index($0, "(")
    match($0, /\)[^)]*$/)
    pid  = substr($0, 1, s - 2)
    comm = substr($0, s + 1, RSTART - s - 1)
    gsub(/[ \t]/, "_", comm)
    split(substr($0, RSTART + 2), f, " ")
    # f[2]=ppid f[12]=utime f[13]=stime f[22]=rss (pages)
    printf "%s\t%s\t%d\t%d\t%s\n", pid, f[2], f[12] + f[13], f[22] * page_kb, comm
  }'
}

# Prints pid<TAB>ppid<TAB>value<TAB>comm, value is RSS KB or CPU%.
proc_values() {
  if [[ $mode == mem ]]; then
    snapshot | awk -F'\t' -v OFS='\t' '{ print $1, $2, $4, $5 }'
    return
  fi
  local a b t0 t1
  a=$(mktemp); b=$(mktemp)
  t0=$EPOCHREALTIME; snapshot > "$a"
  sleep "$sample_secs"
  t1=$EPOCHREALTIME; snapshot > "$b"
  awk -F'\t' -v OFS='\t' -v hz="$hz" -v dt="$(awk -v a="$t0" -v b="$t1" 'BEGIN { print b - a }')" '
    FNR == NR { T0[$1] = $3; next }
    {
      d = $3 - ($1 in T0 ? T0[$1] : 0)
      if (d < 0) d = 0
      printf "%s\t%s\t%.3f\t%s\n", $1, $2, d * 100 / (hz * dt), $5
    }' "$a" "$b"
  rm -f "$a" "$b"
}

# TMUX var prefix for processes started by this tmux server.
tmux_env_prefix() { tmux display -p '#{socket_path},#{pid},'; }

# PIDs of processes that inherited TMUX_PANE=$1 from this server.
pane_env_pids() {
  local prefix
  prefix=$(tmux_env_prefix)
  { grep -azH -e '^TMUX=' -e '^TMUX_PANE=' /proc/[0-9]*/environ 2>/dev/null || true; } \
    | tr '\0' '\n' | awk -v id="$1" -v prefix="$prefix" '
      {
        split($0, a, "/"); pid = a[3]
        kv = substr($0, index($0, ":") + 1)
        if (kv == "TMUX_PANE=" id) hit[pid] = 1
        else if (index(kv, "TMUX=" prefix) == 1) ours[pid] = 1
      }
      END { for (p in hit) if (p in ours) print p }'
}

# SIGTERM, then SIGKILL whatever is still alive after 2s. A process stuck in
# a busy loop (e.g. nvim) catches SIGTERM but never returns to its event loop
# to act on it.
terminate() {
  local alive p
  kill "$@" 2>/dev/null || true
  for _ in {1..20}; do
    alive=$(for p in "$@"; do [[ $(ps -o stat= -p "$p") == [^Z]* ]] && echo "$p" || true; done)
    [[ -z $alive ]] && { tmux display-message "terminated $*"; return; }
    sleep 0.1
  done
  kill -KILL $alive 2>/dev/null || true
  tmux display-message "ignored SIGTERM, sent SIGKILL to $(echo $alive)"
}

list() {
  local panes envs
  panes=$(mktemp); envs=$(mktemp)
  tmux list-panes -a -F '#{pane_pid}	#{pane_id}	#{session_name}:#{window_index}.#{pane_index}	#{window_name}	#{pane_current_command}' > "$panes"
  { grep -azH -e '^TMUX=' -e '^TMUX_PANE=' /proc/[0-9]*/environ 2>/dev/null || true; } | tr '\0' '\n' > "$envs"

  proc_values | awk -F'\t' -v panefile="$panes" -v envfile="$envs" \
    -v server="$(tmux display -p '#{pid}')" -v prefix="$(tmux_env_prefix)" '
  BEGIN {
    while ((getline line < panefile) > 0) {
      split(line, a, "\t")
      is_pane[a[1]] = 1
      PANE_OF_ID[a[2]] = a[1]
      LOC[a[1]]  = a[3]
      WIN[a[1]]  = a[4]
      PCMD[a[1]] = a[5]
    }
    close(panefile)
    # Lines look like /proc/<pid>/environ:TMUX_PANE=%5
    while ((getline line < envfile) > 0) {
      split(line, a, "/"); pid = a[3]
      kv = substr(line, index(line, ":") + 1)
      if (kv ~ /^TMUX_PANE=/)                 EPANE[pid] = substr(kv, 11)
      else if (index(kv, "TMUX=" prefix) == 1) OURS[pid] = 1
    }
    close(envfile)
  }
  {
    pid=$1; ppid=$2; val=$3; comm=$4
    P[pid]=ppid; V[pid]=val; C[pid]=comm; ALL[pid]=1
  }
  END {
    for (pid in ALL) {
      owner = ""; p = pid; hops = 0
      while (p != "" && p != "0" && hops++ < 64) {
        if (p in is_pane) { owner = p; break }
        # Under the server but not a pane: popups, run-shell, this script.
        if (p == server)  { owner = "-"; break }
        if (!(p in P)) break
        p = P[p]
      }
      if (owner == "-") continue
      if (owner == "") {
        if (!(pid in OURS) || !(pid in EPANE)) continue
        id = EPANE[pid]
        if (id in PANE_OF_ID) owner = PANE_OF_ID[id]
        else {
          owner = id
          LOC[id] = "dead:" id; WIN[id] = "pane closed"; PCMD[id] = "-"
        }
      }
      TOTAL[owner] += V[pid]
      COUNT[owner] += 1
      if (V[pid]+0 > TOPV[owner]+0 || !(owner in TOPPID)) {
        TOPV[owner] = V[pid]; TOPPID[owner] = pid; TOPCMD[owner] = C[pid]
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

  rm -f "$panes" "$envs"
}

top_pid() { awk '{for(i=1;i<=NF;i++) if ($i=="(pid") print $(i+1)}' <<< "$1" | tr -d ')'; }

if (( want_list )); then list; exit 0; fi

if [[ -n $kill_line ]]; then
  pid=$(top_pid "$kill_line")
  [[ -n $pid ]] && terminate "$pid"
  exit 0
fi

if [[ -n $preview_loc ]]; then
  if [[ $preview_loc == dead:* ]]; then
    pids=$(pane_env_pids "${preview_loc#dead:}" | paste -sd,)
    [[ -n $pids ]] && ps -o pid,ppid,etime,time,rss,stat,args -p "$pids"
  else
    tmux capture-pane -ep -t "$preview_loc" -S -200 2>/dev/null | tail -80
  fi
  exit 0
fi

self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
other=$([[ $mode == mem ]] && echo cpu || echo mem)
title=$([[ $mode == mem ]] && echo "TOTAL RSS" || echo "TOTAL CPU%")

choice=$(
  list | fzf \
    --ansi --no-sort --reverse \
    --header=$"$title   session:w.p    [window]              cmd         procs      top offender
enter=jump  C-x=kill PID  C-k=kill pane  C-r=refresh  C-t=switch to $other" \
    --preview-window=right:60%:wrap \
    --preview "$self --preview \$(echo {} | awk '{print \$2}')" \
    --bind "ctrl-r:reload($self $mode --list)" \
    --bind "ctrl-x:execute-silent($self --kill-line {})+reload($self $mode --list)" \
    --expect=ctrl-k,ctrl-t
) || exit 0

key=$(echo "$choice" | head -1)
line=$(echo "$choice" | sed -n '2p')
[[ -z $line ]] && exit 0

loc=$(echo "$line" | awk '{print $2}')

case "$key" in
  ctrl-k)
    if [[ $loc == dead:* ]]; then
      pids=$(pane_env_pids "${loc#dead:}")
      [[ -n $pids ]] && terminate $pids
    else
      tmux kill-pane -t "$loc" && tmux display-message "killed pane $loc"
    fi
    ;;
  ctrl-t)
    exec "$self" "$other"
    ;;
  *)
    if [[ $loc == dead:* ]]; then
      tmux display-message "pane ${loc#dead:} is gone"
      exit 0
    fi
    sess=${loc%%:*}
    win=${loc%.*}
    tmux switch-client -t "$sess"
    tmux select-window -t "$win"
    tmux select-pane -t "$loc"
    ;;
esac
