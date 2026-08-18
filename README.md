# far-too-yazi

A [yazi](https://yazi-rs.github.io/) config that adds a FAR Manager / Norton
Commander style dual-pane mode on top of yazi's normal single-pane vim-style
interface — with a single keystroke to swap between the two.

Stay in yazi's native vim-style keybindings for everyday browsing, or flip
into a classic two-panel file-manager layout (F5 copy, F6 move, Tab to swap
panels, conflict prompts on collisions) when you're moving files between
directories. Both modes are full yazi keymaps, not an overlay — switching
between them relaunches yazi with the other keymap loaded and your tabs,
working directories, and dual-pane layout restored exactly as you left them.

## What's actually new here

yazi doesn't have a built-in dual-pane mode, and yazi has no live
keymap-reload (there's no way to swap keybindings without restarting the
process — see [sxyazi/yazi#1757](https://github.com/sxyazi/yazi/issues/1757)).
This project works around both:

- **A real dual-pane compositor** ([`split-tabs.yazi`](plugins/split-tabs.yazi)) —
  two yazi tabs rendered side by side as one composited view, not a
  third-party dual-pane plugin (one was tried and dropped; see
  [docs/FAR-MODE.md](docs/FAR-MODE.md#why-not-the-stock-dual-pane-plugin)).
- **Instant mode-switching** ([`far-mode.yazi`](plugins/far-mode.yazi)) — one
  keystroke atomically swaps the keymap file and relaunches yazi (via a shell
  wrapper, see below), restoring your tabs, cwd, active pane, and dual-pane
  state on the other side. Feels instant; it's a fast full restart under the
  hood.
- **FAR Manager conveniences**: F2/F9/F11 menus (`far-menu.yazi`), Alt+F10
  fuzzy folder jump (`far-tree.yazi`), conflict-aware paste with
  Overwrite/Merge/Skip/Rename prompts (`merge-paste.yazi`) wired into every
  cross-pane transfer, not just an explicit paste.

See [docs/FAR-MODE.md](docs/FAR-MODE.md) for the full module-by-module guide.

## Requirements

- [yazi](https://yazi-rs.github.io/) 26.5.6 or newer (uses `@sync` entries
  and `Tab.layout`/`Tab.build` patching — older versions may not have these).
- [fish shell](https://fishshell.com/) for the mode-switch relaunch wrapper.
  **This is the one hard dependency right now** — see
  [Limitations](#limitations) below if you're on bash/zsh.
- [`fzf`](https://github.com/junegunn/fzf) for the Alt+F10 folder jump; `fd`
  if you have it (falls back to `find`).
- `gh` (GitHub CLI) is *not* required to use this — only mentioned here
  because that's how this repo itself gets published.

## Install

```sh
git clone https://github.com/<your-username>/far-too-yazi.git
cd far-too-yazi
./install.sh
```

This backs up any existing `~/.config/yazi` (timestamped, not deleted),
copies this repo's config into `~/.config/yazi`, sets the default keymap to
vim-style, and — if fish is your shell — installs the `y` wrapper function
that mode-switching depends on.

**Use `y` to launch yazi, not the bare `yazi` command**, if you want
vim↔FAR mode switching to work. Plain `yazi` still works for everything
else; it just can't relaunch itself.

Prefer to manage this as a symlinked dotfile instead of a copy?

```sh
./install.sh --symlink
```

This points `~/.config/yazi` straight at the cloned repo, so `git pull`
updates your live config. Existing config is still backed up first.

## Quick usage

Default mode is vim-style (yazi's own keybindings, unmodified, plus the
additions below). From inside yazi:

| Key | Action |
|---|---|
| `Alt+M` | Switch to FAR mode (relaunches yazi) |
| `b t` | Toggle dual-pane view on/off |
| `Ctrl+H` / `Ctrl+L` | Switch active pane (dual-pane) |
| `t` | New workspace (when dual-pane is on) / new tab (when off) |
| `Y` | Move selection to the other pane (dual-pane) / cancel yank (off) |
| `Ctrl+Y` | Copy selection to the other pane (dual-pane only) |

FAR mode is always dual-pane. From inside yazi:

| Key | Action |
|---|---|
| `F5` | Copy to the other pane |
| `F6` | Move to the other pane |
| `Tab` | Switch active pane |
| `F2` / `F9` / `F11` | User menu / main menu / plugin commands |
| `Alt+F10` | Fuzzy-jump to a folder (fzf) |

Any transfer that collides with an existing name — F5, F6, `Y`, or
`Ctrl+Y` — prompts Overwrite / Merge folders / Skip / Rename / Cancel,
same as a manual conflict-aware paste.

Full keybinding reference and the reasoning behind each module:
[docs/FAR-MODE.md](docs/FAR-MODE.md).

## Limitations

- **fish-only mode switching.** The relaunch wrapper (`y`) is a fish
  function. Porting it to bash/zsh is straightforward (it's ~50 lines, no
  fish-specific logic beyond syntax) but hasn't been done — see
  [Roadmap](#roadmap). Without it you can still use either keymap directly
  by symlinking `keymap.toml` yourself; you just lose the relaunch-on-switch
  convenience.
- **Dual-pane workspaces are 2 panes each**, not N. See Roadmap.
- **Only the active workspace survives a mode-switch relaunch** if you're
  running a build with multiple dual-pane workspaces — background ones
  aren't restored (their underlying tabs aren't lost, just their pane
  layout). Not an issue in this release, since workspaces (plural) aren't
  shipped here yet — noted for when they land.

## Roadmap

Not implemented yet, tracked here so it doesn't get lost:

- **Multiple tabs/workspaces in dual-pane mode** — browser-tab-like
  switching between several independent 2-pane layouts, not just one.
- **3–4 pane layouts**, both in dual-pane and (optionally) single-pane mode
  — the current compositor is hardcoded to exactly 2 panes; extending it to
  a configurable pane count is mostly a data-model change
  (`split-tabs.yazi`'s pane tracking assumes exactly 2 throughout).
- **A non-fish version of the `y` wrapper**, so mode-switching doesn't
  require fish specifically.
- **Tabbed FAR mode** — a visible tab strip in FAR mode showing which
  workspace is active, once multi-workspace support exists.

Contributions on any of these are welcome — see
[docs/FAR-MODE.md](docs/FAR-MODE.md) for the architecture notes you'd need.

## Credits

Built on [yazi](https://yazi-rs.github.io/) and a set of community plugins
(see `package.toml` for the full list and versions) — `full-border`, `git`,
`chmod`, `smart-paste`, `smart-enter`, `mount`, `compress`, `clipboard`,
`relative-motions`, `allmytoes`, `recycle-bin`, `restore`, `toggle-pane`,
`ouch` — plus the custom modules documented in `docs/FAR-MODE.md`.

## License

*(add your license of choice here — MIT is a common default for yazi
plugins)*
