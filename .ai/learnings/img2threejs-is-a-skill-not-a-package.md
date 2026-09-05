# img2three.js is a Claude Code skill, not an npm package

**Context.** Asked to "use Three.js and img2three.js" to recreate a scene. `npm view img2three` and
`img2three.js` both 404.

**Lesson.** The thing meant is [img2threejs/img2threejs](https://github.com/img2threejs/img2threejs):
a Claude Code / Codex skill that rebuilds a reference image as a *code-only* `THREE.Group` factory
(primitives + procedural shaders, with pivots / sockets / colliders and a `userData.tick`). It is
installed by cloning into `~/.claude/skills/`, not by `bun add`.

**How we applied it.** Followed its factory contract for the stargate and gate room without running
its full multi-artifact forge gate pipeline (that is a multi-session workflow). Reference frames were
extracted with ffmpeg and compared side-by-side with screenshots at each pass, which is the spirit of
its review loop.
