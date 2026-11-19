---
name: gwtmux-handoff
description: Write a handoff document, then open a new gwtmux worktree/branch in a new tmux window and start a clauded session there that picks up the handoff.
argument-hint: "[branch name] What will the next session be used for?"
disable-model-invocation: true
---

# gwtmux handoff

Arguments: `$ARGUMENTS`

Hand the work off to a new `clauded` session that runs in a new worktree,
branch and tmux window. Do the steps in sequence. Stop at a step that fails,
tell me why, and show the commands that I must run to finish by hand.

## 1. Preflight

- `$TMUX` is set.
- `~/.local/share/gwtmux/gwtmux.sh` exists.
- The current directory is in a git repo. Find the main repo root with
  `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"`.
  If its basename is `default`, the repo uses the convention layout. Else it
  is a flat repo.
- Record `git status --porcelain`. If it is not empty, the tree is dirty.

The Bash tool does not keep the directory between calls. Start each command
that runs `git` or `gwtmux` with `cd <main repo root> &&`.

## 2. Pick the branch name

If the arguments start with a branch name (a single word such as
`fix-login-redirect` or `feat/foo`, or `branch: <name>`), use it. The rest of
the arguments describe the focus of the next session.

Else make a kebab-case name from the focus of the next session: a maximum of 5
words and 40 characters, with no filler words. If the current branch starts
with a Jira key (for example `PEX-1234-...`) and the new work is part of the
same ticket, keep the key as the prefix.

Make sure that the branch does not exist yet:
`git show-ref --verify --quiet refs/heads/<branch>` must fail. If it exists,
ask me what to do.

If the tree is dirty, ask with `AskUserQuestion`: "Move the uncommitted changes
to the new worktree?" with the options `Leave them here` and `Move them`.

## 3. Write the handoff

Read `~/.claude/skills/handoff/SKILL.md` and follow its instructions, with
these changes:

- Make the file with `mktemp "${TMPDIR:-/tmp}/<branch with / as ->-handoff-XXXXXX.md"`.
- The next agent works in a new worktree on the branch `<branch>`, created from
  the default branch of `origin`. Use paths relative to the repo root, because
  the new worktree has a different absolute path.
- If I selected `Move them`, add a section **Uncommitted changes** that tells
  what the changes are.

## 4. Open the worktree and start the session

1. If I selected `Move them`, run
   `git stash push -u -m "gwtmux-handoff <branch>"`.
2. Run this in one Bash command. Use the path for the layout from step 1:

   ```sh
   # convention layout
   cd <main repo root> && source ~/.local/share/gwtmux/gwtmux.sh && \
     gwtmux -by -c "clauded -n <branch> 'Read the handoff file <handoff path> and continue the work it describes.'" <branch>

   # flat repo: a bare branch name is an error, so give a new path; the branch is its basename
   cd <main repo root> && source ~/.local/share/gwtmux/gwtmux.sh && \
     gwtmux -by -c "clauded -n <branch> 'Read the handoff file <handoff path> and continue the work it describes.'" ../<branch>
   ```

   - `-b` opens the window in the background, so the focus stays here and
     gwtmux never types into this session's window.
   - `-y` creates the branch with no prompt. The Bash tool has no terminal.
   - `-c` types the `clauded` command into the shell of the new window. The
     session is interactive. Do not use `-p`.
   - The prompt must not contain a `'` or a `"`.

   If the output has "Window '<name>' already exists", gwtmux did not run the
   `-c` command. Tell me, and do not send keys to that window.

3. Find the worktree path: in `git worktree list --porcelain`, the `worktree`
   line of the entry whose `branch` is `refs/heads/<branch>`.
4. If you stashed in step 1, run `git -C <worktree path> stash pop`. If the pop
   fails, do not try to fix it. Tell me that the changes are in the stash.

## 5. Report

Show the branch, the worktree path, the tmux window name, the handoff file
path, and the result of the stash if you moved changes.
