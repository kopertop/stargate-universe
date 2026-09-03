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

**Fix.** `git rebase --onto origin/main origin/develop` moved only our commits onto main; zero
conflicts. Then `git push --force-with-lease`. (A `git merge origin/main` would have forced resolving
files we never edited.)

**Rule.** Before opening a PR, check `git merge-base --is-ancestor origin/<base> HEAD`; if the branch
descends from an integration branch instead of the PR base, rebase onto the base first.
