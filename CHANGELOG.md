# Changelog

Notable changes to this config distribution. Grouped by the day the work
landed rather than version tags, since this isn't released as a versioned
package.

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
