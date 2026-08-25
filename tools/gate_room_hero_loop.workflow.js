export const meta = {
  name: 'gate-room-hero-loop-v3',
  description: 'Karpathy loop v3 (anti-oscillation): tighter accept gate (majority closer AND same-panel numeric gain) so best.png climbs instead of thrashing exposure. Robust safeAgent calls.',
  phases: [
    { title: 'Mutate', detail: 'edit scene/shader/assets + render candidate' },
    { title: 'Judge', detail: '3 independent judges score candidate vs best vs target' },
    { title: 'Referee', detail: 'commit (accept) or git revert (reject)' },
  ],
}

const REPO = '/Users/cmoyer/Projects/personal/stargate-universe'
const TARGET = `${REPO}/design/concept-art/gate-room/target/gateroom-hero-target.png`
const BEST = `${REPO}/screenshots/loop/best.png`
const CAND = `${REPO}/screenshots/loop/candidate.png`
const UNITY = '/Users/cmoyer/Projects/unity/unity-sgu/Assets/PaulosCreations/RunesAndPortals'

const RUBRIC = `
ART TARGET — the concept frame (${TARGET}). Score "closeness" on these dimensions, in priority order:
1. TONALITY/KEY: VERY DARK, high-contrast; portal + thin volumetric spot-shafts are the ONLY bright areas. BUT NOT an empty black void — the walls/ceiling are DIMLY visible detailed metal, not pure black.
2. PALETTE: Desaturated cool steel + black, SELECTIVE blue accents. Blue lives in the portal + console screens, not everywhere.
3. ARCHITECTURE DETAIL & DEPTH: Dense industrial detail DIMLY LIT and READABLE — stacked ribbed wall panels, horizontal banding, thin glowing recessed window-slits, LARGE diagonal buttress beams flanking the gate, a tiered ceiling DOME of concentric rings with downlights. Tall and cavernous. (Current renders over-crush the side walls + dome into invisible black — this is the #1 remaining gap.)
4. GATE RING: THICK segmented DARK-metal ring with inward-pointing glowing TRIANGULAR chevrons; railed platform + short central staircase.
5. VORTEX: near-circular churning blue-white PLASMA filling the ring, fine filamentary detail, SMALL dark unstable centre, soft bloom halo.
6. CONSOLE BANKS: rows of faint-blue glowing screens along BOTH side walls in the foreground.
7. FLOOR: dark wet metal grid plates, SUBTLE long reflections, perspective seams converging to the gate.
8. LIGHTING: volumetric god-rays from ceiling spots; portal glow + floor reflection; low-key single-dominant-source.
9. COMPOSITION: symmetric one-point perspective, gate centred, camera near floor.
`

const ANTI_OSC = `CRITICAL — DO NOT THRASH GLOBAL EXPOSURE. Across ~90 prior iterations tonemap_exposure has oscillated 0.62<->0.95 between two judges' preferences and the score plateaued. LEAVE tonemap_exposure roughly where it is (~0.7-0.85). If the room is too black, bring back DIM, READABLE architecture LOCALLY — low-energy emissive accent strips, faint window-slits, a dim cold rim/fill on the walls/dome/buttresses, dome downlight pucks — NOT by raising global exposure (which blows out the portal) or global ambient (which greys everything). The target's walls are dark but you can SEE their ribbing/banding; that's the goal.`

const FILES = `scripts/gate_room_hero.gd (geometry, lighting, materials, camera, WorldEnvironment), shaders/hero_portal.gdshader (the vortex), and scenes/gate_room_hero.tscn`
const RENDER = `cd ${REPO} && timeout 200 bash tools/gate_hero_render.sh candidate 220 2>&1 | tail -6`

