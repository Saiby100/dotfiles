#!/bin/sh
# Record the Claude session ID on the tmux pane it runs in, so a tmux key can
# fork it (see ~/.config/tmux/claude-fork.sh). Wired to SessionStart, which
# also fires on /clear and /resume, so the pane always holds the live ID.

input=$(cat 2>/dev/null)

[ -n "$TMUX" ] && [ -n "$TMUX_PANE" ] || exit 0

id=$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -n "$id" ] && tmux set-option -p -t "$TMUX_PANE" @claude_session_id "$id" 2>/dev/null

# Never fail: a non-zero exit from a hook is surfaced to Claude as an error.
exit 0
