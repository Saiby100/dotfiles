#!/bin/sh
# Mirror Claude Code's attention state onto its tmux pane, for the status bar
# and the session tree. Wired to hooks in ~/.claude/settings.json:
#
#   PermissionRequest, PreToolUse(AskUserQuestion)  -> waiting  (blocked on you)
#   Stop                                            -> done     (turn finished)
#   UserPromptSubmit, PostToolUse(Failure)          -> clear    (working again)
#   SessionEnd                                      -> end      (clear, and forget the session ID)
#
# Notification is deliberately not used: it also fires ~60s after any finished
# turn ("waiting for your input"), which turned every green dot yellow.
#
# State lives on the pane alone, as @claude_pane_state. Windows and sessions
# work theirs out from their panes with #{P:} / #{W:} loops (.tmux.conf,
# tree.sh), so two Claude panes in one window can no longer clear each other's
# dot.

# Hooks receive JSON on stdin. Drain it so Claude never blocks on the pipe.
cat >/dev/null 2>&1

# Claude runs outside tmux plenty (plain terminal, CI, an editor's terminal).
[ -n "$TMUX" ] && [ -n "$TMUX_PANE" ] || exit 0

P=$TMUX_PANE
# The pane on screen right now: active in its window, in the active window,
# in a session a client is attached to.
LOOKING='#{&&:#{session_attached},#{&&:#{window_active},#{pane_active}}}'

# One tmux call per hook: PostToolUse fires on every tool call, so this stays
# cheap. Clearing only touches the server when there is something to clear.
case $1 in
  clear)
    tmux if-shell -F -t "$P" '#{@claude_pane_state}' \
      "set-option -up -t $P @claude_pane_state ; refresh-client -S" ;;
  end)
    tmux set-option -up -t "$P" @claude_pane_state \; \
         set-option -up -t "$P" @claude_session_id \; \
         refresh-client -S ;;
  waiting|done)
    # A dot on the pane you are looking at is noise: you have already seen it.
    tmux if-shell -F -t "$P" "$LOOKING" \
      "set-option -up -t $P @claude_pane_state" \
      "set-option -p -t $P @claude_pane_state $1" \; \
         refresh-client -S ;;
esac 2>/dev/null

# Never fail: a non-zero exit from a hook is surfaced to Claude as an error.
exit 0
