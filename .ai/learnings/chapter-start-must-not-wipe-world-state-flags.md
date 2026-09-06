# Chapter start must not wipe world-state flags

**Symptom:** After Episode 1 completed and Episode 2 started, TAB said "You have no device to open yet"
even though the Kino Remote had been picked up. Locker/console prompts also reappeared.

**Cause:** `quest.startChapter()` did `flags.clear()`. The same flag set held two kinds of facts:
step-completion flags (`arrived`, `ftl_dropped`) and persistent world state (`kino_acquired`,
`power_restored`, `any_breach_sealed`, `scrubber_repaired`) that gates interactables and save/load rebuild.

**Fix:** On chapter start, delete only the flags the new chapter's steps `complete_when` on. Everything
else survives. Data-driven, no hardcoded "persistent" list to maintain.

**Lesson:** A hands-free full playthrough that stops at "episode complete" never exercises the first
input of the *next* chapter. Add one post-completion action (open the menu) to the smoke run.
