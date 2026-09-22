/**
 * @file class1\deferred\cloudsF.glsl
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
/*[EXTRA_CODE_HERE]*/

out vec4 frag_data[4];

/////////////////////////////////////////////////////////////////////////
// The fragment shader for the sky
/////////////////////////////////////////////////////////////////////////

// In
in vec3 pos;

in vec2 vary_texcoord0;
in vec2 vary_texcoord1;
in vec2 vary_texcoord2;
in vec2 vary_texcoord3;

uniform sampler2D cloud_noise_texture;
uniform sampler2D cloud_noise_texture_next;
uniform float blend_factor;
// Shared per-frame sky/water constants, spliced from class1/deferred/environmentBlock.glsl
// and bound at UB_ENVIRONMENT. Members are read by bare name.
//[ENGINE_BLOCK Environment]
uniform float cloud_variance;

uniform vec3 camPosLocal;

uniform vec3 lightnorm;
uniform vec3 sunlight_color;
uniform vec3 moonlight_color;
uniform int sun_up_factor;
uniform vec3 ambient_color;

uniform float density_multiplier;

uniform float sun_moon_glow_factor;


vec4 cloudNoise(vec2 uv)
{
   vec4 a = texture(cloud_noise_texture, uv);
   vec4 b = texture(cloud_noise_texture_next, uv);
   vec4 cloud_noise_sample = mix(a, b, blend_factor);
   return cloud_noise_sample;
}

// Hides the R11F_G11F_B10F emissive attachment's 6/6/5-mantissa banding in this writer's
// smooth gradients. Defined in deferred/globalF.glsl, which every fragment stage attaches.
vec3 ditherEmissive(vec3 v, vec2 frag_px);

#ifdef SS_ATMO

// <SS:Nexii> The sun's horizon-band share (SSAtmoEnvApplier::sunRiseFraction): 1 the whole time the disc's centre stands at or above the horizon, easing smoothly to 0 across the twilight band below it; 0 also means no active Atmo environment, which is exactly stock. The layer's sun glow ramps on it below - full strength while the sun hangs at the horizon, the condition the authored skies painted against, easing out through the dusk after it sets.
uniform float ss_sun_rise;

// <SS:Nexii> The sun's TRUE direction while the rise band is live (SSAtmoEnvApplier::sunSlotDirection). lightnorm hands the direction to the moon the moment the disc's centre sets, and TWO things here must keep looking at the sun through the whole band, dusk included: the glow hotspot below, and the disc-neighbourhood body restore further down - the one that keeps horizon clouds solid around the disc so it cannot burn through them. Both swing to the moon's azimuth at centre-set without this. See the ss_sun_dir note in skyV.glsl.
uniform vec3 ss_sun_dir;

// <SS:Nexii> The disc's half-angle as a direction-z sine (SSAtmoEnvApplier::sunSlotRadius) - the airmass floor the layer's sun term holds while the rise band is live - through the whole rise AND the whole dusk below the horizon - the just-cleared light path, for the same reason skyV.glsl does. Zero while no Atmo environment drives the sky.
uniform float ss_sun_radius;

// <SS:Nexii> The stock ray lift, as in skyV.glsl: the layer's atmosphere ray below is computed 50 m above the geometry it belongs to (the + vec3(0, 50, 0) in rel_pos), a legacy fudge that once rode along with the stock sun disc's own legacy 50 m drop. The Atmo discs draw at the TRUE direction (ssCelestialV.glsl carries no offset of any kind), so while they own the sky the lift drops to 0 and TWO things on this layer land on the disc with it: the glow hotspot, and the disc-neighbourhood body restore - the one that keeps horizon clouds solid around the disc, and which is ring-shaped about a direction, so a lifted ray swings the whole ring off the disc it is there to frame. 1 is exactly stock, which is what an enabled-but-idle viewer keeps.
uniform float ss_ray_lift;

// <SS:Nexii> The glow light's extinction ceiling, in optical depths on the densest attenuation channel - see the long note at the glow light below, and the matching one in skyV.glsl. Keep in sync with skyV.glsl.
const float SS_SUN_GLOW_DEPTH = 2.0;
#endif

#ifdef SS_ATMO
// <SS:Nexii> The dome's authored LARGE-SCALE map, when one is set (lldrawpoolwlsky binds it and raises the gate): the broad octave and its self-shadow read it, while the fine octave keeps the cloud noise. The cloud noise's own blob scale is tuned for the fine octave, so a broad composition art-directed on it comes out samey - one map for every octave means the broad sky is the fine map stretched. Gate 0 leaves every octave on the cloud noise, exactly as before this existed.
uniform sampler2D ss_noise_large;
uniform float ss_noise_large_on;

// <SS:Nexii> The large map's crossfade partner and weight, live while the day cycle fades the broad octave between two authored maps. The pool pins the partner on the same map with weight 0 whenever no fade runs, so the inner mix below is a no-op then.
uniform sampler2D ss_noise_large_next;
uniform float ss_noise_large_blend;

vec4 cloudNoiseLarge(vec2 uv)
{
    vec4 large = texture(ss_noise_large, uv);
    if (ss_noise_large_blend > 0.0)
    {
        large = mix(large, texture(ss_noise_large_next, uv), ss_noise_large_blend);
    }
    return mix(cloudNoise(uv), large, ss_noise_large_on);
}

// <SS:Nexii> One endpoint-scale plate of the cloud layer: uv1..uv4 at THAT scale through the whole density chain - the wind variance disturbances (scale-amplitude gated by the SAME authored scale so each plate's turbulence matches its own tile), the density-variance erosion of cloudDensity, and the two opacities. Everything here is a function of the UVs, so the Scale crossfade is two calls and an output mix - one plate per endpoint scale - while the vary_* cloud colours and the per-fragment fades (altitude, deck edge, plane) are UV-independent and stay single. `authored_scale` is the plate's raw Scale-dial value: the divisor behind the UVs worked from it (ss_plane_base), and the (1 - scale*0.25) variance factor keeps the pre-dial behaviour where the live sky's scale uniform gated the turbulence one-to-one. Both SS_ATMO variants and the stock (non-Atmo) build share this body so one source of truth drives every path.
void ss_cloud_branch(vec2 uv1, vec2 uv2, vec2 uv3, vec2 uv4, float authored_scale,
                     float cloud_density_in, float detail_fade,
                     out float out_alpha1, out float out_alpha2)
{
    vec2 disturbance  = vec2(cloudNoise(uv1 / 8.0f).x, cloudNoise((uv3 + uv1) / 16.0f).x) * cloud_variance * (1.0f - authored_scale * 0.25f);
    // <SS:Nexii> The fine-sourced disturbance rides the same distance fade as the fine layer itself - past it the far deck's variance comes from the broad octaves alone.
    vec2 disturbance2 = vec2(cloudNoise((uv1 + uv3) / 4.0f).x, cloudNoise((uv4 + uv2) / 8.0f).x) * cloud_variance * (1.0f - authored_scale * 0.25f) * detail_fade;

    // Offset texture coords
    uv1 += cloud_pos_density1.xy + (disturbance * 0.2);    //large texture, visible density
    uv2 += cloud_pos_density1.xy;   //large texture, self shadow
    uv3 += cloud_pos_density2.xy;   //small texture, visible density
    uv4 += cloud_pos_density2.xy;   //small texture, self shadow

    float density_variance = min(1.0, (disturbance.x* 2.0 + disturbance.y* 2.0 + disturbance2.x + disturbance2.y) * 4.0);

    cloud_density_in *= 1.0 - (density_variance * density_variance);

    // Compute alpha1, the main cloud opacity
    // <SS:Nexii> The fine octave's weight rides detail_fade: past the fade's range the fine tiling compresses into sub-degree rows that read as striping, so its voice in the opacity fades with its angular size and the broad layer carries the far deck alone. The term is zero-mean, so the fade changes the far field's TEXTURE, not its coverage.
    float alpha1 = (cloudNoiseLarge(uv1).x - 0.5) + (cloudNoise(uv3).x - 0.5) * cloud_pos_density2.z * detail_fade;
    alpha1 = min(max(alpha1 + cloud_density_in, 0.) * 10 * cloud_pos_density1.z, 1.);

    // And smooth
    alpha1 = 1. - alpha1 * alpha1;
    alpha1 = 1. - alpha1 * alpha1;

    // Compute alpha2, for self shadowing effect
    // (1 - alpha2) will later be used as percentage of incoming sunlight
    float alpha2 = (cloudNoiseLarge(uv2).x - 0.5);
    alpha2 = min(max(alpha2 + cloud_density_in, 0.) * 2.5 * cloud_pos_density1.z, 1.);

    // And smooth
    alpha2 = 1. - alpha2;
    alpha2 = 1. - alpha2 * alpha2;

    out_alpha1 = alpha1;
    out_alpha2 = alpha2;
}

