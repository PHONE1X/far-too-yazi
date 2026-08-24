# Changelog

Notable changes to this config distribution. Grouped by the day the work
landed rather than version tags, since this isn't released as a versioned
package.

## 2026-08-24 (later)

### Added

- Multi-shell mode-switching: `bash/y.sh` ports the `y` relaunch wrapper
  (previously fish-only) to bash and zsh, same protocol
  (`YAZI_RESTART_FILE`/`YAZI_STATE_FILE`/`YAZI_KEYMAP_MODE`) as
  `far-mode.yazi` already expects. `install.sh` now detects whichever of
  fish/bash/zsh are present and installs the matching wrapper(s) instead
  of only checking for fish.
- `install.sh` now checks whether `yazi` itself is installed and installs
  it (pacman/brew/apt→cargo/cargo fallback chain) before configuring
  anything, instead of assuming it's already on `PATH`.
- Drag-and-drop, out: `<A-d>` (vim keymap) / `<A-F6>` (FAR keymap) runs
  `dragon -x -i -T %h` on the selection. kitty and iTerm2 support yazi's
  native DnD protocol directly (no binding needed — drag straight out of
  the window); everywhere else needs `dragon` (AUR: `dragon-drag-and-drop`
  — not the KDE media player of the same name in the official repos) as
  the drag source.
- Drag-and-drop, in: `<A-i>` (vim keymap) / `<A-F3>` (FAR keymap) runs
  `dragon --target --and-exit`, copying whatever's dropped on it into the
  current directory. The earlier `dragon -x -i -T` binding only covers
  dragging a selection *out* — it has no drop-target mode, so bringing
  files in needed this separate binding.
- `plugin-manager.yazi`: new plugin, `<A-p>` in both keymaps, rebuilt as a
  full-window popup (same style as `openers.yazi`'s `F` popup) instead of
  a single-page `ya.which` list. Lists a bundled 25-plugin catalog
  (official `yazi-rs/plugins` set plus the community plugins already
  vetted for this project); press `r` inside the popup to merge in a live
  pull of the 100+ repos tagged `topic:yazi-plugin` on GitHub (needs
  `curl`+`jq`, falls back to the bundled list otherwise). `/` filters,
  `Enter`/`i` installs the highlighted entry via `ya pkg add`.

## 2026-08-24

### Fixed

- `merge-paste.yazi`: `cx.yanked` entries are `File` objects here, not bare
  `Url`s. Stringifying the entry directly gave Lua's default userdata
  representation (`File: 0x...`) instead of the path, which then reached
  `cp` as a literal argument and failed with a stat error — every F5/F6
  cross-pane transfer (and any other paste through this plugin) was
  broken. Fixed by reading `.url` off the entry before stringifying.
- `openers.yazi`: `boot()` called `ya.async()` from inside its own plugin
  entry point, which yazi already runs async — that threw
  `ya.async() can only be used in sync context` on every startup and
  silently aborted before the saved dual-pane preference could be
  reapplied. Looked like "Panels: Dual" wasn't being saved; it was — the
  crash just happened before the setting was ever restored.

### Added

- `openers.yazi`: a startup-settings page in the same `F` popup as the
  file-type openers editor. `Tab` switches between the two pages; on the
  settings page, `h`/`l` or Enter/Space cycle a value. Covers keymap mode
  (vim/FAR), panel layout (single/dual/dual+preview), hidden files, sort
  field, folders-first, and reverse-sort — the panel layout choice
  persists to `startup-data.lua` and is re-applied on the next launch.

## 2026-08-23

### Added

- `openers.yazi`: new plugin, an `F`-bound popup for adding/editing/
  deleting file-type → program rules, replacing the old approach of
  hand-editing a Lua table in `init.lua`.
- `smart-enter.yazi`: the file-type → program mapping is now driven by
  `openers.yazi`'s popup/config instead of a hardcoded table in
  `init.lua`.

### Fixed

- `smart-enter.yazi`: opening images, video, audio, PDFs, office docs,
  and archives went through a broken opener path; these now bypass it.
- `smart-enter.yazi`: `nvim` could open a blank buffer instead of the
  target file because of how arguments were being passed to the opener
  command; fixed.

## 2026-08-18

### Added

- Initial release: FAR Manager / Norton Commander–style dual-pane mode for
  yazi, with instant vim ↔ FAR keymap switching, conflict-aware cross-pane
  transfers, F2/F9/F11 menus, Alt+F10 fuzzy folder jump, and KDE Connect
  phone browsing.

### Fixed

- `split-tabs.yazi`: theme-rendering glitch and a stale-working-directory
  bug that both traced back to pane state not being recomputed correctly
  on restore.
- Cross-pane copy/paste (F5/F6/`Y`/`Ctrl+Y`) didn't refresh the
  destination pane's listing, so a transferred file wouldn't show up
  until something else forced a redraw.
- Plugin repos were embedded as nested git repos, so a fresh clone of
  this project didn't actually contain their contents; un-embedded them.
