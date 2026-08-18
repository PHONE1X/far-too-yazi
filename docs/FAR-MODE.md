# FAR mode — architecture and module guide

This document covers how the two-keymap system works, what each custom
module does, and the reasoning behind the less obvious design choices. If
you just want to *use* the config, the keybinding tables in
[README.md](../README.md) are enough — this is for anyone extending it,
debugging it, or curious how it's built.

## The core problem: yazi can't reload its keymap live

yazi reads `keymap.toml` once, at startup. There's no API to swap
keybindings while running ([sxyazi/yazi#1757](https://github.com/sxyazi/yazi/issues/1757)
is the open upstream issue). So "switch keymaps instantly" has to mean
"restart yazi with a different keymap file, fast enough and with enough
state preserved that it feels instant rather than jarring."

That's what `far-mode.yazi` plus the `y` shell wrapper do together.

### The relaunch mechanism

1. `keymap.toml` in the yazi config directory is a **symlink**, not a real
   file — it points at either `keymap-vim.toml` or `keymap-far.toml`.
2. Pressing the switch key (`Alt+M`, or `b f` in vim mode) runs
   `far-mode`'s `entry()`, which:
   - captures the current session state (open tabs, their cwd, which tab is
     active, and dual-pane layout if `split-tabs` is active) — this has to
     happen synchronously, in the `@sync` entry, because `cx` (yazi's live
     state) is only readable there, not from inside an async block;
   - atomically re-points the `keymap.toml` symlink at the other file
     (`ln -sfn` to a temp name, then `fs.rename` over the real symlink —
     avoids a window where the symlink is briefly missing or broken);
   - writes the captured state to a temp file (path comes from
     `$YAZI_STATE_FILE`, set by the wrapper before launch);
   - writes a second temp file (`$YAZI_RESTART_FILE`) as a "please relaunch
     me" sentinel — its *presence* is the signal, content doesn't matter;
   - emits `quit`.
3. The `y` fish function wraps `command yazi` in a loop. After yazi exits,
   it checks whether the restart sentinel file exists. If so, it deletes
   the sentinel and loops back to relaunch yazi (same state file path,
   fresh restart file); if not, the loop ends normally. Capped at 50
   iterations as a runaway guard.
4. On the relaunched process, `far-mode`'s `setup()` (called from
   `init.lua`) checks for the state file, reads it back, and replays it:
   `cd` to the first tab's directory, `tab_create` for the rest, restore
   the active tab, and — if dual-pane was on — hand off to `split-tabs` to
   re-activate with the right two tabs in the right pane order.

Two non-obvious details worth knowing if you're debugging this:

- **`YAZI_RESTART_FILE` / `YAZI_STATE_FILE` / `YAZI_KEYMAP_MODE` must be
  `set -gx` (global export), not `set --local --export`.** The local form
  doesn't reach the child `yazi` process reliably — confirmed by the
  plugin logging "unset" for a variable that was definitely set in the
  parent shell. This is fish-specific behavior, not a yazi quirk.
- **Pane order matters on restore.** `split-tabs` gives pane 1 to whichever
  tab is active when it activates, and pane 2 to the next one. If you
  restore tabs in raw order and then switch to "the tab that was active"
  *before* activating dual-pane, you can get panes swapped from what the
  user actually had (looks exactly like "the left pane's directory reset
  itself" — a real bug this hit once). The restore path reorders tabs
  so the two dual-pane tabs land at positions 1 and 2 in the correct
  pane order *before* calling `spl_activate`.

### Why the mode indicator can lag a frame

The status-line chip that shows `VIM` or `FAR` reads `$YAZI_KEYMAP_MODE`
synchronously on the first frame (fast path). If that's unset — i.e. yazi
was launched without the wrapper — it falls back to an async `readlink` on
`keymap.toml`, which takes a frame or two to resolve. Cosmetic only.

## Why not the stock dual-pane plugin?

An earlier pass tried a third-party `dual-pane.yazi` plugin before building
`split-tabs.yazi`'s own compositor (the disabled `dual-pane.yazi` directory
in this repo, if you still see it, is a leftover from that — it was found
incompatible with the keymap patching this config also does elsewhere, e.g.
`Header.cwd`, `Entity.style`). `split-tabs.yazi` instead patches yazi's own
`Tab.layout` / `Tab.build` to render two tabs' `Current` components
side-by-side, which keeps it working with the rest of this config's
patches rather than fighting them.

## Module guide

### `split-tabs.yazi` — the dual-pane compositor

Not a real "two independent windows" implementation — it patches
`Tab.layout` and `Tab.build` on the *single* active tab's rendering to draw
two tabs' file listings side by side, tracking which of the two underlying
yazi tabs is "pane 1" and which is "pane 2" by tab **position** (index into
`cx.tabs`), not by a stable ID. This is a deliberate simplification for
this release: it means creating/closing tabs *elsewhere* while dual-pane is
active can shift what pane 1/2 point at. Fine for the common case (dual-pane
is usually the only thing managing tabs); worth knowing if you're driving
tabs some other way while it's on.

Key actions (`plugin split-tabs <action>`):

- `spl_toggle` / `spl_activate` / `spl_deactivate` — turn dual-pane on/off.
- `spl_switch_tab` — move focus to the other pane.
- `spl_copy` / `spl_move` — transfer the selection (or hovered file) from
  the active pane to the other one. Internally: yank → switch to the
  destination pane → paste (routed through `merge-paste`, see below) →
  switch back to the source pane. Because paste is a background task and
  the destination pane isn't the "active" yazi tab once we switch back,
  the composited view doesn't auto-repaint the way yazi's own single-pane
  view does — `spl_transfer` covers this with an immediate `ui.render()`
  plus a short poll (six renders over 1.5s via `ya.async` + `ya.sleep`),
  which is enough for typical local transfers. FAR mode's F5/F6 go
  further and trigger a full relaunch after (~2s delay) for a
  guaranteed-correct redraw — see the F5/F6 note under `far-mode.yazi`
  below for the tradeoff that involves.
