# Next steps — run these in your own terminal

Repo is live: **https://github.com/PHONE1X/far-too-yazi**

Run everything below on your machine directly (not through Cowork/Claude)
— this terminal has your git identity and GitHub credentials configured,
the Cowork sandbox has neither.

## 1. Rename yazi-test to yazi (promote it to your real config)

The sandbox I have shell access to can't do this cleanly — it can copy
files across the mount boundary but can't delete the originals afterward,
so a plain `mv` from here leaves duplicates instead of actually moving
anything. Your own terminal doesn't have that restriction:

```sh
# back up the old ~/.config/yazi first -- never overwrite blind
mv ~/.config/yazi ~/.config/yazi.OLD-backup-$(date +%Y%m%d)

# promote the repo to be your real config
mv ~/.config/yazi-test ~/.config/yazi
```

After this, plain `yazi` and `y` both use the new config automatically
(the default lookup is `~/.config/yazi` unless `$YAZI_CONFIG_HOME` is set).
The `yt` fish function (which force-set `YAZI_CONFIG_HOME` to the test
directory) is now pointless — its target no longer exists. Either delete
`~/.config/fish/functions/yt.fish`, or leave it; it'll just silently do
nothing useful since `~/.config/yazi-test` won't exist anymore.

Your git repo's working directory also just changed path (it moves with
the `mv`, `.git` and the `origin` remote are unaffected) — `cd
~/.config/yazi` for everything below, not `yazi-test`.

## 2. Commit and push the embedded-repo fix

This is important, not optional: the initial commit accidentally recorded
`compress.yazi`, `kdeconnect.yazi`, `merge-paste.yazi`, `ouch.yazi`,
`split-tabs.yazi`, and `ucp.yazi` as **gitlinks** (submodule references)
instead of tracked files, because each still had its own `.git` directory
from being cloned individually. Anyone who clones `far-too-yazi` right now
gets 6 **empty** plugin directories — including `split-tabs.yazi` and
`merge-paste.yazi`, the two most important custom modules in the whole
project.

This is already fixed and staged on disk (nested `.git` dirs stripped, the
real files re-added) — it just needs your git identity to actually commit,
which the sandbox doesn't have:

```sh
cd ~/.config/yazi   # after the rename above
git status --short  # sanity check: should show D/A pairs for 7 plugin dirs
git commit -m "Fix: un-embed plugin repos so a fresh clone actually contains them

compress.yazi, kdeconnect.yazi, merge-paste.yazi, ouch.yazi,
split-tabs.yazi, and ucp.yazi were each cloned with their own .git
directory still present, so the initial commit recorded them as gitlinks
(submodule references) instead of tracked files -- a fresh clone of this
repo would have had 6 EMPTY plugin directories, including the two most
important custom ones (split-tabs, merge-paste). Stripped the nested .git
dirs and re-added the actual file contents.

Also removed dual-pane.yazi: no main.lua, disabled in init.lua as
incompatible, purely a leftover from an earlier approach that was
abandoned in favor of split-tabs.yazi's own compositor."
git push
```

Verify it actually worked after pushing — browse to
`https://github.com/PHONE1X/far-too-yazi/tree/main/plugins/split-tabs.yazi`
and confirm you see `main.lua` and the other files, not an empty directory
or a "this is a broken submodule link" notice.

## 3. Clean up the two harmless errors from before

- `git remote add origin ...` failing with "Path 'your-username' does not
  exist" — expected, harmless. `gh repo create ... --push` already added
  `origin` successfully in the step right before it; this second command
  was the "repo already exists" fallback path from my original
  instructions, which didn't apply to you. Nothing to fix.
- The `release/v1` PR failing with "No commits between main and
  release/v1" — also expected. You branched off `main` and immediately
  tried to open a PR with zero new commits on the branch; there was
  nothing to diff. Once you push the embedded-repo fix above, `main` will
  have moved ahead of that stale branch. If you want to delete the unused
  branch:
  ```sh
  git push origin --delete release/v1
  git branch -D release/v1
  ```
  Or just ignore it — an empty branch sitting on the remote costs nothing.

## 4. Announcing it

A draft post is in `ANNOUNCE.md` — replace the `<link>` placeholder with
`https://github.com/PHONE1X/far-too-yazi`, then it's ready to adapt for
GitHub Discussions ("Show and tell"), the yazi Discord/Matrix, or wherever
else you want to post it. Worth checking yazi's own docs/README for
whether a community plugin list exists before posting there too — not
verified from here.