// <SS:Nexii> The deck mapping (doc/atmo_magic_cloud_parallax.md). Each dome band's UVs are derived HERE, per fragment, from the true view ray cloudsV hands down - not from the dome mesh's own texcoords plus a patch. Two things that buys: the parallax rate is per-band and exact in the anchored terms, and the sky curvature is the deck's own rather than whatever rate the dome mesh happens to distribute its vertices at. Per-fragment costs one normalize already paid in the vertex stage and a divide.
uniform vec2 region_offset;    // camera pos - region centre, metres, world X/Y
uniform vec2 ss_cloud_drift;   // metres the band has travelled on the wind, east and north
uniform float ss_cloud_alt_m;  // the BAND'S OWN height above the CAMERA, metres (world deck height minus camera)
uniform float ss_planet_orbit_m; // camera's distance from the planet's centre, metres - 0 falls back to the flat deck
uniform float ss_cloud_plane;  // 1: derive UVs from the view ray (active Atmo). 0: stock dome texcoords
uniform float ss_deck_edge_sin; // the volumetric deck's perceived edge, as an elevation sine over the camera - 0 keeps the narrow rim melt
// SKOOMA-PORT: was the vertex stage's ss_ray_dir; main() fills it per fragment before any ss_* mapping call.
vec3 ss_ray_dir;

// <SS:Nexii> The dome band's Scale crossfade (SSAtmoEnvApplier::cloudScaleTo/cloudScaleBlend, samplings of the Sky Dome tab's keyframed Scale dial). The sky's own cloud_scale uniform keeps holding the fade's FROM endpoint; these carry the TO endpoint's authored scale and the eased weight. main() samples the band at BOTH scales and mixes the two resulting opacities by the weight - the pattern never has its divisor interpolated, the two endpoint-scale renderings crossfade, so a keyframed Scale change between two authored patterns slides between them instead of zooming continuously (the interpolation was the erratic-motion bug: an interpolated divisor drags every feature sideways as the tile zooms). 0 blend is the single-sample rail.
uniform float ss_cloud_scale_to;
uniform float ss_cloud_scale_blend;

// Metres of world per UV at the Scale ANCHOR (SSShellPlane::scaleAnchor). Pinned against the band's HEIGHT,
// so one tile is one fixed piece of world when the altitude moves: the convection merge can
// descend the cirrus band without breathing the pattern. The Scale dial re-enters the render as a
// divisor on this pin (see ss_plane_base) - authored scale / anchor multiplies the metres per UV,
// wider tile, bigger features - so an imported day cycle's keyframed Scale dial changes the
// pattern again, but only through the CROSSFADE built from it (see the branch calls in main): the
// two endpoint scales' renderings are blended, never the divisor interpolated, so the sheets do
// not appear to move while the dial plays. Calibrated for the band's 6 km DEFAULT (the cirrus
// layer's default height): the visibly solid sky spans ~4 band-heights of reach before the
// horizon fade takes it (zenith to ~3 degrees of elevation), so a 32 km tile reads as a 3x3-to-4x4
// repeat across the dome - one tile ~5x the band's height, the broad composition the layer
// is tuned for. (The first pin's 8 km read as ~24 repeats marching into the horizon; the
// stock-anchored 2*alt*cloud_scale divisor it replaced breathed the pattern every time the
// band moved.)
// (that number is SSShellPlane::tileM below, and it is now an ARGUMENT - see the transliteration note.)
//
// The Scale dial's identity point: an authored scale of 0.25 means "the anchor tile, exactly the
// render before the dial was re-added" - the divisor below collapses to the tile pin. Above the
// anchor the tile widens (fewer repeats, larger cloud features), below it narrows. Mirrored by the
// applier's comment at the scale crossfade sample (SSAtmoEnvApplier::applySky). That number is
// SSShellPlane::scaleAnchor below.

// <SS:Nexii> THE GEOMETRY IN THIS BLOCK IS A TRANSLITERATION, NOT AN ORIGINAL. indra/newview/ssshellcore.h (namespace SSShell) is the AUTHORITY for every formula here - the ray/shell intersection on both faces, the rim derived from its discriminant, the rim fade, the layer's own dissolve, the fine-octave give-up and the flat fallback - and the bodies below follow that header statement for statement so V:\Scratch\atmo\tests\twin_shell.cpp can pin the two together over a grid. The geometry moved out of this file because phase 8c adds a SECOND shell at the volumetric deck's own altitude (doc/atmo_magic_phase8_show.md section 5): three of the constants this band used to bake in - the 32 km tile, the 0.125 parallax damp, the 100/250 km detail rails - were calibrated to the CIRRUS band and blocked a second caller, so they are arguments now and this band passes its own values unchanged.
struct SSShellPlane
{
    float tileM;
    float scaleAnchor;
    float parallaxDamp;
    float deckFold;
    float throughLoM;
    float throughHiM;
    float detailLoM;
    float detailHiM;
    float meltGain;
};

// <SS:Nexii> SSShell::CIRRUS - this band's nine values, the exact literals this file carried inline before the parameterisation (32 km tile pinned against the band's 6 km default height; 0.25 scale anchor; 0.125 damp, the rate the shipped vertex nudge moved at and the eye was tuned to in a live viewer; 0.1 horizon fold; 40..300 m through-fade; 100..250 km detail rails; 1.6 melt gain). The deck shell of 8c passes a DIFFERENT struct - undamped above all, because it must agree with the world-honest, drift-anchored tiled veil at the 10-14 km handoff and a damped shell would slide against it as the camera moves.
SSShellPlane ss_shell_cirrus()
{
    return SSShellPlane(32000.0, 0.25, 0.125, 0.1, 40.0, 300.0, 100000.0, 250000.0, 1.6);
}

