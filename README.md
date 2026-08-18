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

This isn't a single plugin — it's a full config distribution, the same idea
as [AstroNvim](https://astronvim.com/) for Neovim: yazi itself (the Rust
binary) is untouched, but this bundles a curated set of community plugins,
several custom ones written specifically for this project, and a FAR
Manager–style keymap and mode-switcher on top, all wired together into one
install.

## What's actually new here

yazi doesn't have a built-in dual-pane mode, and yazi has no live
keymap-reload (there's no way to swap keybindings without restarting the
process — see [sxyazi/yazi#1757](https://github.com/sxyazi/yazi/issues/1757)).
This project works around both:

- **A real dual-pane compositor** ([`split-tabs.yazi`](plugins/split-tabs.yazi)) —
  two yazi tabs rendered side by side as one composited view, not a
  third-party dual-pane plugin (one was tried and dropped; see
  [docs/FAR-MODE.md](docs/FAR-MODE.md#why-not-the-stock-dual-pane-plugin)).
  Fixed here: a theme-rendering glitch and a stale-working-directory bug
  that both traced back to pane state not being recomputed correctly on
  restore.
- **Instant mode-switching** ([`far-mode.yazi`](plugins/far-mode.yazi)) — one
  keystroke atomically swaps the keymap file and relaunches yazi (via a shell
  wrapper, see below), restoring your tabs, cwd, active pane, and dual-pane
  state on the other side. Feels instant; it's a fast full restart under the
  hood.
- **Conflict-aware transfers between panes** ([`merge-paste.yazi`](plugins/merge-paste.yazi)) —
  every cross-pane transfer (F5, F6, `Y`, `Ctrl+Y`), not just an explicit
  paste, prompts Overwrite / Merge / Skip / Rename on a name collision.
  Fixed here: copying or moving a file into the other pane now actually
  shows up in that pane's listing immediately — the target pane wasn't
  always refreshing after a cross-pane transfer landed.
- **FAR Manager conveniences**: F2/F9/F11 menus (`far-menu.yazi`), Alt+F10
  fuzzy folder jump (`far-tree.yazi`).
- **Phone browsing over KDE Connect** ([`kdeconnect.yazi`](plugins/kdeconnect.yazi)) —
  mount a paired phone and `cd` straight into it, or send files to it,
  without leaving yazi. A thin wrapper around `kdeconnect-cli --mount`,
  `--get-mount-point`, and `--share` — see the plugin's own README for why
  the existing `kdeconnect-send.yazi` and gvfs-path guides don't cover this.
- **Disk mount/unmount/eject** ([`mount.yazi`](plugins/mount.yazi), community
  plugin, used as-is) — lists block devices via `lsblk`, mounts/unmounts via
  `udisksctl`. Since `udisksctl` goes through polkit, mounting or unmounting
  a disk this way can trigger your desktop's own password/keyring prompt —
  that's normal, it's the same authorization dialog a GUI file manager would
  show, not something this config adds on top.

See [docs/FAR-MODE.md](docs/FAR-MODE.md) for the full module-by-module guide.

## Neovim

Two separate things, don't confuse them:

- **`nvim` as the default opener** ([`yazi.toml`](yazi.toml)) — text files
  open in `nvim` by default (`run = 'nvim "$@"'`). Change this if your
  editor is something else.
- **Running yazi *inside* Neovim** as a file picker (e.g. via a Neovim
  plugin that shells out to yazi in a terminal buffer) — `toggle-pane.yazi`
  detects this case (`os.getenv("NVIM")`, per
  [yazi's own docs on vim integration](https://yazi-rs.github.io/docs/resources#vim))
  and can hide the preview panel by default when yazi is launched that way,
  since Neovim's own buffer is already showing a preview. Wire this up in
  `init.lua` if you use yazi as a Neovim file picker.

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
git clone https://github.com/PHONE1X/far-too-yazi.git
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
same as a manual conflict-aware paste, and the destination pane refreshes
immediately so the transferred file is visible right away.

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
- **No bookmarks / fast-travel yet.** See Roadmap.

## Roadmap

Not implemented yet, tracked here so it doesn't get lost:

- **Bookmarks / fast-travel for FAR mode** — vim-mode navigation in yazi
  already has quick jump shortcuts; FAR mode has nothing equivalent yet.
  Needs a way to save a directory under a key and jump straight to it,
  Norton-Commander/FAR style, instead of navigating there by hand every
  time.
- **Port more of FAR mode's logic into vim-mode**, including parts of its
  control scheme, where it doesn't conflict with yazi's own vim-style
  bindings — right now the two modes share less than they could.
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

Built on [yazi](https://yazi-rs.github.io/). Every plugin below is either
original to this project, a fork with real modifications, or a community
plugin used essentially as-is (pinned versions in `package.toml`). None of
it is blind copy-paste — forked/modified plugins are called out explicitly.

**Written for this project (Mihailov / PHONE1X):**

- [`merge-paste.yazi`](plugins/merge-paste.yazi) — conflict-aware paste
  (Overwrite/Merge/Skip/Rename), addressing
  [sxyazi/yazi#982](https://github.com/sxyazi/yazi/issues/982), closed
  "not planned" upstream.
- [`kdeconnect.yazi`](plugins/kdeconnect.yazi) — browse and send files to a
  KDE Connect–paired phone.
- `far-mode.yazi`, `far-menu.yazi`, `far-tree.yazi` — the FAR-mode
  machinery itself: keymap-swap/relaunch, F2/F9/F11 menus, Alt+F10 fuzzy
  folder jump. Written specifically for this project; see
  [docs/FAR-MODE.md](docs/FAR-MODE.md) for how they work.

**Forked and modified:**

- [`split-tabs.yazi`](plugins/split-tabs.yazi) — dual-pane compositor,
  originally by [Konstantin Tskhovrebov (terrakok)](https://github.com/terrakok/split-tabs).
  Modified here to fix a theme-rendering bug and a stale-working-directory
  bug on pane restore.

**Community plugins, used as published (see `package.toml` for pinned
versions):**

- [`mount.yazi`](plugins/mount.yazi), [`git.yazi`](plugins/git.yazi),
  [`full-border.yazi`](plugins/full-border.yazi),
  [`chmod.yazi`](plugins/chmod.yazi),
  [`smart-enter.yazi`](plugins/smart-enter.yazi),
  [`smart-paste.yazi`](plugins/smart-paste.yazi),
  [`toggle-pane.yazi`](plugins/toggle-pane.yazi) — [yazi-rs](https://github.com/yazi-rs/plugins)
- [`compress.yazi`](plugins/compress.yazi) — [Ciarán O'Brien / KKV9](https://github.com/KKV9/compress)
- [`ouch.yazi`](plugins/ouch.yazi) — [ndtoan96](https://github.com/ndtoan96/ouch)
- [`clipboard.yazi`](plugins/clipboard.yazi) — [XYenon](https://github.com/XYenon/clipboard)
- [`relative-motions.yazi`](plugins/relative-motions.yazi) — [dedukun](https://github.com/dedukun/relative-motions)
- [`allmytoes.yazi`](plugins/allmytoes.yazi) — [Sonico98](https://github.com/Sonico98/allmytoes)
- [`restore.yazi`](plugins/restore.yazi) — [boydaihungst](https://github.com/boydaihungst/restore)
- [`recycle-bin.yazi`](plugins/recycle-bin.yazi) — [uhs-robert](https://github.com/uhs-robert/recycle-bin)
- [`ucp.yazi`](plugins/ucp.yazi) — [boydaihungst](https://github.com/boydaihungst)

## License

*(add your license of choice here — MIT is a common default for yazi
plugins)*
