---
name: commit
description: Commit only task-related changes (Claude's + user's) with repo commit conventions, one commit per task. Use whenever committing changes, whether the user asks or a task calls for a commit.
user-invocable: true
allowed-tools: Bash, Read, Grep, Glob
---

# Commit

Commit the changes you made, plus any related changes the user made as part of the same task or issue. Exclude unrelated modifications in the working tree.

## Steps

1. Run `git status` (never use `-uall`) and `git diff` to see all staged and unstaged changes.
2. Run `git log --oneline -5` to see recent commit message style.
3. Identify which files are **in scope** — files you changed, plus any user-modified files that are clearly part of the same task/issue being addressed. If unsure whether a user change is related, ask.
4. **Partition the in-scope changes by task.** Each task gets its own commit. Group multiple tasks into one commit only when their functionality overlaps (e.g. they touch the same logic and can't be split cleanly). If unsure how to split, ask.
5. For each commit, stage only its files using `git add <file1> <file2> ...`. Never use `git add -A` or `git add .`. If one file holds changes for separate tasks, ask the user how to split it (interactive `git add -p` is not available).
6. Write a commit message following the repo conventions:
   - **Format**: `<type>: <Short description>`
   - **Types**: `feat` (new feature), `fix` (bug fix), `chore` (maintenance), `refactor` (code change with no behavior change), `wip` (work in progress)
   - **Title**: Under 72 characters. Say what changed in plain words.
   - **Body**: Optional for a single task — add one or two short lines only if the title needs context. When a commit groups overlapping tasks, add a bullet list with one short bullet per task.
   - Use simple language. Avoid jargon and filler; describe the change, not the process.
7. Commit using a HEREDOC for the message. Append `Co-Authored-By: Claude <Model> <noreply@anthropic.com>`, where `<Model>` is the model you are actually running as (e.g. `Opus 5`) — do not copy a hardcoded version from this file.
8. Repeat steps 5–7 for each remaining commit.
9. Run `git status` after committing to verify success.

## Rules

- Do NOT push unless the user explicitly asks.
- Do NOT amend existing commits unless the user explicitly asks.
- Do NOT commit files that may contain secrets (`.env`, credentials, tokens).
- If a pre-commit hook fails, fix the issue and create a NEW commit — do not amend.
