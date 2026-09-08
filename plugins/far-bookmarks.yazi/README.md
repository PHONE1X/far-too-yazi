# far-bookmarks.yazi

FAR Manager's **folder shortcuts** for [yazi](https://yazi-rs.github.io/) —
a hand-built list of the directories you keep coming back to, each with a
one-character key, so any of them is two keystrokes away.

Total Commander calls the same feature the *directory hotlist*. yazi ships
neither. `zoxide` and `fzf` are the closest things it has, but both work by
guessing from history; this list contains only what you put in it, which is
what you want for the handful of folders you open every single day.

## Keys

Bound in this config's keymaps (rebind them freely):

| vim mode | FAR mode | Action |
|---|---|---|
| `` ` `` | `Ctrl+D` | Open the list — add, jump, rename, delete, reorder |
| `'` | `Alt+F11` | Jump menu: one keypress per bookmark, no popup |
| `Alt+B` | `Alt+B` | Bookmark the directory the panel is in |

Inside the list:

| Key | Action |
|---|---|
| `Enter` | Go to the highlighted bookmark |
| `t` | Open it in a new tab instead |
| a bookmark's own key | Go straight there |
| `a` | Bookmark the current directory |
| `A` | Bookmark the hovered folder instead |
| `r` | Rename |
| `s` | Change the shortcut key |
| `d` / `x` | Delete |
| `J` / `K` | Move the entry down / up |
| `q` / `Esc` | Close |

## Commands

```
plugin far-bookmarks                  open the list
plugin far-bookmarks jump             one-keypress jump menu
plugin far-bookmarks add              bookmark the current directory
plugin far-bookmarks -- add hovered   bookmark the hovered folder
plugin far-bookmarks -- go w          jump to the bookmark keyed "w"
```

The `--` on the last two matters. yazi passes a single bare word after the
plugin name straight through, but drops a second one, so `plugin
far-bookmarks add hovered` would silently run plain `add`. The `--`
separator is what makes yazi split the rest into real arguments.

Use the `go` form to give one favourite folder its own dedicated key:

```toml
[[mgr.prepend_keymap]]
on   = "<A-1>"
run  = "plugin far-bookmarks -- go w"
desc = "Jump to the work directory"
```

## Where the list lives

`$YAZI_CONFIG_HOME/bookmarks-data.lua` (normally
`~/.config/yazi/bookmarks-data.lua`) — a plain Lua table, so you can
hand-edit it or check it into your dotfiles:

```lua
return {
	{ key = "g", name = "Steam games", path = "/home/you/.local/share/Steam/steamapps/common" },
	{ key = "w", name = "Work",        path = "/home/you/projects" },
}
```

`key` may be empty, in which case the bookmark is still reachable with
`Enter` on its row — it just has no direct shortcut. A bookmark whose
directory has since been deleted or unmounted says so when you try to jump
to it, instead of the jump quietly doing nothing.

## First run

If no data file exists at all, the first invocation seeds one with the
gaming directories that are tedious to reach by hand, skipping any that
are not present on the machine:

- Steam library — `steamapps/common`
- Proton prefixes — `steamapps/compatdata`
- PortProton prefixes — `PortProton/data/prefixes`
- Installed Proton builds — `compatibilitytools.d`

Each is looked up across the native, Flatpak and legacy `~/.steam` layouts.
This happens exactly once: after the file exists the list is yours, and
emptying it does not bring the seed back.

## `add` vs `add hovered`

`add` always bookmarks the directory the panel is **in**, never the folder
the cursor happens to be sitting on. That is deliberate: a command that
silently retargets itself based on the cursor is a command you cannot
predict. When you do want the folder under the cursor, ask for it
explicitly with `A` in the popup or `-- add hovered`.

## Part of

[far-too-yazi](https://github.com/PHONE1X/far2yazi) — a FAR
Manager-style yazi configuration. Works standalone in any yazi config too;
it has no dependencies beyond yazi itself.

## License

MIT
