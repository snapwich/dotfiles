export XDG_CONFIG_HOME="$HOME/.config"

export N_PREFIX="$HOME/n"
export PATH="$PATH:$HOME/n/bin"

export VISUAL=nvim
export EDITOR="$VISUAL"

gs() {
  git switch $(git branch | fzf | tr -d '[:space:]')
}

ports() {
    sudo lsof -iTCP -sTCP:LISTEN -n -P | \
    awk 'NR>1 {print $9, $1, $2}' | \
    sed 's/.*://' | \
    while read port process pid; do
        echo "Port $port: $(ps -p $pid -o command= | sed 's/^-//') (PID: $pid)"
    done | sort -n
}

if [ -d "$HOME/.zprofile.d" ]; then
  for f in "$HOME/.zprofile.d"/*; do
    [ -r "$f" ] && . "$f"
  done
fi
