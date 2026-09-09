#!/bin/sh
# One fzf popup listing every session, window and pane in the server as a tree
# (prefix + w). fzf matches incrementally across the whole row — session name,
# window name, pane title and path at once.
#
# Enter jumps to the row under the cursor; m marks rows and M moves everything
# marked into the row the cursor is on.
#
# The script re-enters itself: fzf's reload/execute/preview bindings all call
# "$0" with a mode argument. Modes are `list`, `act <verb> <key>` and
# `preview <key>`; no argument is the interactive entry.

# display-popup runs a non-login sh whose PATH comes from the tmux *server's*
# environment; Homebrew's bin is the one that goes missing.
case ":$PATH:" in
  *:/opt/homebrew/bin:*) ;;
  *) PATH="/opt/homebrew/bin:$PATH" ;;
esac
export PATH

# display-popup -E tears the popup down the instant the command exits, so a
# failure that just prints and returns reads as the popup flashing open and
# closing. Every abnormal exit goes through die() to hold the window open.
die() {
  printf '%s\n\n' "$*"
  printf 'Press enter to close.'
  read -r _
  exit 1
}

# Set TMUX_TREE_DEBUG=1 in the tmux server environment to trace a run:
#   tmux setenv -g TMUX_TREE_DEBUG 1
# The trace lands in the log below and survives the popup closing.
if [ "${TMUX_TREE_DEBUG:-0}" = "1" ]; then
  exec 2>>"${TMPDIR:-/tmp}/tmux-tree.log"
  echo "--- $(date '+%F %T') pid=$$ argv=$* ---" >&2
  set -x
fi

