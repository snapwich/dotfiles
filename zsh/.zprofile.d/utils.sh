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

    # Get the first absolute path from lsof's UNIX-socket output
    socket="$(
      sudo lsof -n -P -U -a -p "$pid" 2>/dev/null | awk '
        NR == 1 { next }      # skip header
        {
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^\//) { # first field that looks like a path
              print $i
              exit
            }
          }
        }
      '
    )"

    if [ -z "$socket" ]; then
      echo "ssh-agent $pid (no socket found)"
      continue
    fi

    echo "ssh-agent $pid $socket"

    # List identities for this agent
    ids="$(SSH_AUTH_SOCK="$socket" ssh-add -l 2>/dev/null || true)"

    if [ -n "$ids" ]; then
      echo "$ids" | while IFS= read -r line; do
        printf '\t%s\n' "$line"
      done
    else
      printf '\t(no identities)\n'
    fi
  done
}