- `spl_preview` — toggle a preview pane (peek) alongside the two panes.

### `far-mode.yazi` — mode switching + FAR-mode dispatch

Covered above for the relaunch mechanism. It also:

- Owns `FAR_ACTIONS`, the table mapping FAR-mode-flavored action names
  (`far_copy`, `far_move`, `far_switch_pane`) to the underlying
  `split-tabs` actions, and auto-activates dual-pane if it's somehow off
  when one of these fires (FAR mode is meant to always be dual-pane).
- Renders the `VIM`/`FAR` status-line chip.
- **F5/F6 reload behavior**: after dispatching a copy/move, it captures
  session state immediately (safe — copying a file doesn't change which
  tabs exist or what directory they're in) and, after a fixed ~2 second
  delay, writes the state/restart files and quits — the same relaunch
  mechanism as a mode switch, just without changing the keymap symlink.
  This guarantees a correct redraw of both panes, at the cost of a visible
  reload flash on every F5/F6 press. **Known risk**: the delay is a guess,
  not a real "transfer finished" signal — `merge-paste` (see below) is
  invoked as a fire-and-forget plugin emit, so there's no way to await its
  completion, including any conflict prompt it might be showing. If the
  delay elapses while a conflict prompt is still waiting on a keypress,
  the process quits anyway and the prompt (and whatever it hadn't decided
  yet) is lost. Fixing this properly means calling `merge-paste`'s
  `entry()` directly via `require()` from inside an async block (unlike a
  `@sync` entry, `require()` across plugins does work there) so the reload
  can wait on real completion instead of a timer.

### `merge-paste.yazi` — conflict-aware paste

yazi's built-in `paste` has exactly two behaviors: silently auto-rename on
a name collision, or silently overwrite with `--force`. No prompt, and no
way to merge a folder into an existing one — a feature request for that
was closed "not planned" upstream
([sxyazi/yazi#982](https://github.com/sxyazi/yazi/issues/982)). This
plugin replaces `paste` for interactive use: on each colliding name it asks
Overwrite / Merge folders / Skip / Rename / Cancel, with an "apply to all
remaining conflicts" shortcut. Every cross-pane transfer in this config
(F5, F6, `Y`, `Ctrl+Y`) routes through this instead of bare `paste`.

### `far-menu.yazi` — F2/F9/F11 menus

Recreates FAR Manager's three menu keys as `ya.which()` pickers. Entries
are plain data (`{ on, desc, cmd, args }` or `{ on, desc, cmds }` for
several commands in order, or `{ on, desc, menu }` to nest another list),
overridable from `init.lua` via `require("far-menu"):setup({ user = {...} })`
without touching the plugin's code. One subtlety: `setup()` runs in yazi's
sync Lua state, but the menu entry itself runs in the async state (`ya.which`
yields, so it can't run sync) — the two states don't share memory, so the
menu table set by `setup()` is read back through a `ya.sync` block rather
than a plain upvalue, or the async side would only ever see the plugin's
hardcoded defaults.

### `far-tree.yazi` — Alt+F10 fuzzy folder jump

yazi has no tree panel and no core support for one
([sxyazi/yazi#3070](https://github.com/sxyazi/yazi/issues/3070) is still
open) — building a real one means reimplementing the file list widget.
What FAR users actually reach for Alt+F10 to do, though, is "show me the
folders under here and let me pick one" — a fuzzy picker over a directory
list covers that. Uses `fzf` (required); `fd` if present, `find` as a
fallback. Three modes: current directory, `$HOME`, or `/`.

### `ucp.yazi` — universal copy/paste

Handles copy/paste across more than just files — images (to/from the
system clipboard) and arbitrary text, in addition to file lists. Not
central to the FAR-mode workflow specifically, but bundled since it's part
of this config's clipboard story alongside `clipboard.yazi`.

## Custom `kdeconnect.yazi`

The upstream `kdeconnect-send.yazi` only sends files to a paired phone.
This local version can also *browse* the phone's filesystem (`g p`) in
addition to sending (`c s`), via `kdeconnect-cli`, so both directions go
through one module instead of two.

## Extending this: adding a third/fourth pane

If you're picking up the multi-pane roadmap item: `split-tabs.yazi`'s
`dp` table currently hardcodes two pane slots throughout — `dp.tabs[1]` /
`dp.tabs[2]`, `active_pane()` returning `1 or 2`, the `Tab.layout` chunk
layout building exactly 3 constraints (2 panes + 1 zero-width). The shape
of the change is: make `dp.tabs` a variable-length array, make
`active_pane()` return an explicit tracked index instead of a two-way
comparison, and generate N chunks/panes in `Tab.layout`/`Tab.build` from a
configurable pane count. None of it is conceptually hard; it's just
touching every place that currently assumes exactly 2.

## Extending this: multiple dual-pane workspaces

Also on the roadmap: browser-tab-like switching between several
*independent* 2-pane layouts (not to be confused with more panes in one
layout, above). The natural design is a `WORKSPACES` array alongside the
single live `dp`, with the active one mirrored into `dp` and the rest kept
as suspended `{ tabs, pane, preview }` snapshots whose underlying yazi tabs
still exist, just aren't currently composited into view. The tricky part
isn't the switching itself — it's making the far-mode relaunch/restore
chain (above) save and restore *all* workspaces, not just the active one,
since right now that chain only knows about a single dual-pane layout.
