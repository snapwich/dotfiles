# create a git worktree from branch or pr number in new tmux window
gwtmux() {
  local -r git_cmd="git"
  if [[ -z "$TMUX" ]]; then
    print -u2 "Error: not in tmux"
    return 1
  fi

  if [[ -z "$1" ]]; then
    # Multi-worktree mode - only works from ../default
    if [[ ! -d "default/.git" ]]; then
      print -u2 "Error: branch or PR number required"
      return 1
    fi

    $git_cmd -C "$PWD/default" fetch -a
    local repo_name="$(basename "$PWD")"
    $git_cmd -C "$PWD/default" worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' | while IFS= read -r worktree_path; do
      # Only process worktrees in current directory
      if [[ "$(dirname -- "$worktree_path")" == "$PWD" ]]; then
        local window_name
        if [[ "$worktree_path" == "$PWD/default" ]]; then
          window_name="$repo_name/default"
        else
          local branch_name="$($git_cmd -C "$worktree_path" branch --show-current 2>/dev/null)"
          window_name="$repo_name/$branch_name"
        fi
        if [[ -n "$window_name" ]]; then
          # Check if window already exists
          if ! tmux list-windows -F "#W" | grep -Fxq -- "$window_name"; then
            tmux new-window -n "$window_name" -c "$worktree_path"
          fi
        fi
      fi
    done
    return 0
  fi

  local git_common_dir git_root
  if $git_cmd rev-parse --git-dir &>/dev/null; then
    git_common_dir="$($git_cmd rev-parse --git-common-dir)"
    if [[ "$git_common_dir" == .git ]]; then
      git_root="$PWD"
    elif [[ "$git_common_dir" == /* ]]; then
      git_root="$(dirname -- "$git_common_dir")"
    else
      git_root="$PWD/$(dirname -- "$git_common_dir")"
    fi
  elif [[ -d "default/.git" ]]; then
    git_root="$PWD/default"
  else
    print -u2 "Error: not in a git repo or parent of default/.git"
    return 1
  fi

  $git_cmd -C "$git_root" fetch -a
  local branch
  branch="$(
    (cd "$git_root" 2>/dev/null && GH_PAGER= gh pr view "$1" --json headRefName --jq '.headRefName') 2>/dev/null
  )"
  [[ -z "$branch" ]] && branch="$1"

  local repo_name="$(basename "$(dirname -- "$git_root")")"
  local window_name="$repo_name/$branch"

  if tmux list-windows -F "#W" | grep -Fxq -- "$window_name"; then
    tmux select-window -t "$window_name"
    return 0
  fi

  local dir_branch="${branch//\//_}"
  local -r worktree_path="$(dirname -- "$git_root")/$dir_branch"
  local worktree_exists=0
  if $git_cmd -C "$git_root" worktree list --porcelain |
    awk '/^worktree /{print substr($0,10)}' |
    grep -Fxq -- "$worktree_path"; then
    worktree_exists=1
  fi

  if [[ $worktree_exists -eq 0 ]]; then
    local has_local has_remote
    $git_cmd -C "$git_root" show-ref --verify --quiet "refs/heads/$branch"
    has_local=$?
    $git_cmd -C "$git_root" show-ref --verify --quiet "refs/remotes/origin/$branch"
    has_remote=$?
    local default_branch
    default_branch="$(
      $git_cmd -C "$git_root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null |
        sed 's|^origin/||'
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
    if [[ $rc -ne 0 ]]; then
      print -u2 "Error: failed to create worktree for '$branch'."
      return $rc
    fi
  fi

  tmux new-window -n "$window_name" -c "$worktree_path"
}

# remove git worktree, delete local branch, and kill tmux window
gwtdone() {
  local branch="$(git branch --show-current)"
  local git_dir="$(git rev-parse --git-dir)"
  local git_common_dir="$(git rev-parse --git-common-dir)"
  if [[ "$git_dir" == "$git_common_dir" ]]; then
    print -u2 "Error: in main repo, not a worktree. Refusing to delete."
    return 1
  fi
  local worktree_root="$(git rev-parse --show-toplevel)"
  cd $(dirname $git_common_dir)
  git worktree remove "$worktree_root" || return $?
  if [[ -n "$branch" ]]; then
    git branch -D "$branch"
  fi
  tmux kill-window
}
