# create a git worktree from branch or pr number in new tmux window
gwtmux() {
  local -r git_cmd="git"
  if [[ -z "$TMUX" ]]; then
    echo >&2 "Error: not in tmux"
    return 1
  fi

  # Capture zsh window to potentially reuse or kill (before any commands run)
  local current_window="$(tmux display-message -p '#W')"
  local current_window_id="$(tmux display-message -p '#{window_id}')"
  local pane_count="$(tmux display-message -p '#{window_panes}')"
  local can_reuse_window=0
  if [[ "$current_window" == "zsh" && "$pane_count" == "1" ]]; then
    can_reuse_window=1
  fi

  if [[ -z "$1" ]]; then
    # Multi-worktree mode - only works from ../default
    if [[ ! -d "default/.git" ]]; then
      echo >&2 "Error: branch or PR number required"
      return 1
    fi

    $git_cmd -C "$PWD/default" fetch -a
    local repo_name="$(basename "$PWD")"

    while IFS= read -r worktree_path; do
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
    done < <($git_cmd -C "$PWD/default" worktree list --porcelain | awk '/^worktree /{print substr($0,10)}')

    # Kill original zsh window if it was single pane
    if [[ $can_reuse_window -eq 1 ]]; then
      tmux kill-window -t "$current_window_id"
    fi
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
    echo >&2 "Error: not in a git repo or parent of default/.git"
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
    if [[ -z "$default_branch" ]]; then
      if $git_cmd -C "$git_root" show-ref --verify --quiet refs/remotes/origin/main; then
        default_branch="main"
      elif $git_cmd -C "$git_root" show-ref --verify --quiet refs/remotes/origin/master; then
        default_branch="master"
      else
        default_branch="main"  # ultimate fallback
      fi
    fi
    local rc=0
    if [[ $has_local -eq 0 ]]; then
      $git_cmd -C "$git_root" worktree add --quiet -- "$worktree_path" "$branch" || rc=$?
    elif [[ $has_remote -eq 0 ]]; then
      $git_cmd -C "$git_root" worktree add --quiet -b "$branch" -- "$worktree_path" "origin/$branch" || rc=$?
    else
      $git_cmd -C "$git_root" worktree add --quiet -b "$branch" -- "$worktree_path" "$default_branch" || rc=$?
    fi
    if [[ $rc -ne 0 ]]; then
      echo >&2 "Error: failed to create worktree for '$branch'."
      return $rc
    fi
  fi

  if [[ $can_reuse_window -eq 1 ]]; then
    tmux rename-window "$window_name"
    cd "$worktree_path"
  else
    tmux new-window -n "$window_name" -c "$worktree_path"
  fi
}

# rename current: worktree dir, branch, remote tracking branch (if exists), tmux window
gwtrename() {
  if [[ -z "$TMUX" ]]; then
    echo >&2 "Error: not in tmux"
    return 1
  fi

  if [[ -z "$1" ]]; then
    echo >&2 "Error: new name required"
    return 1
  fi

  local -r new_name="$1"
  local git_dir git_common_dir
  if ! git_dir="$(git rev-parse --git-dir 2>/dev/null)"; then
    echo >&2 "Error: not in a git repo"
    return 1
  fi

  git_common_dir="$(git rev-parse --git-common-dir)"
  if [[ "$git_dir" == "$git_common_dir" ]]; then
    echo >&2 "Error: in main repo, not a worktree. Refusing to rename."
    return 1
  fi

  local current_branch="$(git branch --show-current)"
  if [[ -z "$current_branch" ]]; then
    echo >&2 "Error: not on a branch"
    return 1
  fi

  # Check latest commit author matches current user to prevent renaming remote branch that is not yours
  local commit_author="$(git log -1 --format='%ae')"
  local current_user="$(git config user.email)"
  if [[ "$commit_author" != "$current_user" ]]; then
    echo >&2 "Error: latest commit not authored by you ($commit_author vs $current_user)"
    return 1
  fi

  local worktree_root="$(git rev-parse --show-toplevel)"
  local parent_dir="$(dirname "$worktree_root")"
  local repo_name="$(basename "$parent_dir")"

  # Convert slashes to underscores like gwtmux does
  local dir_new_name="${new_name//\//_}"
  local new_path="$parent_dir/$dir_new_name"

  if [[ -e "$new_path" ]]; then
    echo >&2 "Error: $new_path already exists"
    return 1
  fi

  # Check if has remote tracking
  local has_remote=0
  if git rev-parse --abbrev-ref --symbolic-full-name @{u} &>/dev/null; then
    has_remote=1
  fi

  # Rename directory
  git worktree move "$worktree_root" "$new_path" || return $?

  # cd into new directory
  cd "$new_path" || return $?

  # Rename branch
  git branch -m "$current_branch" "$new_name" || return $?

  # Update remote if exists
  if [[ $has_remote -eq 1 ]]; then
    if ! git push origin "$new_name"; then
      echo >&2 "Error: failed to push new branch. Reverting local changes..."
      git branch -m "$new_name" "$current_branch"
      git worktree move "$new_path" "$worktree_root"
      cd "$worktree_root"
      return 1
    fi
    git push origin --delete "$current_branch" || return $?
    git branch -u "origin/$new_name" || return $?
  fi

  # Update tmux window
  tmux rename-window "$repo_name/$new_name"
}

