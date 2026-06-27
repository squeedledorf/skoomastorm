/**
 * @file bdmlaimmotion.cpp
 * @brief Implementation of BDMLAimMotion class.
 *
 * $LicenseInfo:firstyear=2001&license=viewerlgpl$
 * Second Life Viewer Source Code
 * Copyright (C) 2010, Linden Research, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation;
 * version 2.1 of the License only.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 *
 * Linden Research, Inc., 945 Battery Street, San Francisco, CA  94111  USA
 * $/LicenseInfo$
 */

//-----------------------------------------------------------------------------
// Header Files
//-----------------------------------------------------------------------------
#include "linden_common.h"

#include "bdmlaimmotion.h"
#include "llcharacter.h"
#include "llrand.h"
#include "m3math.h"
#include "v3dmath.h"
#include "llcriticaldamp.h"

//BD
#include "llviewercontrol.h"
#include "llviewercamera.h"
#include "llagentcamera.h"
#include "llagent.h"
#include "aimdiag.h" // SkoomaStorm temporary combat-aim diagnostics

//-----------------------------------------------------------------------------
// Constants
//-----------------------------------------------------------------------------
const F32 MIN_HEAD_LOOKAT_DISTANCE = 0.1f;	// minimum distance from head before we turn to look at it
// SkoomaStorm: TORSO_LAG / TORSO_LOOKAT_LAG_HALF_LIFE removed; the chest now stages off the
// SSCombatAim* settings and eases via SSCombatAimChestSmoothHalfLife (see onUpdate).

//-----------------------------------------------------------------------------
// BDMLAimMotion()
// Class Constructor
//-----------------------------------------------------------------------------
BDMLAimMotion::BDMLAimMotion(const LLUUID &id) :
	LLMotion(id),
	mCharacter(nullptr),
	mTorsoJoint(nullptr),
	mChestJoint(nullptr),
    mPelvisJoint(nullptr),
    mRootJoint(nullptr)
{
	mName = "ml_aim";

	mTorsoState = new LLJointState;
	mChestState = new LLJointState;

	mHeadConstrains = (S32)gSavedSettings.getF32("YawFromMousePosition");

}


//-----------------------------------------------------------------------------
// ~BDMLAimMotion()
// Class Destructor
//-----------------------------------------------------------------------------
BDMLAimMotion::~BDMLAimMotion()
{
}

//-----------------------------------------------------------------------------
// BDMLAimMotion::onInitialize(LLCharacter *character)
//-----------------------------------------------------------------------------
LLMotion::LLMotionInitStatus BDMLAimMotion::onInitialize(LLCharacter *character)
{
	if (!character)
		return STATUS_FAILURE;
	mCharacter = character;

	mPelvisJoint = character->getJoint("mPelvis");
	if ( ! mPelvisJoint )
	{
		LL_INFOS() << getName() << ": Can't get pelvis joint." << LL_ENDL;
		return STATUS_FAILURE;
	}

	mRootJoint = character->getJoint("mRoot");
	if ( ! mRootJoint )
	{
		LL_INFOS() << getName() << ": Can't get root joint." << LL_ENDL;
		return STATUS_FAILURE;
	}

	mTorsoJoint = character->getJoint("mTorso");
	if ( ! mTorsoJoint )
	{
		LL_INFOS() << getName() << ": Can't get torso joint." << LL_ENDL;
		return STATUS_FAILURE;
	}

	mChestJoint = character->getJoint("mChest");
	if (!mChestJoint)
	{
		LL_INFOS() << getName() << ": Can't get torso joint." << LL_ENDL;
		return STATUS_FAILURE;
	}

	mTorsoState->setJoint( character->getJoint("mTorso") );
	if ( ! mTorsoState->getJoint() )
	{
		LL_INFOS() << getName() << ": Can't get torso joint." << LL_ENDL;
		return STATUS_FAILURE;
	}

	mChestState->setJoint(character->getJoint("mChest"));
	if (!mChestState->getJoint())
	{
		LL_INFOS() << getName() << ": Can't get torso joint." << LL_ENDL;
		return STATUS_FAILURE;
	}

	mTorsoState->setUsage(LLJointState::ROT);
	mChestState->setUsage(LLJointState::ROT);

	addJointState( mTorsoState );
	addJointState( mChestState );

	mLastHeadRot.loadIdentity();

	return STATUS_SUCCESS;
}


