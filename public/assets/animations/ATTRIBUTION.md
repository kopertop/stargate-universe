# Player locomotion VRMA — license attribution

| File | License | Credit |
|------|---------|--------|
| `female-idle.vrma` | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | Motion capture © [ACCAD](https://accad.osu.edu/research/motion-lab/mocap-system-and-data) (`Female1_bvh.zip`); converted with [bvh2vrma](https://github.com/vrm-c/bvh2vrma). Source VRMA: [GeminiVRM `accad_female1_wait.vrma`](https://github.com/Sunwood-ai-labs/GeminiVRM). Shared idle for female crew VRMs. |
| `eli-idle.vrma` | MIT (sample) | `Relax.vrma` from [tk256ailab/vrm-viewer](https://github.com/tk256ailab/vrm-viewer). Default idle for male crew / player fallback. |
| `eli-walk.vrma`, `eli-run.vrma` | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | Native VRMA from [sashii CC0 pack](https://booth.pm/en/items/7861818) (Josie Character Model). Same bytes as `cc0-locomotion/CC0-walk.vrma` / `CC0-run.vrma`. |
| `cc0-locomotion/*.vrma` | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | [CC0-animation-retarget-vrm](https://booth.pm/en/items/7861818) — Walk, Run, SlowRun retargeted from [Josie Character Model](https://jenjell.itch.io/josie-character-model). |
| `vroid-motion-pack/vrma/*.vrma` (7 clips) | VRoid Project terms | Free pack from [VRoid Project on BOOTH](https://booth.pm/en/items/5512385). Credit: *Animation credits to pixiv Inc.'s VRoid Project* (commercial use). |
| `eli-jump.vrma` | MIT | `Jump.vrma` from [tk256ailab/vrm-viewer](https://github.com/tk256ailab/vrm-viewer). Played at 1.35×; mesh faces movement direction at takeoff for the full jump. |
| `tk256-emotes/*.vrma` (11 clips) | MIT (sample) | Emotion/action samples from [tk256ailab/vrm-viewer](https://github.com/tk256ailab/vrm-viewer). |

**Lateral movement (A/D):** no dedicated strafe clips — controller blends walk/run while the character faces movement direction.

**Adding more native clips:** prefer authoring or downloading `.vrma` directly (Blender VRM Add-on export). Avoid batch BVH→VRMA conversion for VRoid characters — retarget quality is poor except official bvh2vrma outputs like `female-idle`.

In-game credits (suggested):

> Idle (female): ACCAD / Ohio State University (CC BY 3.0) · Locomotion: sashii (CC0) · Emotes: tk256ailab/vrm-viewer (MIT) · VRoid motions: pixiv Inc. VRoid Project
