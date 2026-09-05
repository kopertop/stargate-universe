# Quaternius UAL1 + UAL2 share one skeleton: load one mesh, use both clip sets

**Need.** Animations for every interaction (dig, interact, pick up, open, repair, talk, phone/device idle).
The OpenBot rig only ships idle/walk/run/jump/attack. Mixamo packs are gitignored (ToS) and need an
Adobe login, so they cannot be fetched by an agent.

**Finding.** `models/quaternius/anim_lib/UAL1_Standard.glb` and `UAL2_Standard.glb` have identical bone
names and bounds. Load UAL1 for the mesh, load UAL2 only for `gltf.animations`, and register both clip
sets on one `AnimationMixer` — tracks bind by bone name, so UAL2's `Farm_Harvest`, `Chest_Open`,
`Walk_Carry_Loop`, `Idle_TalkingPhone_Loop` play on the UAL1 body.

**Pattern.** Gameplay code never names a clip. `CLIPS = { dig: 'Farm_Harvest', interact: 'Interact', … }`
in `player.js`; a Mixamo pack later is a URL + map change. Per-character instances via
`SkeletonUtils.clone()`; strip `root.position` tracks (RM variants carry root motion separately).

**Action layer.** One-shots (`LoopOnce`, `clampWhenFinished`) freeze locomotion; loops (dig, device)
don't. Run the gameplay effect at a fraction of the clip (`withAnim(name, effect, { at: 0.45 })`) so the
result lands on the gesture.
