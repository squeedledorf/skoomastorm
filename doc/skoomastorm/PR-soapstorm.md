# OTS / aim-convergence / combat: fixes and updates, plus ADS and a few new tools

This is mostly **fixes and refinements to soapstorm's existing systems** — the
over-the-shoulder (OTS) camera, aim convergence, and the Combat 2.0 HUD — with a smaller
set of **genuinely new** additions layered on top. Everything new is opt-in and off by
default; with the new toggles off the viewer behaves as it does today.

30 commits, 53 files, ~+2150 / −340 lines. Built and play-tested on Windows (VS2022,
ReleaseFS_open).

---

## Fixes & updates to existing systems

### OTS camera
- **Camera collision ignores phantom prims.** Phantom objects have no physics, so the
  shoulder camera now re-casts past them instead of pinching in on a phantom wall.
- **Strafe-into-ADS no longer yaws the avatar.** During the OTS→mouselook transition
  `mLastCameraMode` is still OTS, so `cameraMouselook()` briefly reported third-person;
  `getMode()` then returned third-person and held movement keys flipped from slide to
  turn (keys.xml: `first_person`=slide vs `third_person`=turn). Treating the
  OTS→mouselook transition as first-person input fixes it.
- **No camera lag when turning during a mode swap.** The camera-mode animation re-anchors
  its start to the avatar's current frame each step, so turning/strafing mid-glide no
  longer leaves the view pinned to a stale world direction.

### Aim convergence
- **Converge on the avatar hitbox, not the render position.** Avatars now converge on the
  oriented hitbox an `llCastRay` weapon actually hits (object position / scale / region
  rotation) via a new `rayOBBIntersect`, instead of the smoothly-rendered mesh that leads
  the hitbox during fast movement. (Replaces the earlier capsule-proxy approach.)
- **Stop snapping to avatars behind the player** — a hitbox hit must be at least as far as
  the eye along the aim, and the world-depth ray no longer tests avatars/attachments at
  all (it uses the static-geometry cast, so a bystander's mesh can't steal convergence).
- **Phantom prims are skipped** in the convergence world ray too.
- Min-distance lean guard and along-the-ray depth smoothing to keep close-range and
  rough-geometry aim from swinging/snapping.

### Combat 2.0 HUD
- Kill-feed: own-name / other-name coloring, color UI polish, de-duplicated Combat prefs.
- Hitmarker: agent-only target filter, collision-damage filter, hit-sound gain slider,
  and sound test buttons.

### Mouselook / login / preferences
- Mouselook-zoom: zoomed sensitivity and zoom-transition tuning.
- Preferences cleanup: Soapstorm tab split into **Combat** and **Login Options**, ADS/OTS
  collapsed to an enable checkbox + **Options…** floater, plus terminology renames
  (fair-fire → convergence, true-aim → line-of-sight/LOS dot).

---

## New additions

### Aim down sights (ADS)
**Double-tap-and-hold right-click** to aim down sights; release to exit. From OTS it dives
into first-person mouselook for the duration and pops back on release; in first person it
just zooms. Independent of the normal hold-zoom: configurable double-tap window, FOV,
zoom-transition and swap timing, and separate zoom and mouse sensitivity. A radial
post-process vignette (in the existing vignette shader) creeps in with the zoom —
falloff-power darkness, per-mode toggles, eases out on its own clock so a normal zoom
interrupting the release can't snap it off. Includes the cleanup so the ADS zoom and
vignette can't get stuck when leaving mouselook while aimed.
*Settings: `FSDoubleTapADS`, `FSADSZoomFOV`, `FSADSZoomTransitionSpeed`,
`FSADSSwapTransitionSpeed`, `FSADSDoubleTapTime`, `FSADSZoomSensitivity`,
`FSADSMouseSensitivity`, `FSADSVignette*`.*

### Phantom-object pass-through
A `skip_phantom` option on the world-geometry raycast that re-casts past phantom prims, so
the OTS camera collision and the aim-convergence ray treat phantom objects as the
non-colliding things they are. Default off; unrelated callers (mouselook IFF
line-of-sight) are unchanged.

### Sound → Notecard bulk upload
A **Upload to Notecard…** action that bulk-uploads WAV files and writes the music-player
notecard automatically: first line is the modal clip length (seconds, one decimal),
following lines are the sound asset UUIDs in upload order, placed in a new subfolder in
the Sounds folder named from the shared filename prefix. The generated notecard does not
auto-open.

### Login Options tab
The login-screen settings (offline splash + custom background/logo, optional-update
toggle) move into a dedicated **Login Options** sub-tab as part of the prefs reorg above.

---

## Notes for review
- The new features default off / to prior behavior; the only always-on changes are
  bug-class fixes (and `skip_phantom` is opt-in per call site).
- New settings are namespaced (`FSADS*`, and the hitbox-convergence `FSOTSAvatarConverge`
  / `FSOTSConvergeMinDistance` / `FSOTSConvergeSmoothingHalfLife`).
- Happy to split this into smaller PRs (e.g. convergence/camera fixes vs. ADS vs. the
  upload tool) if that's easier to review.
