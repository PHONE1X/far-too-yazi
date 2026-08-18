function y
    set --local cwd_file (mktemp -u)
    set --local restart_file (mktemp -u)
    # far-mode writes the tab/cwd layout here before quitting, and reads it
    # back on the next launch to restore the session. One path for the whole
    # loop, so it survives across relaunch iterations.
    set --local state_file (mktemp -u)
    set --local iterations 0

    while test $iterations -lt 50
        set iterations (math $iterations + 1)

        # Which keymap is live right now? far-mode shows this in the status
        # line. Recomputed every iteration, because a mode swap is exactly
        # what caused the relaunch.
        set --local cfg $YAZI_CONFIG_HOME
        test -n "$cfg"; or set cfg $HOME/.config/yazi

        # These are GLOBAL exports on purpose. Two earlier forms failed:
        #   env VAR=x command yazi  -> `command` is a fish builtin, not a
        #                              binary, so env couldn't exec it.
        #   begin; set --local --export ...; end
        #                           -> the variables did not reach the yazi
        #                              process; the plugin logged
        #                              "YAZI_RESTART_FILE unset".
        # Global export is the form that actually arrives. Erased below.
        set -gx YAZI_RESTART_FILE "$restart_file"
        set -gx YAZI_STATE_FILE "$state_file"
        set -gx YAZI_KEYMAP_MODE (readlink "$cfg/keymap.toml" 2>/dev/null)

        command yazi $argv --cwd-file="$cwd_file"

        if test -f "$cwd_file"
            set --local last_cwd (cat "$cwd_file")
            if test -n "$last_cwd" -a -d "$last_cwd"
                cd "$last_cwd"
            end
            rm -f "$cwd_file"
        end

        if test -f "$restart_file"
            rm -f "$restart_file"
            continue
        else
            break
        end
    end

    set -e YAZI_RESTART_FILE
    set -e YAZI_STATE_FILE
    set -e YAZI_KEYMAP_MODE

    # far-mode normally consumes the state file itself on restore; this is
    # just belt-and-braces so a crashed run can't leave stale layout behind
    # for the next `y`.
    rm -f "$state_file"
end