//-----------------------------------------------------------------------------
// BDMLAimMotion::onActivate()
//-----------------------------------------------------------------------------
bool BDMLAimMotion::onActivate()
{
	return true;
}


//-----------------------------------------------------------------------------
// BDMLAimMotion::onUpdate()
//-----------------------------------------------------------------------------
bool BDMLAimMotion::onUpdate(F32 time, U8* joint_mask)
{
    LL_PROFILE_ZONE_SCOPED_CATEGORY_AVATAR;
	LLQuaternion	targetHeadRotWorld;
	LLQuaternion	currentRootRotWorld = mPelvisJoint->getWorldRotation();
	LLQuaternion	currentInvRootRotWorld = ~currentRootRotWorld;

	// SkoomaStorm: chest ease half-life is live-tunable (was a hardcoded 0.015 that settled in ~1
	// frame and read as a pop). Default 0.12 matches the receive-side aim smoothing.
	static LLCachedControl<F32> s_chest_smooth_hl(gSavedSettings, "SSCombatAimChestSmoothHalfLife", 0.025f);
	F32 head_slerp_amt = LLSmoothInterpolation::getInterpolant(llmax(0.001f, (F32)s_chest_smooth_hl));

	LLVector3* targetPos = (LLVector3*)mCharacter->getAnimationData("LookAtPoint");

	// SkoomaStorm: original aim verticality (sin of pitch; +/-1 = straight up/down) BEFORE the pitch
	// clamp below, used to fade the chest twist out near vertical so the torso does not roll/contort.
	F32 orig_aim_vert = 0.f;

	if (targetPos)
	{
		LLVector3 headLookAt = *targetPos;

		F32 lookatDistance = headLookAt.normVec();
		orig_aim_vert = headLookAt.mV[VZ];

		if (lookatDistance < MIN_HEAD_LOOKAT_DISTANCE)
		{
			targetHeadRotWorld = mPelvisJoint->getWorldRotation();
		}
		else
		{
			// SkoomaStorm: clamp the CHEST aim pitch away from vertical. Near straight up/down the
			// up x aim basis below degenerates (left -> 0), which flips the rotation axis and rolls
			// the torso ~50 deg (the up/down contortion). Clamping the vertical component keeps the
			// basis well-conditioned; the head and camera still pitch fully. The chest does not need
			// to bend past this anyway. Tunable: SSCombatAimChestMaxPitch (deg).
			static LLCachedControl<F32> s_chest_max_pitch(gSavedSettings, "SSCombatAimChestMaxPitch", 55.f);
			F32 max_z = sinf((F32)s_chest_max_pitch * DEG_TO_RAD);
			if (headLookAt.mV[VZ] > max_z || headLookAt.mV[VZ] < -max_z)
			{
				F32 z = llclamp(headLookAt.mV[VZ], -max_z, max_z);
				F32 new_horiz = sqrtf(llmax(0.f, 1.f - z * z));
				F32 old_horiz = sqrtf(headLookAt.mV[VX] * headLookAt.mV[VX] + headLookAt.mV[VY] * headLookAt.mV[VY]);
				if (old_horiz > 1e-4f)
				{
					F32 s = new_horiz / old_horiz;
					headLookAt.mV[VX] *= s;
					headLookAt.mV[VY] *= s;
				}
				headLookAt.mV[VZ] = z;
			}

			LLVector3 root_up = LLVector3(0.f, 0.f, 1.f);
			LLVector3 left(root_up % headLookAt);
			// if look_at has zero length, fail
			// if look_at and skyward are parallel, fail
			//
			// Test both of these conditions with a cross product.

			if (left.magVecSquared() < 0.05f)
			{
				LLVector3 root_at = LLVector3(1.f, 0.f, 0.f);
				root_at.mV[VZ] = 0.f;
				root_at.normVec();

				headLookAt = lerp(headLookAt, root_at, 0.1f);
				headLookAt.normVec();

				left = root_up % headLookAt;
			}

			// Make sure look_at and skyward and not parallel
			// and neither are zero length
			LLVector3 up(headLookAt % left);

			if (gAgentCamera.cameraMouselook())
			{
				//BD - For first person (your own avatar only)
				targetHeadRotWorld = LLQuaternion(headLookAt, left, up); // SkoomaStorm: always world-up basis (correct for remote avatars + fixes OTS freeze)



			}
			else
			{
				//BD - For third person and for other avatars.
				targetHeadRotWorld = LLQuaternion(headLookAt, left, up);
			}

		}
	}
	else
	{
		targetHeadRotWorld = currentRootRotWorld;
	}

	// head_rot_local is the FULL aim rotation expressed relative to the avatar root (pelvis). Its
	// angle is the total head-vs-root deviation, the same quantity the head motion and the root cone
	// (updateOrientation) work in. SkoomaStorm cascade: the head owns the first SSCombatAimHeadMax
	// degrees; the chest takes ONLY the overflow past that, capped so it runs out exactly at the
	// leg-hold cone (SSCombatAimLegMaxDeviation), past which the legs turn. The chest twists about
	// the SAME aim axis, so direction is preserved with no Euler/convention risk. This staging is
	// what makes head -> torso -> legs saturate in order instead of all consuming the aim at once.
	LLQuaternion head_rot_local = targetHeadRotWorld * currentInvRootRotWorld;

	static LLCachedControl<F32> s_aim_head_max(gSavedSettings, "SSCombatAimHeadMax", 5.f);
	static LLCachedControl<F32> s_aim_leg_max(gSavedSettings, "SSCombatAimLegMaxDeviation", 85.f);
	F32 head_max_rad  = (F32)s_aim_head_max * DEG_TO_RAD;
	F32 chest_max_rad = llmax(0.f, ((F32)s_aim_leg_max - (F32)s_aim_head_max)) * DEG_TO_RAD;

	F32 dev_angle;
	LLVector3 dev_axis;
	head_rot_local.getAngleAxis(&dev_angle, dev_axis);

	LLQuaternion fresh_chest; // freshly-computed twist from the current aim (identity until head budget spent)
	F32 chest_angle_dbg = 0.f; // SkoomaStorm diag
	if (dev_angle > 1e-4f && dev_axis.magVecSquared() > 1e-6f)
	{
		F32 chest_angle = llclamp(dev_angle - head_max_rad, 0.f, chest_max_rad);
		chest_angle_dbg = chest_angle;
		if (chest_angle > 1e-4f)
		{
			dev_axis.normVec();
			fresh_chest.setAngleAxis(chest_angle, dev_axis);
		}
	}

	// SkoomaStorm diag (self only): record the chest staging inputs/outputs for this frame.
	if ((const void*)mCharacter == gAimDiagSelf)
	{
		gAimDiag.chest_valid = true;
		LLVector3 la = targetPos ? *targetPos : LLVector3::zero;
		F32 lam = la.normVec();
		gAimDiag.lookat_x = la.mV[0]; gAimDiag.lookat_y = la.mV[1]; gAimDiag.lookat_z = la.mV[2];
		gAimDiag.lookat_pitch_deg = (lam > 0.f) ? asinf(llclamp(la.mV[2], -1.f, 1.f)) * RAD_TO_DEG : 0.f;
		gAimDiag.dev_angle_deg = dev_angle * RAD_TO_DEG;
		gAimDiag.dev_axis_x = dev_axis.mV[0]; gAimDiag.dev_axis_y = dev_axis.mV[1]; gAimDiag.dev_axis_z = dev_axis.mV[2];
		gAimDiag.head_max_deg = (F32)s_aim_head_max;
		gAimDiag.chest_max_deg = chest_max_rad * RAD_TO_DEG;
		gAimDiag.chest_angle_deg = chest_angle_dbg * RAD_TO_DEG;
	}

	// Near vertical the aim axis is unstable and twisting about it ROLLS the torso (the up/down
	// contortion). Blend the target from the fresh twist (horizontal aim) toward the last stable
	// twist as the aim goes vertical, so the torso KEEPS its aim twist when you look straight down
	// instead of straightening or rolling. vfade: 1 when aim is shallow, 0 when near vertical.
	F32 vfade = clamp_rescale(fabsf(orig_aim_vert), 0.80f, 0.97f, 1.f, 0.f);
	LLQuaternion chest_target = nlerp(vfade, mLastHeadRot, fresh_chest);
	// Time-smooth so the head->torso handoff settles instead of popping.
	LLQuaternion chest_local = nlerp(head_slerp_amt, mLastHeadRot, chest_target);
	mLastHeadRot = chest_local;

	if (mChestState->getJoint())
	{
		mChestState->setRotation(chest_local);
	}

	return true;
}


//-----------------------------------------------------------------------------
// BDMLAimMotion::onDeactivate()
//-----------------------------------------------------------------------------
void BDMLAimMotion::onDeactivate()
{
}

// End
