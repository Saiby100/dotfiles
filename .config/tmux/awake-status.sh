#!/bin/sh
# The sleep-disabled glyph in status-right. Prints one styled character while
# `awake on` has sleep disabled, and nothing otherwise; tmux expands the
# #[fg=...] tag that comes back from #().
#
# It is a warning light: disabled sleep is system-wide and keeps the Mac awake
# on battery too, so it should be hard to forget.

GLYPH="󰅶"   # nf-md-coffee (U+F0176) — deliberately not the ● used for Claude state

# pmset -g reads without root and answers in a few ms, well inside the 5s
# status-interval. Off macOS there is no pmset, so the glyph never shows.
pmset -g 2>/dev/null | grep -q 'SleepDisabled[[:space:]]*1' || exit 0

# Newline-terminated: tmux reads a #() job's output a line at a time.
printf '#[fg=%s]%s\n' "$(tmux show-options -gv @yellow)" "$GLYPH"
