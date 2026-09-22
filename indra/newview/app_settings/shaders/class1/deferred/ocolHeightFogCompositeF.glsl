/**
 * @file class1/deferred/ocolHeightFogCompositeF.glsl
 * @brief Atmo Magic height fog, volumetric mode: upsamples the reduced-
 *        resolution march (ocolHeightFogF.glsl) onto the scene. Each fog
 *        texel is weighted by how close its depth is to this pixel's, so fog
 *        doesn't bleed across silhouettes. Drawn full-screen with the flat
 *        path's blend (ONE / SOURCE_ALPHA): rgb in-scatter added, the scene
 *        multiplied by the transmittance in alpha.
 *
 *        Linked with deferredUtil.glsl (isDeferred) for the depth helpers;
 *        prototypes only, as ssPostFogF.glsl does.
 *
 * $LicenseInfo:firstyear=2026&license=viewerlgpl$
 * Outer Colonies Viewer Source Code
 * Copyright (C) 2026, Outer Colonies
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

// <OCOL> volumetric height fog

/*[EXTRA_CODE_HERE]*/

out vec4 frag_color;

in vec2 vary_fragcoord;

uniform sampler2D diffuseRect;  // the march: rgb in-scatter, a transmittance
uniform sampler2D depthMap;
//[ENGINE_BLOCK Matrices]
uniform vec2 ocolFogRes;        // the march target's size

// Diagnosis, the flat path's view 1: the fog amount as grayscale, alpha 0 so the blend shows
// the debug colour alone.
uniform float ssFogDebug;

float getDepth(vec2 pos_screen);
vec4 getPositionWithDepth(vec2 pos_screen, float depth);

float viewDistance(vec2 tc)
{
    return length(getPositionWithDepth(tc, getDepth(tc)).xyz);
}

void main()
{
    vec2 tc = vary_fragcoord.xy;
    float dist = viewDistance(tc);

    // 4x4 tent filter over the reduced-resolution fog: averages many different ray-march
    // start offsets, which dissolves the per-pixel jitter pattern
    vec2 texel = tc * ocolFogRes - 0.5;
    vec2 base = floor(texel) - 1.0;

    vec4 sum = vec4(0.0);
    float weight_sum = 0.0;
    vec4 closest = vec4(0.0);
    float closest_relative = 1e9;

    for (int y = 0; y < 4; ++y)
    {
        for (int x = 0; x < 4; ++x)
        {
            vec2 cell = base + vec2(float(x), float(y));
            vec2 sample_tc = (cell + 0.5) / ocolFogRes;

            vec2 d = abs(cell - texel);
            float tent = max(2.0 - d.x, 0.0) * max(2.0 - d.y, 0.0);
            if (tent <= 0.0)
            {
                continue;
            }

            float sample_dist = viewDistance(sample_tc);
            // Only reject samples across a real depth edge. A strict weight here made every
            // other pixel on distant, sloped ground copy a single fog texel while its
            // neighbours got the smooth average, which showed up as a fixed checker.
            float relative = abs(sample_dist - dist) / max(dist, 0.1);
            float weight = tent * (1.0 - smoothstep(0.1, 0.35, relative));

            vec4 fog = texture(diffuseRect, sample_tc);
            sum += fog * weight;
            weight_sum += weight;

            if (relative < closest_relative)
            {
                closest_relative = relative;
                closest = fog;
            }
        }
    }

    // thin features narrower than a fog texel have no matching neighbours: use the sample
    // nearest in depth rather than smearing the background's fog over them
    vec4 fog = (weight_sum <= 0.05) ? closest : sum / weight_sum;

    if (ssFogDebug > 1.5)
    {   // the march wrote the midpoint density view in rgb
        frag_color = vec4(fog.rgb, 0.0);
        return;
    }
    if (ssFogDebug > 0.5)
    {
        frag_color = vec4(vec3(1.0 - fog.a), 0.0);
        return;
    }

    frag_color = fog;
}

// </OCOL>
