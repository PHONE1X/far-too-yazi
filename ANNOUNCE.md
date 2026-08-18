Draft for posting to yazi's community channels (GitHub Discussions "Show
and tell", the yazi Discord/Matrix, r/commandline, etc.) — edit to taste,
this is a starting point, not a final copy.

---

**far-too-yazi: a FAR Manager-style dual-pane mode for yazi, one keystroke
away from yazi's normal vim-style layout**

I wanted the classic two-panel file-manager workflow (FAR Manager / Norton
Commander style — F5 copy, F6 move, Tab between panels) without giving up
yazi's own vim-style single-pane mode for everyday browsing. yazi has no
live keymap reload, so switching modes means restarting the process — this
project does that fast enough, and restores your tabs/cwd/pane layout
across the restart, that it feels like a live toggle rather than a
relaunch.

What's in it:
- A dual-pane compositor built by patching yazi's own `Tab.layout`/
  `Tab.build` (not a third-party dual-pane plugin) — two tabs rendered
  side by side as one view.
- Instant-feeling mode switching (Alt+M) between a vim-style keymap and a
  FAR-style one, via a shell wrapper that relaunches yazi and restores
  session state.
- Conflict-aware transfers everywhere (F5/F6/Y/Ctrl+Y all prompt
  Overwrite/Merge/Skip/Rename on name collisions, not just a plain paste).
- FAR's F2/F9/F11 menus and Alt+F10 fuzzy folder jump.

Repo: <link>
Fish shell required for the mode-switch relaunch wrapper right now (a
bash/zsh port would be a welcome contribution). Roadmap includes multiple
dual-pane workspaces (browser-tab-style) and 3-4 pane layouts, both
documented in the repo for anyone who wants to pick them up.

Happy to answer questions about how the relaunch/restore mechanism works —
write-up is in `docs/FAR-MODE.md` if you want the details before asking.
