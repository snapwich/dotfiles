#!/usr/bin/env bats

# Load test helpers
BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME:-$(dirname "$BATS_TEST_FILENAME")}"
load test_helper/bats-support/load
load test_helper/bats-assert/load
load test_helper/bats-file/load

# Source the functions to test (now bash-compatible!)
source "${BATS_TEST_DIRNAME}/../.zprofile.d/tmux.sh"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Setup a basic git repository with a bare remote
setup_git_repos() {
  # Create bare "remote" repository
  REMOTE_REPO="$TEST_TEMP_DIR/remote.git"
  git init --bare "$REMOTE_REPO" >/dev/null 2>&1

  # Create main repository
  MAIN_REPO="$TEST_TEMP_DIR/repo"
  git clone "$REMOTE_REPO" "$MAIN_REPO" >/dev/null 2>&1

  cd "$MAIN_REPO"

  # Configure git user for commits
  git config user.name "Test User"
  git config user.email "test@example.com"

  # Create initial commit on main branch
  git checkout -b main >/dev/null 2>&1
  echo "initial" >README.md
  git add README.md
  git commit -m "Initial commit" >/dev/null 2>&1
  git push -u origin main >/dev/null 2>&1

  # Set symbolic-ref for origin/HEAD
  cd "$REMOTE_REPO"
  git symbolic-ref HEAD refs/heads/main
  cd "$MAIN_REPO"
  git remote set-head origin main >/dev/null 2>&1
}

# Setup worktree structure: <repo-name>/default/.git layout
setup_worktree_structure() {
  local repo_name="${1:-testrepo}"

  # Create directory structure
  WORKTREE_PARENT="$TEST_TEMP_DIR/$repo_name"
  mkdir -p "$WORKTREE_PARENT"

  # Move repo to be the default worktree
  mv "$MAIN_REPO" "$WORKTREE_PARENT/default"
  MAIN_REPO="$WORKTREE_PARENT/default"
}

# Create a fake gh command that returns a PR branch name
stub_gh_pr() {
  local pr_number="$1"
  local branch_name="$2"

  cat >"$STUB_DIR/gh" <<EOF
#!/bin/bash
if [[ "\$1" == "pr" && "\$2" == "view" && "\$3" == "$pr_number" ]]; then
  echo "$branch_name"
  exit 0
fi
exit 1
EOF
  chmod +x "$STUB_DIR/gh"
}

# Create a fake gh command that always fails
stub_gh_fail() {
  cat >"$STUB_DIR/gh" <<EOF
#!/bin/bash
exit 1
EOF
  chmod +x "$STUB_DIR/gh"
}

# Get tmux windows for test session
get_tmux_windows() {
  tmux list-windows -t "$TEST_SESSION" -F "#W" 2>/dev/null || true
}

# Check if tmux window exists
tmux_window_exists() {
  local window_name="$1"
  get_tmux_windows | grep -Fxq "$window_name"
}

# Get current tmux window name
get_current_window() {
  tmux display-message -t "$TEST_SESSION" -p '#W' 2>/dev/null || true
}

# ============================================================================
# SETUP / TEARDOWN
# ============================================================================

setup() {
  # Use bats built-in temp directory
  TEST_TEMP_DIR="$BATS_TEST_TMPDIR"

  # Create unique tmux session name for this test
  TEST_SESSION="bats_test_$$_${BATS_TEST_NUMBER}"

  # Setup PATH for stubs
  STUB_DIR="$TEST_TEMP_DIR/stubs"
  mkdir -p "$STUB_DIR"

  # Create detached tmux session
  tmux new-session -d -s "$TEST_SESSION" -c "$TEST_TEMP_DIR" 2>/dev/null

  # Source tmux.sh and set PATH in the tmux session
  tmux send-keys -t "$TEST_SESSION" "source ${BATS_TEST_DIRNAME}/../.zprofile.d/tmux.sh" Enter
  tmux send-keys -t "$TEST_SESSION" "export PATH=$STUB_DIR:\$PATH" Enter
  sleep 0.1

  # Set TMUX variable so functions think we're in tmux (for direct calls in test process)
  export TMUX="/tmp/tmux-$(id -u)/default,$TEST_SESSION,0"
  export PATH="$STUB_DIR:$PATH"

  # Setup git repos
  setup_git_repos
}

teardown() {
  # Kill test tmux session if it exists
  if tmux has-session -t "$TEST_SESSION" 2>/dev/null; then
    tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
  fi

  # Stubs are automatically cleaned up when BATS_TEST_TMPDIR is removed
}

