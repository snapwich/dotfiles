gs() {
  git switch $(git branch | fzf | tr -d '[:space:]')
}

ports() {
  sudo lsof -iTCP -sTCP:LISTEN -n -P |
    awk 'NR>1 {print $9, $1, $2}' |
    sed 's/.*://' |
    while read port process pid; do
      echo "Port $port: $(ps -p $pid -o command= | sed 's/^-//') (PID: $pid)"
    done | sort -n
}

ssh-agents() {
  # Find ssh-agent PIDs (exact match)
  if command -v pgrep >/dev/null 2>&1; then
    pids="$(pgrep -x ssh-agent 2>/dev/null)"
  else
    pids="$(ps ax -o pid= -o comm= | awk '$2=="ssh-agent"{print $1}')"
  fi

  [ -z "$pids" ] && return 0

  echo "$pids" | while read -r pid; do
    [ -z "$pid" ] && continue

    socket="$(
      sudo lsof -n -P -U -a -p "$pid" 2>/dev/null | awk '
        /unix/ {
          # find the first field that looks like a path
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^\//) {
              print $i
              exit
            }
          }
        }
      '
    )"

    if [ -n "$socket" ]; then
      echo "ssh-agent $pid $socket"
    else
      echo "ssh-agent $pid (no socket found)"
    fi
  done
}
