/**
 * @file llhudeffectcombataim.cpp
 * @brief LLHUDEffectCombatAim class implementation
 *
 * SkoomaStorm combat-aim side-channel. See llhudeffectcombataim.h.
 *
 * $LicenseInfo:firstyear=2026&license=viewerlgpl$
 * $/LicenseInfo$
 */

#include "llviewerprecompiledheaders.h"

#include "llhudeffectcombataim.h"

#include "message.h"
#include "llagent.h"
#include "llviewercontrol.h"
#include "llviewerobjectlist.h"
#include "llvoavatar.h"
#include "llcriticaldamp.h"

// packet layout (TypeData)
const S32 SOURCE_AVATAR = 0;
const S32 AIM_OFFSET    = 16;
const S32 PKT_SIZE      = 28;       // 16 (source uuid) + 12 (LLVector3 aim offset)

const F32 MAX_SENDS_PER_SEC = 10.f; // aim update rate to other viewers (receiver eases between)
const F32 AIM_KILL_TIMEOUT  = 0.75f; // drop the remote pose this long after the last update
const F32 AIM_SMOOTH_HALF_LIFE = 0.12f; // receive-side easing half-life (s); higher = smoother/laggier

// defined in llvoavatar.cpp
extern const LLUUID ANIM_BD_ML_AIM_MOTION;

LLHUDEffectCombatAim::LLHUDEffectCombatAim(const U8 type)
:   LLHUDEffect(type),
    mKillTime(0.f),
    mLastSendTime(0.f),
    mLastLogTime(0.f),
    mHasSmoothed(false)
{
    mAimOffset.clear();
    mSmoothedOffset.clear();
}

LLHUDEffectCombatAim::~LLHUDEffectCombatAim()
{
}

void LLHUDEffectCombatAim::setAim(LLViewerObject* source, const LLVector3& aim_offset)
{
    setSourceObject(source);
    mAimOffset = aim_offset;
    F32 now = mTimer.getElapsedTimeF32();
    if (now - mLastSendTime > (1.f / MAX_SENDS_PER_SEC))
    {
        setNeedsSendToSim(true);
    }
}

void LLHUDEffectCombatAim::packData(LLMessageSystem *mesgsys)
{
    LLViewerObject* source = (LLViewerObject*)mSourceObject;
    if (!source || !source->isAvatar())
    {
        markDead();
        return;
    }

    LLHUDEffect::packData(mesgsys);

    U8 packed_data[PKT_SIZE];
    memset(packed_data, 0, PKT_SIZE);
    htolememcpy(&(packed_data[SOURCE_AVATAR]), source->mID.mData, MVT_LLUUID, 16);
    htolememcpy(&(packed_data[AIM_OFFSET]), mAimOffset.mV, MVT_LLVector3, 12);
    mesgsys->addBinaryDataFast(_PREHASH_TypeData, packed_data, PKT_SIZE);

    mLastSendTime = mTimer.getElapsedTimeF32();
}

void LLHUDEffectCombatAim::unpackData(LLMessageSystem *mesgsys, S32 blocknum)
{
    // processViewerEffect() matched this effect by ID; if it originated here it is our own
    // outgoing effect echoed back by the sim, so ignore it (we drive our own pose locally).
    if (getOriginatedHere())
    {
        return;
    }

    LLHUDEffect::unpackData(mesgsys, blocknum);

    S32 size = mesgsys->getSizeFast(_PREHASH_Effect, blocknum, _PREHASH_TypeData);
    if (size != PKT_SIZE)
    {
        LL_WARNS("CombatAim") << "Combat-aim effect with bad size " << size << LL_ENDL;
        return;
    }

    U8 packed_data[PKT_SIZE];
    mesgsys->getBinaryDataFast(_PREHASH_Effect, _PREHASH_TypeData, packed_data, PKT_SIZE, blocknum);

    LLUUID source_id;
    htolememcpy(source_id.mData, &(packed_data[SOURCE_AVATAR]), MVT_LLUUID, 16);
    htolememcpy(mAimOffset.mV, &(packed_data[AIM_OFFSET]), MVT_LLVector3, 12);

    LLViewerObject* objp = gObjectList.findObject(source_id);
    if (objp && objp->isAvatar())
    {
        setSourceObject(objp);
    }
    else
    {
        return;
    }
    mKillTime = mTimer.getElapsedTimeF32() + AIM_KILL_TIMEOUT;
}

void LLHUDEffectCombatAim::update()
{
    if (mSourceObject.isNull() || mSourceObject->isDead())
    {
        markDead();
        return;
    }

    // Our own outgoing effect: the local avatar's pose is driven directly in
    // LLVOAvatar::updateCharacter(); nothing to render locally for it here.
    if (getOriginatedHere())
    {
        return;
    }

    LLViewerObject* source = (LLViewerObject*)mSourceObject;
    if (!source->isAvatar())
    {
        markDead();
        return;
    }
    LLVOAvatar* avatar = (LLVOAvatar*)source;

    // Never double-drive our own avatar (the feeder already does); guards against sim echo.
    if (avatar->isSelf())
    {
        return;
    }

    static LLCachedControl<bool> body_aim(gSavedSettings, "SSCombatBodyAim", true);
    F32 now = mTimer.getElapsedTimeF32();

    if (!body_aim || now > mKillTime)
    {
        avatar->removeAnimationData("LookAtPoint");
        if (avatar->isMotionActive(ANIM_BD_ML_AIM_MOTION))
        {
            avatar->stopMotion(ANIM_BD_ML_AIM_MOTION);
        }
        if (now > mKillTime)
        {
            markDead();
        }
        return;
    }

    // Drive this remote avatar's head + chest aim from the transmitted direction. The samples
    // arrive in discrete steps (MAX_SENDS_PER_SEC), so ease a smoothed offset toward the latest
    // each frame; without this the remote pose snaps between samples and looks jerky.
    // setAnimationData stores the pointer; mSmoothedOffset is a member so it stays valid, and the
    // avatar's head-rot + BDMLAimMotion both read "LookAtPoint" during updateMotions this frame.
    F32 interp = LLSmoothInterpolation::getInterpolant(AIM_SMOOTH_HALF_LIFE);
    if (!mHasSmoothed)
    {
        mSmoothedOffset = mAimOffset;
        mHasSmoothed = true;
    }
    else
    {
        mSmoothedOffset = lerp(mSmoothedOffset, mAimOffset, interp);
    }
    avatar->setAnimationData("LookAtPoint", &mSmoothedOffset);
    if (!avatar->isMotionActive(ANIM_BD_ML_AIM_MOTION))
    {
        avatar->startMotion(ANIM_BD_ML_AIM_MOTION);
    }

    // Diagnostic (silent unless the "CombatAim" debug tag is enabled): sim relay confirmed working.
    if (now - mLastLogTime > 3.f)
    {
        mLastLogTime = now;
        LL_DEBUGS("CombatAim") << "Received combat-aim from " << source->getID()
                               << " dir " << mAimOffset << LL_ENDL;
    }
}