# ============================================================================
# TESTS: gwtmux
# ============================================================================

# ----------------------------------------------------------------------------
# Basic functionality
# ----------------------------------------------------------------------------

@test "gwtmux: creates worktree and window for new branch" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  tmux send-keys -t "$TEST_SESSION" "cd $MAIN_REPO && gwtmux new-feature 2>&1; echo EXIT_CODE:\$?" Enter
  sleep 0.3

  # Check what happened in tmux
  run tmux capture-pane -t "$TEST_SESSION" -p
  echo "Tmux pane output:"
  echo "$output"

  assert_dir_exists "$WORKTREE_PARENT/new-feature"
  run get_tmux_windows
  assert_output --partial "myrepo/new-feature"
}

@test "gwtmux: creates worktree from existing local branch" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Create a local branch
  git checkout -b existing-branch >/dev/null 2>&1
  git checkout main >/dev/null 2>&1

  tmux send-keys -t "$TEST_SESSION" "cd $MAIN_REPO && gwtmux existing-branch" Enter
  sleep 0.2

  assert_dir_exists "$WORKTREE_PARENT/existing-branch"
  run get_tmux_windows
  assert_output --partial "myrepo/existing-branch"
}

@test "gwtmux: creates worktree from existing remote branch" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Create a remote branch (simulate another developer's branch)
  git checkout -b remote-feature >/dev/null 2>&1
  echo "remote work" >remote.txt
  git add remote.txt
  git commit -m "Remote work" >/dev/null 2>&1
  git push -u origin remote-feature >/dev/null 2>&1
  git checkout main >/dev/null 2>&1
  git branch -D remote-feature >/dev/null 2>&1

  # Fetch to update remote refs
  git fetch >/dev/null 2>&1

  tmux send-keys -t "$TEST_SESSION" "cd $MAIN_REPO && gwtmux remote-feature" Enter
  sleep 0.2

  assert_dir_exists "$WORKTREE_PARENT/remote-feature"
  run get_tmux_windows
  assert_output --partial "myrepo/remote-feature"
}

@test "gwtmux: handles PR number via gh CLI" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  stub_gh_pr "123" "pr-123-feature"

  tmux send-keys -t "$TEST_SESSION" "cd $MAIN_REPO && gwtmux 123" Enter
  sleep 0.2

  assert_dir_exists "$WORKTREE_PARENT/pr-123-feature"
  run get_tmux_windows
  assert_output --partial "myrepo/pr-123-feature"
}

@test "gwtmux: falls back to branch name when gh fails" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  stub_gh_fail

  tmux send-keys -t "$TEST_SESSION" "cd $MAIN_REPO && gwtmux not-a-pr" Enter
  sleep 0.2

  # Should create worktree with "not-a-pr" as branch name
  assert_dir_exists "$WORKTREE_PARENT/not-a-pr"
}

@test "gwtmux: selects existing window if already exists" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Create worktree first
  git worktree add -b existing "$WORKTREE_PARENT/existing" main >/dev/null 2>&1

  # Create tmux window for it
  tmux new-window -t "$TEST_SESSION" -n "myrepo/existing" -c "$WORKTREE_PARENT/existing" 2>/dev/null

  # Try to create again - should just select the window
  local first_window=$(tmux list-windows -t "$TEST_SESSION" -F "#{window_id}" | head -1)
  tmux send-keys -t "$first_window" "cd $MAIN_REPO && gwtmux existing" Enter
  sleep 0.2

  # Should have selected the window (not created a duplicate)
  run get_tmux_windows
  refute_output --partial "myrepo/existing
myrepo/existing"
}

# ----------------------------------------------------------------------------
# Multi-worktree mode (no arguments)
# ----------------------------------------------------------------------------

@test "gwtmux: no args opens all worktrees in windows" {
  setup_worktree_structure "myrepo"
  cd "$WORKTREE_PARENT"

  # Create multiple worktrees
  git -C default worktree add -b feature-1 "$WORKTREE_PARENT/feature-1" main >/dev/null 2>&1
  git -C default worktree add -b feature-2 "$WORKTREE_PARENT/feature-2" main >/dev/null 2>&1

  # Run gwtmux without arguments from parent directory
  tmux send-keys -t "$TEST_SESSION" "cd $WORKTREE_PARENT && gwtmux" Enter
  sleep 0.3

  # Should create windows for all worktrees
  run get_tmux_windows
  assert_output --partial "myrepo/default"
  assert_output --partial "myrepo/feature-1"
  assert_output --partial "myrepo/feature-2"
}

