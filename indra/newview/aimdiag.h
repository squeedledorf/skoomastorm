/**
 * @file aimdiag.h
 * @brief SkoomaStorm TEMPORARY combat-aim diagnostics sink. Remove before ship.
 *
 * A single global struct filled in across updateOrientation() (root/legs) and
 * BDMLAimMotion::onUpdate() (chest), then emitted as one rich line per frame at
 * the end of LLVOAvatar::updateCharacter() for the SELF avatar while combat-aiming.
 * All writes are gated on the self avatar, and self's updateOrientation -> feeder ->
 * updateMotions -> emit run consecutively within one updateCharacter call, so no
 * other avatar can clobber the struct between fill and emit.
 */
#ifndef LL_AIMDIAG_H
#define LL_AIMDIAG_H

#include "stdtypes.h"

struct AimDiagFrame
{
    // --- updateOrientation() : root / legs ---
    bool  combat_aiming;
    bool  turning;
    F32   speed;
    F32   primdir_yaw;        // deg, atan2(y,x) of the aim/body facing
    F32   veldir_yaw;         // deg, of the velocity direction
    F32   fwd_pre_yaw;        // deg, fwdDir before the pelvis-threshold correction
    F32   fwd_post_yaw;       // deg, fwdDir after the correction
    F32   pelvis_yaw;         // deg, current root/pelvis facing
    F32   orient_angle_deg;   // angle_between(pelvisDir, fwdDir)
    F32   pelvis_threshold_deg;
    F32   correction_mag;     // magnitude of the correction_vector applied to fwdDir
    S32   turn_flag;          // -1 = TURN_LEFT set, +1 = TURN_RIGHT set, 0 = none

    // --- BDMLAimMotion::onUpdate() : chest ---
    bool  chest_valid;
    F32   lookat_x, lookat_y, lookat_z;
    F32   lookat_pitch_deg;   // asin(z) of the normalized lookat
    F32   dev_angle_deg;      // total root-relative aim deviation
    F32   dev_axis_x, dev_axis_y, dev_axis_z;
    F32   head_max_deg;       // SSCombatAimHeadMax
    F32   chest_max_deg;      // legMax - headMax
    F32   chest_angle_deg;    // clamped chest twist actually applied this frame
};

extern AimDiagFrame gAimDiag;

// Set to the self avatar's LLCharacter* by updateOrientation() each frame, so BDMLAimMotion
// (which runs for every avatar) can tell whether it is updating the self avatar's chest.
extern const void* gAimDiagSelf;

#endif // LL_AIMDIAG_H
