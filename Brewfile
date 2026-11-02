# Brewfile — everything this config needs on a new Mac.
#
#   brew bundle --file=~/Developer/Config/Brewfile
#
# Run alongside ./setup.sh (which symlinks the configs into place and installs
# tpm + tmux plugins). Idempotent: re-running only installs what's missing.

# --- CLI tools -------------------------------------------------------------
brew "neovim"                   # editor ($EDITOR); config in .config/nvim
brew "tmux"                     # multiplexer; .tmux.conf (tpm installed by setup.sh)
brew "lazygit"                  # git TUI (`lg` alias); .config/lazygit
brew "ripgrep"                  # Telescope find_files / live_grep need it
brew "tree-sitter-cli"          # nvim-treesitter compiles parsers with it
brew "git-delta"                # lazygit diff pager (syntax-highlighted diffs)
brew "fzf"                      # prefix+w tmux tree popup (.config/tmux/tree.sh)
brew "autojump"                 # directory jumping; sourced by .zshrc
brew "zsh-autosuggestions"      # sourced by .zshrc
brew "zsh-syntax-highlighting"  # sourced by .zshrc (must load last)

# --- Apps & fonts ----------------------------------------------------------
cask "ghostty"                          # terminal; .config/ghostty
cask "font-jetbrains-mono-nerd-font"    # ghostty font-family

# --- Installed separately (not Homebrew) -----------------------------------
# - Claude Code CLI (`cc` alias): https://docs.anthropic.com/en/docs/claude-code
# - nvm (sourced by .zshrc, if you use it): https://github.com/nvm-sh/nvm
#   `brew "nvm"` works too, but nvm's install script is the recommended path.