@test "gwtmux: no args errors if not in parent of default/.git" {
  cd "$TEST_TEMP_DIR"

  run gwtmux
  assert_failure
  assert_output --partial "branch or PR number required"
}

# ----------------------------------------------------------------------------
# Slash handling (branch names with slashes)
# ----------------------------------------------------------------------------

@test "gwtmux: converts slashes to underscores in directory name" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  tmux send-keys -t "$TEST_SESSION" "cd $MAIN_REPO && gwtmux feature/with/slashes" Enter
  sleep 0.2

  # Directory should use underscores
  assert_dir_exists "$WORKTREE_PARENT/feature_with_slashes"
  refute [ -d "$WORKTREE_PARENT/feature/with/slashes" ]

  # Window name should keep slashes
  run get_tmux_windows
  assert_output --partial "myrepo/feature/with/slashes"
}

# ----------------------------------------------------------------------------
# Zsh window reuse logic
# ----------------------------------------------------------------------------

@test "gwtmux: reuses single-pane zsh window" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Rename the initial window to "zsh" with single pane
  # Use the actual first window ID instead of assuming :0
  local first_window=$(tmux list-windows -t "$TEST_SESSION" -F "#{window_id}" | head -1)
  tmux rename-window -t "$first_window" "zsh"

  local initial_window_count=$(tmux list-windows -t "$TEST_SESSION" | wc -l)

  tmux send-keys -t "$first_window" "cd $MAIN_REPO && gwtmux new-branch" Enter
  sleep 0.2

  # Window should have been renamed (not created new)
  local final_window_count=$(tmux list-windows -t "$TEST_SESSION" | wc -l)
  assert_equal "$initial_window_count" "$final_window_count"

  # Window should now be named after the worktree
  run get_tmux_windows
  assert_output --partial "myrepo/new-branch"
  refute_output --partial "zsh"
}

@test "gwtmux: creates new window if zsh has multiple panes" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Rename window to "zsh" and split it
  local first_window=$(tmux list-windows -t "$TEST_SESSION" -F "#{window_id}" | head -1)
  tmux rename-window -t "$first_window" "zsh"
  tmux split-window -t "$first_window"

  local initial_window_count=$(tmux list-windows -t "$TEST_SESSION" | wc -l)

  # Get the first pane of the window
  local first_pane=$(tmux list-panes -t "$first_window" -F "#{pane_id}" | head -1)
  tmux send-keys -t "$first_pane" "cd $MAIN_REPO && gwtmux new-branch" Enter
  sleep 0.2

  # Should have created a new window (not reused)
  local final_window_count=$(tmux list-windows -t "$TEST_SESSION" | wc -l)
  assert [ "$final_window_count" -gt "$initial_window_count" ]

  # Both windows should exist
  run get_tmux_windows
  assert_output --partial "zsh"
  assert_output --partial "myrepo/new-branch"
}

@test "gwtmux: creates new window if current window is not named zsh" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Rename window to something other than "zsh"
  local first_window=$(tmux list-windows -t "$TEST_SESSION" -F "#{window_id}" | head -1)
  tmux rename-window -t "$first_window" "other-window"

  local initial_window_count=$(tmux list-windows -t "$TEST_SESSION" | wc -l)

  tmux send-keys -t "$first_window" "cd $MAIN_REPO && gwtmux new-branch" Enter
  sleep 0.2

  # Should have created a new window
  local final_window_count=$(tmux list-windows -t "$TEST_SESSION" | wc -l)
  assert [ "$final_window_count" -gt "$initial_window_count" ]
}

# ----------------------------------------------------------------------------
# Default branch detection
# ----------------------------------------------------------------------------

@test "gwtmux: detects default branch from symbolic-ref" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Verify symbolic-ref is set
  run git symbolic-ref refs/remotes/origin/HEAD
  assert_output "refs/remotes/origin/main"

  # Create new branch (should be based on main)
  tmux send-keys -t "$TEST_SESSION" "cd $MAIN_REPO && gwtmux test-branch" Enter
  sleep 0.2

  # Verify the branch was created
  assert_dir_exists "$WORKTREE_PARENT/test-branch"
}

@test "gwtmux: falls back to main when symbolic-ref not set" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Remove symbolic-ref
  git remote set-head origin -d >/dev/null 2>&1

  # Create new branch (should still find main)
  tmux send-keys -t "$TEST_SESSION" "cd $MAIN_REPO && gwtmux test-branch" Enter
  sleep 0.2

  assert_dir_exists "$WORKTREE_PARENT/test-branch"
}

