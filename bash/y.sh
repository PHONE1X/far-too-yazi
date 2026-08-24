# far-too-yazi mode-switch relaunch wrapper -- bash/zsh port of fish/y.fish.
# Source this from .bashrc / .zshrc (install.sh does this for you).
#
# Protocol (shared with far-mode.yazi, see plugins/far-mode.yazi/main.lua):
#   YAZI_RESTART_FILE  -- far-mode touches this before quitting to ask for
#                          a relaunch; its presence is the only signal, the
#                          content is irrelevant.
#   YAZI_STATE_FILE    -- far-mode writes the tab/cwd/pane layout here
#                          before quitting, and reads it back on the next
#                          launch to restore the session. One path for the
#                          whole loop, so it survives across relaunches.
#   YAZI_KEYMAP_MODE   -- which keymap is live right now (far-mode shows
#                          this in the status line), recomputed every
#                          iteration since a mode swap is exactly what
#                          caused the relaunch.
y() {
    local cwd_file restart_file state_file iterations=0 cfg last_cwd

    cwd_file="$(mktemp -u)"
    restart_file="$(mktemp -u)"
    state_file="$(mktemp -u)"

    while [ "$iterations" -lt 50 ]; do
        iterations=$((iterations + 1))

        cfg="${YAZI_CONFIG_HOME:-$HOME/.config/yazi}"

        export YAZI_RESTART_FILE="$restart_file"
        export YAZI_STATE_FILE="$state_file"
        export YAZI_KEYMAP_MODE="$(readlink "$cfg/keymap.toml" 2>/dev/null)"

        command yazi "$@" --cwd-file="$cwd_file"

        if [ -f "$cwd_file" ]; then
            last_cwd="$(cat "$cwd_file")"
            if [ -n "$last_cwd" ] && [ -d "$last_cwd" ]; then
                cd "$last_cwd" || true
            fi
            rm -f "$cwd_file"
        fi

        if [ -f "$restart_file" ]; then
            rm -f "$restart_file"
            continue
        else
            break
        fi
    done

    unset YAZI_RESTART_FILE YAZI_STATE_FILE YAZI_KEYMAP_MODE

    # far-mode normally consumes the state file itself on restore; this is
    # just belt-and-braces so a crashed run can't leave stale layout behind
    # for the next `y`.
    rm -f "$state_file"
}
