/**
 * @file ssglmcompat.h
 * @brief LL's glm matrix helpers, re-expressed on Alchemy's per-pass camera
 *
 * $LicenseInfo:firstyear=2026&license=viewerlgpl$
 * Phoenix Firestorm Viewer Source Code
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
 * $/LicenseInfo$
 */

#ifndef SS_GLMCOMPAT_H
#define SS_GLMCOMPAT_H

// LL kept the frame's view and projection in glm globals (gGLModelView and friends) that each pass
// overwrote with set_current_*. Alchemy keeps them on the camera the pass renders with,
// LLViewerCamera::getCurrent(), which a pass swaps in and restores the same way. LLMatrix4a is laid
// out column-major like glm::mat4, so these are straight copies. Code written against the old
// helpers keeps its meaning; new code should use the camera directly.

#include "llviewercamera.h"
#include "glm/mat4x4.hpp"
#include "glm/gtc/type_ptr.hpp"

inline glm::mat4 ss_to_glm(const LLMatrix4a& m) { return glm::make_mat4(m.getF32ptr()); }

inline LLMatrix4a ss_from_glm(const glm::mat4& m)
{
    LLMatrix4a out;
    out.loadu(glm::value_ptr(m));
    return out;
}

inline glm::mat4 get_current_modelview()  { return ss_to_glm(LLViewerCamera::getCurrent().getModelview()); }
inline glm::mat4 get_current_projection() { return ss_to_glm(LLViewerCamera::getCurrent().getProjection()); }
inline glm::mat4 get_last_modelview()     { return ss_to_glm(LLViewerCamera::getInstance()->getLastModelview()); }

inline void set_current_modelview(const glm::mat4& m)
{
    LLCamera camera = LLViewerCamera::getCurrent();
    camera.setModelview(ss_from_glm(m));
    LLViewerCamera::setCurrent(camera);
}

inline void set_current_projection(const glm::mat4& m)
{
    LLCamera camera = LLViewerCamera::getCurrent();
    camera.setProjection(ss_from_glm(m));
    LLViewerCamera::setCurrent(camera);
}

// Transforms a point by a matrix with the perspective divide, as LL's helper did.
inline glm::vec3 mul_mat4_vec3(const glm::mat4& mat, const glm::vec3& vec)
{
    const float w = vec[0] * mat[0][3] + vec[1] * mat[1][3] + vec[2] * mat[2][3] + mat[3][3];
    return glm::vec3(
        (vec[0] * mat[0][0] + vec[1] * mat[1][0] + vec[2] * mat[2][0] + mat[3][0]) / w,
        (vec[0] * mat[0][1] + vec[1] * mat[1][1] + vec[2] * mat[2][1] + mat[3][1]) / w,
        (vec[0] * mat[0][2] + vec[1] * mat[1][2] + vec[2] * mat[2][2] + mat[3][2]) / w);
}

#endif // SS_GLMCOMPAT_H