@test "gwtmux: uses master if main doesn't exist" {
  # Create repo with master branch instead of main
  local master_remote="$TEST_TEMP_DIR/remote-master.git"
  git init --bare "$master_remote" >/dev/null 2>&1

  local master_repo="$TEST_TEMP_DIR/repo-master"
  git clone "$master_remote" "$master_repo" >/dev/null 2>&1
  cd "$master_repo"

  git config user.name "Test User"
  git config user.email "test@example.com"
  git checkout -b master >/dev/null 2>&1
  echo "initial" >README.md
  git add README.md
  git commit -m "Initial commit" >/dev/null 2>&1
  git push -u origin master >/dev/null 2>&1

  # Override MAIN_REPO for setup_worktree_structure
  MAIN_REPO="$master_repo"
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Remove symbolic-ref to force fallback
  git remote set-head origin -d >/dev/null 2>&1

  tmux send-keys -t "$TEST_SESSION" "cd $MAIN_REPO && gwtmux test-branch" Enter
  sleep 0.2

  assert_dir_exists "$WORKTREE_PARENT/test-branch"
}

# ----------------------------------------------------------------------------
# Error cases
# ----------------------------------------------------------------------------

@test "gwtmux: errors when not in tmux" {
  unset TMUX
  cd "$MAIN_REPO"

  run gwtmux new-branch
  assert_failure
  assert_output --partial "not in tmux"
}

@test "gwtmux: errors when not in git repo" {
  cd "$TEST_TEMP_DIR"
  mkdir -p not-a-repo
  cd not-a-repo

  run gwtmux test
  assert_failure
  assert_output --partial "not in a git repo"
}

@test "gwtmux: errors when worktree creation fails" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Create a file where worktree dir would be created
  touch "$WORKTREE_PARENT/conflict"

  tmux send-keys -t "$TEST_SESSION" "cd $MAIN_REPO && gwtmux conflict" Enter
  sleep 0.2

  # Should see error about failed worktree creation
  run tmux capture-pane -t "$TEST_SESSION" -p
  assert_output --partial "failed to create worktree"
}

# ============================================================================
# TESTS: gwtrename
# ============================================================================

# ----------------------------------------------------------------------------
# Basic functionality
# ----------------------------------------------------------------------------

@test "gwtrename: renames directory, branch, and window (no remote)" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Create a worktree
  git worktree add -b old-name "$WORKTREE_PARENT/old-name" main >/dev/null 2>&1

  # Switch to the worktree
  cd "$WORKTREE_PARENT/old-name"
  git config user.name "Test User"
  git config user.email "test@example.com"

  # Make a commit so we're on a proper branch
  echo "test" >test.txt
  git add test.txt
  git commit -m "Test commit" >/dev/null 2>&1

  # Create tmux window
  tmux new-window -t "$TEST_SESSION" -n "myrepo/old-name" -c "$WORKTREE_PARENT/old-name" 2>/dev/null

  # Rename
  tmux send-keys -t "$TEST_SESSION:1" "cd $WORKTREE_PARENT/old-name && gwtrename new-name" Enter
  sleep 0.2

  # Verify directory renamed
  assert_dir_exists "$WORKTREE_PARENT/new-name"
  refute [ -d "$WORKTREE_PARENT/old-name" ]

  # Verify branch renamed
  run git -C "$WORKTREE_PARENT/new-name" branch --show-current
  assert_output "new-name"

  # Verify window renamed
  run get_tmux_windows
  assert_output --partial "myrepo/new-name"
  refute_output --partial "myrepo/old-name"
}

@test "gwtrename: renames with remote tracking branch" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Create a worktree with remote tracking
  git worktree add "$WORKTREE_PARENT/old-name" -b old-name main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/old-name"
  git config user.name "Test User"
  git config user.email "test@example.com"

  echo "test" >test.txt
  git add test.txt
  git commit -m "Test commit" >/dev/null 2>&1
  git push -u origin old-name >/dev/null 2>&1

  # Create tmux window
  tmux new-window -t "$TEST_SESSION" -n "myrepo/old-name" -c "$WORKTREE_PARENT/old-name" 2>/dev/null

  # Rename
  tmux send-keys -t "$TEST_SESSION:1" "cd $WORKTREE_PARENT/old-name && gwtrename new-name" Enter
  sleep 0.3

  # Verify remote branch was renamed
  run git -C "$MAIN_REPO" branch -r
  assert_output --partial "origin/new-name"
  refute_output --partial "origin/old-name"

  # Verify tracking is set correctly
  run git -C "$WORKTREE_PARENT/new-name" rev-parse --abbrev-ref --symbolic-full-name @{u}
  assert_output "origin/new-name"
}

