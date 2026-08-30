# Art Notes / Touch-up Backlog

- **soldier_parts/arm_front.png** — has a stray line at the shoulder edge
  that doesn't mesh cleanly against the torso when assembled. Owner will
  repaint later (source: art/characters/soldier-side-parts.xcf). Rig
  proceeds with it as-is; hide the seam behind the torso overlap if
  possible when binding.

## Rig notes (soldier)

- Leg bones simplified and renamed: **Hip/FrontLeg** and **Hip/BackLeg**
  (redundant thigh leaf bones removed). Rotate those for leg animation.
- Head art has a permanently open mouth — make closed-mouth (and blink?)
  head variant PNGs; animate via Sprite2D texture keyframes, not bones.
- Idle's watch-check gesture wants an elbow joint on FrontArm — the one
  approved rig upgrade (split arm art at the elbow, add one Bone2D).