function mutatorPrompt(i, bold, lastGaps) {
  return `You are iteration #${i} of a Karpathy-style self-improvement loop refining a Godot gate-room scene toward a concept image. The scene is already strong (dark cathedral, segmented gate ring + inward chevrons, churning blue plasma vortex, flanking console banks, reflective floor). Push it CLOSER.

Study both with the Read tool:
- TARGET (goal): ${TARGET}
- CURRENT BEST render: ${BEST}

${RUBRIC}

${ANTI_OSC}

${lastGaps && lastGaps.length ? `Judges' biggest remaining gaps last round: ${JSON.stringify(lastGaps)}` : ''}

YOUR JOB: ONE focused, high-impact change that makes the BEST render measurably closer to TARGET. The TOP gap right now is the over-crushed, invisible side walls + ceiling dome — strongly consider attacking that (restore dim readable ribbing/banding/window-slits/dome via localized accents, NOT global exposure). Otherwise pick another concrete gap.${bold ? ' Recent attempts were REVERTED — take a BOLDER swing and attack a DIFFERENT dimension than recent ones.' : ''}

EDIT ONLY: ${FILES}. NEW ASSETS only inside ${REPO}/assets/hero/ (so a revert can clean them); you may copy the licensed Unity assets from ${UNITY} there. Keep GDScript statically typed (no ':=' on Variant/Dictionary; loop vars over literal arrays need ': float'). Shader: do NOT redefine built-ins (TAU/PI are predefined — redefining them silently fails compile and the material vanishes).

RENDER (only here): ${RENDER}
VERIFY "SHOT ... (save err=0)" and a fresh candidate.png. Also confirm NO "SHADER ERROR"/"Parse Error"/"SCRIPT ERROR" in the output — if present your edit is broken: cd ${REPO} && git checkout -- scripts/gate_room_hero.gd shaders/hero_portal.gdshader scenes/gate_room_hero.tscn assets/hero && git clean -fdq assets/hero/ ; then return render_ok=false with the error in self_assessment.
If clean, Read ${CAND} and honestly compare to TARGET and BEST. Return render_ok=true. Do NOT git commit — leave edits in place. Return the structured result.`
}

function judgePrompt(i, j) {
  const lens = ['Focus on TONALITY/PALETTE and whether the side walls + ceiling dome are DIMLY READABLE detail vs an empty black void (penalise pure-black walls). Plus overall gestalt.',
                'Focus on the GATE RING + VORTEX (thick segmented DARK ring, glowing triangular chevrons, near-circular churning plasma with a small dark eye).',
                'Focus on ARCHITECTURE DEPTH, CONSOLE BANKS, FLOOR REFLECTIONS, COMPOSITION.'][(j - 1) % 3]
  return `You are judge #${j} for iteration #${i} of a loop matching a Godot render to a concept image. Be a STRICT, HONEST art director — not charitable, but calibrate consistently.

Read all three:
- TARGET (goal): ${TARGET}
- BEST (previous best render): ${BEST}
- CANDIDATE (new render): ${CAND}

${RUBRIC}

${lens}

Is CANDIDATE genuinely closer to TARGET than BEST? Lateral/regression/merely-different => closer_to_target=false. Give each a 0-100 similarity-to-TARGET score (calibrate: a dark cathedral with the right ring+vortex+consoles but over-black walls is ~35-45; getting the dim wall/dome detail + polished vortex right pushes 55-70). Name the single biggest remaining gap. Do NOT edit/render/git. You MUST finish by calling the StructuredOutput tool.`
}

function acceptPrompt(i, summary, score) {
  return `Iteration #${i} ACCEPTED (~${score}/100). Promote:
cd ${REPO}
cp screenshots/loop/candidate.png screenshots/loop/best.png
git add -A scripts/gate_room_hero.gd shaders/hero_portal.gdshader scenes/gate_room_hero.tscn assets/hero
git commit -q -m "loop(#${i}): ${summary.replace(/"/g, "'").slice(0, 80)} — closer to concept (~${score}/100)" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git rev-parse --short HEAD
Return action="committed" + short SHA in commit. If nothing to commit, note it and still return action="committed".`
}

function rejectPrompt(i) {
  return `Iteration #${i} REJECTED. Revert:
