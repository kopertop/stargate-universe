# A PR "full of conflicts" usually means the branch was cut from the wrong base

**Symptom.** PR #180 to `main` showed conflicts in a dozen Godot files this branch never touched
(`scripts/power_grid.gd`, `scripts/room.gd`, `tests/run.sh`, …).

**Cause.** The worktree branch was created from `develop`, which carried two commits (`a6e16eb`,
`9395f4f`) that `main` had received as *rebased copies* with different SHAs. Our commits only touched
`web/`, `.ai/learnings/` and `.claude/launch.json`, but the PR diff against `main` dragged the
develop-only commits along and they collided with main's versions.

**Diagnosis in three commands.**
```bash
git merge-base origin/main HEAD                       # where main and this branch diverge
git log --oneline origin/develop..HEAD                 # exactly OUR commits (8 here)
git diff --name-only origin/develop..HEAD | rg -v '^web/'   # confirm scope
```

**Fix (no history rewrite — force pushes are off the table on shared branches).** Merge `origin/main`
into the branch and resolve every conflict by taking main's side, then make *all* non-feature paths equal
main so the PR diff is only your work:
```bash
git merge origin/main                                   # conflicts in files you never edited
for f in $(git diff --name-only --diff-filter=U); do git checkout --theirs -- "$f"; git add "$f"; done
git diff --name-only origin/main -- . ':(exclude)web' | while read f; do   # develop-only leftovers
  git cat-file -e "origin/main:$f" 2>/dev/null && git checkout origin/main -- "$f" || git rm -q --cached "$f"; done
git commit && git push                                  # plain fast-forward push
git diff --name-only origin/main | rg -v '^web/'        # must print nothing
```
A rebase onto main would also produce a clean diff, but it rewrites published history and needs a force
push, which the project rejects.

**Rule.** Cut feature branches from the PR base (`main`), not from `develop`. Check with
`git merge-base --is-ancestor origin/<base> HEAD` before the first push; fixing it later means a merge commit.
