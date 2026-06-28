# SkoomaStorm Combat-Aim Movement & Camera

A SkoomaStorm-only combat-aiming system: while aiming (OTS / mouselook), the avatar's
head, torso (chest), and legs articulate toward the aim in a natural cascade, the aim is
broadcast to other SkoomaStorm viewers (no leaky lookat crosshair), and the over-the-shoulder
combat camera is stabilized at the vertical pole.

All behavior is gated on combat-aim being active, so non-combat locomotion is byte-for-byte
stock. Everything is tunable live via Debug Settings (the `SSCombatAim*` keys below).

## Dynamic vs Legacy (master toggle)

`SSCombatBodyAim` is the user-facing **Dynamic Movement** toggle (Preferences > Soapstorm > Combat >
Movement). On = the dynamic cascade below; off = stock **Legacy** locomotion (the whole feature is
gated on it, so Legacy is byte-for-byte stock). It ships **default OFF** (opt-in) because the feature
is in development. Enabling it shows a one-time warning ("at your own risk", OK + don't-show-again):
notification `SSDynamicMovementWarning` (notifications.xml), fired by `handleCombatBodyAimChanged`
in `llviewercontrol.cpp` when the control flips true after login. The OTS camera pole fixes are NOT
gated on this (always on in OTS, since they're pure improvements).

## How it engages

`LLVOAvatar::updateCharacter()` feeder (self only): when `SSCombatBodyAim` is on AND the camera
is OTS or mouselook (`cameraOTS() || cameraMouselook()`), the avatar is "combat-aiming":
- Feeds `"LookAtPoint"` = camera at-axis each frame (drives head + chest).
- Starts `ANIM_BD_ML_AIM_MOTION` (BDMLAimMotion, the procedural chest motion).
- Publishes the head/torso cap as anim-data `"CombatHeadLeadMaxRad"`.
- Broadcasts the aim to other SkoomaStorm viewers via the custom `LL_HUD_EFFECT_COMBAT_AIM`
  ViewerEffect (`llhudeffectcombataim.{h,cpp}`); stock viewers ignore the unknown effect type.
- The real lookat is suppressed in combat (`llhudeffectlookat.cpp`) so no crosshair leaks.

`combat_aiming` in `updateOrientation()` = `isMotionActive(ANIM_BD_ML_AIM_MOTION)` — true for the
local avatar while aiming AND for remote avatars driven by the side-channel.

## The cascade (head -> torso -> legs)

The aim deviation from the body is absorbed in order so the parts saturate sequentially:

1. **Head** (`LLHeadRotMotion`, indra/llcharacter/llheadrotmotion.cpp): points at the lookat.
   While combat-aiming it is additionally constrained to within `SSCombatAimHeadTorsoMax` of the
   **chest** (not just the root), so the head stays glued to the torso instead of pinning at its
   root limit and riding the body when the legs lag far from the aim.
2. **Chest/torso** (`BDMLAimMotion`, indra/newview/bdmlaimmotion.cpp): twists toward the aim as
   the OVERFLOW past the head's lead (`SSCombatAimHeadMax`), up to `legMax - headMax`. Eased by
   `SSCombatAimChestSmoothHalfLife`. The chest aim PITCH is clamped (`SSCombatAimChestMaxPitch`)
   and the twist fades to its last stable value as the aim nears vertical, so the torso does not
   roll/contort when looking straight up/down.
3. **Legs/root** (`LLVOAvatar::updateOrientation()`): held within a cone
   (`SSCombatAimLegMaxDeviation`) while the torso/head turn; past the cone the legs turn.

### Lower-body facing while moving (the "lock")

When `SSCombatAimLockFacing` is on, the legs face the aim (`primDir`) instead of spinning to face
the travel direction, so moving backward keeps you facing the target (back-pedal reads). The legs
**lean** toward a strafe by up to `SSCombatAimStrafeLean`, scaled by the lateral velocity and a
hysteresis forward/back latch (so a pure sideways strafe holds a stable lean, no jitter), eased by
`SSCombatAimLeanSmoothHalfLife`. The lean inverts when moving backward.

### Turn-in-place

When standing (speed < 0.5) and the aim exceeds the leg cone, the legs commit to ONE smooth,
decisive sweep toward the aim (decelerating), settling `SSCombatAimTurnSettle` degrees behind the
aim. Wide hysteresis (enter at the cone, release just above the settle angle) prevents chatter;
settle is clamped to `[4, cone-8]` so it can never close the band or stick. While MOVING the legs
keep tracking the lean/movement instead (the leg-keepup below applies only when moving).

NOTE: SL's `ANIM_AGENT_TURNLEFT/RIGHT` are walk-based keyframe motions that TRANSLATE the avatar at
zero control-speed, which drifted the avatar and cascaded into the walk anim. So we do NOT trigger
a turn animation; the decisive leg sweep stands in for it. True foot-stepping (vs the feet
pivoting) without drift would need a non-translating turn anim / AO hook — not yet done.

### Violent-turn leg-keepup (moving only)

While MOVING, the leg cone shrinks with camera angular speed so the legs follow a fast camera whip
instead of pinning at the hold limit. Disabled when standing so it cannot crush the turn-in-place
settle band.

## OTS combat camera (indra/newview/llagentcamera.cpp)

The over-the-shoulder camera derives its frame from the agent look direction. Two fixes for the
vertical pole (looking straight up/down):

- `ots_stable_frame()` builds the camera frame with the **heading taken from the agent LEFT axis**
  (stays horizontal through the pole AND follows mouse-yaw even at straight-down), the pitch from
  the at-axis, and zero roll. Deriving heading from the at-axis instead gimbal-locks: it spins when
  held and stops following yaw when turning.
- Near vertical, the focus eases to sit straight ahead of the camera along the aim
  (`calcFocusPositionTargetGlobal`), so the look stops swinging from the shoulder-offset geometry
  (forward shrinks, side/height offsets take over the azimuth). The camera POSITION keeps its full
  offset (no pull-in toward the avatar).

## Settings reference (all live-tunable; defaults in app_settings/settings.xml)

| Key | Default | Meaning |
|-----|---------|---------|
| `SSCombatBodyAim` | 1 (on) | Master toggle for combat body aim. |
| `SSCombatAimLegMaxDeviation` | 85 | Leg hold cone (deg). Legs hold this far from the aim before turning; also the top of the chest-twist budget. |
| `SSCombatAimHeadMax` | 5 | Degrees the head leads before the chest begins to twist. Small = torso follows strongly; large = torso freezes. Must be < LegMaxDeviation. |
| `SSCombatAimHeadTorsoMax` | 35 | Max degrees the head may lead the chest/torso. Lower = head glued to torso. |
| `SSCombatAimChestSmoothHalfLife` | 0.025 | Half-life (s) easing the chest twist. Higher = smoother/slower. |
| `SSCombatAimChestMaxPitch` | 55 | Max chest pitch toward the aim (deg). Clamps the torso away from vertical so it does not contort looking up/down. |
| `SSCombatAimStrafeLean` | 85 | Max degrees the legs lean toward a strafe. Inverts when moving backward. |
| `SSCombatAimLeanSmoothHalfLife` | 0.025 | Half-life (s) easing the strafe lean. |
| `SSCombatAimLockFacing` | 1 (on) | Lock the lower body to the aim instead of spinning to face travel direction. |
| `SSCombatAimTurnSettle` | 8 | Standing turn-in-place: how far behind the aim the legs settle. Lower = bigger turn (legs face the aim); higher = smaller nudge. Clamped to [4, cone-8]. |

Pre-existing OTS camera knobs (not part of this feature, but relevant): `OTSCameraDistance`,
`OTSCameraSide`, `OTSCameraHeight`, `OTSFocusDistance`, `OTSCameraCollision`.

## Files

- `indra/newview/llvoavatar.{cpp,h}` — feeder, `updateOrientation()` cascade/lock/lean/turn-in-place,
  side-channel hookup, motion registration, **temporary diagnostics** (see below).
- `indra/newview/bdmlaimmotion.{cpp,h}` — chest procedural motion: staging, pitch clamp, vertical fade.
- `indra/llcharacter/llheadrotmotion.cpp` — head-vs-chest cap (gated on combat anim-data).
- `indra/newview/llhudeffectcombataim.{cpp,h}` — custom combat-aim side-channel ViewerEffect.
- `indra/newview/llhudobject.{cpp,h}` — registers the custom effect type.
- `indra/newview/llhudeffectlookat.cpp` — suppresses the real lookat in combat.
- `indra/newview/llagentcamera.{cpp,h}` — OTS camera pole stabilization.
- `indra/newview/app_settings/settings.xml` — the `SSCombatAim*` settings.

## Temporary diagnostics (REMOVE before ship)

`indra/newview/aimdiag.h` + the `gAimDiag`/`gAimDiagSelf` globals and capture blocks in
`updateOrientation()`/`BDMLAimMotion::onUpdate()` emit one rich `LL_INFOS("AimDiag")` line per ~2
frames for the self avatar while fully loaded. Parsed during tuning; logs to Firestorm.log. To
ship: delete aimdiag.h, the `gAimDiag*` definitions, the `if (isSelf()) { gAimDiag... }` capture
blocks, the chest-capture block in bdmlaimmotion.cpp, and the `LL_INFOS("AimDiag")` emit block at
the end of `updateCharacter()`.

## Build

AVX2+FMOD `build-vc171-64` per the `skoomastorm-build` skill. After editing, CLOSE the running
viewer first (it locks firestorm-bin.exe and blocks the relink), then verify the exe mtime advanced.

## Open / further tweaks

- Turn-in-place: true foot-stepping (non-translating turn anim) instead of the feet pivoting.
- Tuning pass on `SSCombatAimTurnSettle` feel (smaller-vs-slower turn; a turn-rate knob could be added).
- Port the cap to remote avatars' head (side-channel only sends LookAtPoint today).
