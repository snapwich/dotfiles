export XDG_CONFIG_HOME="$HOME/.config"
export PATH="$PATH:$HOME/.local/bin"

export N_PREFIX="$HOME/n"
export PATH="$PATH:$HOME/n/bin"

export VISUAL=nvim
export EDITOR="$VISUAL"

gs() {
  git switch $(git branch | fzf | tr -d '[:space:]')
}

# create a git worktree from branch or pr number in new tmux window
gwtmux() {
  local git_root
  if git rev-parse --git-dir &>/dev/null; then
    git_root=$(git rev-parse --show-toplevel)
  elif [ -d "default/.git" ]; then
    git_root="$PWD/default"
  else
    echo "Error: not in a git repo or parent of default/.git" >&2
    return 1
  fi
  local branch
  if [ -n "$1" ]; then
    branch=$(GH_PAGER= gh -R "$(git -C "$git_root" remote get-url origin)" pr view "$1" --json headRefName --jq '.headRefName' 2>/dev/null)
    if [ -z "$branch" ]; then
      branch="$1"
    fi
    tmux rename-window "$branch"
  else
    branch=$(tmux display-message -p '#W')
  fi
  local worktree_path="$(dirname "$git_root")/$branch"
  if git -C "$git_root" worktree list | grep -q "$worktree_path"; then
    cd "$worktree_path"
    return 0
  fi
  local has_remote=$(git -C "$git_root" show-ref --verify --quiet "refs/remotes/origin/$branch" && echo 1 || echo 0)
  local has_local=$(git -C "$git_root" show-ref --verify --quiet "refs/heads/$branch" && echo 1 || echo 0)
  local git_result
  if [ "$has_local" -eq 1 ]; then
    git -C "$git_root" worktree add "$worktree_path" "$branch" 2>&1 | grep -v "^Preparing\|^Updating\|^HEAD is now"
    git_result=${pipestatus[1]}
  elif [ "$has_remote" -eq 1 ]; then
    git -C "$git_root" worktree add -b "$branch" "$worktree_path" "origin/$branch" 2>&1 | grep -v "^Preparing\|^Updating\|^HEAD is now"
    git_result=${pipestatus[1]}
  else
    git -C "$git_root" worktree add -b "$branch" "$worktree_path" origin/main 2>&1 | grep -v "^Preparing\|^Updating\|^HEAD is now"
    git_result=${pipestatus[1]}
  fi
  if [ "$git_result" -eq 0 ]; then
    cd "$worktree_path"
  fi
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
