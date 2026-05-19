# Player locomotion VRMA — license attribution

| File | License | Credit |
|------|---------|--------|
| `eli-idle.vrma` | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | Motion capture © [ACCAD](https://accad.osu.edu/research/motion-lab/mocap-system-and-data) (`Female1_bvh.zip`); converted with [bvh2vrma](https://github.com/vrm-c/bvh2vrma). Source VRMA: [GeminiVRM](https://github.com/Sunwood-ai-labs/GeminiVRM). |
| `eli-walk.vrma`, `eli-run.vrma` | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | Retargeted from [Josie Character Model](https://jenjell.itch.io/josie-character-model) by [sashii on BOOTH](https://booth.pm/en/items/7861818). |
| `eli-jump.vrma` | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | Motion capture © [ACCAD](https://accad.osu.edu/research/motion-lab/mocap-system-and-data) (`Female1_B18_WalkToLeapToWalk.bvh` in `Female1_bvh.zip`); converted with [bvh2vrma](https://github.com/vrm-c/bvh2vrma) via `bun scripts/convert-bvh-to-vrma.ts`. Playback skips the walk-in (starts at ~42% of the clip). Character faces camera forward while airborne. |

Optional lateral clips (not in the CC0 sashii pack): add `eli-strafe-left.vrma` / `eli-strafe-right.vrma` here when available; the animation controller picks them up automatically. Until then, pure A/D uses walk/run with the character facing movement direction.

In-game credits (suggested line for CC BY idle):

> Idle motion: ACCAD / Ohio State University (CC BY 3.0)
