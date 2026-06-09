# DAILY SYNC — merge `develop` into the gate-room feature branch

Runs once a day on sparky. Keep `feature/gate-room-hero-portal` current with the
team's integration branch `develop` so the long-running loop doesn't drift. One
pass, then stop.

## Steps
1. **Guard.**
   ```
   git rev-parse --abbrev-ref HEAD        # MUST be feature/gate-room-hero-portal
   git checkout -- '*.import' 2>/dev/null || true
   git ls-files -m | grep -E '\.res$' | xargs -r git checkout -- 2>/dev/null || true
   git status --porcelain                 # must be clean now
   ```
   If not on the feature branch, or the tree is dirty with non-churn changes, STOP and report.

2. **Fetch + check.**
   ```
   git fetch origin
   git log --oneline HEAD..origin/develop | head    # what's new on develop?
   ```
   If `origin/develop` has nothing new since the last merge (empty), STOP — nothing to do.

3. **Merge develop → feature.**
   ```
   git merge --no-edit origin/develop
   ```
   - Clean merge → go to step 5.
   - CONFLICTS → step 4.

4. **Resolve conflicts (sensibly) or bail.**
   - For the loop's own files — `scripts/gate_room_hero.gd`, `shaders/hero_portal.gdshader`,
     `scenes/gate_room_hero.tscn`, anything under `tools/hermes/` and `.claude/skills/gate-room-hero-loop/`
     — KEEP OURS (`git checkout --ours <file> && git add <file>`); the loop owns these.
   - For shared/config files (`.gitignore`, docs, unrelated game code) — integrate BOTH
     sides if it's obvious and safe; prefer theirs for files the loop never touches.
   - If a conflict is non-trivial, risky, or you are unsure: ABORT and report —
     `git merge --abort` — do NOT guess. A human will merge it.
   - Discard any import/bake churn before committing the merge (`git checkout -- '*.import'`, `*.res`).

5. **Commit + push.**
   ```
   git add -A
   git commit --no-edit 2>/dev/null || true     # finalize the merge commit if one is pending
   git push origin feature/gate-room-hero-portal
   ```

## Rules
- ONE-WAY only: merge `develop` INTO the feature branch. NEVER push to `develop` or `main`.
- Never force-push. If push is rejected, `git pull --rebase origin feature/gate-room-hero-portal` then push once; if it still fails, report.
- When in doubt about a conflict, `git merge --abort` and report rather than risk a bad merge.
- One pass per run; the scheduler re-invokes daily.
