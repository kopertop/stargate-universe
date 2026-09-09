# `node --check foo.js` can pass a module the browser refuses to parse

**Context:** A Python patch inserted a new `interact.register(...)` block after "the line containing `id: 'grow_console'`" —
which was only the first line of a multi-line statement. The pre-commit hook (`node --check src/main.js`) passed, the commit
landed, and the game came up as `LOADING DESTINY…` forever with `Uncaught SyntaxError: Unexpected token '['`. Copying the
same file to `main.mjs` made `node --check` report the error with a line number.

**Lesson:** Without `"type": "module"` in a package.json, `node --check` parses a `.js` file as CommonJS, and the failure
modes differ from the browser's module parser — a file can pass one and fail the other. Check ES modules as `.mjs` (the hook
and CI now copy each file to a temp `.mjs` first), and after any automated splice into source, load the page and confirm
`window.__dbg` exists before doing anything else. When inserting code by line search, anchor on the statement's *closing*
line (`} });`), never on a line that merely contains the identifier.

**Applies to:** `.githooks/pre-commit`, `.github/workflows/ci.yml`, every scripted edit of `src/*.js`.
