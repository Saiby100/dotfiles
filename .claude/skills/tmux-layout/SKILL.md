---
name: tmux-layout
description: Read and rearrange the user's tmux panes, windows and sessions. Use when the user asks what is in a pane or next to you ("what pane is to your left?", "what's the other Claude doing?", "which session has nvim?"), or asks for a layout change — side by side, stacked, moved to another window or session, resized, renamed, split out, reordered, zoomed or killed ("put the two Claude panes side by side", "move this to the work session", "make nvim take 70%", "close the zsh panes").
user-invocable: true
allowed-tools: Bash(~/.claude/skills/tmux-layout/scripts/tmuxctl), Bash(~/.claude/skills/tmux-layout/scripts/tmuxctl *)
argument-hint: "<question, or the layout you want>"
---

# tmux layout

Use `~/.claude/skills/tmux-layout/scripts/tmuxctl` (called `tmuxctl` below)
for everything. Do not call `tmux` directly unless `tmuxctl` has no command for
the job. `tmuxctl` already does the following:

- it reads the whole server in one `tmux` call
- it resolves every target to an ID before running anything
- it keeps `-d` (the user's focus stays put) and `-s` (never the marked pane)
  on every move
- it prints the affected windows after each change

## 1. Look

```sh
tmuxctl            # me, my neighbours, then every session/window/pane
tmuxctl peek left  # last 40 lines on that pane's screen (-n 80 for more)
tmuxctl find work claude
```

Each pane row shows: ID, index, where it sits in the window (`left 50%x100%`),
command (`claude` for Claude panes), tags with Claude's state (`claude[done]`,
`claude[waiting]`), title and path. `ME` marks this pane and `*` marks the
active pane. `--json` gives the same data as JSON.

## 2. Targets

Any command accepts:

| Form | Meaning |
|---|---|
| `%12` `@4` `$1` | pane / window / session ID |
| `me` | this pane |
| `left` `right` `up` `down` | my neighbour that way |
| `work:1` `work:1.2` | session:window[.pane], resolved now |
| `work` | that session (exact name) |
| words, e.g. `"work nvim"` | must match exactly one pane, or it lists the candidates and stops |

When words match several panes, pick from the list or ask the user. Don't
guess. Once you have IDs, keep using them: indexes shift after every move.

## 3. Change

```sh
tmuxctl beside %5 %3 --right --size 35%   # %5 next to %3; --left/--above/--below
tmuxctl break %5 --name review [--session work]
tmuxctl window-to @4 work
tmuxctl swap %5 %3
tmuxctl swap-window @4 @2
tmuxctl resize %5 --width 70% [--height 40%]
tmuxctl layout @4 main-vertical --main 65%   # even-horizontal, even-vertical, tiled, main-horizontal
tmuxctl rename-window @4 api
tmuxctl rename-session work main
tmuxctl new-window --session work --dir ~/Developer/x --name x
tmuxctl zoom %5
```

- For a layout that no preset gives, build it with `beside ... --size`,
  working from the outside in.
- Moving your own pane is fine. Don't break it out into another session
  unless asked, or the user loses sight of you.
- Only move the user's view (`tmux select-window`, `switch-client`) when they
  ask to go somewhere.

## 4. Killing needs a yes

```sh
tmuxctl kill %5 @4          # preview only: lists every pane that would go, exits 3
tmuxctl kill %5 @4 --yes    # after the user confirms
```

The user confirms through Claude Code's permission dialog, not in chat:
`settings.json` has an `ask` rule for `tmuxctl kill *--yes*`. So in **one
response**:

1. Run the preview.
2. Write what will go in a line or two, naming any Claude, nvim or running
   process the preview flagged.
3. Run the same kill with `--yes`. The dialog is the user's yes or no.

Don't ask "kill it?" in chat as well; that makes them answer twice. If they
decline the dialog, stop and don't retry. If `--yes` runs without a dialog
(the `ask` rule is gone), say so. `tmuxctl` refuses to kill its own pane.

## 5. Report

Each change prints an `after:` tree. From it, say in one or two lines what now
sits where. If something failed, quote the `tmuxctl:` error and say what is
still undone.
