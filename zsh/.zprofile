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
  local -r git_cmd="git"
  local git_root

  if $git_cmd rev-parse --git-dir &>/dev/null; then
    git_root="$($git_cmd rev-parse --show-toplevel)"
  elif [[ -d "default/.git" ]]; then
    git_root="$PWD/default"
  else
    print -u2 "Error: not in a git repo or parent of default/.git"
    return 1
  fi
  local branch
  if [[ -n "$1" ]]; then
    branch="$(
      ( cd "$git_root" 2>/dev/null && GH_PAGER= gh pr view "$1" --json headRefName --jq '.headRefName' ) 2>/dev/null
    )"
    [[ -z "$branch" ]] && branch="$1"
    if [[ -n "$TMUX" && -n "$branch" ]]; then
      tmux rename-window -- "$branch"
    fi
  else
    branch="$(tmux display-message -p '#W' 2>/dev/null)"
    if [[ -z "$branch" ]]; then
      print -u2 "Error: no branch provided and not in tmux."
      return 1
    fi
  fi
  local dir_branch="$branch"
  local -r worktree_path="$(dirname -- "$git_root")/$dir_branch"
  if $git_cmd -C "$git_root" worktree list --porcelain \
      | awk '/^worktree /{print substr($0,10)}' \
      | grep -Fxq -- "$worktree_path"; then
    builtin cd -- "$worktree_path" || return $?
    return 0
  fi
  local has_local has_remote
  $git_cmd -C "$git_root" show-ref --verify --quiet "refs/heads/$branch";  has_local=$?
  $git_cmd -C "$git_root" show-ref --verify --quiet "refs/remotes/origin/$branch"; has_remote=$?
  local default_branch
  default_branch="$(
    $git_cmd -C "$git_root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
      | sed 's|^origin/||'
  )"
  [[ -z "$default_branch" ]] && default_branch="main"
  local rc=0
  if [[ $has_local -eq 0 ]]; then
    $git_cmd -C "$git_root" worktree add --quiet -- "$worktree_path" "$branch" || rc=$?
  elif [[ $has_remote -eq 0 ]]; then
    $git_cmd -C "$git_root" worktree add --quiet -b "$branch" -- "$worktree_path" "origin/$branch" || rc=$?
  else
    $git_cmd -C "$git_root" worktree add --quiet -b "$branch" -- "$worktree_path" "$default_branch" || rc=$?
  fi
  if [[ $rc -eq 0 ]]; then
    builtin cd -- "$worktree_path" || return $?
  else
    print -u2 "Error: failed to create worktree for '$branch'."
    return $rc
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
