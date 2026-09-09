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

# Toggle the Tailscale mesh VPN together with the sleep setting that keeps this
# Mac reachable over it.
#
#   ts          flip — down if it is up, up if it is down
#   ts on/off   explicit
#   ts status   passthrough to `tailscale status`
#
# The two have to move together: on Apple Silicon, clamshell sleep overrides
# both caffeinate assertions and `pmset -c sleep 0`, and `pmset -a disablesleep`
# — the only knob that survives it — is system-wide, so leaving the VPN on while
# unplugged keeps the Mac fully awake on battery. Remember to `ts off`.
#
# tailscale up/down and pmset both need root, so `sudo -v` primes the credential
# cache once up front — one password prompt per toggle rather than two.
function ts() {
  emulate -L zsh
  local want="${1:-}"

  case "$want" in
    status) tailscale status; return $? ;;
    on|off) ;;
    '')
      # exit 0 means the backend is Running; anything else counts as down.
      if tailscale status --peers=false >/dev/null 2>&1; then want=off; else want=on; fi
      ;;
    *) print -u2 "ts: usage: ts [on|off|status]"; return 1 ;;
  esac

  sudo -v || return 1

  # pmset is macOS-only; this file is shared with Linux (see _source_first below).
  local darwin=0 note=""
  [[ "$(uname)" == Darwin ]] && darwin=1

  if [[ $want == on ]]; then
    # Sleep guard first, so the link does not come up racing an idle sleep.
    (( darwin )) && { sudo pmset -a disablesleep 1 || return 1 }
    if ! sudo tailscale up; then
      # Never leave sleep disabled for a VPN that failed to come up.
      (( darwin )) && sudo pmset -a disablesleep 0
      return 1
    fi
    (( darwin )) && note=" · sleep disabled"
    print "vpn on$note"
  else
    sudo tailscale down || return 1
    (( darwin )) && sudo pmset -a disablesleep 0
    (( darwin )) && note=" · sleep restored"
    print "vpn off$note"
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

# Machine-local overrides — keep this last so it can override anything above.
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