@test "gwtrename: converts slashes to underscores in directory name" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add -b old-name "$WORKTREE_PARENT/old-name" main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/old-name"
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "test" >test.txt
  git add test.txt
  git commit -m "Test" >/dev/null 2>&1

  tmux new-window -t "$TEST_SESSION" -n "myrepo/old-name" -c "$WORKTREE_PARENT/old-name" 2>/dev/null

  tmux send-keys -t "$TEST_SESSION:1" "cd $WORKTREE_PARENT/old-name && gwtrename feature/new-name" Enter
  sleep 0.2

  # Directory should use underscores
  assert_dir_exists "$WORKTREE_PARENT/feature_new-name"

  # Branch name should keep slashes
  run git -C "$WORKTREE_PARENT/feature_new-name" branch --show-current
  assert_output "feature/new-name"

  # Window name should keep slashes
  run get_tmux_windows
  assert_output --partial "myrepo/feature/new-name"
}

# ----------------------------------------------------------------------------
# Error cases and rollback
# ----------------------------------------------------------------------------

@test "gwtrename: errors when not in tmux" {
  unset TMUX
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add -b test-wt "$WORKTREE_PARENT/test-wt" main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"

  run gwtrename new-name
  assert_failure
  assert_output --partial "not in tmux"
}

@test "gwtrename: errors when no name provided" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add -b test-wt "$WORKTREE_PARENT/test-wt" main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"

  run gwtrename
  assert_failure
  assert_output --partial "new name required"
}

@test "gwtrename: errors when not in git repo" {
  cd "$TEST_TEMP_DIR"
  mkdir -p not-a-repo
  cd not-a-repo

  run gwtrename new-name
  assert_failure
  assert_output --partial "not in a git repo"
}

@test "gwtrename: errors when in main repo (not worktree)" {
  cd "$MAIN_REPO"

  run gwtrename new-name
  assert_failure
  assert_output --partial "in main repo, not a worktree"
}

@test "gwtrename: errors when not on a branch" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add -b test-wt "$WORKTREE_PARENT/test-wt" main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"

  # Detach HEAD
  git checkout HEAD~0 >/dev/null 2>&1

  run gwtrename new-name
  assert_failure
  assert_output --partial "not on a branch"
}

@test "gwtrename: errors when target path already exists" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add -b old-name "$WORKTREE_PARENT/old-name" main >/dev/null 2>&1
  mkdir -p "$WORKTREE_PARENT/new-name"

  cd "$WORKTREE_PARENT/old-name"
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "test" >test.txt
  git add test.txt
  git commit -m "Test" >/dev/null 2>&1

  run gwtrename new-name
  assert_failure
  assert_output --partial "already exists"
}

@test "gwtrename: errors when commit author doesn't match current user" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add -b test-wt "$WORKTREE_PARENT/test-wt" main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"

  # Configure different user
  git config user.name "Other User"
  git config user.email "other@example.com"

  # Make commit
  echo "test" >test.txt
  git add test.txt
  git commit -m "Test" >/dev/null 2>&1

  # Change user back
  git config user.email "test@example.com"

  run gwtrename new-name
  assert_failure
  assert_output --partial "not authored by you"
}

# ============================================================================
# TESTS: gwtdone
# ============================================================================

# ----------------------------------------------------------------------------
# Basic functionality
# ----------------------------------------------------------------------------

@test "gwtdone: kills window only (no flags)" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add "$WORKTREE_PARENT/test-wt" -b test-branch main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"
  git config user.name "Test User"
  git config user.email "test@example.com"

  tmux new-window -t "$TEST_SESSION" -n "myrepo/test-branch" -c "$WORKTREE_PARENT/test-wt" 2>/dev/null
  local window_count_before=$(tmux list-windows -t "$TEST_SESSION" | wc -l)

  tmux send-keys -t "$TEST_SESSION:1" "cd $WORKTREE_PARENT/test-wt && gwtdone" Enter
  sleep 0.2

  # Worktree should still exist
  assert [ -d "$WORKTREE_PARENT/test-wt" ]

  # Branch should still exist
  run git -C "$MAIN_REPO" branch
  assert_output --partial "test-branch"

  # Window should be killed
  local window_count_after=$(tmux list-windows -t "$TEST_SESSION" 2>/dev/null | wc -l)
  assert [ "$window_count_after" -lt "$window_count_before" ]
}

