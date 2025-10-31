export XDG_CONFIG_HOME="$HOME/.config"
export PATH="$PATH:$HOME/.local/bin"

export N_PREFIX="$HOME/n"
export PATH="$PATH:$HOME/n/bin"

export VISUAL=nvim
export EDITOR="$VISUAL"

if [ -d "$HOME/.zprofile.d" ]; then
  for f in "$HOME/.zprofile.d"/*; do
    [ -r "$f" ] && . "$f"
  done
fi
