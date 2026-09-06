[[ -n $ZPROFILE_LOADED ]] && return
ZPROFILE_LOADED=1

export XDG_CONFIG_HOME="$HOME/.config"
export PATH="$PATH:$HOME/.local/bin"

export N_PREFIX="$HOME/n"
export PATH="$PATH:$HOME/n/bin"

export VISUAL=nvim
export EDITOR="$VISUAL"

export TZ="America/Denver"

for f in "$HOME"/.zprofile.d/*(N); do
  [ -f "$f" ] && [ -r "$f" ] && . "$f"
done

alias k="kubectl"

alias clauded="claude --dangerously-skip-permissions"
alias claudes="claude --model 'sonnet[1m]' --dangerously-skip-permissions"
alias claudeh="claude --model haiku"

alias fixcursor="tput cnorm"

# prevent ctrl-d logout
setopt ignore_eof