@test "gwtdone: safe delete with -wb flag (merged branch)" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Create and merge a branch
  git worktree add "$WORKTREE_PARENT/test-wt" -b test-branch main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "test" >test.txt
  git add test.txt
  git commit -m "Test" >/dev/null 2>&1

  # Merge into main
  cd "$MAIN_REPO"
  git checkout main >/dev/null 2>&1
  git merge test-branch >/dev/null 2>&1

  cd "$WORKTREE_PARENT/test-wt"
  local new_window=$(tmux new-window -t "$TEST_SESSION" -n "myrepo/test-branch" -c "$WORKTREE_PARENT/test-wt" -P -F "#{window_id}")

  tmux send-keys -t "$new_window" "cd $WORKTREE_PARENT/test-wt && gwtdone -wb" Enter
  sleep 0.5

  # Both worktree and branch should be removed
  refute [ -d "$WORKTREE_PARENT/test-wt" ]
  run git -C "$MAIN_REPO" branch
  refute_output --partial "test-branch"
}

@test "gwtdone: safe delete fails on unmerged branch" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add "$WORKTREE_PARENT/test-wt" -b test-branch main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "test" >test.txt
  git add test.txt
  git commit -m "Unmerged commit" >/dev/null 2>&1

  run gwtdone -b
  assert_failure
  assert_output --partial "not merged"

  # Worktree should still exist
  assert_dir_exists "$WORKTREE_PARENT/test-wt"
}

@test "gwtdone: force delete with -wB flag" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add "$WORKTREE_PARENT/test-wt" -b test-branch main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "test" >test.txt
  git add test.txt
  git commit -m "Unmerged commit" >/dev/null 2>&1

  tmux new-window -t "$TEST_SESSION" -n "myrepo/test-branch" -c "$WORKTREE_PARENT/test-wt" 2>/dev/null

  tmux send-keys -t "$TEST_SESSION:1" "cd $WORKTREE_PARENT/test-wt && gwtdone -wB" Enter
  sleep 0.2

  # Both should be removed despite not being merged
  refute [ -d "$WORKTREE_PARENT/test-wt" ]
  run git -C "$MAIN_REPO" branch
  refute_output --partial "test-branch"
}

@test "gwtdone: deletes remote branch with -wbr flag" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add "$WORKTREE_PARENT/test-wt" -b test-branch main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "test" >test.txt
  git add test.txt
  git commit -m "Test" >/dev/null 2>&1
  git push -u origin test-branch >/dev/null 2>&1

  # Merge into main
  cd "$MAIN_REPO"
  git checkout main >/dev/null 2>&1
  git merge test-branch >/dev/null 2>&1

  cd "$WORKTREE_PARENT/test-wt"
  local new_window=$(tmux new-window -t "$TEST_SESSION" -n "myrepo/test-branch" -c "$WORKTREE_PARENT/test-wt" -P -F "#{window_id}")

  tmux send-keys -t "$new_window" "cd $WORKTREE_PARENT/test-wt && gwtdone -wbr" Enter
  sleep 0.3

  # Local and remote should be deleted
  refute [ -d "$WORKTREE_PARENT/test-wt" ]
  run git -C "$MAIN_REPO" branch -r
  refute_output --partial "origin/test-branch"
}

@test "gwtdone: force deletes remote with -wBr flag" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add "$WORKTREE_PARENT/test-wt" -b test-branch main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "test" >test.txt
  git add test.txt
  git commit -m "Unmerged commit" >/dev/null 2>&1
  git push -u origin test-branch >/dev/null 2>&1

  tmux new-window -t "$TEST_SESSION" -n "myrepo/test-branch" -c "$WORKTREE_PARENT/test-wt" 2>/dev/null

  tmux send-keys -t "$TEST_SESSION:1" "cd $WORKTREE_PARENT/test-wt && gwtdone -wBr" Enter
  sleep 0.3

  # Everything should be deleted
  refute [ -d "$WORKTREE_PARENT/test-wt" ]
  run git -C "$MAIN_REPO" branch -r
  refute_output --partial "origin/test-branch"
}

