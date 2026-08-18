# merge-paste.yazi

Conflict-aware paste for [Yazi](https://github.com/sxyazi/yazi) — Overwrite / Merge / Skip / Rename,
the way Dolphin, Explorer, and every other GUI file manager handle a name clash on paste.

## Why this exists

Yazi's built-in `paste` only has two behaviors:

- by default it **silently renames** the pasted item (`file.txt` → `file_1.txt`);
- with `--force` it **silently overwrites** whatever was there.

There's no prompt, and — more importantly — **no way to merge a folder into an existing one of the
same name**. A request for exactly that was
[closed "not planned" upstream](https://github.com/sxyazi/yazi/issues/982), so it's unlikely to land
in Yazi itself.

This plugin replaces `paste` for interactive use. For every yanked item whose name collides with
something already at the destination, it asks:

- **Overwrite** — delete what's there, paste the new item in its place.
- **Merge** *(folders only)* — copy the source folder's contents into the existing destination
  folder, combining the two trees. Anything that *also* collides inside gets overwritten — this
  is a straightforward merge-and-replace, not a 3-way/diff merge.
- **Skip** — leave the destination untouched, don't paste this item.
- **Rename** — paste alongside it with a `_1`/`_2`/... suffix, same convention as Yazi's own
  default behavior.

The first conflict in a batch also offers **"do this for all remaining conflicts"**, so pasting a
big folder tree over an existing one doesn't turn into a wall of prompts — one decision, applied
to the rest (with a per-item fallback prompt if a later conflict doesn't fit, e.g. you picked
"Merge" but the next clash is file-vs-file, not folder-vs-folder).

## Requirements

- Yazi with Lua plugin support (any recent version).
- Standard Unix tools already on virtually every Linux/macOS system: `cp`, `mv`, `rm`, `test`.
  Nothing extra to install.

## Installation

```sh
ya pkg add PHONE1X/merge-paste.yazi
# or
git clone https://github.com/PHONE1X/merge-paste.yazi.git ~/.config/yazi/plugins/merge-paste.yazi
```

## Usage

This intentionally does **not** override Yazi's default `p`/`P` — add it under its own key so you
can reach for it only when you expect a conflict (or rebind it over `paste` yourself if you'd
rather it always be in charge):

```toml
# ~/.config/yazi/keymap.toml
[[mgr.prepend_keymap]]
on   = [ "c", "v" ]
run  = "plugin merge-paste"
desc = "Paste with conflict prompt (overwrite / merge / skip / rename)"
```

Workflow: yank files as usual (`y` to copy, `x` to cut), navigate to the destination, then
`c v` instead of `p`.

## Caveats

- "Merge" is a straightforward copy-over — it does not diff file contents, it just overwrites
  same-named files inside the merged folder. If you need per-nested-file review, this isn't a
  substitute for something like `rsync -i` or a dedicated diff/merge tool.
- Moves (cut + paste) into a "Merge" resolution are implemented as copy-then-delete-source, not an
  atomic rename, since a true merge can't be a single `mv`. For very large trees, this is slower
  than a plain move and needs enough free space to hold both copies briefly.
- This shells out to `cp -a` / `mv` / `rm -rf` rather than reimplementing file copying — same
  approach the rest of this author's Yazi plugins use, for the same reason: these are
  battle-tested and handle permissions/symlinks/edge cases correctly.

## Credits

Written to close a real, upstream-acknowledged gap in Yazi's own `paste` command
(see [sxyazi/yazi#982](https://github.com/sxyazi/yazi/issues/982)). MIT-licensed, see
[LICENSE](./LICENSE).
