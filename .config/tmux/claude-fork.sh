#!/bin/sh
# Fork the Claude session in a pane into a new pane or window.
#
#   claude-fork.sh <pane-id> <h|v|w>
#
# h splits right, v splits below, w opens a new window. The source pane's
# session ID comes from @claude_session_id, set by the SessionStart hook in
# ~/.claude/tmux-claude-session.sh. The fork gets its own ID, so forks of
# forks work the same way.

pane=$1
mode=${2:-h}

id=$(tmux show-options -pqv -t "$pane" @claude_session_id)
if [ -z "$id" ]; then
  tmux display-message "No Claude session in this pane"
  exit 0
fi

dir=$(tmux display-message -p -t "$pane" '#{pane_current_path}')
cmd="claude --resume $id --fork-session"

case "$mode" in
  v) tmux split-window -v -t "$pane" -c "$dir" "$cmd" ;;
  w) tmux new-window -c "$dir" -n fork "$cmd" ;;
  *) tmux split-window -h -t "$pane" -c "$dir" "$cmd" ;;
esac
