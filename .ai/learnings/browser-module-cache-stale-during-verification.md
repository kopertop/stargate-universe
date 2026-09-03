# ES module imports can stay cached across reloads; force-refetch before trusting a "bug"

**Symptom.** Edited `player.js` to add `samplePoint()`, reloaded the page, got
`TypeError: player.samplePoint is not a function` even though the file on disk had it.

**Cause.** The page HTML revalidated on reload but the imported module (served by python
`http.server` with only `Last-Modified`) was reused under heuristic freshness.

**Fix.** Before reloading in the in-app browser, refetch the module graph with cache bypass:

```js
await Promise.all(['main','player','stargate'].map((f) => fetch(`./src/${f}.js`, { cache: 'reload' })));
location.reload();
```

Rule: if a stack trace contradicts the file on disk, suspect the cache before the code.
