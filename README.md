# Config

Dotfiles managed via symlinks. Run `setup.sh` to link everything into place.

## Dependencies

Install these before running the setup script.

### macOS (Homebrew)

```sh
brew install neovim tmux lazygit ghostty ripgrep tree-sitter-cli git-delta fzf
brew install --cask font-jetbrains-mono-nerd-font
```

### Linux (apt)

```sh
sudo apt install neovim tmux zsh ripgrep git-delta
# tree-sitter CLI: cargo install tree-sitter-cli (or npm install -g tree-sitter-cli)
```

- [Lazygit](https://github.com/jesseduffield/lazygit#installation) — install from GitHub releases or your distro's package manager
- [Ghostty](https://ghostty.org/) — see official install instructions
- [JetBrainsMono Nerd Font](https://www.nerdfonts.com/font-downloads) — used by Ghostty
- [ripgrep](https://github.com/BurntSushi/ripgrep) — required by Telescope's `find_files` and `live_grep`; without it the pickers return no results
- [tree-sitter CLI](https://github.com/tree-sitter/tree-sitter) — nvim-treesitter's `main` branch compiles parsers with it; without it syntax highlighting silently fails
- [fzf](https://github.com/junegunn/fzf) — powers the `prefix + w` tmux tree popup; without it the popup just prints an install hint
- [delta](https://github.com/dandavison/delta) (`git-delta`) — lazygit pipes diffs through it for syntax-highlighted, word-level review; without it on PATH lazygit falls back to raw diffs

### Shared

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — CLI for Claude

> tmux's plugin manager (tpm) is cloned and its plugins installed automatically by `setup.sh`.

## Setup

```sh
git clone <repo-url> ~/Developer/Config
cd ~/Developer/Config
./setup.sh
```

This creates symlinks for:

| Target            | Symlink                                                                             |
| ----------------- | ----------------------------------------------------------------------------------- |
| `.zshenv`         | `~/.zshenv`                                                                         |
| `.tmux.conf`      | `~/.tmux.conf`                                                                      |
| `.config/nvim`    | `~/.config/nvim`                                                                    |
| `.config/zsh`     | `~/.config/zsh`                                                                     |
| `.config/ghostty` | `~/.config/ghostty`                                                                 |
| `.config/tmux`    | `~/.config/tmux`                                                                    |
| `.config/lazygit` | `~/.config/lazygit` (+ `~/Library/Application Support/lazygit/config.yml` on macOS) |

On macOS, lazygit ignores `~/.config` and reads from
`~/Library/Application Support/lazygit`, so `setup.sh` also links the tracked
config into that path. It additionally installs `git-delta` if missing (lazygit's
diff pager).

`setup.sh` also clones tpm, installs the tmux plugins, and reloads any running
tmux server — so the config (including the theme and vim-tmux-navigator) takes
effect without a manual `prefix + I` or server restart.

## Structure

```
.zshenv                        # Points ZDOTDIR to ~/.config/zsh
.tmux.conf                     # Tmux config (prefix: Ctrl+Space)
.claude/                       # Claude Code skills, settings, tmux/statusline scripts
.config/
  ghostty/config               # Terminal (One Dark Two, JetBrainsMono Nerd Font)
  lazygit/config.yml           # Lazygit (review-focused layout, delta pager, pink/cyan theme)
  nvim/                        # Neovim (lazy.nvim, onedark, LSP, telescope)
  tmux/tree.sh                 # fzf session/window/pane tree behind prefix + w
  tmux/awake-status.sh         # Sleep-disabled glyph in the tmux status bar
  zsh/
    .zshrc                     # Shell config (prompt, history, completions)
    .zsh/aliasrc               # Aliases and shortcuts
keybinds.ahk                   # AutoHotKey remaps (Windows)
```

## Key Aliases

| Alias   | Command                                                                           |
| ------- | --------------------------------------------------------------------------------- |
| `lg`    | `lazygit`                                                                         |
| `cc`    | `claude`                                                                          |
| `ref`   | Re-source `.zshrc`                                                                |
| `zrc`   | Edit `.zshrc` in nvim                                                             |
| `zal`   | Edit `aliasrc` in nvim                                                            |
| `wp`    | `cd ~/Developer`                                                                  |
| `awake` | Toggle macOS sleep for remote-control (`awake on` / `awake off` / `awake status`) |
