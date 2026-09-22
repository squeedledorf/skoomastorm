/**
 * @file class1/deferred/cloudsV.glsl
 *
 * $LicenseInfo:firstyear=2005&license=viewerlgpl$
 * Second Life Viewer Source Code
 * Copyright (C) 2005, Linden Research, Inc.
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

// Shared matrix stack + derived matrices, spliced from
// class1/deferred/matricesBlock.glsl and bound at UB_MATRICES.
//[ENGINE_BLOCK Matrices]

in vec3 position;
in vec2 texcoord0;

//////////////////////////////////////////////////////////////////////////
// The vertex shader for creating the atmospheric sky
///////////////////////////////////////////////////////////////////////////////

// Output parameters
out vec3 pos;

out vec2 vary_texcoord0;
out vec2 vary_texcoord1;
out vec2 vary_texcoord2;
out vec2 vary_texcoord3;

// Inputs
uniform vec3 lightnorm;
// Shared per-frame sky/water constants, spliced from class1/deferred/environmentBlock.glsl
// and bound at UB_ENVIRONMENT. Members are read by bare name.
//[ENGINE_BLOCK Environment]

#ifdef SS_ATMO
// <SS:Nexii> Region-relative cloud parallax and wind travel (doc/atmo_magic_cloud_parallax.md) have moved to the FRAGMENT stage, which derives the band's UVs from the true view ray - the vertex stage's only remaining job is to hand that ray down. Atmo-only, so a stock environment compiles the pristine texcoord path. The layer's own depth slot, 0.99998 - or 0 for the stock projection squash. Zero unless an ACTIVE Atmo environment is driving the sky (lldrawpoolwlsky.cpp): the slot exists to order the band against the Atmo discs, and with no discs drawn an idle EEP sky keeps stock depth.
uniform float ss_cloud_depth;
#endif

// NOTE: Keep these in sync!
//       indra\newview\app_settings\shaders\class1\deferred\skyV.glsl
//       indra\newview\app_settings\shaders\class1\deferred\cloudsV.glsl
//       indra\newview\app-settings\shaders\class2\windlight\cloudsV.glsl
//       indra\newview\lllegacyatmospherics.cpp
//       indra\newview\llsettingsvo.cpp
void main()
{
    // World / view / projection
    pos = position.xyz;
#ifdef SS_ATMO
    // <SS:Nexii> The cloud layer's own depth slot. LLGLSPipelineSkyBox's LLGLSquashToFarClip would otherwise put this on 0.99999 along with the haze dome and everything else in the sky, which leaves no room to order the sky's layers against each other - and the celestial discs need to be ordered against this one, since a disc is added to the sky rather than composited over it and so can only be hidden by depth. Its layer parameter cannot express this: it steps in units of 0.0001 (0.99999 - 0.0001 * layer, see setProjectionMatrix), and what is wanted here is one step of 0.00001. Set in the same FORM the disc shader uses - w times a constant, in a vertex shader - and that matters as much as the value. Reaching the same number by two different routes (a multiply here, a rewritten projection row there) leaves the two disagreeing in the last bits, so the depth test flips per pixel and the layers speckle through each other. Same expression, same result, no fight. Runtime-gated by ss_cloud_depth (see the uniform note above): 0 leaves gl_Position exactly as stock computed it, so an idle EEP sky takes the untouched squash the projection row bakes.
    vec4 cloud_pos = modelview_projection_matrix * vec4(position.xyz, 1.0);
    if (ss_cloud_depth > 0.)
    {
        // PORT-TODO: forward-Z only (like the sky's horizon clip) - under Alchemy's REVERSE_Z this slot must be 1.0 - ss_cloud_depth.
        cloud_pos.z = cloud_pos.w * ss_cloud_depth;
    }
    gl_Position = cloud_pos;
#else
    gl_Position = modelview_projection_matrix * vec4(position.xyz, 1.0);
#endif

    // Texture coords
    // SL-13084 EEP added support for custom cloud textures -- flip them horizontally to match the preview of Clouds > Cloud Scroll
    vary_texcoord0 = vec2(-texcoord0.x, texcoord0.y);  // See: LLSettingsVOSky::applySpecial

    vary_texcoord0.xy -= 0.5;
    vary_texcoord0.xy /= cloud_scale;
    vary_texcoord0.xy += 0.5;

    vary_texcoord1 = vary_texcoord0;
    vary_texcoord1.x += lightnorm.x * 0.0125;
    vary_texcoord1.y += lightnorm.z * 0.0125;

    vary_texcoord2 = vary_texcoord0 * 16.;
    vary_texcoord3 = vary_texcoord1 * 16.;
}
