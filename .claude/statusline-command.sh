#!/bin/bash
input=$(cat)

# Core fields
cwd_full=$(echo "$input" | jq -r '.workspace.current_dir')
cwd=$(echo "$cwd_full" | sed "s|^$HOME|~|")
model=$(echo "$input" | jq -r '.model.display_name')
effort=$(echo "$input" | jq -r '.effort.level // empty')

# Git branch
git_branch=""
if cd "$cwd_full" 2>/dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
  export GIT_OPTIONAL_LOCKS=0
  git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

# --- Fill colour and bar ---------------------------------------------------
# OneDark Pro: green -> yellow -> red as the meter fills.
fill_col() {
  if   [ "$1" -lt 50 ]; then printf '152;195;121'
  elif [ "$1" -lt 80 ]; then printf '229;192;123'
  else                       printf '224;108;117'
  fi
}

bar_seg() {
  local pct=$1 label=$2 col=$3 i bar=""
  for i in $(seq 1 10); do
    if [ "$i" -le $(( pct / 10 )) ]; then bar="${bar}█"; else bar="${bar}░"; fi
  done
  printf '\033[38;2;%sm%s %s\033[0m' "$col" "$bar" "$label"
}

# --- Context indicator -----------------------------------------------------
# The window size comes from the session, so this tracks whatever model is
# active instead of assuming a fixed ceiling.
ctx_seg=""
ctx=$(echo "$input" | jq -r '[.context_window.total_input_tokens // 0, .context_window.used_percentage // -1] | @tsv')
IFS=$'\t' read -r ctx_tokens pct <<< "$ctx"
pct=${pct%.*}
if [ "$ctx_tokens" -gt 0 ] 2>/dev/null && [ "$pct" -ge 0 ] 2>/dev/null; then
  [ "$pct" -gt 100 ] && pct=100
  ctx_seg=$(bar_seg "$pct" "${pct}% ($(( ctx_tokens / 1000 ))k)" "$(fill_col "$pct")")
fi

# --- Session usage ---------------------------------------------------------
# The 5h rate-limit window, absent on API-key billing. Purple keeps it distinct
# from the context bar, turning red once the window is nearly spent.
usage_col() { [ "$1" -lt 80 ] && printf '198;120;221' || printf '224;108;117'; }

limit_seg=""
usage=$(echo "$input" | jq -r '[(.rate_limits.five_hour.used_percentage // -1), (.rate_limits.five_hour.resets_at // 0)] | @tsv')
IFS=$'\t' read -r fh resets <<< "$usage"
fh=${fh%.*}
if [ "$fh" -ge 0 ] 2>/dev/null; then
  [ "$fh" -gt 100 ] && fh=100
  label="${fh}%"
  left=$(( resets - $(date +%s) ))
  if [ "$resets" -gt 0 ] 2>/dev/null && [ "$left" -gt 0 ]; then
    if [ "$left" -ge 3600 ]; then
      label="${label} $(( left / 3600 ))h$(( left % 3600 / 60 ))m"
    else
      label="${label} $(( left / 60 ))m"
    fi
  fi
  limit_seg=$(bar_seg "$fh" "$label" "$(usage_col "$fh")")
fi

# --- Model and reasoning effort --------------------------------------------
# Six effort levels are more than a colour can carry, so the level is spelled
# out next to the model. .effort.level is absent on models without the setting.
model_seg="\033[38;2;86;182;194m${model}\033[0m"      # cyan  #56b6c2
[ -n "$effort" ] && model_seg="${model_seg} \033[38;2;92;99;112m${effort}\033[0m"  # grey #5c6370

# --- Assemble --------------------------------------------------------------
# OneDark Pro palette (24-bit, matches tmux-onedark-theme)
sep=" \033[38;2;92;99;112m|\033[0m "                  # comment-grey #5c6370
out="\033[38;2;97;175;239m${cwd}\033[0m"        # blue  #61afef
[ -n "$git_branch" ] && out="${out}${sep}\033[38;2;152;195;121m${git_branch}\033[0m"  # green #98c379
out="${out}${sep}${model_seg}"
[ -n "$ctx_seg" ]   && out="${out}${sep}${ctx_seg}"
[ -n "$limit_seg" ] && out="${out}${sep}${limit_seg}"

printf "%b" "$out"
