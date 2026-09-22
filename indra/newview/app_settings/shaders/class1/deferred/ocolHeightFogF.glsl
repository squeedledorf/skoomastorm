/**
 * @file class1/deferred/ocolHeightFogF.glsl
 * @brief Atmo Magic height fog, volumetric mode: OCOL's mist marcher
 *        (tileable bank noise, per-pixel start offsets, sun shafts through
 *        the shadow maps, an analytic tail past the march distance) driven
 *        by Atmo's own density model - the same five weather terms, the same
 *        surface-field column gate, the same wind, the same colours and
 *        Henyey-Greenstein sun term as ssPostFogF.glsl. Runs at reduced
 *        resolution; ocolHeightFogCompositeF.glsl upsamples it onto the
 *        scene with the flat path's own blend.
 *
 *        Reads the SAME uniforms as ssPostFogF.glsl (ssFog*, ssField*), so
 *        SSHeightFog::render uploads them once for either path. Only the
 *        ocolFog* uniforms are this file's own. Linked like the flat
 *        program - postDeferredNoTCV.glsl, deferredUtil.glsl (isDeferred),
 *        ssSurfaceFieldF.glsl - plus shadowUtil.glsl (hasShadows) for the
 *        shafts; everything from those files is reached through the
 *        prototypes below.
 *
 *        Output contract is the flat shader's: rgb = in-scattered fog light,
 *        a = the scene's transmittance.
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

// LOCKSTEP ssPostFogF.glsl - the five terms' scale heights and the phase constants; the
// density below is that file's ssFogDensityAt, and must stay it.
const float SS_FOG_GROUND_SCALE_M = 6.0;
const float SS_FOG_PRECIP_SCALE_M = 60.0;
const float SS_FOG_HG_G = 0.55;
const float SS_FOG_SUN_GLOW = 0.35;
const float SS_FOG_PI = 3.14159265359;

// The march distance, metres: past it the layer is integrated analytically (no noise, no
// gate, unshadowed) against the flat ground reference.
const float OCOL_FOG_MARCH_M = 512.0;

// The bank noise: feature size (metres per lattice cell), the layer-top roll (metres the
// banks lift and lower the ground fog's top), and the tile period in cells. LOCKSTEP
// SSHeightFog::renderOCOL wraps the drift offsets to OCOL_FOG_FEATURE_M * OCOL_FOG_TILE_CELLS.
// Bank size and layer-top roll are settings (OCOLHeightFogFeatureM / OCOLHeightFogRollM), so
// they can be tuned live from the Simulation floater.
uniform float ocolFogFeatureM;
uniform float ocolFogRollM;
#define OCOL_FOG_FEATURE_M ocolFogFeatureM
#define OCOL_FOG_ROLL_M ocolFogRollM
const int   OCOL_FOG_TILE_CELLS = 64;

out vec4 frag_color;

in vec2 vary_fragcoord;

uniform sampler2D depthMap;
//[ENGINE_BLOCK Matrices]
uniform vec2 screen_res;

// Atmo's inputs, exactly as ssPostFogF.glsl declares them.
uniform mat4 ssFieldInvView;
uniform vec3 ssFogColor;
uniform vec3 ssFogSunColor;
uniform vec3 ssFogSunDir;
uniform float ssFogGround;
uniform float ssFogPrecip;
uniform float ssFogSquall;
uniform float ssFogLift;
uniform float ssFogMist;
uniform float ssFogSquallScale;
uniform float ssFogBand;
uniform float ssFogRange;
uniform float ssFogGroundZ;
uniform float ssFogWaterZ;
uniform vec3 ssFogWind;
uniform float ssFogTime;
uniform float ssFogDebug;

// This mode's own: the step count, whether to sample the sun shadow maps along the ray, and
// the two bank-noise drift offsets (Atmo's wind times time, wrapped to the noise tile CPU-side).
uniform int ocolFogSteps;
uniform int ocolFogShafts;
uniform vec3 ocolFogDrift0;
uniform vec3 ocolFogDrift1;

vec4 ssFieldFetch(vec2 xy_agent);
float ssFieldFetchCover(vec2 xy_agent);

float getDepth(vec2 pos_screen);
vec4 getPositionWithDepth(vec2 pos_screen, float depth);
bool isFarDepth(float d);

#if defined(HAS_SUN_SHADOW)
// One compare tap on the right cascade, no derivatives: the march runs in non-uniform
// control flow, where the receiver-plane bias's dFdx would be undefined, and a shaft only
// needs the one tap anyway.
float sampleDirectionalShadowSingleTap(vec3 pos);
#endif

// ---------------------------------------------------------------------------
// Noise. Atmo's wisp (fract-sin value noise) rides the ground and mist terms as in the flat
// path; the banks and wisps below are the volumetric shape on top of it - tileable value
// noise from an integer hash, so the drift wraps without a seam.

float ssFogHash3(vec3 p)
{
    return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
}

float ssFogValueNoise3(vec3 p)
{
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float n000 = ssFogHash3(i + vec3(0.0, 0.0, 0.0));
    float n100 = ssFogHash3(i + vec3(1.0, 0.0, 0.0));
    float n010 = ssFogHash3(i + vec3(0.0, 1.0, 0.0));
    float n110 = ssFogHash3(i + vec3(1.0, 1.0, 0.0));
    float n001 = ssFogHash3(i + vec3(0.0, 0.0, 1.0));
    float n101 = ssFogHash3(i + vec3(1.0, 0.0, 1.0));
    float n011 = ssFogHash3(i + vec3(0.0, 1.0, 1.0));
    float n111 = ssFogHash3(i + vec3(1.0, 1.0, 1.0));

    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);

    float nxy0 = mix(nx00, nx10, f.y);
    float nxy1 = mix(nx01, nx11, f.y);

    return mix(nxy0, nxy1, f.z);
}

float hash13(ivec3 c)
{
    uint h = uint(c.x) * 1664525u + uint(c.y) * 22695477u + uint(c.z) * 1103515245u;
    h ^= h >> 16;
    h *= 2246822519u;
    h ^= h >> 13;
    h *= 3266489917u;
    h ^= h >> 16;
    return float(h & 0x00ffffffu) / 16777215.0;
}

float tileNoise(vec3 p, int period)
{
    vec3 cell = floor(p);
    vec3 f = p - cell;
    vec3 u = f * f * (3.0 - 2.0 * f);

    // keep lattice coordinates positive before wrapping; GLSL % is undefined for negatives
    ivec3 a = (ivec3(cell) + ivec3(period * 1024)) % period;
    ivec3 b = (a + ivec3(1)) % period;

    float n000 = hash13(ivec3(a.x, a.y, a.z));
    float n100 = hash13(ivec3(b.x, a.y, a.z));
    float n010 = hash13(ivec3(a.x, b.y, a.z));
    float n110 = hash13(ivec3(b.x, b.y, a.z));
    float n001 = hash13(ivec3(a.x, a.y, b.z));
    float n101 = hash13(ivec3(b.x, a.y, b.z));
    float n011 = hash13(ivec3(a.x, b.y, b.z));
    float n111 = hash13(ivec3(b.x, b.y, b.z));

    return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
               mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

float ssFogHG(float cos_theta, float g)
{
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * SS_FOG_PI * pow(max(1.0 + g2 - 2.0 * g * cos_theta, 1.0e-4), 1.5));
}

// Interleaved gradient noise for per-pixel start offsets
float ign(vec2 px)
{
    return fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));
}

// ---------------------------------------------------------------------------
// Density: ssPostFogF.glsl's ssFogDensityAt - the column gate graded by the cover window,
// the five terms, Atmo's wisp - with the volumetric shape folded onto the two sources Atmo
// lets wisp (ground and mist): the banks roll the layer's top and break it into drifting
// masses. Precipitation, the squall and the drift band are driven weather already in
// motion and stay as the flat path has them. The water gate is the caller's, as there.
float ocolFogDensityAt(vec3 q)
{
    vec4 here = ssFieldFetch(q.xy);

    float surface_z = ssFogGroundZ;
    float openness = 1.0;

    if (here.x > -1.0e5)
    {
        if (here.x - q.z > 0.75)
        {
            float cover = ssFieldFetchCover(q.xy);
            openness = (cover > -0.5) ? 1.0 - clamp(cover, 0.0, 1.0) : 0.0;
            if (openness < 0.001) return 0.0;
        }
        else
        {
            surface_z = here.x;
        }
    }

    float h = max(q.z - surface_z, 0.0);

    float precip_term = ssFogPrecip * exp(-h / SS_FOG_PRECIP_SCALE_M);
    float squall_term = ssFogSquall * exp(-h / max(ssFogSquallScale, 4.0));
    float band_term   = (h < ssFogBand) ? ssFogLift : 0.0;

    float ground_mist = 0.0;
    if (ssFogGround + ssFogMist > 1.0e-5)
    {
        vec3 p = q / OCOL_FOG_FEATURE_M;
        // large rolling banks, squashed vertically so they read as layers, not blobs
        float banks = tileNoise((p + ocolFogDrift0 / OCOL_FOG_FEATURE_M) * vec3(1.0, 1.0, 2.0), OCOL_FOG_TILE_CELLS);
        // fine wisps drifting at a different rate
        float wisps = tileNoise((p + ocolFogDrift1 / OCOL_FOG_FEATURE_M) * 3.0, OCOL_FOG_TILE_CELLS * 3);
        float n = banks * 0.7 + wisps * 0.3;
        float breakup = smoothstep(0.25, 0.75, n) * 1.5;

        // the top of the layer rises and falls with the banks
        float hb = max(h - (banks - 0.5) * OCOL_FOG_ROLL_M, 0.0);
        float ground_term = ssFogGround * exp(-hb / SS_FOG_GROUND_SCALE_M);
        float mist_term = ssFogMist * exp(-hb / SS_FOG_GROUND_SCALE_M);

        float wisp = 0.75 + 0.25 * ssFogValueNoise3(q * 0.18 - ssFogWind * ssFogTime * 0.18);
        ground_mist = (ground_term + mist_term) * wisp * breakup;
    }

    return (ground_mist + precip_term + squall_term + band_term) * openness;
}

// Optical depth of one exponential term along a straight ray past the march: constant
// density below the reference (Atmo's h = max(..., 0)), exponential thinning above it.
// h0: start height over the reference, dz: the ray's rise per metre, len: the stretch.
float ocolFogLayerOD(float h0, float dz, float len, float density, float falloff)
{
    const float EPS = 1e-4;
    float od = 0.0;

    float below_a = 0.0;
    float below_b = 0.0;
    if (abs(dz) > EPS)
    {
        float t_base = -h0 / dz;
        below_a = (dz > 0.0) ? 0.0 : clamp(t_base, 0.0, len);
        below_b = (dz > 0.0) ? clamp(t_base, 0.0, len) : len;
    }
    else if (h0 <= 0.0)
    {
        below_b = len;
    }
    od += density * max(below_b - below_a, 0.0);

    float above_a = (below_a > 0.0) ? 0.0 : below_b;
    float above_b = (below_a > 0.0) ? below_a : len;
    if (above_b > above_a)
    {
        float ha = max(h0 + dz * above_a, 0.0);
        float hb = max(h0 + dz * above_b, 0.0);
        if (abs(dz) > EPS)
        {
            od += density * falloff / dz * (exp(-ha / falloff) - exp(-hb / falloff));
        }
        else
        {
            od += density * exp(-ha / falloff) * (above_b - above_a);
        }
    }
    return max(od, 0.0);
}

// The tail's four terms plus the drift band, against the flat ground reference. The marched
// stretch multiplies ground and mist by wisp (0.75-1) and breakup (0-1.5); the tail carries
// their mean so the density does not step up at the march distance.
const float OCOL_FOG_TAIL_BREAKUP = 0.66;
float ocolFogTailOD(float h0, float dz, float len)
{
    float od = ocolFogLayerOD(h0, dz, len, (ssFogGround + ssFogMist) * OCOL_FOG_TAIL_BREAKUP, SS_FOG_GROUND_SCALE_M)
             + ocolFogLayerOD(h0, dz, len, ssFogPrecip, SS_FOG_PRECIP_SCALE_M)
             + ocolFogLayerOD(h0, dz, len, ssFogSquall, max(ssFogSquallScale, 4.0));
    // the band: constant ssFogLift wherever h < ssFogBand
    float band_len = len;
    if (abs(dz) > 1e-4)
    {
        float t_band = (ssFogBand - h0) / dz;
        band_len = (dz > 0.0) ? clamp(t_band, 0.0, len) : len - clamp(t_band, 0.0, len);
    }
    else if (h0 >= ssFogBand)
    {
        band_len = 0.0;
    }
    return od + ssFogLift * band_len;
}

void main()
{
    vec2 tc = vary_fragcoord.xy;

    // Every depth read in this pass and the composite goes through the same point-clamped
    // sampler on the same depth copy (OCOL's lesson: a filtered read here against a point read
    // there drew dark rims of too-thin fog around every silhouette).
    float depth = getDepth(tc);
    vec3 pos = getPositionWithDepth(tc, depth).xyz;

    // Sky by depth alone, as the flat path: no G-buffer is bound to this post program.
    bool is_sky = isFarDepth(depth);
    float scene_len = length(pos);
    vec3 view_dir = pos / max(scene_len, 1e-4);

    vec3 cam_agent = (ssFieldInvView * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    vec3 dir_agent = normalize((ssFieldInvView * vec4(view_dir, 0.0)).xyz);

    // The sky ray marches the layer itself instead of the flat path's closed-form climb: the
    // same density integrated along the climb, banks and gate included, up to the march
    // distance, the analytic tail after.
    float ray_len = is_sky ? OCOL_FOG_MARCH_M * 16.0 : scene_len;
    float end_len = min(ray_len, OCOL_FOG_MARCH_M);

    // Extinction coefficient: a full-strength layer collapses visibility to roughly ssFogRange metres.
    float extinction = 3.0 / max(ssFogRange, 4.0);

    // Atmo's in-scatter per unit scattered: the horizon colour plus the Henyey-Greenstein
    // share toward the sun or moon; the shafts modulate only the sun share.
    float phase = ssFogHG(dot(dir_agent, ssFogSunDir), SS_FOG_HG_G);
    vec3 sun_light = ssFogSunColor * SS_FOG_SUN_GLOW * phase;

    if (ssFogDebug > 1.5)
    {   // the flat path's diagnosis: the density at the ray's midpoint, x5
        vec3 q = cam_agent + dir_agent * (end_len * 0.5);
        float d = ocolFogDensityAt(q) * smoothstep(ssFogWaterZ - 0.10, ssFogWaterZ + 0.15, q.z);
        frag_color = vec4(vec3(d * 5.0), 1.0);
        return;
    }

    float transmittance = 1.0;
    vec3 inscatter = vec3(0.0);

    int steps = max(ocolFogSteps, 4);
    float jitter = ign(gl_FragCoord.xy);

    for (int i = 0; i < steps; ++i)
    {
        // quadratic spacing: fine steps near the camera where fog moves fastest on screen.
        // Step i owns the segment [t0, t1] and samples it at a jittered point, so the whole
        // ray to end_len is integrated whatever the jitter.
        float s0 = float(i) / float(steps);
        float s1 = float(i + 1) / float(steps);
        float t0 = end_len * s0 * s0;
        float t1 = end_len * s1 * s1;
        float t = mix(t0, t1, jitter);
        float dt = t1 - t0;

        vec3 q = cam_agent + dir_agent * t;

        // Fog stops at the water surface: a fade straddling the plane, not a cut (ssPostFogF).
        float water_gate = smoothstep(ssFogWaterZ - 0.10, ssFogWaterZ + 0.15, q.z);

        float sigma = ocolFogDensityAt(q) * water_gate * extinction;
        if (sigma <= 1e-6)
        {
            continue;
        }

        float shadow = 1.0;
#if defined(HAS_SUN_SHADOW)
        if (ocolFogShafts == 1)
        {
            shadow = clamp(sampleDirectionalShadowSingleTap(view_dir * t), 0.0, 1.0);
        }
#endif

        float step_t = exp(-sigma * dt);
        inscatter += transmittance * (1.0 - step_t) * (ssFogColor + sun_light * shadow);
        transmittance *= step_t;

        if (transmittance < 0.01)
        {
            break;
        }
    }

    // beyond the march distance, integrate the layer analytically (no noise, unshadowed)
    if (ray_len > end_len && transmittance >= 0.01)
    {
        float h_end = cam_agent.z + dir_agent.z * end_len - ssFogGroundZ;
        float od = ocolFogTailOD(h_end, dir_agent.z, ray_len - end_len) * extinction;
        float far_t = exp(-od);
        inscatter += transmittance * (1.0 - far_t) * (ssFogColor + sun_light);
        transmittance *= far_t;
    }

    transmittance = clamp(transmittance, 0.0, 1.0);
    inscatter = max(inscatter, vec3(0.0));

    frag_color = vec4(inscatter, transmittance);
}

// </OCOL>