// SSShell::discriminant. The bracket under the intersection's root: with the camera at distance a
// from the body's centre and the shell at radius a + alt, |C + t*d|^2 = (a+alt)^2 expands to
// t^2 + 2*a*u*t - (2*a*alt + alt*alt) = 0, so this is a*a*u*u + 2*a*alt + alt*alt. Everything else
// in this block is derived from it - including, and this is the 8c fix, whether the ray meets the
// shell at all.
float ss_shell_disc(float orbit_m, float alt, float ray_up)
{
    float u = (alt >= 0.0) ? max(ray_up, 0.0) : ray_up;
    return orbit_m * orbit_m * u * u + 2.0 * orbit_m * alt + alt * alt;
}

// SSShell::flatReachM. The no-home-body fallback, SOFTENED not clamped: smooth in the ray
// everywhere, exact at the zenith, and capped at ~(1+F)/F layer-altitudes in the horizon fold. It
// is also the orbit -> infinity limit of the curved reach, which the core's ladder measures.
float ss_shell_flat_reach(float alt, float ray_up, float deck_fold)
{
    float side = (alt >= 0.0) ? 1.0 : -1.0;
    return (1.0 + deck_fold) * abs(alt) / (max(ray_up * side, 0.0) + deck_fold);
}

// SSShell::shellReachM. Distance along the view ray to the shell, both signs of altitude: the PLUS
// root below the shell, the MINUS root above it (the near face of the deck as a sky build looks
// down on it). `side` carries the sign of the root so the two faces are one expression.
float ss_shell_reach(float orbit_m, float alt, float ray_up, float deck_fold)
{
    if (orbit_m > 0.0)
    {
        float side = (alt >= 0.0) ? 1.0 : -1.0;
        float u    = (alt >= 0.0) ? max(ray_up, 0.0) : ray_up;
        float d    = ss_shell_disc(orbit_m, alt, ray_up);
        return -orbit_m * u + side * sqrt(max(d, 0.0));
    }
    return ss_shell_flat_reach(alt, ray_up, deck_fold);
}

// SSShell::tangentSin. The rim, taken from the discriminant rather than mirrored off the near
// face: disc(u) = a*a*u*u + (r*r - a*a) is a parabola in u whose only root is |u| = sqrt(|r*r -
// a*a|)/a, and r*r - a*a is exactly 2*a*alt + alt*alt. Below the shell that bracket is positive,
// disc never vanishes, every ray hits, and the root names the elevation at which the shell crosses
// the camera's horizontal plane - the rail this band's melt has always used. ABOVE the shell the
// bracket is negative and the same root is a genuine rim: flatter rays miss the shell entirely.
float ss_shell_tangent_sin(float orbit_m, float alt)
{
    float q = 2.0 * orbit_m * alt + alt * alt;
    return sqrt(abs(q)) / orbit_m;
}

// SSShell::planeFade. How much of the layer survives the camera's own altitude: the mapping
// degenerates as the camera meets the layer and the layer's own volume takes over exactly there.
// The step term drops rays heading away from the face.
float ss_shell_plane_fade(float alt, float ray_up, float through_lo, float through_hi)
{
    float side = (alt >= 0.0) ? 1.0 : -1.0;
    return step(0.0, ray_up * side) * smoothstep(through_lo, through_hi, abs(alt));
}

// SSShell::detailFade. Where the fine layers give up: perspective compresses the layer toward its
// rim and the fine detail's angular size collapses with it, so past these rails the broad layer
// carries the far sheet alone. The term it gates is zero-mean - the far field's TEXTURE simplifies,
// its coverage does not change.
float ss_shell_detail_fade(float reach_m, float lo, float hi)
{
    return 1.0 - smoothstep(lo, hi, reach_m);
}

// SSShell::edgeFade. The layer's curved horizon melt: zero AT the rim, full a melt_gain multiple of
// the rim sine away from it, so the edge reads as a cloud horizon dissolving into the atmosphere
// rather than a seam. deck_edge_sin raises the melt's TOP on the NEAR face only - it is the
// volumetric deck's perceived edge over the camera, and past that edge the band has no cloud in
// front of it, so the melt spends the whole span between the deck's edge and the rim instead of
// running a flat grey sheet into it. It has no meaning on the far face and the CPU zeroes it there
// by construction (lldrawpoolwlsky gates it on deck_top_m > 0).
//
// THE alt < 0 BRANCH IS THE 8c FIX. This function used to return 1.0 for every ray whenever the
// layer sat below the camera, so a deck seen from a sky build covered the whole lower hemisphere at
// full opacity - including the entire cone of directions where, by the discriminant above, there is
// no shell to see. It now melts on the DOWN-ness of the ray against the same rim, which lands the
// fade exactly where the intersection stops existing: alpha reaches 0 as disc reaches 0.
float ss_shell_edge_fade(float orbit_m, float alt, float ray_up, float deck_edge_sin, float melt_gain)
{
    if (orbit_m <= 0.0) return 1.0;
    float edge_dy = ss_shell_tangent_sin(orbit_m, alt);
    if (edge_dy <= 0.0) return 1.0;
    float melt_hi = edge_dy * melt_gain;
    if (alt < 0.0)
    {
        return smoothstep(edge_dy, melt_hi, -ray_up);
    }
    if (deck_edge_sin > melt_hi)
    {
        melt_hi = deck_edge_sin;
    }
    return smoothstep(edge_dy, melt_hi, ray_up);
}

// SSShell::planeBase. The whole shell mapping for one fragment: intersect, anchor at the region
// centre, subtract the wind travel, divide by the pinned metres-per-UV. `ray` rides the dome mesh's
// Y-up local frame, which is why the horizontal components reach the layer as (ray.z, ray.x) -
// east, north - matching region_off's (world X, world Y) order; the v axis is negated because world
// north runs down the texture. reach_m comes back out because 8c's deck shell needs its own
// intersection distance for the veil handoff; this band discards it.
vec2 ss_shell_plane_base(float orbit_m, float alt, vec3 ray, float scale, vec2 region_off, vec2 drift,
                         SSShellPlane p, out float plane_fade, out float detail_fade, out float reach_m)
{
    plane_fade  = ss_shell_plane_fade(alt, ray.y, p.throughLoM, p.throughHiM);
    reach_m     = ss_shell_reach(orbit_m, alt, ray.y, p.deckFold);
    detail_fade = ss_shell_detail_fade(reach_m, p.detailLoM, p.detailHiM);

    float deck_x  = ray.z * reach_m;
    float deck_y  = ray.x * reach_m;
    float world_x = p.parallaxDamp * (region_off.x - drift.x);
    float world_y = p.parallaxDamp * (region_off.y - drift.y);
    float div     = p.tileM * scale / p.scaleAnchor;

    return vec2((deck_x + world_x) / div, (-deck_y - world_y) / div);
}