@test "gwtdone: handles combined -wbr flags in either order" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add "$WORKTREE_PARENT/test-wt" -b test-branch main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "test" >test.txt
  git add test.txt
  git commit -m "Test" >/dev/null 2>&1
  git push -u origin test-branch >/dev/null 2>&1

  cd "$MAIN_REPO"
  git checkout main >/dev/null 2>&1
  git merge test-branch >/dev/null 2>&1

  cd "$WORKTREE_PARENT/test-wt"
  local new_window=$(tmux new-window -t "$TEST_SESSION" -n "myrepo/test-branch" -c "$WORKTREE_PARENT/test-wt" -P -F "#{window_id}")

  # Try -rbw instead of -wbr
  tmux send-keys -t "$new_window" "cd $WORKTREE_PARENT/test-wt && gwtdone -rbw" Enter
  sleep 0.3

  # Should work the same
  refute [ -d "$WORKTREE_PARENT/test-wt" ]
  run git -C "$MAIN_REPO" branch -r
  refute_output --partial "origin/test-branch"
}

@test "gwtdone: only deletes remote if remote ref exists" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Create branch without pushing
  git worktree add "$WORKTREE_PARENT/test-wt" -b test-branch main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "test" >test.txt
  git add test.txt
  git commit -m "Test" >/dev/null 2>&1

  # Merge into main (so -b will work)
  cd "$MAIN_REPO"
  git checkout main >/dev/null 2>&1
  git merge test-branch >/dev/null 2>&1

  cd "$WORKTREE_PARENT/test-wt"
  local new_window=$(tmux new-window -t "$TEST_SESSION" -n "myrepo/test-branch" -c "$WORKTREE_PARENT/test-wt" -P -F "#{window_id}")

  # Try to delete with -wbr (should succeed even though no remote)
  tmux send-keys -t "$new_window" "cd $WORKTREE_PARENT/test-wt && gwtdone -wbr" Enter
  sleep 0.2

  # Should complete without error
  refute [ -d "$WORKTREE_PARENT/test-wt" ]
}

# ----------------------------------------------------------------------------
# Default branch detection for merge check
# ----------------------------------------------------------------------------

@test "gwtdone: uses symbolic-ref for merge check" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Verify symbolic-ref is set to main
  run git symbolic-ref refs/remotes/origin/HEAD
  assert_output "refs/remotes/origin/main"

  # Create and merge branch
  git worktree add "$WORKTREE_PARENT/test-wt" -b test-branch main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "test" >test.txt
  git add test.txt
  git commit -m "Test" >/dev/null 2>&1

  cd "$MAIN_REPO"
  git checkout main >/dev/null 2>&1
  git merge test-branch >/dev/null 2>&1

  cd "$WORKTREE_PARENT/test-wt"
  local new_window=$(tmux new-window -t "$TEST_SESSION" -n "myrepo/test-branch" -c "$WORKTREE_PARENT/test-wt" -P -F "#{window_id}")

  tmux send-keys -t "$new_window" "cd $WORKTREE_PARENT/test-wt && gwtdone -wb" Enter
  sleep 0.5

  # Should succeed
  refute [ -d "$WORKTREE_PARENT/test-wt" ]
}

@test "gwtdone: falls back to master for merge check" {
  # Create repo with master branch
  local master_remote="$TEST_TEMP_DIR/remote-master2.git"
  git init --bare "$master_remote" >/dev/null 2>&1

  local master_repo="$TEST_TEMP_DIR/repo-master2"
  git clone "$master_remote" "$master_repo" >/dev/null 2>&1
  cd "$master_repo"

  git config user.name "Test User"
  git config user.email "test@example.com"
  git checkout -b master >/dev/null 2>&1
  echo "initial" >README.md
  git add README.md
  git commit -m "Initial" >/dev/null 2>&1
  git push -u origin master >/dev/null 2>&1

  # Override MAIN_REPO for setup_worktree_structure
  MAIN_REPO="$master_repo"
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  # Remove symbolic-ref
  git remote set-head origin -d >/dev/null 2>&1

  # Create and merge branch
  git worktree add "$WORKTREE_PARENT/test-wt" -b test-branch master >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"
  echo "test" >test.txt
  git add test.txt
  git commit -m "Test" >/dev/null 2>&1

  cd "$MAIN_REPO"
  git checkout master >/dev/null 2>&1
  git merge test-branch >/dev/null 2>&1

  cd "$WORKTREE_PARENT/test-wt"
  local new_window=$(tmux new-window -t "$TEST_SESSION" -n "myrepo/test-branch" -c "$WORKTREE_PARENT/test-wt" -P -F "#{window_id}")

  tmux send-keys -t "$new_window" "cd $WORKTREE_PARENT/test-wt && gwtdone -wb" Enter
  sleep 0.5

  # Should succeed using master
  refute [ -d "$WORKTREE_PARENT/test-wt" ]
}

# ----------------------------------------------------------------------------
# Error cases
# ----------------------------------------------------------------------------

