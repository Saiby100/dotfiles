# Prompt — custom git status via git_remote_status() defined below.
setopt prompt_subst
PROMPT=' %B%F{#61afef}%~%b
 %B$(git_remote_status)%b%F{#56b6c2}%B❯%b%f '

# Custom Variables
export EDITOR=vim

# Vi keybindings on the command line. Set explicitly instead of relying on
# zsh's auto-detection from $EDITOR (which only triggers if EDITOR contains
# "vi" and is exported before ZLE initializes — too fragile).
bindkey -v
KEYTIMEOUT=1                       # ~10ms after Esc, so mode switch feels instant

# History in cache directory:
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.cache/zshhistory
setopt appendhistory


# Basic auto/tab complete:
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)               # Include hidden files.

[ -f "$HOME/.config/zsh/.zsh/aliasrc" ] && source "$HOME/.config/zsh/.zsh/aliasrc"


function git_remote_status() {
  if [[ $(git rev-parse --is-inside-work-tree 2>/dev/null) == "true" ]]; then
    local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    local upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
    if [[ -n $upstream ]]; then
      # Compare local HEAD against the last-fetched upstream commit. Reflects
      # ahead/behind/diverged without a network call (run `git fetch` to refresh).
      local local_rev=$(git rev-parse @ 2>/dev/null)
      local remote_rev=$(git rev-parse @{u} 2>/dev/null)
      if [[ $local_rev == $remote_rev ]]; then
        echo "%F{#98c379}$branch⎇ %f"  # In sync with upstream
      else
        echo "%F{#e06c75}$branch⎇ %f"  # Ahead / behind / diverged
      fi
    elif [[ -n $branch ]]; then
      echo "%F{#e5c07b}$branch⎇ %f"  # Local only — no upstream yet
    fi
  fi
}

# Open a directory as an Obsidian vault: `obs` (cwd) or `obs ~/some/vault`.
# Obsidian only takes a folder via its obsidian:// URI, so the path has to be
# percent-encoded first. nomultibyte makes the loop walk raw bytes, which is
# what turns a non-ASCII char into its UTF-8 escapes (ü -> %C3%BC) rather than
# a single wrong codepoint escape.
function obs() {
  emulate -L zsh
  setopt localoptions nomultibyte
  local dir="${1:-$PWD}"
  dir="$(cd -- "$dir" 2>/dev/null && pwd)" || {
    print -u2 "obs: no such directory: ${1}"; return 1
  }
  local enc="" c i
  for (( i = 1; i <= ${#dir}; i++ )); do
    c="${dir[i]}"
    case "$c" in
      ([a-zA-Z0-9._~-]) enc+="$c" ;;   # RFC 3986 unreserved — safe as-is
      (*)               enc+="$(printf '%%%02X' "'$c")" ;;
    esac
  done
  open "obsidian://open?path=$enc"
}

# Keep this Mac awake so Claude remote-control sessions stay reachable.
#
#   awake          flip — restore sleep if it is disabled, disable it otherwise
#   awake on/off   explicit
#   awake status   print whether sleep is disabled
#
# On Apple Silicon, clamshell sleep overrides both caffeinate assertions and
# `pmset -c sleep 0`; `pmset -a disablesleep` is the only knob that survives it.
# It is system-wide, so leaving it on while unplugged keeps the Mac fully awake
# on battery — the tmux status bar shows a glyph while it is on. Remember to
# `awake off`.
function awake() {
  emulate -L zsh
  # pmset is macOS-only; this file is shared with Linux (see _source_first below).
  if [[ "$(uname)" != Darwin ]]; then
    print -u2 "awake: macOS only"; return 1
  fi

  local want="${1:-}" disabled=0
  [[ "$(pmset -g)" =~ "SleepDisabled[[:space:]]+1" ]] && disabled=1

  case "$want" in
    status) (( disabled )) && print "sleep disabled" || print "sleep normal"; return 0 ;;
    on|off) ;;
    '') (( disabled )) && want=off || want=on ;;
    *) print -u2 "awake: usage: awake [on|off|status]"; return 1 ;;
  esac

  if [[ $want == on ]]; then
    sudo pmset -a disablesleep 1 || return 1
    print "sleep disabled"
  else
    sudo pmset -a disablesleep 0 || return 1
    print "sleep restored"
  fi

  # Repaint the status bar now instead of up to status-interval seconds later.
  [[ -n $TMUX ]] && tmux refresh-client -S
  return 0
}

#Path Variables
export PATH=$HOME/.local/bin:$PATH

# Plugins — source the first path that exists. Covers Linux (/usr/share) and
# Homebrew on macOS (Apple Silicon /opt/homebrew, Intel /usr/local). Sourced
# near the end so syntax-highlighting wraps the final ZLE setup.
_source_first() {
  local f
  for f in "$@"; do
    [ -r "$f" ] && { source "$f"; return; }
  done
}

_source_first \
  /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh

_source_first \
  /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

_source_first \
  /usr/share/autojump/autojump.zsh \
  /opt/homebrew/etc/profile.d/autojump.sh \
  /usr/local/etc/profile.d/autojump.sh

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Cloudflare Workers AI credentials for image generation. The values live in the
# macOS Keychain, not in this file, because this repo is public. Add them with
# `security add-generic-password -a "$USER" -s <name> -w`. macOS-only, since
# `security` doesn't exist on Linux.
if [[ "$(uname)" == Darwin ]]; then
  export CF_ACCOUNT_ID="$(security find-generic-password -a "$USER" -s CF_ACCOUNT_ID -w 2>/dev/null)"
  export CF_API_TOKEN="$(security find-generic-password -a "$USER" -s CF_API_TOKEN -w 2>/dev/null)"
fi

# Machine-local overrides — keep this last so it can override anything above.
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