// The fine layers' multiplier. Stock's 16 made the fine tile a fraction of the broad one -
// dozens of copies of the same clump across the sky, marching in rows under the perspective
// compression. At 2x the fine tile is half the broad one: two close octaves a single factor
// apart, so their repetitions never align into a visible grid. Stock's texcoord path keeps
// its 16.
const float SS_FINE_LAYER = 2.0;

// WHY THIS BAND'S MAPPING LOOKS THE WAY IT DOES (the mechanism itself is ss_shell_plane_base above,
// transliterated from SSShell::planeBase in indra/newview/ssshellcore.h; this is the call site's own
// record of the calibration it passes in).
//
// One band's base UVs, and how much of the band survives. Intersect the view ray with the band's
// deck, anchor at the region centre, subtract the wind travel, and divide by a PINNED
// metres-per-uv (see THE TILE IS PINNED below). ss_ray_dir rides the dome mesh's Y-up local space (renderDome's 120 degree
// permute: local y is world UP, local x is world Y, local z is world X), so the horizontal
// components reach deck_m as (ray.z, ray.x) - east, north, matching region_offset's (world X,
// world Y) order.
//
// THE TILE IS PINNED - deliberately free of the band's HEIGHT, and of the Scale dial's
// CONTINUOUS play only because the dial is re-added as the crossfade built on this function (see
// the branch calls in main). One tile is one fixed piece of world: the height above the camera
// survives into the pattern (vertical parallax, on the flat fallback too), altitude changes slide
// instead of zoom. What `scale` does here is pick WHICH pin the plane samples at: the divisor is
// p.tileM * scale / p.scaleAnchor, so an authored 0.25 is identity - the exact
// pre-dial render - and any other authored value tiles the pattern by that factor (wider for
// larger, like the stock divide-by-cloud_scale it restores). (An earlier cut anchored the tile at
// 2*alt*cloud_scale - stock EEP's zenith calibration - which matched stock at any altitude but
// breathed the pattern as the band moved and cancelled the vertical parallax out of the static
// pattern entirely.)
//
// THE DECK CURVES. With ss_planet_orbit_m set, the ray meets a SPHERE centred on the planet at
// radius orbit + deck height - the deck is a finite disc that terminates at its own curved horizon
// (the tangent elevation sqrt(2*alt/orbit), about 1.4 degrees for a 1500 m deck under a 5000 km
// home planet) instead of stretching flat into the world's horizon line. The camera's own height
// rides the orbit uniform, so the shell stays at its world altitude while you fly: rising toward
// it brings its rim up and over. Above the shell the near intersection switches to the minus root
// and only down-rays hit - the deck seen from above. Orbit 0 keeps the flat-deck fallback.
//
// The flat fallback's denominator is SOFTENED, not clamped: (1+F)*alt / (|up| + F) is smooth in
// the ray everywhere, exact at the zenith, and caps the deck distance at ~10 band-altitudes in
// the horizon fold. The old hard max(up, 0.02) clamp did two kinds of damage the horizon fade
// never hid: below ~1.2 degrees it froze the UVs into an azimuth-only field, which smears the
// band into vertical stripes toward the horizon, and exactly on the clamp line the screen-space
// derivative jumps, which collapses the mip selection into a grid of tile boundaries in the
// distance. The sphere needs no fold: it is smooth to its own edge and bounded beyond it.
//
// The world-anchored terms - camera travel and wind drift - run DAMPED: the shipped vertex nudge
// moved at one eighth of the plane-honest rate (its /16 compensation over the stock 2*cs-radian
// zenith tile, hand-tuned in the live viewer), and the undamped plane rate read as the deck
// swimming. The ray's own hit keeps the honest geometry; only the terms that MOVE are damped, so
// the motion matches the version the eye tuned. Sign conventions are the old vertex patches':
// world north runs down the texture's v, and the wind travel negates the same way.
//
// NO DOMAIN WARP. An earlier cut ran three nested warp levels at incommensurate frequencies and
// rotated frames - an attempt at aperiodic tiling against the pinned tile, where the same
// clumps can genuinely march across the sky in rows toward the horizon. It read as smear and
// buckle, not as aperiodicity: a displacement field sampled from the same map it displaces is
// itself periodic, so the warped grid was still a grid, just bent. The mapping is a straight,
// honest lookup now - the repetition is softened by the fine octave's distance fade and by an
// authored large map (ss_noise_large) art-directing the broad octave when one is set.
// <SS:Nexii> The cirrus band's call site: bind this band's uniforms and its own nine constants to the shared shell mapping above. The body that used to live here is ss_shell_plane_base, transliterated from SSShell::planeBase; nothing about the render changes, and the harness proves that rather than asserting it (twin_shell.cpp SS_CHECK_BITS's the core against a transliteration of the PRE-refactor spelling of this function over a grid of altitudes, rays, scales, offsets, drifts and orbits, including the flat fallback).
vec2 ss_plane_base(float alt, float scale, out float plane_fade, out float detail_fade)
{
    float reach_m;
    return ss_shell_plane_base(ss_planet_orbit_m, alt, ss_ray_dir, scale,
                               region_offset, ss_cloud_drift, ss_shell_cirrus(),
                               plane_fade, detail_fade, reach_m);
}

// The curved deck's own horizon fade (mechanism: ss_shell_edge_fade above, SSShell::edgeFade in the
// core). The layer ends at the rim its discriminant defines - sqrt(2*alt/orbit) to first order - and
// the last stretch before the rim compresses endlessly, so the band dissolves across the approach:
// alpha zero at the rim, full a fraction of the rim's elevation away from it. The edge reads as a
// curved cloud horizon melting into the atmosphere rather than a smeared seam. BOTH faces melt now;
// on the far face the rim is a real miss boundary (flatter rays pass over the shell), on the near
// face it is the elevation at which the shell crosses the camera's own horizontal plane.
//
// <SS:Nexii> The melt's TOP follows the volumetric deck's perceived edge (ss_deck_edge_sin) when one stands over the camera. The deck's own field ends at ~4.9 km horizontal - several degrees UP the sky from the band's rim - and past that edge the band has no cloud in front of it, so letting it run saturated to the waterline painted a flat grey plane across the whole span between the deck's edge and the horizon. The melt now spends that span: full at the deck's edge, gone at the rim. No deck, or the camera up near the deck's top (its edge sine below the old window's top), keeps the old narrow melt.
// <SS:Nexii> The cirrus band's call site for the rim melt. The `alt < 0.0` early-out this function used to carry - a layer below the camera got no melt at all, so it painted the whole lower hemisphere solid - is gone: ss_shell_edge_fade melts BOTH faces against the rim its own discriminant defines. Nothing on this band's face changes (unit_edge_fade_above_bit_identical), and the far face now ends on a curved horizon.
float ss_deck_edge_fade(float alt)
{
    SSShellPlane p = ss_shell_cirrus();
    return ss_shell_edge_fade(ss_planet_orbit_m, alt, ss_ray_dir.y, ss_deck_edge_sin, p.meltGain);
}
#endif


