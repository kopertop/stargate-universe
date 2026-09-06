# `location.reload()` from javascript_tool: the next evaluation may run on the OLD document

**Symptom.** After `location.reload()`, a follow-up script that polled for `window.__dbg` found it
immediately, clicked the title screen, and read back "no progress / no save" — it had driven the outgoing
page, which the reload then discarded.

**Fix.** Mark the old document before reloading (`window.__old = true; setTimeout(() => location.reload(), 50)`),
then in the next script `await sleep(1500)` first and poll until `!window.__old && window.__dbg`. If the
evaluation still dies with "Inspected target navigated", just re-run the polling script — the reload happened.
Also: don't run two `browser_batch` calls in parallel on different tabs; `wait` steps get routed to the
active tab and the sequences interleave.