@test "gwtdone: errors when in main repo (not worktree)" {
  cd "$MAIN_REPO"

  run gwtdone
  assert_failure
  assert_output --partial "in main repo, not a worktree"
}

@test "gwtdone: errors on unknown flag" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add -b test-wt "$WORKTREE_PARENT/test-wt" main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"

  run gwtdone -x
  assert_failure
  assert_output --partial "unknown option"
}

@test "gwtdone: errors on unknown argument" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add -b test-wt "$WORKTREE_PARENT/test-wt" main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"

  run gwtdone invalid-arg
  assert_failure
  assert_output --partial "unknown argument"
}

# ----------------------------------------------------------------------------
# New window handling functionality
# ----------------------------------------------------------------------------

@test "gwtdone: deletes worktree with -w flag" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add "$WORKTREE_PARENT/test-wt" -b test-branch main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"
  git config user.name "Test User"
  git config user.email "test@example.com"

  tmux new-window -t "$TEST_SESSION" -n "myrepo/test-branch" -c "$WORKTREE_PARENT/test-wt" 2>/dev/null

  tmux send-keys -t "$TEST_SESSION:1" "cd $WORKTREE_PARENT/test-wt && gwtdone -w" Enter
  sleep 0.2

  # Worktree should be removed
  refute [ -d "$WORKTREE_PARENT/test-wt" ]

  # Branch should still exist
  run git -C "$MAIN_REPO" branch
  assert_output --partial "test-branch"
}

@test "gwtdone: renames last window instead of killing" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add "$WORKTREE_PARENT/test-wt" -b test-branch main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"
  git config user.name "Test User"
  git config user.email "test@example.com"

  # Ensure we only have one window
  local window_count_before=$(tmux list-windows -t "$TEST_SESSION" | wc -l)
  assert [ "$window_count_before" -eq 1 ]

  # Get the actual window ID
  local window_id=$(tmux list-windows -t "$TEST_SESSION" -F "#{window_id}" | head -1)

  tmux send-keys -t "$window_id" "cd $WORKTREE_PARENT/test-wt && gwtdone" Enter
  sleep 0.3

  # Window should still exist
  local window_count_after=$(tmux list-windows -t "$TEST_SESSION" | wc -l)
  assert [ "$window_count_after" -eq 1 ]

  # Window should be renamed to shell name
  run tmux display-message -t "$window_id" -p '#W'
  assert_output "$(basename "${SHELL:-zsh}")"
}

@test "gwtdone: navigates to parent when renaming last window" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add "$WORKTREE_PARENT/test-wt" -b test-branch main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"
  git config user.name "Test User"
  git config user.email "test@example.com"

  # Ensure we only have one window
  local window_count=$(tmux list-windows -t "$TEST_SESSION" | wc -l)
  assert [ "$window_count" -eq 1 ]

  # Get the actual window ID
  local window_id=$(tmux list-windows -t "$TEST_SESSION" -F "#{window_id}" | head -1)

  # Execute gwtdone and capture PWD after
  tmux send-keys -t "$window_id" "cd $WORKTREE_PARENT/test-wt && gwtdone && pwd > /tmp/gwtdone_pwd_$$" Enter
  sleep 0.3

  # Verify we're in the parent directory
  run cat "/tmp/gwtdone_pwd_$$"
  assert_output "$WORKTREE_PARENT"
  rm -f "/tmp/gwtdone_pwd_$$"
}

@test "gwtdone: kills window when multiple windows exist" {
  setup_worktree_structure "myrepo"
  cd "$MAIN_REPO"

  git worktree add "$WORKTREE_PARENT/test-wt" -b test-branch main >/dev/null 2>&1
  cd "$WORKTREE_PARENT/test-wt"
  git config user.name "Test User"
  git config user.email "test@example.com"

  # Create a second window so we have multiple
  tmux new-window -t "$TEST_SESSION" -n "myrepo/test-branch" -c "$WORKTREE_PARENT/test-wt" 2>/dev/null
  local window_count_before=$(tmux list-windows -t "$TEST_SESSION" | wc -l)
  assert [ "$window_count_before" -gt 1 ]

  tmux send-keys -t "$TEST_SESSION:1" "cd $WORKTREE_PARENT/test-wt && gwtdone" Enter
  sleep 0.2

  # Window should be killed
  local window_count_after=$(tmux list-windows -t "$TEST_SESSION" 2>/dev/null | wc -l)
  assert [ "$window_count_after" -lt "$window_count_before" ]
}
