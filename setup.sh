#!/bin/bash
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.config"

ln -sf "$REPO_DIR/.zshenv" "$HOME/.zshenv"
ln -sf "$REPO_DIR/.tmux.conf" "$HOME/.tmux.conf"

# Claude Code writes into ~/.claude, so only link the scripts — settings.json
# is left as a live file. The hooks wiring tmux-claude-state.sh to Claude's
# Notification/Stop/UserPromptSubmit events live there, so a fresh machine
# needs them re-added by hand.
mkdir -p "$HOME/.claude"
ln -sf "$REPO_DIR/.claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
ln -sf "$REPO_DIR/.claude/tmux-claude-state.sh" "$HOME/.claude/tmux-claude-state.sh"

# Link the whole skills dir so new skills need no re-run. Claude Code writes its
# account-synced skills into skills/synced/, which .gitignore keeps out. Unlike
# the loop below this never deletes what is in the way: a real non-empty
# skills/ dir holds skills that aren't tracked here.
CLAUDE_SKILLS="$HOME/.claude/skills"
if [ -d "$CLAUDE_SKILLS" ] && [ ! -L "$CLAUDE_SKILLS" ] && ! rmdir "$CLAUDE_SKILLS" 2>/dev/null; then
  echo "! $CLAUDE_SKILLS is a non-empty real directory — move its contents into" >&2
  echo "  $REPO_DIR/.claude/skills, then re-run to link it." >&2
else
  ln -sfn "$REPO_DIR/.claude/skills" "$CLAUDE_SKILLS"
fi

for dir in nvim zsh ghostty lazygit tmux; do
  rm -rf "$HOME/.config/$dir"
  ln -s "$REPO_DIR/.config/$dir" "$HOME/.config/$dir"
done

# macOS lazygit ignores ~/.config and reads from ~/Library/Application Support,
# so point that path at the same tracked config (Linux uses the loop above).
if [ "$(uname)" = "Darwin" ]; then
  LG_MAC_DIR="$HOME/Library/Application Support/lazygit"
  mkdir -p "$LG_MAC_DIR"
  ln -sf "$REPO_DIR/.config/lazygit/config.yml" "$LG_MAC_DIR/config.yml"
fi

echo "Symlinks created."

# Telescope shells out to ripgrep for both find_files and live_grep, so without
# `rg` on PATH every picker comes back empty.
if command -v brew >/dev/null && ! command -v rg >/dev/null; then
  brew install ripgrep
fi

# nvim-treesitter's `main` branch compiles parsers by shelling out to the
# `tree-sitter` CLI, which Homebrew ships separately from the library-only
# `tree-sitter` formula. Without it, syntax highlighting silently fails.
if command -v brew >/dev/null && ! command -v tree-sitter >/dev/null; then
  brew install tree-sitter-cli
fi

# Lazygit's config pipes diffs through `delta` for syntax-highlighted,
# word-level review. Without it on PATH, lazygit falls back to raw diffs.
if command -v brew >/dev/null && ! command -v delta >/dev/null; then
  brew install git-delta
fi

# Install TPM and the plugins declared in .tmux.conf; without them
# vim-tmux-navigator's C-h/j/k/l pane navigation silently does nothing.
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ ! -d "$TPM_DIR" ]; then
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi
"$TPM_DIR/bin/install_plugins"

# tmux only reads ~/.tmux.conf when the server starts.
if command -v tmux >/dev/null && tmux info >/dev/null 2>&1; then
  tmux source-file "$HOME/.tmux.conf"
  echo "Reloaded running tmux server."
fi

echo "Done."
