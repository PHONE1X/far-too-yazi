# Commands to run in your own terminal

Run these on your machine directly (not through Cowork/Claude) — this
terminal has your GitHub credentials, the Cowork sandbox doesn't.

```sh
cd ~/.config/yazi-test
```

## 1. Commit everything locally

```sh
git init
git checkout -b main
git add -A
git commit -m "far-too-yazi: FAR Manager-style dual-pane mode for yazi"
```

(`git init` and `git checkout -b main` are safe to re-run if you already
did this — `git init` on an existing repo is a no-op, and `git checkout -b
main` will just error harmlessly if `main` already exists, which you can
ignore.)

## 2. Push — pick whichever matches your situation

**If the GitHub repo does NOT exist yet:**

```sh
gh repo create far-too-yazi --public --source=. --remote=origin --push
```

This creates the repo under your account, adds it as `origin`, and pushes
`main` in one step. Drop `--public` (or use `--private`) if you'd rather
keep it private for now.

**If the GitHub repo already exists** (you mentioned it might):

```sh
git remote add origin git@github.com:<your-username>/far-too-yazi.git
git push -u origin main
```

(Use the HTTPS URL instead of the SSH one above if that's how you've
authenticated `gh`/`git` before — whichever you already use for other
repos.)

## 3. Optional: review your own first commit via PR before it's "official"

If you'd rather not push straight to `main` and want to look it over as a
PR first:

```sh
git checkout -b release/v1
git push -u origin release/v1
gh pr create --title "far-too-yazi initial release" --body "First public release: FAR Manager-style dual-pane mode, mode-switch relaunch, conflict-aware transfers. See README.md and docs/FAR-MODE.md." --base main --head release/v1
```

Note this only makes sense if `main` already exists on the remote with
*something* in it (even just this same commit) — a PR needs two branches
to diff against each other. If you used the `gh repo create ... --push`
path above, `main` is already there; branch off it before making further
changes and this works as expected. If `main` doesn't exist remotely yet,
skip this step and just push directly per step 2 — there's nothing to
review against for a first commit anyway.

## 4. Announcing it

A draft post is in `ANNOUNCE.md` — edit the `<link>` placeholder to your
repo URL, then it's ready to adapt for GitHub Discussions ("Show and
tell"), the yazi Discord/Matrix, or wherever else you want to post it.
Submitting to yazi's own repo (e.g. an entry in a community plugin list,
if one exists) is worth checking for in yazi's own docs/README before
posting — I didn't verify whether such a list currently exists.