void main()
{
#ifdef SS_ATMO
    // SKOOMA-PORT: the band's airlight below is cloudsV.glsl's former vertex stage, statement for statement, now
    // evaluated per fragment like Alchemy's stock path; its former varyings (vary_CloudColorSun/Ambient,
    // vary_CloudGlow, vary_CloudDensity, altitude_blend_factor, vary_ray_dir) are locals here.
    if (cloud_scale < 0.001)
    {
        discard;
    }

    // Get relative position
    // <SS:Nexii> The lift rides ss_ray_lift (see the uniform note above): 1 keeps the stock ray bit for bit, 0 aims the glow hotspot and the disc-neighbourhood restore at the true direction the Atmo discs draw at.
    vec3 rel_pos = pos.xyz - camPosLocal.xyz + vec3(0, 50.0 * ss_ray_lift, 0);

    // <SS:Nexii> The TRUE camera-relative view ray, for the plane mapping below (SKOOMA-PORT: now normalised per fragment). The lift is 0 whenever the plane path runs - an active Atmo environment - so this is the exact direction the ray actually travels, not the stock-fudged one.
    ss_ray_dir = normalize(pos.xyz - camPosLocal.xyz);

    // <SS:Nexii> The horizon fade decoupled from max altitude: dividing by max_y let the ATMOSPHERE ceiling thin every low-sky cloud - at an authored 1000m ceiling a cloud at the horizon sat at half alpha before anything else touched it, which is exactly the "sun disc through solid clouds" leak, and no amount of disc-side machinery could out-engineer an alpha the author never chose. A short fixed ramp keeps the horizon soft; the below-horizon droop cut below is untouched. (Eased back a touch from the first cut of (y+100)/200, which held clouds fully solid to ~1 degree and read as too hard a wall at the waterline.)
    float altitude_blend_factor = clamp((rel_pos.y + 90.0) / 300.0, 0.0, 1.0);

    // ...except INTO the sun: the eased fade reads beautifully against sky but lets the disc burn through the same half-faded clouds, and the two aesthetics only collide inside the disc's
    // angular neighbourhood - so exactly there, and nowhere else, horizon clouds keep their body. The ramp spans roughly the width of a large authored sun disc.
    // <SS:Nexii> And the neighbourhood follows the DISC (ss_sun_dir), not the lightnorm: lightnorm hands the direction to the moon the moment the disc's centre sets, which silently revoked the restore for the still-half-risen disc - the clouds around it collapsed onto their eased fade, and the disc burned through them exactly at centre-set. See skyV.glsl's ss_sun_dir note. .yzx puts the world-axes ss_sun_dir into the ogl frame rel_pos and lightnorm share - see the frame note in skyV.glsl.
    vec3 disc_dir = (ss_sun_rise > 0.0) ? ss_sun_dir.yzx : lightnorm.xyz;
    float sun_prox = smoothstep(0.965, 0.992, dot(normalize(rel_pos), disc_dir));
    altitude_blend_factor = max(altitude_blend_factor, sun_prox);

    // Set altitude
    if (rel_pos.y > 0)
    {
        rel_pos *= (max_y / rel_pos.y);
    }
    if (rel_pos.y < 0)
    {
        altitude_blend_factor = 0; // SL-11589 Fix clouds drooping below horizon
        rel_pos *= (-32000. / rel_pos.y);
    }

    // Can normalize then
    vec3  rel_pos_norm = normalize(rel_pos);
    float rel_pos_len  = length(rel_pos);

    // Initialize temp variables
    vec3 sunlight = sunlight_color;
    vec3 light_atten;

    // <SS:Nexii> THE AIRLIGHT, ONE AUTHORITY (doc/atmo_magic_phase8_show.md section 5b). Everything from this line down to oHazeColorBelowCloud is a transliteration of indra/newview/ssairlightcore.h: that header holds the formulas, this block spells its function bodies statement for statement in GLSL (a shader cannot include a C++ header, so the transliteration IS the wiring), and V:\Scratch\atmo\tests\twin_airlight.cpp reads this file's text and asserts the core reproduces every intermediate of it bit-for-bit. Each site below names the core function it is. Where this file used to disagree with skyV.glsl - the zero-density weight guard, the ambient headroom clamp, the shadow-dim clamp and the non-Atmo glow's grouping - it now says exactly what skyV says, which is what the core says; the reason is written at each of those four sites.
    // Sunlight attenuation effect (hue and brightness) due to atmosphere
    // this is used later for sunlight modulation at various altitudes
    // <SS:Nexii> ssairlightcore.h : lightAtten() - the haze share and the (multiplier * ceiling) product are grouped exactly as the core groups them, which is what makes the twin's equality bit-for-bit rather than algebraic.
    light_atten = (blue_density + vec3(haze_density * 0.25)) * (density_multiplier * max_y);

    // <SS:Nexii> While the rise band is live, the sun's term in the light path floors at the DISC'S OWN half-angle (ss_sun_radius) - see the long note in skyV.glsl. Stock collapses every ray near the horizon to unlit the moment the disc's CENTRE dips under, cutting the sunset band out from under a disc that is still half up; elevation 0 is the infinite airmass, not the horizon-sitting one, so the floor holds the just-cleared path (1/radius at the horizon line) through the whole rise, and the dusk below the horizon keeps it while the band's share fades the glow out. The floor releases once the centre clears the radius and the gate is stock with it off.
    float sun_elev = (ss_sun_rise > 0.0) ? max(ss_sun_dir.z, ss_sun_radius) : lightnorm.y;

    // Calculate relative weights
    // <SS:Nexii> ssairlightcore.h : hazeSplit(), transliterated - and the max() is the core's DENSITY_FLOOR, which this file did not carry and skyV.glsl always has. The weights DIVIDE by this sum, so a sky authored with a black blue_density and haze_density 0 divided zero by zero here and handed every cirrus vertex NaN weights - and that sky is two clicks away, not a degenerate impossibility: blue_density is a colour swatch (reaches black) and haze_density a slider whose floor is exactly 0 (panel_ss_atmo_env_sky_scattering.xml, panel_settings_sky_atmos.xml), both inside EEP's own validated ranges (blue_density [0,3] per channel, haze_density [0,5]; llsettingssky.cpp legacyHazeValidationList). Guarded, the weights are 0 there instead of NaN. Identical to the old line for every summed density >= 1e-6, which every non-degenerate authored sky is by about five orders of magnitude - twin_airlight.cpp measures both halves of that claim.
    vec3 combined_haze = max(abs(blue_density) + vec3(abs(haze_density)), vec3(1e-6));
    vec3 blue_weight   = blue_density / combined_haze;
    vec3 haze_weight   = haze_density / combined_haze;

    // Compute sunlight from rel_pos & lightnorm (for long rays like sky)
    // <SS:Nexii> ssairlightcore.h : offAxis() - the airmass the beam crosses to reach this point, as a multiple of the vertical path.
    float off_axis = 1.0 / max(1e-6, max(0., rel_pos_norm.y) + sun_elev);
    // The pre-attenuation light, kept for the glow's own extinction below - see skyV.glsl.
    vec3 ss_raw_light = sunlight;
    // <SS:Nexii> ssairlightcore.h : beamToElevation() - the beam's extinction to this elevation, and the only place the sunset's reddening comes from.
    sunlight *= exp(-light_atten * off_axis);

    // Distance
    // <SS:Nexii> ssairlightcore.h : pathTransmittance() - density_dist then the exp, in the core's own two steps.
    float density_dist = rel_pos_len * density_multiplier;

    // Transparency (-> combined_haze)
    // ATI Bugfix -- can't store combined_haze*density_dist in a variable because the ati
    // compiler gets confused.
    combined_haze = exp(-combined_haze * density_dist);

    // Compute haze glow
    // <SS:Nexii> The glow tracks the disc (ss_sun_dir), not the lightnorm - lightnorm belongs to the moon below centre-set, and the layer's glow must stay on the sun while any part of it is in sight. See the ss_sun_dir note above and in skyV.glsl. .yzx puts the world-axes ss_sun_dir into the ogl frame rel_pos and lightnorm share - see the frame note in skyV.
    vec3 glow_dir = (ss_sun_rise > 0.0) ? ss_sun_dir.yzx : lightnorm.xyz;
    float haze_glow = 1.0 - dot(rel_pos_norm, glow_dir);
    // haze_glow is 0 at the sun and increases away from sun
    haze_glow = max(haze_glow, .001);
        // Set a minimum "angle" (smaller glow.y allows tighter, brighter hotspot)
    haze_glow *= glow.x;
        // Higher glow.x gives dimmer glow (because next step is 1 / "angle")
    haze_glow = pow(haze_glow, glow.z);
        // glow.z should be negative, so we're doing a sort of (1 / "angle") function

    // <SS:Nexii> The glow is the light the disc sheds, so while the rise band is live it is built from the RAW angular term and scaled by the horizon-band share - full strength the whole time the disc is up (the stock sun line, and the condition the authored skies painted against), easing out across the twilight below the horizon. Stock's factor lines cannot be allowed to touch it in the band: below centre-rise the factor belongs to the moon (< 1.0), whose branch zeroes the term entirely (SL-13768 - right for the moon, which must not glow), and ramping on the zeroed term grew a FLAT 0.25 wash with no hotspot at all until the factor snapped to 1.0 at centre-rise - the sunrise horizon simply was not there while the disc poked over. See the matching note in skyV.glsl. With the gate off, stock.
    if (ss_sun_rise > 0.0)
    {
        haze_glow = ss_sun_rise * (haze_glow + 0.25);
    }
    else
    {
        // Add "minimum anti-solar illumination"
        // For sun, add to glow.  For moon, remove glow entirely. SL-13768
        // <SS:Nexii> ONE SPELLING with skyV.glsl. This branch used to scale the angular term by the factor on its own line and then add the floor - `f * haze_glow + 0.25` - while skyV.glsl reads `f * (haze_glow + 0.25)` - the same expression only when f is exactly 1, and the old form left the anti-solar FLOOR at full strength under a dimmed light while the hotspot was scaled. skyV's grouping is the one kept: the 0.25 is part of the glow's light and dims with it. This is not a behaviour change at any value the viewer binds - LLSettingsSky::getSunMoonGlowFactor() returns exactly 1.0 with the sun up and moon_brightness * 0.25 (<= 0.25, so < 1) otherwise, and the ternary zeroes both forms below 1 - which twin_airlight.cpp asserts over the bound set with an unreachable f = 1.5 as its failing control. The term is ANGULAR, not air, so ssairlightcore.h deliberately does not own it (see its header note); the two shaders still have to say it the same way.
        haze_glow = (sun_moon_glow_factor < 1.0) ? 0.0 : (sun_moon_glow_factor * (haze_glow + 0.25));
    }

    // <SS:Nexii> The layer's glow rides the same capped light as the dome (see the long note in skyV.glsl): the extinction crush is bounded - airmass floored at the depth where the densest channel has shed SS_SUN_GLOW_DEPTH optical depths, scaled uniformly so the hue survives - and binds only where the beam maths would total the colour. It is a ceiling, not a window: no edge to see, the sunset band simply keeps its fire. Live only while the rise band is; idle environments keep stock bit for bit.
    vec3 ss_glow_light = sunlight;
    if (ss_sun_rise > 0.0)
    {
        float ss_max_atten = max(light_atten.r, max(light_atten.g, light_atten.b));
        float ss_glow_airmass = min(off_axis, SS_SUN_GLOW_DEPTH / max(ss_max_atten, 1e-6));
        ss_glow_light = ss_raw_light * exp(-light_atten * ss_glow_airmass);
    }

    // Increase ambient when there are more clouds
    // <SS:Nexii> ssairlightcore.h : ambientUnderClouds(), transliterated - and the ONE site in this consolidation that is a real behaviour change rather than a guard on input nothing can bind. The stock comment above says "increase ambient when there are more clouds"; without the max() an ambient above 1 does the opposite, because the headroom (1 - ambient) goes negative and cover DARKENS the sky. Ambient above 1 is not off-range: it is the top two thirds of Atmo's own ambient dial (SSFloaterAtmoEnv scales that colour swatch by SCALE_SUN_AMBIENT = 3) and well inside EEP's validator ([0,3] per channel). So at an authored ambient of 1.4 under the default cover 0.2699 this line used to hand the cirrus band a 1.346 ambient while skyV.glsl handed the dome 1.4 - and the band and the dome are built to land on the SAME colour at the rim (section 5b's handoff, which is what phase 8c's shell inherits). skyV's guard is adopted: the lift is monotone in cover at every ambient, the band meets the dome again, and every ambient <= 1 is bit-identical to the old line. twin_airlight.cpp measures the identity below 1 and the size of the change above it. Note this ambient is also the cloud body's own (cloudColorAmbient below), which is the same lifted value skyV composes with - one ambient, one spelling.
    vec3 tmpAmbient = ambient_color + max(vec3(0), (1. - ambient_color)) * cloud_shadow * 0.5;

    // Dim sunlight by cloud shadow percentage
    // <SS:Nexii> ssairlightcore.h : dimByCloudShadow(). The max() is skyV.glsl's and is INERT here - measured, not inferred: cloud_shadow is bound from the dome's coverage dial, whose slider AND spinner are both [0,1] (panel_ss_atmo_env_clouds_dome.xml) through an identity modulation (SSAtmoEnvSkyModulation::cloudCoverage with mCoverTarget frozen at 0), and EEP validates SETTING_CLOUD_SHADOW to [0,1] as well. twin_airlight.cpp asserts old and new bit-identical across that whole range, with the divergence above 1 - where the unguarded form NEGATES the light - as the failing control.
    sunlight *= max(0.0, (1. - cloud_shadow));
    ss_glow_light *= max(0.0, (1. - cloud_shadow));

    // Haze color below cloud
    // <SS:Nexii> ssairlightcore.h : skyColor() - two scattering populations, each taking its share of the beam and the ambient, grouped left to right as the core groups them. This is the composition skyV.glsl spells twice (above and below cloud) and the volumetric deck spells once; the core is the authority for all of them.
    vec3 additiveColorBelowCloud =
        (blue_horizon * blue_weight * (sunlight + tmpAmbient) + (haze_horizon * haze_weight) * (ss_glow_light * haze_glow + tmpAmbient));

    // CLOUDS
    sunlight = sunlight_color;
    off_axis = 1.0 / max(1e-6, lightnorm.y * 2.);
    sunlight *= exp(-light_atten * off_axis);

    // Cloud color out
    // <SS:Nexii> The glow SPLIT OUT of the cloud body colour instead of multiplied into it: haze_glow is the sky's forward-scatter airlight, which lives BEHIND a cloud - baked into cloudColorSun it recoloured every cloud in a wide cone around the sun toward the glow, when a backlit cloud is a dark silhouette whose thin fringes alone transmit the fire. The fragment shader gates it by per-fragment thinness; the body keeps glow-free sunlight.
    vec3 cloudColorSun = sunlight * cloud_color;
    float cloudGlow     = haze_glow;
    vec3 cloudColorAmbient = tmpAmbient * cloud_color;

    // Attenuate cloud color by atmosphere
    // <SS:Nexii> Full-strength optical depth, no sqrt: the stock halving left horizon clouds crisp, which never showed while the max_y alpha fade was thinning them into the sky anyway - with that fade decoupled, the honest colour convergence has to carry the melt alone. This is the density/distance dials doing on the dome band exactly what they do on the volumetric deck: cloud extinguishes and takes on the airlight over the same slab path the sky itself is hazed by, so at the horizon the band dissolves into the atmosphere instead of silhouetting against it.
    cloudColorSun *= combined_haze;
    cloudColorAmbient *= combined_haze;
    // <SS:Nexii> ssairlightcore.h : airlightOverPath() - the light this path has scattered into the eye, weighted by exactly the complement of what the path let through. As the transmittance goes to zero this goes to the pure below-cloud sky colour, which is what skyV.glsl's dome blend lands on at the horizon too: that coincidence is the rim handoff section 5b's shell is built on, and it is only a handoff while both sides read the same composition - which is what this rewire makes true.
    vec3 oHazeColorBelowCloud = additiveColorBelowCloud * (1. - combined_haze);

    // Make a nice cloud density based on the cloud_shadow value that was passed in.
    float cloudDensity = 2. * (cloud_shadow - 0.25);

    // Combine these to minimize register use
    cloudColorAmbient += oHazeColorBelowCloud;

    // The four texcoords: base, base plus the self-shadow offset, and both at the fine multiplier
    // for the fine layers. Stock derives them per-vertex from the dome mesh's own mapping; the
    // Atmo plane path derives the base per-fragment from the view ray (see ss_plane_base) and
    // rebuilds the other three from it with stock's own offsets, so the two paths agree about WHAT
    // each coordinate is and differ only about where it comes from. Either way the coordinates
    // feed ss_cloud_branch - one plate per Scale endpoint where the dial is keyframed mid-fade.
    float alpha1;
    float alpha2;
    float deck_edge_fade = 1.0;
    float plane_fade = 1.0;
    float detail_fade = 1.0;

    if (ss_cloud_plane > 0.0)
    {
        // <SS:Nexii> The Scale crossfade (the Sky Dome tab's Scale dial, keyframed across the day cycle). The sky's own cloud_scale uniform holds the fade's FROM endpoint - the applier keeps valueAt there (blendAt's from is the same keyframe) - and ss_cloud_scale_to names the TO endpoint with the eased weight. Both endpoints run the whole density chain at THEIR tile (SS_SCALE_ANCHOR makes an authored 0.25 the pre-dial anchor pin), and the two resulting opacities are mixed by the weight: the two endpoint-scale renderings crossfade, the divisor between them is never interpolated. An interpolated divisor is the erratic motion this replaces - zooming the tile mid-fade drags every feature sideways as the pivot point moves, reading as the clouds creeping when they should stand still. The TO plate is the FROM base scaled by from/to: the plane base is a pure metres/divisor quotient, so the partner is the same ray, the same fades and the same anchor - one geometric intersection, no recompute. A live Cloud Image crossfade composes exactly: its two maps are mixed inside cloudNoise(), which both plates call after their own UVs, so the two dials fade on their own axes regardless of where each set its keyframes.
        float scale_from = cloud_scale;
        float scale_to   = ss_cloud_scale_to;
        float scale_blend = (scale_from > 0.001 && scale_to > 0.001) ? ss_cloud_scale_blend : 0.0;

        vec2 base_from = ss_plane_base(ss_cloud_alt_m, scale_from, plane_fade, detail_fade);
        vec2 base_to   = (scale_blend > 0.0)
                       ? base_from * (scale_from / scale_to)
                       : base_from;

        float alpha1_a, alpha2_a;
        ss_cloud_branch(base_from,
                        base_from + vec2(lightnorm.x, lightnorm.z) * 0.0125,
                        base_from * SS_FINE_LAYER,
                        (base_from + vec2(lightnorm.x, lightnorm.z) * 0.0125) * SS_FINE_LAYER,
                        scale_from, cloudDensity, detail_fade, alpha1_a, alpha2_a);
        if (scale_blend > 0.0)
        {
            float alpha1_b, alpha2_b;
            ss_cloud_branch(base_to,
                            base_to + vec2(lightnorm.x, lightnorm.z) * 0.0125,
                            base_to * SS_FINE_LAYER,
                            (base_to + vec2(lightnorm.x, lightnorm.z) * 0.0125) * SS_FINE_LAYER,
                            scale_to, cloudDensity, detail_fade, alpha1_b, alpha2_b);
            alpha1 = mix(alpha1_a, alpha1_b, scale_blend);
            alpha2 = mix(alpha2_a, alpha2_b, scale_blend);
        }
        else
        {
            alpha1 = alpha1_a;
            alpha2 = alpha2_a;
        }
        deck_edge_fade = ss_deck_edge_fade(ss_cloud_alt_m);
    }
    else
    {
    ss_cloud_branch(vary_texcoord0.xy, vary_texcoord1.xy, vary_texcoord2.xy, vary_texcoord3.xy,
                    cloud_scale, cloudDensity, 1.0, alpha1, alpha2);
    }

    alpha1 *= altitude_blend_factor * deck_edge_fade * plane_fade;
    alpha1 = clamp(alpha1, 0.0, 1.0);

    // Combine
    vec3 color;
    // <SS:Nexii> The glow reaches a fragment only through its THINNESS: the forward-scatter fire belongs to the airlight behind the cloud, so a dense core stays a dark silhouette right up to the disc's edge (it gets only the anti-solar base the stock far-field carries) while the ragged fringes transmit the full glow and catch fire - which is what every backlit-cloud photograph shows and the baked-in glow never could. Far from the sun haze_glow sits near its 0.25 floor, below the base cap, so open-sky cloud shading is unchanged.
    float glow_thin = (1.0 - alpha1) * (1.0 - alpha1);
    float glow_gate = mix(min(cloudGlow, 0.35), cloudGlow, glow_thin);
    color = (cloudColorSun*(1.-alpha2)*glow_gate + cloudColorAmbient);
    color.rgb = clamp(color.rgb, vec3(0), vec3(1));
    color.rgb *= 2.0;

#else
    if (cloud_scale < 0.001)
    {
        discard;
    }

    // Set variables
    vec2 uv1 = vary_texcoord0.xy;
    vec2 uv2 = vary_texcoord1.xy;
    vec2 uv3 = vary_texcoord2.xy;
    vec2 uv4 = vary_texcoord3.xy;

    // Get relative position
    vec3 rel_pos = pos.xyz - camPosLocal.xyz + vec3(0, 50, 0);

    float altitude_blend_factor = clamp((rel_pos.y + 512.0) / max_y, 0.0, 1.0);

    // Set altitude
    if (rel_pos.y > 0)
    {
        rel_pos *= (max_y / rel_pos.y);
    }
    if (rel_pos.y < 0)
    {
        altitude_blend_factor = 0; // SL-11589 Fix clouds drooping below horizon
        rel_pos *= (-32000. / rel_pos.y);
    }

    // Can normalize then
    vec3  rel_pos_norm = normalize(rel_pos);
    float rel_pos_len  = length(rel_pos);

    // Initialize temp variables
    vec3 sunlight = sunlight_color;
    vec3 light_atten;

    // Sunlight attenuation effect (hue and brightness) due to atmosphere
    // this is used later for sunlight modulation at various altitudes
    light_atten = (blue_density + vec3(haze_density * 0.25)) * (density_multiplier * max_y);

    // Calculate relative weights
    vec3 combined_haze = abs(blue_density) + vec3(abs(haze_density));
    vec3 blue_weight   = blue_density / combined_haze;
    vec3 haze_weight   = haze_density / combined_haze;

    // Compute sunlight from rel_pos & lightnorm (for long rays like sky)
    float off_axis = 1.0 / max(1e-6, max(0., rel_pos_norm.y) + lightnorm.y);
    sunlight *= exp(-light_atten * off_axis);

    // Distance
    float density_dist = rel_pos_len * density_multiplier;

    // Transparency (-> combined_haze)
    // ATI Bugfix -- can't store combined_haze*density_dist in a variable because the ati
    // compiler gets confused.
    combined_haze = exp(-combined_haze * density_dist);

    // Compute haze glow
    float haze_glow = 1.0 - dot(rel_pos_norm, lightnorm.xyz);
    // haze_glow is 0 at the sun and increases away from sun
    haze_glow = max(haze_glow, .001);
    // Set a minimum "angle" (smaller glow.y allows tighter, brighter hotspot)
    haze_glow *= glow.x;
    // Higher glow.x gives dimmer glow (because next step is 1 / "angle")
    haze_glow = pow(haze_glow, glow.z);
    // glow.z should be negative, so we're doing a sort of (1 / "angle") function

    haze_glow *= sun_moon_glow_factor;

    // Add "minimum anti-solar illumination"
    // For sun, add to glow.  For moon, remove glow entirely. SL-13768
    haze_glow = (sun_moon_glow_factor < 1.0) ? 0.0 : (haze_glow + 0.25);

    // Increase ambient when there are more clouds
    vec3 tmpAmbient = ambient_color;
    tmpAmbient += (1. - tmpAmbient) * cloud_shadow * 0.5;

    // Dim sunlight by cloud shadow percentage
    sunlight *= (1. - cloud_shadow);

    // Haze color below cloud
    vec3 additiveColorBelowCloud =
        (blue_horizon * blue_weight * (sunlight + tmpAmbient) + (haze_horizon * haze_weight) * (sunlight * haze_glow + tmpAmbient));

    // CLOUDS
    sunlight = sunlight_color;
    off_axis = 1.0 / max(1e-6, lightnorm.y * 2.);
    sunlight *= exp(-light_atten * off_axis);

    // Cloud color out
    vec3 cloudColorSun = (sunlight * haze_glow) * cloud_color;
    vec3 cloudColorAmbient = tmpAmbient * cloud_color;

    // Attenuate cloud color by atmosphere
    combined_haze = sqrt(combined_haze);  // less atmos opacity (more transparency) below clouds
    cloudColorSun *= combined_haze;
    cloudColorAmbient *= combined_haze;
    vec3 oHazeColorBelowCloud = additiveColorBelowCloud * (1. - combined_haze);

    // Make a nice cloud density based on the cloud_shadow value that was passed in.
    float cloudDensity = 2. * (cloud_shadow - 0.25);

    // Combine these to minimize register use
    cloudColorAmbient += oHazeColorBelowCloud;

    // Cloud Fragment
    vec2 disturbance  = vec2(cloudNoise(uv1 / 8.0f).x, cloudNoise((uv3 + uv1) / 16.0f).x) * cloud_variance * (1.0f - cloud_scale * 0.25f);
    vec2 disturbance2 = vec2(cloudNoise((uv1 + uv3) / 4.0f).x, cloudNoise((uv4 + uv2) / 8.0f).x) * cloud_variance * (1.0f - cloud_scale * 0.25f);

    // Offset texture coords
    uv1 += cloud_pos_density1.xy + (disturbance * 0.2);    //large texture, visible density
    uv2 += cloud_pos_density1.xy;   //large texture, self shadow
    uv3 += cloud_pos_density2.xy;   //small texture, visible density
    uv4 += cloud_pos_density2.xy;   //small texture, self shadow

    float density_variance = min(1.0, (disturbance.x* 2.0 + disturbance.y* 2.0 + disturbance2.x + disturbance2.y) * 4.0);

    cloudDensity *= 1.0 - (density_variance * density_variance);

    // Compute alpha1, the main cloud opacity

    float alpha1 = (cloudNoise(uv1).x - 0.5) + (cloudNoise(uv3).x - 0.5) * cloud_pos_density2.z;
    alpha1 = min(max(alpha1 + cloudDensity, 0.) * 10 * cloud_pos_density1.z, 1.);

    // And smooth
    alpha1 = 1. - alpha1 * alpha1;
    alpha1 = 1. - alpha1 * alpha1;

    alpha1 *= altitude_blend_factor;
    alpha1 = clamp(alpha1, 0.0, 1.0);

    // Compute alpha2, for self shadowing effect
    // (1 - alpha2) will later be used as percentage of incoming sunlight
    float alpha2 = (cloudNoise(uv2).x - 0.5);
    alpha2 = min(max(alpha2 + cloudDensity, 0.) * 2.5 * cloud_pos_density1.z, 1.);

    // And smooth
    alpha2 = 1. - alpha2;
    alpha2 = 1. - alpha2 * alpha2;

    // Combine
    vec3 color;
    color = (cloudColorSun*(1.-alpha2) + cloudColorAmbient);
    color.rgb = clamp(color.rgb, vec3(0), vec3(1));
    color.rgb *= 2.0;

#endif

    /// Gamma correct for WL (soft clip effect).

    frag_data[1] = vec4(0.0,0.0,0.0,0.0);
    frag_data[2] = vec4(0,0,0,GBUFFER_FLAG_SKIP_ATMOS);

#if defined(HAS_EMISSIVE)
    frag_data[0] = vec4(0);
    frag_data[3] = vec4(ditherEmissive(color.rgb, gl_FragCoord.xy), alpha1);
#else
    frag_data[0] = vec4(color.rgb, alpha1);
#endif
}