# remove git worktree, optionally delete branches, and kill tmux window
# Usage: gwtdone [-d|-D] [-r]
#   -d  Safe delete local branch (only if merged)
#   -D  Force delete local branch (even if unmerged)
#   -r  Also delete remote branch (requires -d or -D)
gwtdone() {
  # Parse flags
  local delete_local=0 # 0=no delete, 1=safe delete (-d), 2=force delete (-D)
  local delete_remote=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -*)
      # Handle combined flags like -Dr or -dr
      local flags="${1#-}"
      local i
      for ((i = 0; i < ${#flags}; i++)); do
        case "${flags:$i:1}" in
        d)
          if [[ $delete_local -eq 0 ]]; then
            delete_local=1
          fi
          ;;
        D)
          delete_local=2
          ;;
        r)
          delete_remote=1
          ;;
        *)
          echo >&2 "Error: unknown option '-${flags:$i:1}'"
          return 1
          ;;
        esac
      done
      shift
      ;;
    *)
      echo >&2 "Error: unknown argument '$1'"
      return 1
      ;;
    esac
  done

  local branch="$(git branch --show-current)"
  local git_dir="$(git rev-parse --git-dir)"
  local git_common_dir="$(git rev-parse --git-common-dir)"
  if [[ "$git_dir" == "$git_common_dir" ]]; then
    echo >&2 "Error: in main repo, not a worktree. Refusing to delete."
    return 1
  fi
  local worktree_root="$(git rev-parse --show-toplevel)"

  # Pre-flight checks: validate branch deletion before making any destructive changes
  if [[ -n "$branch" && $delete_local -eq 1 ]]; then
    # Safe delete - check if merged BEFORE removing worktree
    local default_branch
    default_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
    if [[ -z "$default_branch" ]]; then
      if git show-ref --verify --quiet refs/remotes/origin/main; then
        default_branch="main"
      elif git show-ref --verify --quiet refs/remotes/origin/master; then
        default_branch="master"
      else
        default_branch="main"  # ultimate fallback
      fi
    fi

    if ! git branch --merged "$default_branch" | grep -Eq "^[* ] +$branch\$"; then
      echo >&2 "Error: branch '$branch' is not merged into '$default_branch'. Use -D to force delete."
      return 1
    fi
  fi

  # Remove worktree
  cd "$(dirname "$git_common_dir")"
  git worktree remove "$worktree_root" || return $?

  # Delete local branch if requested
  if [[ -n "$branch" && $delete_local -gt 0 ]]; then
    if [[ $delete_local -eq 1 ]]; then
      # Safe delete (already validated above)
      git branch -d "$branch" || return $?
    else
      # Force delete
      git branch -D "$branch" || return $?
    fi

    # Delete remote branch if requested
    if [[ $delete_remote -eq 1 ]]; then
      if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        git push origin --delete "$branch" || {
          echo >&2 "Warning: failed to delete remote branch 'origin/$branch'"
        }
      fi
    fi
  fi

  tmux kill-window
}
