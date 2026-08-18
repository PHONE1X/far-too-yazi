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
# 4. fish wrapper (mode-switch relaunch support)
# ---------------------------------------------------------------------------
if command -v fish >/dev/null 2>&1; then
    mkdir -p "$FISH_FUNCTIONS_DIR"
    if [ -e "$FISH_FUNCTIONS_DIR/y.fish" ]; then
        cp "$FISH_FUNCTIONS_DIR/y.fish" "$FISH_FUNCTIONS_DIR/y.fish.bak-$(date +%Y%m%d-%H%M%S)"
        echo "Existing $FISH_FUNCTIONS_DIR/y.fish backed up before overwrite."
    fi
    cp "$REPO_DIR/fish/y.fish" "$FISH_FUNCTIONS_DIR/y.fish"
    echo "Installed the 'y' wrapper function to:"
    echo "  $FISH_FUNCTIONS_DIR/y.fish"
    echo
    echo "IMPORTANT: launch yazi with 'y', not the bare 'yazi' command, or"
    echo "vim<->FAR mode switching (Alt+M) won't be able to relaunch."
    echo
    echo "If you already have a function named 'y' defined elsewhere in your"
    echo "fish config (e.g. in conf.d/*.fish), make sure nothing re-defines"
    echo "it after this file loads -- a later definition silently shadows it"
    echo "and mode-switching will look broken with no obvious error."
else
    echo "fish shell not found -- skipping the 'y' wrapper install."
    echo "Mode-switching (vim<->FAR, Alt+M) needs a shell wrapper that can"
    echo "relaunch yazi on request; only a fish version exists right now"
    echo "(see README.md's Roadmap section). You can still use either"
    echo "keymap directly by re-pointing keymap.toml's symlink by hand:"
    echo "  ln -sfn \"$YAZI_CONFIG_DIR/keymap-far.toml\" \"$YAZI_CONFIG_DIR/keymap.toml\""
fi

echo
echo "Done."
if command -v fish >/dev/null 2>&1; then
    echo "Launch with: y"
else
    echo "Launch with: yazi"
fi