cd ${REPO}
git checkout -- scripts/gate_room_hero.gd shaders/hero_portal.gdshader scenes/gate_room_hero.tscn assets/hero
git clean -fdq assets/hero/
git status --short
Confirm the three core files + assets/hero clean. Return action="reverted". Do NOT touch screenshots/loop/best.png.`
}

const JUDGE_SCHEMA = { type: 'object', required: ['closer_to_target', 'candidate_score', 'best_score', 'biggest_remaining_gap'], properties: { closer_to_target: { type: 'boolean' }, candidate_score: { type: 'integer', minimum: 0, maximum: 100 }, best_score: { type: 'integer', minimum: 0, maximum: 100 }, biggest_remaining_gap: { type: 'string' }, reasoning: { type: 'string' } } }
const MUT_SCHEMA = { type: 'object', required: ['render_ok', 'hypothesis', 'change_summary', 'files_touched'], properties: { render_ok: { type: 'boolean' }, hypothesis: { type: 'string' }, change_summary: { type: 'string' }, files_touched: { type: 'array', items: { type: 'string' } }, self_assessment: { type: 'string' } } }
const REF_SCHEMA = { type: 'object', required: ['action'], properties: { action: { type: 'string' }, commit: { type: 'string' }, note: { type: 'string' } } }

async function safeAgent(prompt, opts) {
  try { return await agent(prompt, opts) } catch (e) { log(`  (agent ${opts && opts.label ? opts.label : '?'} failed: ${String(e).slice(0, 80)})`); return null }
}
const avg = (xs) => xs.length ? Math.round(xs.reduce((a, b) => a + b, 0) / xs.length) : 0

const MAX = 60
const history = []
let consecutiveReverts = 0
let highStreak = 0
let lastGaps = []
let bestScoreNow = 0

for (let i = 1; i <= MAX; i++) {
  const bold = consecutiveReverts >= 3
  phase('Mutate')
  let mut = await safeAgent(mutatorPrompt(i, bold, lastGaps), { label: `mutate#${i}`, phase: 'Mutate', schema: MUT_SCHEMA, agentType: 'general-purpose' })
  if (!mut) mut = await safeAgent(mutatorPrompt(i, bold, lastGaps), { label: `mutate#${i}r`, phase: 'Mutate', schema: MUT_SCHEMA, agentType: 'general-purpose' })
  if (!mut) { log(`#${i} skipped (mutator failed twice)`); continue }

  if (!mut.render_ok) {
    await safeAgent(rejectPrompt(i), { label: `clean#${i}`, phase: 'Referee', schema: REF_SCHEMA, agentType: 'general-purpose' })
    consecutiveReverts++
    history.push({ i, accepted: false, reason: 'render_failed', hypothesis: mut.hypothesis })
    log(`#${i} ⚠ render failed/reverted — ${mut.hypothesis}`)
    if (consecutiveReverts >= 10) { log('10 consecutive failures — stopping.'); break }
    continue
  }

  const votes = (await parallel([1, 2, 3].map((j) => () =>
    safeAgent(judgePrompt(i, j), { label: `judge#${i}.${j}`, phase: 'Judge', schema: JUDGE_SCHEMA, agentType: 'general-purpose' })
  ))).filter(Boolean)

  if (votes.length < 2) {
    await safeAgent(rejectPrompt(i), { label: `revert#${i}`, phase: 'Referee', schema: REF_SCHEMA, agentType: 'general-purpose' })
    consecutiveReverts++
    history.push({ i, accepted: false, reason: 'panel_too_thin', hypothesis: mut.hypothesis })
    log(`#${i} ✗ revert (only ${votes.length} judges)`)
    continue
  }

  const closer = votes.filter((v) => v.closer_to_target).length
  const avgCand = avg(votes.map((v) => v.candidate_score))
  const avgBest = avg(votes.map((v) => v.best_score))
  lastGaps = votes.map((v) => v.biggest_remaining_gap).filter(Boolean)
  // v3 gate: majority "closer" AND a same-panel numeric gain — kills lateral thrash.
  const accept = closer >= 2 && avgCand > avgBest

  if (accept) {
    const ref = await safeAgent(acceptPrompt(i, mut.change_summary, avgCand), { label: `accept#${i}`, phase: 'Referee', schema: REF_SCHEMA, agentType: 'general-purpose' })
    consecutiveReverts = 0
    bestScoreNow = avgCand
    history.push({ i, accepted: true, score: avgCand, hypothesis: mut.hypothesis, change: mut.change_summary, commit: ref ? ref.commit : null })
    log(`#${i} ✓ ACCEPT — score ${avgCand} (was ${avgBest}) — ${mut.change_summary}`)
    highStreak = avgCand >= 88 ? highStreak + 1 : 0
    if (highStreak >= 3) { log(`Reached ~target (${avgCand}/100) x3 — stopping.`); break }
  } else {
    await safeAgent(rejectPrompt(i), { label: `revert#${i}`, phase: 'Referee', schema: REF_SCHEMA, agentType: 'general-purpose' })
    consecutiveReverts++
    history.push({ i, accepted: false, score: avgCand, hypothesis: mut.hypothesis })
    log(`#${i} ✗ revert (closer ${closer}/3 · cand ${avgCand} vs best ${avgBest})`)
    if (consecutiveReverts >= 10) { log('10 consecutive reverts — stuck, stopping.'); break }
  }
}

const accepted = history.filter((h) => h.accepted)
return { iterations: history.length, accepted: accepted.length, final_best_score: bestScoreNow, commits: accepted.map((h) => ({ i: h.i, score: h.score, commit: h.commit, change: h.change })), history }
