---
name: vault
description: Add, complete, edit, and delete tasks and add notes to daily notes in the user's Obsidian vault, following its conventions.
argument-hint: "what to do, in plain words (e.g. 'add follow up with betsy under frontend leads')"
disable-model-invocation: true
---

The user tells you in plain words what to do with their Obsidian vault. Do it with the script, then confirm.

Script: `~/.claude/skills/vault/scripts/vault` (below: `vault`). It runs headless nvim with the user's obsidian.nvim and obsidian-tasks.nvim config, so placement follows the plugin's rules. Do not edit task lines by hand when a script command covers the change.

## Vault

The script picks the vault: `--vault NAME|PATH` (first argument), else the vault that holds the cwd, else `~/vaults/work-notes`, else `~/vaults/notes`. Pass `--vault` only when the user names a vault ("in my personal notes" → `--vault notes`). If the vault has a `CLAUDE.md`, read it before you write prose.

## Workflow

1. Run `vault tasks` to see the dashboard (`tasks.md`), unless you already have a current listing in context. Each task row starts with its source ref `path:line`. `## Name` lines are group headers (in these vaults: the heading the task is under in its daily note). `# Name` lines are dashboard headings.
   - To keep output small, filter: `vault tasks --group TEXT` (groups whose name contains TEXT) or `vault tasks --match TEXT` (tasks that contain TEXT).
2. Turn the request into one or more commands (below). Refs go stale after any write to that file: run `vault tasks` again, or use the ref printed in the last confirmation.
3. Confirm to the user with one line per change: what, the task text, and where, e.g. `added "check amplify branch limits" → daily/2026-10-23.md › ## AI prototyping`. Show a diff only if the user asks.

## Choosing where a new task goes

- "under/in GROUP" or the request matches a dashboard group → `add --heading "GROUP"`. This puts the task in **today's** daily note under that heading (made if missing). Use the group name exactly as `vault tasks` prints it.
- "after/below TASK" → `add --below REF`: same note, after that task and its subtree.
- "subtask of / under TASK" → `add --under REF`.
- No group named: pick the group that fits best and use `--heading`. Name the group in your confirmation so the user can move it. Ask first only if no group fits; then suggest a new heading.
- `--no-heading`: top of today's daily, before the first heading. Use only when asked.

## Script

```
vault [--vault V] info                                     vault root, today's daily path
vault [--vault V] tasks [--group T] [--match T] [--file F] render dashboard (F default tasks.md)
vault [--vault V] add --heading H  [--date D] TEXT [CHILD…] task in daily D (default today) under ## H
vault [--vault V] add --no-heading [--date D] TEXT [CHILD…] task in daily D before its first heading
vault [--vault V] add --below REF --expect E TEXT [CHILD…]  sibling after task REF and its subtree
vault [--vault V] add --under REF --expect E TEXT [CHILD…]  last child of task REF
vault [--vault V] done|undone|start|cancel REF --expect E   set status [x] [ ] [/] [-]
vault [--vault V] set REF --expect E TEXT                   replace task text (keeps indent and status)
vault [--vault V] delete REF --expect E [--force]           delete task + subtree
vault [--vault V] note [--heading H] [--date D] TEXT…       prose at the end of section H of daily D
vault [--vault V] daily [--date D]                          print daily D with line numbers
vault sync                                                  commit, pull --rebase, push every vault
```

- `REF` is `path:line` from `vault tasks` (vault-relative, 1-indexed). `--expect E` is a short, distinctive part of that line's text (case-insensitive). If the line no longer has E, the script looks for one unique match in the same file; otherwise it stops with an error. Do not guess: run `vault tasks` again.
- `TEXT` is the task text without `- [ ] `. Each extra `CHILD` argument becomes a `- ` bullet under the task (for notes or context the user gave).
- `D` is `YYYY-MM-DD`. The daily note is made from the vault template if it does not exist.
- Exit 0 = done, 1 = error, 2 = refused (see delete).

## Rules

- "Remove", "finish", "close", "check off" a task → `done`. Use `delete` only when the user says delete (or clearly means the task was a mistake).
- `delete` with lines under the task exits 2 and prints them. Show the user what will go and ask. Re-run with `--force` only after they agree.
- "Drop", "won't do" → `cancel`.
- Never commit. Run `vault sync` only when the user asks to sync, back up, or push the vault.
- Task fields go in TEXT as emoji, in this order after the description: priority, then dates.
  - Priority: 🔺 highest, ⏫ high, 🔼 medium, 🔽 low, ⏬ lowest.
  - Dates (`YYYY-MM-DD`): 📅 due, ⏳ scheduled, 🛫 start. Recurrence: 🔁 every week.
  - Change a field on an existing task with `set` and the full new text.
- Keep the user's voice: lower case, short, no added detail. Do not add `[[links]]`; the dashboard shows the source note.
- For daily-note edits the script does not cover (rewrite a paragraph, move a section), use `vault daily` to read the note, then the Edit tool. Keep the frontmatter as it is. Use `## ` headings and `- ` lists.
- Do not touch `tasks.md` query blocks unless the user asks to change the dashboard.
