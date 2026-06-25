/**
 * @file llhudeffectcombataim.h
 * @brief LLHUDEffectCombatAim class definition
 *
 * SkoomaStorm: a custom ViewerEffect type that carries an avatar's combat aim direction to
 * other SkoomaStorm viewers, in place of the standard LookAt effect. Stock/other viewers that
 * don't recognize this type ignore it (LLHUDObject::addHUDEffect returns NULL), so no aim
 * crosshair ever leaks. Receiving SkoomaStorm viewers decode it and drive the source avatar's
 * head + chest aim pose via its "LookAtPoint" anim-data, so aim reads as natural body language.
 *
 * $LicenseInfo:firstyear=2026&license=viewerlgpl$
 * $/LicenseInfo$
 */

#ifndef LL_LLHUDEFFECTCOMBATAIM_H
#define LL_LLHUDEFFECTCOMBATAIM_H

#include "llhudeffect.h"

class LLViewerObject;

class LLHUDEffectCombatAim : public LLHUDEffect
{
public:
    friend class LLHUDObject;

    // Send side: refresh the local agent avatar's aim each frame (throttles its own sim send).
    void setAim(LLViewerObject* source, const LLVector3& aim_offset);

protected:
    LLHUDEffectCombatAim(const U8 type);
    ~LLHUDEffectCombatAim();

    /*virtual*/ void update();
    /*virtual*/ void render() {}            // no on-screen draw; the avatar pose IS the visual
    /*virtual*/ void packData(LLMessageSystem *mesgsys);
    /*virtual*/ void unpackData(LLMessageSystem *mesgsys, S32 blocknum);

private:
    LLVector3       mAimOffset;     // world-space aim direction, scaled, as an offset from the avatar
    F32             mKillTime;      // received side: stop posing if no fresh update arrives
    F32             mLastSendTime;  // send side: throttle
    F32             mLastLogTime;   // throttle for the transport-verification log
    LLVector3       mSmoothedOffset; // receive-side eased aim, smooths the discrete update rate
    bool            mHasSmoothed;    // false until the first received sample seeds mSmoothedOffset
    LLFrameTimer    mTimer;
};

#endif // LL_LLHUDEFFECTCOMBATAIM_H
