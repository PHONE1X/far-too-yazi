# kdeconnect.yazi

Browse and send files to a [KDE Connect](https://kdeconnect.kde.org/)-paired phone straight from
[Yazi](https://github.com/sxyazi/yazi) — the same "browse this device" your file manager already
does, and file sharing, without leaving the terminal.

Two actions in one plugin:

- **`browse`** — mounts the paired phone (via KDE Connect's own SFTP/sshfs mechanism) and `cd`s
  straight into it, remounting fresh every time it's invoked.
- **`send`** — shares the selected files (or the hovered file, if nothing is explicitly selected)
  to a paired device.

## Why not the existing `kdeconnect-send.yazi` / a `gvfs`-based shortcut?

- The popular [`kdeconnect-send.yazi`](https://github.com/Deepak22903/kdeconnect-send.yazi) only
  sends files — there's no way to browse the phone's filesystem from Yazi with it.
- Older guides point at a gvfs mount under `~/run/user/<uid>/gvfs/` — that's the *previous*
  KDE Connect implementation. Current KDE Connect (Plasma 6 and later) mounts phones via `sshfs`
  at a path KDE Connect itself decides, and there's no reliable way to guess it in advance.
- `kdeconnect-cli` actually already exposes exactly what's needed for both: `--mount`,
  `--get-mount-point`, and `--share`. This plugin is a thin, honest wrapper around those three
  flags — no DBus calls of its own, no guessed paths.

## Three real KDE Connect quirks this plugin works around

These took a fair bit of live debugging to pin down, so they're documented here in case they
save someone else the trouble:

1. **The mounted root isn't listable.** `kdeconnect-cli --mount` mounts
   `kdeconnect@phone:/` — but that bare root is a synthetic root on the Android side that
   permission-denies any attempt to *list* it directly, even on a perfectly healthy, freshly
   authenticated mount. The real files live one level of indirection deeper, at
   `storage/emulated/0`. KDE Connect's own "View this device" button already knows this and jumps
   straight there — this plugin does the same, falling back to the bare root only if that path
   doesn't exist.
2. **`--mount` is idempotent and doesn't detect a dead session.** If the phone drops the
   connection (screen off, Wi-Fi sleep, etc.), the mountpoint can be left registered but
   permission-denying every read, forever — and since KDE Connect's DBus side still thinks it's
   mounted, calling `--mount` again does nothing. This plugin always force-unmounts
   (`fusermount -u`) before remounting, so `browse` reliably gets a live session instead of
   possibly reusing a stale one.
3. **The mountpoint can exist before the SSH session is actually ready.** A read attempted in
   that narrow window fails with permission denied even though the same path works moments later.
   Instead of just checking the directory exists, this plugin polls with a real `ls` (up to ~6s)
   before handing control back to Yazi, and surfaces the real underlying error if it never
   recovers rather than dropping you into a directory that silently looks empty.

## Requirements

- KDE Connect installed and running, with `kdeconnect-cli` in `PATH`.
- `sshfs` installed — KDE Connect's `--mount` reports success even when the underlying `sshfs`
  mount silently fails (a known KDE Connect quirk), so this plugin double-checks the mount point
  actually exists afterwards and tells you to check `sshfs` if it doesn't.
- `fusermount` (part of `fuse`/`fuse3`, virtually always already present alongside `sshfs`).
- At least one device paired and reachable.

## Installation

```sh
ya pkg add PHONE1X/kdeconnect.yazi
# or
git clone https://github.com/PHONE1X/kdeconnect.yazi.git ~/.config/yazi/plugins/kdeconnect.yazi
```

## Usage

Add to your `~/.config/yazi/keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on   = [ "g", "p" ]
run  = "plugin kdeconnect browse"
desc = "Browse phone via KDE Connect"

[[mgr.prepend_keymap]]
on   = [ "c", "s" ]
run  = "plugin kdeconnect send"
desc = "Send selected/hovered files via KDE Connect"
```

If more than one device is paired and reachable, both actions prompt you to pick one. With a
single reachable device, it's used automatically unless you turn that off:

```lua
-- ~/.config/yazi/init.lua
require("kdeconnect"):setup({
  auto_select_single = false, -- always show the device picker
})
```

## Credits

Written from scratch against `kdeconnect-cli`'s documented `--mount` / `--get-mount-point` /
`--share` options (see [kdeconnect-cli.cpp](https://github.com/KDE/kdeconnect-kde/blob/master/cli/kdeconnect-cli.cpp)).
MIT-licensed, see [LICENSE](./LICENSE).
