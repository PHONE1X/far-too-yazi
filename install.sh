#!/usr/bin/env bash
# far-too-yazi installer.
#
#   ./install.sh            copy this repo's config into ~/.config/yazi
#   ./install.sh --symlink  point ~/.config/yazi at this repo instead
#                           (so `git pull` here updates your live config)
#
# Either way, an existing ~/.config/yazi is backed up first, never deleted.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAZI_CONFIG_DIR="${YAZI_CONFIG_HOME:-$HOME/.config/yazi}"
FISH_FUNCTIONS_DIR="$HOME/.config/fish/functions"

MODE="copy"
if [ "${1:-}" = "--symlink" ]; then
    MODE="symlink"
fi

echo "far-too-yazi installer ($MODE mode)"
echo "===================================="
echo "Target config directory: $YAZI_CONFIG_DIR"
echo

# ---------------------------------------------------------------------------
# 0. Make sure yazi itself is installed
# ---------------------------------------------------------------------------
if ! command -v yazi >/dev/null 2>&1; then
    echo "yazi not found on PATH -- installing it first."
    if command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --needed yazi
    elif command -v brew >/dev/null 2>&1; then
        brew install yazi
    elif command -v apt >/dev/null 2>&1; then
        # Debian/Ubuntu's apt repos don't reliably carry a current yazi, so
        # fall back to cargo instead of shipping a stale/missing package.
        if ! command -v cargo >/dev/null 2>&1; then
            echo "apt found but no cargo -- installing Rust via rustup first."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            . "$HOME/.cargo/env"
        fi
        cargo install --locked yazi-fm yazi-cli
    elif command -v cargo >/dev/null 2>&1; then
        cargo install --locked yazi-fm yazi-cli
    else
        echo "ERROR: no supported package manager (pacman/brew/apt) or cargo" >&2
        echo "found to install yazi automatically. Install it yourself --" >&2
        echo "see https://yazi-rs.github.io/docs/installation -- then re-run" >&2
        echo "this script." >&2
        exit 1
    fi
    echo "yazi installed."
    echo
else
    echo "yazi found: $(command -v yazi) ($(yazi --version 2>/dev/null))"
    echo
fi

# ---------------------------------------------------------------------------
# 1. Back up any existing config
# ---------------------------------------------------------------------------
if [ -e "$YAZI_CONFIG_DIR" ] || [ -L "$YAZI_CONFIG_DIR" ]; then
    BACKUP="$YAZI_CONFIG_DIR.bak-$(date +%Y%m%d-%H%M%S)"
    echo "Existing config found -- backing up to:"
    echo "  $BACKUP"
    mv "$YAZI_CONFIG_DIR" "$BACKUP"
fi

mkdir -p "$(dirname "$YAZI_CONFIG_DIR")"

# ---------------------------------------------------------------------------
# 2. Install the config
# ---------------------------------------------------------------------------
if [ "$MODE" = "symlink" ]; then
    ln -sfn "$REPO_DIR" "$YAZI_CONFIG_DIR"
    echo "Symlinked $YAZI_CONFIG_DIR -> $REPO_DIR"
else
    mkdir -p "$YAZI_CONFIG_DIR"
    for item in init.lua keymap-vim.toml keymap-far.toml package.toml \
                theme.toml yazi.toml plugins flavors; do
        if [ -e "$REPO_DIR/$item" ]; then
            cp -r "$REPO_DIR/$item" "$YAZI_CONFIG_DIR/"
        fi
    done
    echo "Copied config into $YAZI_CONFIG_DIR"
fi

# ---------------------------------------------------------------------------
# 3. Default keymap: vim-style
# ---------------------------------------------------------------------------
ln -sfn "$YAZI_CONFIG_DIR/keymap-vim.toml" "$YAZI_CONFIG_DIR/keymap.toml"
echo "Default keymap set to vim-style. Switch to FAR mode from inside yazi"
echo "with Alt+M (see README.md)."
echo

# ---------------------------------------------------------------------------
# 4. Shell wrapper (mode-switch relaunch support)
# ---------------------------------------------------------------------------
WRAPPER_INSTALLED=""

install_bash_zsh_wrapper() {
    # $1 = rc file to append the source line to
    local rc="$1"
    local source_line="[ -f \"$YAZI_CONFIG_DIR/bash/y.sh\" ] && . \"$YAZI_CONFIG_DIR/bash/y.sh\"  # far-too-yazi"

    mkdir -p "$YAZI_CONFIG_DIR/bash"
    cp "$REPO_DIR/bash/y.sh" "$YAZI_CONFIG_DIR/bash/y.sh"

    if [ -e "$rc" ] && grep -qF "far-too-yazi" "$rc" 2>/dev/null; then
        echo "  $rc already sources the y wrapper -- leaving it alone."
        return
    fi

    touch "$rc"
    printf '\n%s\n' "$source_line" >> "$rc"
    echo "  Added a source line to $rc"
}

if command -v fish >/dev/null 2>&1; then
    mkdir -p "$FISH_FUNCTIONS_DIR"
    if [ -e "$FISH_FUNCTIONS_DIR/y.fish" ]; then
        cp "$FISH_FUNCTIONS_DIR/y.fish" "$FISH_FUNCTIONS_DIR/y.fish.bak-$(date +%Y%m%d-%H%M%S)"
        echo "Existing $FISH_FUNCTIONS_DIR/y.fish backed up before overwrite."
    fi
    cp "$REPO_DIR/fish/y.fish" "$FISH_FUNCTIONS_DIR/y.fish"
    echo "Installed the 'y' wrapper function (fish) to:"
    echo "  $FISH_FUNCTIONS_DIR/y.fish"
    WRAPPER_INSTALLED="yes"
fi

if command -v bash >/dev/null 2>&1; then
    echo "Installing the 'y' wrapper function (bash) --"
    install_bash_zsh_wrapper "$HOME/.bashrc"
    WRAPPER_INSTALLED="yes"
fi

if command -v zsh >/dev/null 2>&1; then
    echo "Installing the 'y' wrapper function (zsh) --"
    install_bash_zsh_wrapper "${ZDOTDIR:-$HOME}/.zshrc"
    WRAPPER_INSTALLED="yes"
fi

if [ -n "$WRAPPER_INSTALLED" ]; then
    echo
    echo "IMPORTANT: launch yazi with 'y', not the bare 'yazi' command, or"
    echo "vim<->FAR mode switching (Alt+M) won't be able to relaunch."
    echo
    echo "If you already have a function/alias named 'y' defined elsewhere"
    echo "in your shell config, make sure nothing re-defines it AFTER this"
    echo "wrapper loads -- a later definition silently shadows it and"
    echo "mode-switching will look broken with no obvious error."
    echo "(Open a new shell, or re-source your rc file, before using 'y'.)"
else
    echo "No supported shell (fish/bash/zsh) found -- skipping the 'y'"
    echo "wrapper install. Mode-switching (vim<->FAR, Alt+M) needs a shell"
    echo "wrapper that can relaunch yazi on request. You can still use"
    echo "either keymap directly by re-pointing keymap.toml's symlink:"
    echo "  ln -sfn \"$YAZI_CONFIG_DIR/keymap-far.toml\" \"$YAZI_CONFIG_DIR/keymap.toml\""
fi

echo
echo "Done."
if [ -n "$WRAPPER_INSTALLED" ]; then
    echo "Launch with: y"
else
    echo "Launch with: yazi"
fi