# fzf's reload/execute/preview bindings all re-run this script, so the path has
# to survive being handed to a child with a different cwd. The tmux bindings
# already pass an absolute path; this only covers running it by hand.
SELF=$0
case $SELF in
  /*) ;;
  *)  SELF=$(cd "$(dirname "$SELF")" && pwd)/$(basename "$SELF") ;;
esac
TAB=$(printf '\t')
FOLD_FILE="${TMPDIR:-/tmp}/tmux-tree-folds"
MARK_FILE="${TMPDIR:-/tmp}/tmux-tree-marks"

# --- Palette ---------------------------------------------------------------
# fzf does not expand tmux formats, so the onedark user options from .tmux.conf
# are read once and turned into truecolor SGR sequences by hand. Fetched in a
# single display-message and parsed with expansions only: show-options per
# colour cost five server round-trips before the list was even built, on a
# script that reruns on every keystroke of a search.
sgr() {
  h=${1#\#}
  [ ${#h} -eq 6 ] || return 0
  r=${h%????} gb=${h#??}
  printf '\033[38;2;%d;%d;%dm' "$((0x$r))" "$((0x${gb%??}))" "$((0x${gb#??}))"
}

# Computed once and exported, so the reload and preview children inherit them
# instead of paying for the round-trip again.
if [ -z "${C_OFF:-}" ]; then
  IFS="$TAB" read -r _blue _fg _muted _green _yellow <<EOF
$(tmux display-message -p "#{@blue}${TAB}#{@fg}${TAB}#{@muted}${TAB}#{@green}${TAB}#{@yellow}")
EOF
  C_OFF=$(printf '\033[0m')
  C_BOLD=$(printf '\033[1m')
  C_BLUE=$(sgr "$_blue")
  C_FG=$(sgr "$_fg")
  C_MUTED=$(sgr "$_muted")
  C_GREEN=$(sgr "$_green")
  C_YELLOW=$(sgr "$_yellow")
  export C_OFF C_BOLD C_BLUE C_FG C_MUTED C_GREEN C_YELLOW
fi

# --- Row formats -----------------------------------------------------------
# One `list-panes -a` produces the whole tree: every pane line already carries
# its ancestors, and awk emits a session or window row the first time it sees a
# new one. That turns three server round-trips into one.
#
# Padding is tmux's own #{pN:...} (pad) and #{=N:...} (clip) rather than printf
# or column(1): both are display-width aware, so the box-drawing prefixes and
# any wide characters in a title stay in their columns.
#
# pane_title defaults to the hostname, so that case falls back to the running
# command — the same suppression pane-border-format uses in .tmux.conf.
#
# Fields 12 and 13 are the ancestry column, drawn only while searching: a
# filtered pane row has lost the parent rows that said where it came from.
#
# The last three are Claude Code's state, written by ~/.claude/tmux-claude-state.sh
# at pane, window and session scope under three separate names. Every field is
# evaluated in pane context, so a pane carries its own state *and* its window's
# and session's — which is what lets a folded session or window row still show
# that something inside it finished.
ROW_FMT="#{session_name}${TAB}#{session_windows}${TAB}#{p46:#{=45:#{session_name}}}${TAB}#{session_windows} window#{?#{==:#{session_windows},1},,s}\
${TAB}#{window_index}${TAB}#{window_panes}${TAB}#{p45:#{=44:#{window_name}}}${TAB}#{window_panes} pane#{?#{==:#{window_panes},1},,s}\
${TAB}#{pane_id}${TAB}#{p42:#{=41:#{?#{==:#{pane_title},#{host}},#{pane_current_command},#{pane_title}}}}${TAB}#{s|^$HOME|~|:pane_current_path}\
${TAB}#{p28:#{=27:#{session_name}}}${TAB}#{p28:#{=27:#{session_name} › #{window_index}: #{window_name}}}\
${TAB}#{@claude_pane_state}${TAB}#{@claude_state}${TAB}#{@claude_session_state}"

# --- Building the list -----------------------------------------------------
# A fold hides rows, and a hidden row cannot be fuzzy-matched, so folds only
# apply while the query is empty: the moment you type, the whole tree is in the
# list, and clearing the query folds it back up.
#
# Rows come out as key TAB coloured-display, with --with-nth=2.. so the key is
# hidden and never matched against.
#
# Row numbers (`:N` jumps to one) are positions in the list, not tmux indexes,
# and are drawn only while the query is empty — fzf filters the list after awk
# has numbered it, so under a search the numbers on screen would no longer be
# the positions they name.
#
# Four fixed-width columns sit in front of every label: a four-cell number
# gutter, a two-cell mark gutter, a two-cell Claude-state gutter and a two-cell
# type icon. Being fixed on every row is what keeps the label padding tmux
# already did in ROW_FMT honest.
#
# The state gutter is the same ● the tmux status bar draws, and sits on session
# and window rows as well as panes — that is how you find which pane is waiting
# when the session or window holding it is folded shut.
#
# The ancestry column sits between the label and the meta, where every row is
# already flush; in front it would break the per-depth label padding. fzf
# matches the display column, so it is matched too: "mrm claude" finds the
# Claude pane in the MRM window even though neither its title nor its path
# says MRM.
TREE_AWK='
function emit(key, prefix, colour, icon, label, anc, meta, state,   c, g, n, d) {
  c = (key == srcpane) ? ccur : colour
  g = (key in mark) ? (cmark gmark " " coff) : "  "
  d = (state == "waiting") ? (cwait gstate " " coff) \
    : (state == "done")    ? (cdone gstate " " coff) : "  "
  n = searching ? "    " : sprintf("%3d ", ++nr)
  printf "%s\t%s\n", key,
         cmuted n coff g d cmuted prefix c icon label coff canc anc cmuted meta coff
}
BEGIN {
  FS = "\t"
  while ((getline line < foldfile) > 0) fold[line] = 1
  while ((getline line < markfile) > 0) mark[line] = 1
  down = "\342\226\276 "; right = "\342\226\270 "
  tee = "\342\224\234\342\224\200 "; elbow = "\342\224\224\342\224\200 "
  pipe = "\342\224\202  "; blank = "   "
  isess = "\357\210\263 "; iwin = "\357\213\220 "; ipane = "\357\204\240 "
  gmark = "\357\200\214"; gstate = "\342\227\217"
  # A session row has no ancestor to name, but still owes the column its width
  # while searching, or its meta would sit left of everything else there.
  noanc = sprintf("%28s", "")
}
{
  if ($1 != sess) {
    sess = $1; swins = $2 + 0; wseen = 0; win = ""
    skey = "s:" sess
    sshut = (!searching && (skey in fold))
    emit(skey, sshut ? right : down, csess, isess, $3, searching ? noanc : "", $4, $16)
  }
  if (sshut) next

  wkey = "w:" sess ":" $5
  if (wkey != win) {
    win = wkey; wpanes = $6 + 0; pseen = 0; wseen++
    wlast = (wseen == swins)
    emit(wkey, wlast ? elbow : tee, cwin, iwin, $7, searching ? $12 : "", $8, $15)
    wshut = (!searching && (wkey in fold))
    trunk = wlast ? blank : pipe
  }
  if (wshut) next

  pseen++
  emit("p:" $9, trunk (pseen == wpanes ? elbow : tee), cpane, ipane, $10,
       searching ? $13 : "", $11, $14)
}'

list() {
  tmux list-panes -a -F "$ROW_FMT" 2>/dev/null \
    | awk -v searching="$1" -v foldfile="$FOLD_FILE" -v markfile="$MARK_FILE" \
          -v srcpane="p:$SRC_PANE" \
          -v csess="$C_BLUE$C_BOLD" -v cwin="$C_FG$C_BOLD" -v cpane="$C_FG" \
          -v cmuted="$C_MUTED" -v ccur="$C_BLUE" -v cmark="$C_YELLOW" \
          -v cwait="$C_YELLOW" -v cdone="$C_GREEN" \
          -v canc="$C_BLUE" -v coff="$C_OFF" "$TREE_AWK"
}

# --- Targets ---------------------------------------------------------------
# A tmux target string for any key. A session or window key resolves to its
# active pane, which is what makes preview and M work on a collapsed row
# without the cursor having to reach a pane.
target() {
  case $1 in
    p:*) printf '%s' "${1#p:}" ;;
    w:*) printf '%s' "${1#w:}" ;;
    s:*) printf '%s:' "${1#s:}" ;;
  esac
}

# The new thing opens where the row it was created from is, which is almost
# always the intent. Resolved with display-message rather than passing
# -c "#{pane_current_path}" straight to tmux: that format would be expanded
# against whatever tmux considers current, not against the chosen row.
cwd_of() { tmux display-message -p -t "$1" '#{pane_current_path}'; }

pause() {
  printf '\n\nPress enter to continue.'
  read -r _
}

# --- Moving marked rows -----------------------------------------------------
# m marks a row; M drops everything marked into the row the cursor is on, so
# one key covers both directions and any number of rows at once.
#
# A pane can live in any window, so it goes to the window holding the chosen
# row. A window cannot sit inside another window, so a marked window takes the
# chosen row's *session* instead — which is what makes M on a pane row
# meaningful for a marked window rather than an error.
#
# Rows already at their destination are skipped rather than refused; only real
# failures are reported.
#
# join-pane names its source with -s. Without it tmux prefers its own marked
# pane (select-pane -m, which the status-bar drag bindings in .tmux.conf set),
# and a leftover one there would move a pane nobody chose. -d on both moves
# keeps focus where it is.
move_marked() {
  dst=$1
  if [ ! -s "$MARK_FILE" ]; then
    printf 'Nothing marked. Press m on a row first.'
    pause
    return
  fi

  # One lookup, not two: the session is the window target minus its index.
  # Trimming from the right rather than the left is what keeps a session name
  # containing a colon intact. The pattern test is the liveness check —
  # display-message exits 0 on a target that no longer exists and prints a
  # half-empty answer, so the exit status is no use here.
  dst_win=$(tmux display-message -p -t "$dst" '#{session_name}:#{window_index}' 2>/dev/null)
  case $dst_win in
    ?*:[0-9]*) dst_sess=${dst_win%:*} ;;
    *) printf 'That row is gone.'; pause; return ;;
  esac

  moved=0 errs=''
  while IFS= read -r mk; do
    case $mk in
      p:*)
        src=${mk#p:}
        here=$(tmux display-message -p -t "$src" '#{session_name}:#{window_index}' 2>/dev/null)
        [ -n "$here" ] || { errs="$errs
  $src is gone."; continue; }
        [ "$here" != "$dst_win" ] || continue
        if out=$(tmux join-pane -dh -s "$src" -t "$dst_win" 2>&1); then
          moved=$((moved + 1))
        else
          errs="$errs
  $src: $out"
        fi
        ;;
      w:*)
        # The key is w:<session>:<index>, so stripping "w:" leaves a target
        # window tmux takes as-is.
        src=${mk#w:}
        [ "${src%%:*}" != "$dst_sess" ] || continue
        # -t "<session>:" with no index is how tmux is asked for the next free
        # one; naming an index would collide with whatever already holds it.
        if out=$(tmux move-window -d -s "$src" -t "$dst_sess:" 2>&1); then
          moved=$((moved + 1))
        else
          errs="$errs
  $src: $out"
        fi
        ;;
    esac
  done < "$MARK_FILE"

  : > "$MARK_FILE"
  [ -z "$errs" ] || { printf 'Moved %d.%s' "$moved" "$errs"; pause; }
}

# --- Mutations -------------------------------------------------------------
# Run from fzf bindings, each followed by reload($SELF list), so the tree
# redraws in place and the popup never closes for a create, rename, kill or
# fold.
#
# Anything that needs a name or a confirmation is handed it as $4 rather than
# reading it here: a prompt of its own needs the terminal, and fzf only gives a
# child the terminal by painting it over the list. See Prompt mode below.
act() {
  verb=$1 key=$2 pos=$3 text=$4
  [ -n "$key" ] || exit 0
  tgt=$(target "$key")
  save_pos "$key" "${pos:-0}" "$verb"

  case $verb in
    collapse|expand)
      # h on a pane closes the window holding it, the way h on a file closes
      # its directory in a file tree — otherwise the key is a dead end on a
      # third of the rows. Panes have nothing of their own to fold.
      case $key in
        p:*) [ "$verb" = collapse ] || exit 0
             key="w:$(tmux display-message -p -t "$tgt" '#{session_name}:#{window_index}')" ;;
      esac
      touch "$FOLD_FILE"
      if grep -qxF "$key" "$FOLD_FILE"; then
        [ "$verb" = collapse ] && exit 0
        # Not `grep ... && mv`: grep exits 1 when it selects no lines, which is
        # exactly the unfold-the-last-row case. The redirection has already
        # written the (possibly empty) file by then, so move it regardless.
        grep -vxF "$key" "$FOLD_FILE" > "$FOLD_FILE.tmp"
        mv "$FOLD_FILE.tmp" "$FOLD_FILE"
      else
        [ "$verb" = expand ] && exit 0
        printf '%s\n' "$key" >> "$FOLD_FILE"
      fi
      ;;
    new)
      # "new" is a sibling of whatever the cursor sits on. Sessions and windows
      # are named, for the same reason as bind c/C in .tmux.conf; panes have no
      # name to ask for, which is why p: is the one row where n does not prompt.
      case $key in
        s:*) tmux new-session -d -s "$text" -c "$(cwd_of "$tgt")" ;;
        # -a inserts after the window under the cursor; without it a bare
        # index that is already taken is an error rather than a sibling.
        w:*) tmux new-window -d -a -n "$text" -t "$tgt" -c "$(cwd_of "$tgt")" ;;
        p:*) tmux split-window -h -d -t "$tgt" -c "$(cwd_of "$tgt")" ;;
      esac
      ;;
    rename)
      case $key in
        s:*) tmux rename-session -t "$tgt" "$text" ;;
        w:*) tmux rename-window -t "$tgt" "$text"
             # automatic-rename is on globally in .tmux.conf, so a hand-typed
             # name would be overwritten by the directory basename on the next
             # cd. rename-window does turn it off itself; saying so is free.
             tmux set-window-option -t "$tgt" automatic-rename off ;;
        p:*) tmux select-pane -t "$tgt" -T "$text" ;;
      esac
      ;;
    kill)
      # Only sessions confirm, before act() is reached: a session takes every
      # window and pane with it, while a pane or window is cheap enough that
      # confirming every kill would defeat the point of the key.
      case $key in
        s:*) tmux kill-session -t "$tgt" ;;
        w:*) tmux kill-window -t "$tgt" ;;
        p:*) tmux kill-pane -t "$tgt" ;;
      esac
      ;;
    mark)
      # Same toggle-in-a-file shape as the folds above, and the same reason the
      # mv is unconditional.
      touch "$MARK_FILE"
      if grep -qxF "$key" "$MARK_FILE"; then
        grep -vxF "$key" "$MARK_FILE" > "$MARK_FILE.tmp"
        mv "$MARK_FILE.tmp" "$MARK_FILE"
      else
        printf '%s\n' "$key" >> "$MARK_FILE"
      fi
      ;;
    unmark) : > "$MARK_FILE" ;;
    move)   move_marked "$tgt" ;;
  esac
}

# A reload drops the cursor at the top of the list, which after folding or
# renaming a row means losing your place. fzf's --track --id-nth is unusable
# here: tracking blocks query input while it re-finds the row after each
# reload, and this list reloads on every keystroke, so fast typing lost
# characters. So the cursor is placed by hand instead.
#
# Each action leaves the answer in a file for a transform after the reload to
# read back as a pos() action. A file rather than the obvious transform
# argument because fzf expands {1} and {n} separately for each action in a
# chain, at the moment that action runs — by the time a trailing transform
# fires, both describe the row the cursor accidentally landed on.
POS_FILE="${TMPDIR:-/tmp}/tmux-tree-pos"

# Always writes: an empty transform leaves the cursor where the reload put it,
# which is the top. $2 is the row's zero-based index, so +1 is the 1-based
# position pos() wants. h on a pane is the exception — it closes the window
# above, which sits exactly pane_index rows up. Marking goes the other way: m
# steps down a row so a run of panes can be marked in sequence. fzf clamps a
# pos() past the end, so the last row needs no special case.
save_pos() {
  _off=0
  case $3:$1 in
    collapse:p:*) _off=$(tmux display-message -p -t "${1#p:}" '#{pane_index}' 2>/dev/null) || _off=0 ;;
    mark:*)       _off=-1 ;;
  esac
  printf 'pos(%d)' "$(($2 + 1 - _off))" > "$POS_FILE"
}

# --- Modal editing ---------------------------------------------------------
# fzf has no modes, but it has unbind() and rebind(): every normal-mode key is
# declared as a binding, i/a// unbind the lot so they type like ordinary
# characters again (insert mode), and esc rebinds them (normal mode).
#
# The popup opens in normal mode — bindings live, no `start:unbind` — because
# the first thing you do is almost always move to a row you can already see.
#
# Only rebind() can turn a binding back on, and only for a key declared at
# startup, which is why the dead keys below have to be declared rather than
# left out. Bound to ignore, they keep a stray `w` out of the query.
#
# There is a third mode: prompt mode, where the query line is borrowed as the
# input box for a name or a confirmation. It unbinds the same set and is
# unwound by enter or esc. See Prompt mode.
VIM_NAV='j,k,g,G,d,u,:'
VIM_MODE='i,a,/,q'
VIM_ACT='h,l,n,r,x,p,m,M,U'

dead_keys=''
dead_binds=''
for k in b c e f o s t v w y z space \
         A B C D E F H I J K L N O P Q R S T V W X Y Z \
         0 1 2 3 4 5 6 7 8 9; do
  dead_keys="$dead_keys,$k"
  dead_binds="$dead_binds,$k:ignore"
done
MODAL_KEYS="$VIM_NAV,$VIM_MODE,$VIM_ACT${dead_keys}"
dead_binds=${dead_binds#,}

# The prompt says what the query line is for — "Search" normally, the action's
# own label while one is pending — and is yellow in normal mode for the same
# reason the status bar is while the prefix is pending: the next key does
# something other than what it says.
P_TAIL='> '
P_INSERT="Search $P_TAIL"
P_NORMAL="$C_YELLOW$P_INSERT"

# --- Prompt mode -----------------------------------------------------------
# Naming a new window, renaming a row, confirming a kill and jumping to a row
# number all need a line of text. Read in an execute() child, fzf gives that
# child the terminal, so its prompt paints over the tree you are acting on.
#
# So the query line is borrowed instead. The only reasons it filters and
# searches are two bindings and a flag, and fzf can turn all three off:
#
#   disable-search   what you type stops filtering the list, but {q} still
#                    carries it, so the tree stays whole and on screen
#   unbind(change)   and stops rebuilding it on every keystroke
#   unbind(MODAL)    the normal-mode keys type again, exactly as i does
#   change-prompt    the label says which prompt this is
#
# What is pending lives in a file, since fzf holds no state of its own: enter
# and esc are one binding each and have to work out whether there is a prompt
# open to commit or cancel.
PEND_FILE="${TMPDIR:-/tmp}/tmux-tree-pending"

# The label is the only thing that says which prompt is open, so it names the
# row type too — "New window" and "New session" are different enough answers
# to be worth distinguishing before you type, not after.
prompt_label() {
  case $1:$2 in
    new:s:*)    printf 'New session' ;;
    new:w:*)    printf 'New window' ;;
    rename:p:*) printf 'Pane title' ;;
    rename:*)   printf 'Rename' ;;
    kill:*)     printf 'Kill session?' ;;
    goto:*)     printf 'Go to row' ;;
  esac
}

open_prompt() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" > "$PEND_FILE"
  # The cursor has to survive the reload the binding does next, and the row is
  # not moving, so this is the ordinary no-offset case save_pos already covers.
  save_pos "$2" "${3:-0}" prompt
  printf 'disable-search+unbind(change)+unbind(%s)+clear-query+change-prompt(%s %s)' \
         "$MODAL_KEYS" "$(prompt_label "$1" "$2")" "$P_TAIL"
}

# Unwinding is the same four switches thrown back, plus the redraw: the query
# was cleared on the way in, so `list` with no argument is the unfiltered,
# numbered tree, and pos() puts the cursor back on the row that was acted on.
close_prompt() {
  # act() may have left one behind through save_pos. The position is emitted
  # here instead, so a stale file would only misplace the next transform.
  rm -f "$POS_FILE"
  printf 'clear-query+enable-search+rebind(change)+rebind(%s)+change-prompt(%s)+reload-sync(%s list)+pos(%d)' \
         "$MODAL_KEYS" "$P_NORMAL" "$SELF" "$1"
}

# Which verbs need typing is a property of the row, not just the verb: n on a
# pane is a split with nothing to name, and x on anything but a session does
# not ask. Those run here and print nothing, leaving the binding's own reload
# to redraw — which is what every non-prompting key already does.
begin() {
  case $1:$2 in
    goto:*)                  open_prompt "$1" "$2" "$3" ;;
    *:'')                    exit 0 ;;
    new:p:*|kill:w:*|kill:p:*) act "$1" "$2" "$3" '' 2>/dev/null ;;
    *)                       open_prompt "$1" "$2" "$3" ;;
  esac
}

# Enter means commit while a prompt is open and jump otherwise, which is why it
# is a binding rather than --expect: --expect fixes one meaning for the whole
# run. With nothing pending it prints `accept`, and fzf closes the popup with
# the row under the cursor exactly as before.
commit() {
  [ -s "$PEND_FILE" ] || { printf 'accept'; return; }
  IFS="$TAB" read -r _verb _key _pos < "$PEND_FILE"
  rm -f "$PEND_FILE"
  case $_verb in
    goto)
      # A blank or non-numeric answer just closes the prompt, which is the same
      # thing esc does — there is nothing to half-apply.
      case $2 in
        ''|*[!0-9]*) ;;
        *) _pos=$(($2 - 1)) ;;
      esac
      ;;
    kill)
      # Enter is the confirmation, so there is nothing to check: esc is how you
      # back out, the same key that backs out of every other prompt.
      act kill "$_key" "$_pos" '' 2>/dev/null
      ;;
    *)
      # An empty name cancels rather than renaming something to nothing, which
      # is what the old read -r prompt did by returning non-zero on a blank.
      [ -n "$2" ] && act "$_verb" "$_key" "$_pos" "$2" 2>/dev/null
      ;;
  esac
  close_prompt "$((_pos + 1))"
}

# Esc out of a search is only a mode switch: the query stays, so there is
# nothing to redraw and no place to restore. Esc out of a prompt is the full
# unwind, minus the action.
cancel() {
  if [ -s "$PEND_FILE" ]; then
    IFS="$TAB" read -r _verb _key _pos < "$PEND_FILE"
    rm -f "$PEND_FILE"
    close_prompt "$((_pos + 1))"
  else
    printf 'rebind(%s)+change-prompt(%s)' "$MODAL_KEYS" "$P_NORMAL"
  fi
}

case ${1:-} in
  list)    list "$2"; exit 0 ;;
  begin)   begin "$2" "$3" "$4"; exit 0 ;;
  commit)  commit "$2" "$3" "$4"; exit 0 ;;
  cancel)  cancel; exit 0 ;;
  after-act) cat "$POS_FILE" 2>/dev/null; rm -f "$POS_FILE"; exit 0 ;;
  act)     act "$2" "$3" "$4" "$5"; exit 0 ;;
  preview) tmux capture-pane -ep -t "$(target "$2")" 2>/dev/null; exit 0 ;;
esac

# --- Interactive -----------------------------------------------------------
command -v fzf >/dev/null 2>&1 || die "fzf not found on PATH.

  brew install fzf

PATH was:
$PATH"

# Resolved here rather than passed in from the binding: display-popup does NOT
# format-expand its shell-command, so '#{pane_id}' arrived as the literal
# placeholder. The popup belongs to the client, so this resolves against the
# client's active pane. Exported so the reload/execute children see it too.
SRC_PANE=$(tmux display-message -p '#{pane_id}')
export SRC_PANE
[ -n "$SRC_PANE" ] || die "could not determine the current tmux pane."

# Folds and marks are reseeded on every open rather than persisted: a fold is
# only meant to last as long as the popup is up, and a leftover mark would name
# a row you have since forgotten about — and M would move it.
: > "$FOLD_FILE"
: > "$MARK_FILE"
rm -f "$POS_FILE" "$PEND_FILE"


# ctrl-based keys work in both modes, so nothing has to be remembered twice.
# Marking during a search is the reason that matters: a search is how you reach
# the rows you want to mark. Folding is the exception — h/l only, since a tree
# wants a direction rather than a toggle and there is no unmodified pair to
# alias it to. Enter and esc mean different things in different modes, so both
# ask the script which it is.
#
# The header lists only the keys you would not guess.
header=':N row  n new  r rename  x kill  m mark  M move marked  U unmark  / search'

out=$(list | fzf \
  --ansi \
  --no-sort \
  --layout=reverse \
  --delimiter="$TAB" \
  --with-nth=2.. \
  --prompt="$P_NORMAL" \
  --header="$header" \
  --header-first \
  --bind='ctrl-j:down,ctrl-k:up' \
  --bind="enter:transform('$SELF' commit {1} {q} {n})" \
  --bind="esc:transform('$SELF' cancel)" \
  --bind="i:unbind($MODAL_KEYS)+change-prompt($P_INSERT)" \
  --bind="a:unbind($MODAL_KEYS)+change-prompt($P_INSERT)" \
  --bind="/:unbind($MODAL_KEYS)+change-prompt($P_INSERT)" \
  --bind='j:down,k:up,g:first,G:last,d:half-page-down,u:half-page-up' \
  --bind="::transform('$SELF' begin goto {1} {n})+reload-sync('$SELF' list {q})+transform('$SELF' after-act)" \
  --bind='q:abort,p:toggle-preview' \
  --bind="$dead_binds" \
  --bind="n:transform('$SELF' begin new {1} {n})+reload-sync('$SELF' list {q})+transform('$SELF' after-act)" \
  --bind="r:transform('$SELF' begin rename {1} {n})+reload-sync('$SELF' list {q})+transform('$SELF' after-act)" \
  --bind="x:transform('$SELF' begin kill {1} {n})+reload-sync('$SELF' list {q})+transform('$SELF' after-act)" \
  --bind="h:execute-silent('$SELF' act collapse {1} {n})+reload-sync('$SELF' list {q})+transform('$SELF' after-act)" \
  --bind="l:execute-silent('$SELF' act expand {1} {n})+reload-sync('$SELF' list {q})+transform('$SELF' after-act)" \
  --bind="m:execute-silent('$SELF' act mark {1} {n})+reload-sync('$SELF' list {q})+transform('$SELF' after-act)" \
  --bind="U:execute-silent('$SELF' act unmark {1} {n})+reload-sync('$SELF' list {q})+transform('$SELF' after-act)" \
  --bind="M:execute('$SELF' act move {1} {n})+reload-sync('$SELF' list {q})+transform('$SELF' after-act)" \
  --bind='?:toggle-preview' \
  --bind="change:reload('$SELF' list {q})" \
  --bind='alt-j:preview-down,alt-k:preview-up' \
  --bind="ctrl-n:transform('$SELF' begin new {1} {n})+reload-sync('$SELF' list {q})+transform('$SELF' after-act)" \
  --bind="ctrl-r:transform('$SELF' begin rename {1} {n})+reload-sync('$SELF' list {q})+transform('$SELF' after-act)" \
  --bind="ctrl-x:transform('$SELF' begin kill {1} {n})+reload-sync('$SELF' list {q})+transform('$SELF' after-act)" \
  --bind="ctrl-t:execute-silent('$SELF' act mark {1} {n})+reload-sync('$SELF' list {q})+transform('$SELF' after-act)" \
  --bind="ctrl-g:execute('$SELF' act move {1} {n})+reload-sync('$SELF' list {q})+transform('$SELF' after-act)" \
  --preview="'$SELF' preview {1}" \
  --preview-window=right,45%)
rc=$?

# 0 chose something, 1 is "no match", 130 is Esc/Ctrl-C. Those three are the
# user deciding, so close quietly. Anything else is fzf itself failing and
# would otherwise be the flash-and-vanish case.
case "$rc" in
  0)      ;;
  1|130)  exit 0 ;;
  *)      die "fzf exited with status $rc." ;;
esac

# One line, the chosen row: enter is a binding printing `accept` now, not
# --expect, so there is no key line in front of it.
key=$(printf '%s\n' "$out" | cut -d"$TAB" -f1)
[ -n "$key" ] || exit 0
tgt=$(target "$key")

# Enter is the only key that closes the popup with a row: everything else acts
# in place and reloads. select-window resolves a pane target to its containing
# window, and select-pane unzooms that window on its own if it was zoomed on
# some other pane — so the row you picked is always the one you land on and can
# see. switch-client first, because the target may be another session.
tmux switch-client -t "$(tmux display-message -p -t "$tgt" '#{session_name}')"
tmux select-window -t "$tgt"
case $key in p:*) tmux select-pane -t "$tgt" ;; esac
