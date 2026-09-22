/**
 * @file class1/deferred/skyF.glsl
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

// Outputs
out vec4 frag_data[4];

// Inputs
in vec3 pos;

#ifdef HAS_HDRI
in vec4 vary_position;
uniform float sky_hdr_scale;
uniform float hdri_split_screen;
uniform mat3 env_mat;
uniform sampler2D environmentMap;
#endif

uniform sampler2D rainbow_map;
uniform sampler2D halo_map;

uniform float moisture_level;
uniform float droplet_radius;
uniform float ice_level;

uniform vec3 camPosLocal;

uniform vec3  lightnorm;
uniform vec3  sunlight_color;
uniform vec3  moonlight_color;
uniform int   sun_up_factor;
uniform vec3  ambient_color;
// Shared per-frame sky/water constants, spliced from class1/deferred/environmentBlock.glsl
// and bound at UB_ENVIRONMENT. Members are read by bare name.
//[ENGINE_BLOCK Environment]

uniform float density_multiplier;

uniform float sun_moon_glow_factor;

uniform int cube_snapshot;

#ifdef SS_ATMO
// <SS:Nexii> Below-horizon ray treatment: 1 mirrors the ray (Atmo look), 0 leaves the stock -32000 collapse. Zero unless an ACTIVE Atmo environment is driving the sky (lldrawpoolwlsky.cpp), so an enabled-but-idle viewer's EEP sky stays stock.
uniform float ss_horizon_mirror;


// <SS:Nexii> The sun's horizon-band share (SSAtmoEnvApplier::sunRiseFraction): 1 the whole time the disc's centre stands at or above the horizon, easing smoothly to 0 across the twilight band below it; 0 also means no active Atmo environment, which is exactly stock. The dome's light and its sun glow are ramped on this below. Stock switches BOTH the moment the disc's centre crosses zero - and the first cut of the ramp ran it across the disc's own span, which scaled the glow down by the risen share of the disc and halved the sunset exactly where the authored skies put it at full strength. So the band runs DOWN from the horizon instead: the disc's light hits the atmosphere long before the disc reaches the horizon and keeps lighting it long after, and the ramp now honours both - full glow from centre-rise to centre-set, the dusk easing out below.
uniform float ss_sun_rise;

// <SS:Nexii> The sun's TRUE direction while the rise band is live (SSAtmoEnvApplier::sunSlotDirection). The shared lightnorm direction switches from the sun to the moon the moment the disc's CENTRE sets (LLSettingsSky::getLightDirection) - stock never saw it because stock zeroes the glow and culls the disc below the horizon, but the ramps keep both alive through the whole band, dusk included, and the takeover rule is sun > moon until the band is spent: the glow and the extinction below keep aiming at the SUN while ss_sun_rise is positive, and the moon takes the lightnorm back only once it is not.
uniform vec3 ss_sun_dir;


// <SS:Nexii> The optics' light colour's MOONLIGHT fallback, bound by the sky pool: while no sun band is live the optics are the moonlight family, which deliberately keeps its faint white tint (moonlight optics are not wired to their own light yet). The sun-band case is computed in main() below (ss_optic_tint); this uniform only stands in below the band.
uniform vec3 ss_optic_sun_col;

// <SS:Nexii> The stock ray lift. The atmosphere ray below is computed 50 m above the geometry it belongs to (the + vec3(0, 50, 0) in rel_pos), a legacy fudge that once rode along with the stock sun disc's own legacy 50 m drop (sunDiscV.glsl) - glow hotspot and drawn disc wrong together, which passed for agreement. The Atmo discs draw at the TRUE direction (ssCelestialV.glsl carries no offset of any kind), so while they own the sky the lift drops to 0 and the glow hotspot lands on the disc: 50 m of lift at the ~5000 m dome is 0.57 degrees, about one sun-diameter of visible droop. 1 is exactly stock - 50 * 1.0 is the same ray bit for bit - which is what an enabled-but-idle viewer keeps.
uniform float ss_ray_lift;

// <SS:Nexii> The glow light's extinction ceiling, in optical depths on the densest attenuation channel. 2.0 is the warm-orange horizon band of a real sunset - deep enough to burn, shallow enough to stay bright; raise it toward the darker reds, lower it toward the golds. See the long note at the glow light below.
const float SS_SUN_GLOW_DEPTH = 2.0;

// <SS:Nexii> How far below the horizon line the sun's glow and haze effects fade out over when the clip is on, as a SINE of the angle below eye level - about a degree - so the cut reads the same from any camera height. See the fade at vary_ss_below_horizon below.
const float SS_SUN_HORIZON_FADE = 0.02;

// SKOOMA-PORT: C++ injects LL_SHADER_CONST_HORIZON_DEPTH via addConstant(SHADER_CONST_HORIZON_DEPTH); this
// fallback only keeps the variant compiling if a program forgets it. Keep the value equal to gShaderConstsVal.
#ifndef LL_SHADER_CONST_HORIZON_DEPTH
#define LL_SHADER_CONST_HORIZON_DEPTH 0.99993
#endif
#endif

#ifdef SS_ATMO
// SKOOMA-PORT: the sky's atmospherics run per fragment here (Alchemy moved them out of skyV), so what used to
// arrive as vary_ss_below_horizon / vary_ss_optic_sun_col are module globals main() fills before ss_optics() reads them.
uniform float ss_horizon_clip;
float ss_below_horizon_y;

// <SS:Nexii> Weather-driven optics (ss_optics below), bound from the sky pool's active Atmo applier. ss_optic_light is the light direction in the dome's own frame (the same permuted frame lightnorm lives in, with +Y up) and the amplitudes are the weather's corona / crystal drives. ss_optic_gate is 0 unless an ACTIVE Atmo environment is pushing at least one of them, so an idle viewer keeps stock halo_map exactly.
uniform vec3  ss_optic_light;
uniform float ss_optic_gate;
uniform float ss_optic_active;
uniform float ss_optic_corona;
uniform float ss_optic_halo22;
uniform float ss_optic_halo46;
uniform float ss_optic_align;

// <SS:Nexii> The optics' light colour, from the SUN only (for now): ss_optic_tint is the sun's own light as the DOME renders it, computed in main() below as the capped-glow light the sunset band actually burns with, evaluated along the light's ray - so the halos, arcs and sundogs keep their sunrise/sunset hue down through the horizon band and below it, where the old CPU-bound replica of the uncapped beam underflowed and snapped to the raw near-white authored colour. Ice-crystal optics scatter the SUN's light - a sundog is a mock sun - so while the sun is physically up the phenomena wear this tint whatever the scene-light handover says. Moonlight optics are not wired up yet; while no sun band is live the shader keeps the bound faint-white tint. The stock sunlight_color uniform is the raw authored colour, near-white even when everything red, so this explicit varying is the honest one.
vec3 ss_optic_tint;

// <SS:Nexii> The sun slot disc's half-angle as a direction-z sine (SSAtmoEnvApplier:: sunSlotRadius) - the same value skyV holds its airmass with. The corona scales its every angle by this relative to the stock quad's 0.05, so it stays a rim around WHATEVER disc is drawn rather than the fixed-angle aureole tuned for the old 10x quad.
uniform float ss_sun_radius;

// <SS:Nexii> The physical rainbow's gate (SSAtmoRainbow, lldrawpoolwlsky.cpp): 1 lets ss_rainbow below take the stock strip's place, 0 keeps the stock single bow bit for bit.
uniform float ss_rainbow_gate;

#endif

vec3 srgb_to_linear(vec3 c);
vec3 linear_to_srgb(vec3 c);

#define PI 3.14159265

/////////////////////////////////////////////////////////////////////////
// The fragment shader for the sky
/////////////////////////////////////////////////////////////////////////


vec3 rainbow(float d)
{
    // 'Interesting' values of d are -0.75 .. -0.825, i.e. when view vec nearly opposite of sun vec
    // Rainbox tex is mapped with REPEAT, so -.75 as tex coord is same as 0.25.  -0.825 -> 0.175. etc.
    // SL-13629
    // Unfortunately the texture is inverted, so we need to invert the y coord, but keep the 'interesting'
    // part within the same 0.175..0.250 range, i.e. d = (1 - d) - 1.575
    d         = clamp(-0.575 - d, 0.0, 1.0);

    // With the colors in the lower 1/4 of the texture, inverting the coords leaves most of it inaccessible.
    // So, we can stretch the texcoord above the colors (ie > 0.25) to fill the entire remaining coordinate
    // space. This improves gradation, reduces banding within the rainbow interior. (1-0.25) / (0.425/0.25) = 4.2857
    float interior_coord = max(0.0, d - 0.25) * 4.2857;
    d = clamp(d, 0.0, 0.25) + interior_coord;

    float rad = (droplet_radius - 5.0f) / 1024.0f;
    return pow(texture(rainbow_map, vec2(rad+0.5, d)).rgb, vec3(1.8)) * moisture_level;
}

#ifdef SS_ATMO
// <SS:Nexii> The physical rainbow, painted from the same strip texture the stock lookup reads. Stock sweeps one texcoord across the whole strip and adds whatever is there at one strength - the bow band and the bright interior stretch together - which is why the interior arrives as the blinding wash below the arc. The three phenomena the strip (and physics) carry are read separately here, each at its own strength: * the PRIMARY bow, the colour band at 34.4..41.4 deg off the antisolar point (red outer, violet inner), at ~30% - a real bow is a faint thing against the storm light behind it; * the INTERIOR brightening - light re-scattered inside the bow - on the stock stretch above the band, at ~8%: real photos show it, never as a wash; * the SECONDARY bow at ~49..55 deg, the same colour band read REVERSED (red inner, violet outer) at ~a third of the primary. Every rainbow is a double: the second bow rides two internal reflections instead of one and arrives faint. The gap between the bows is Alexander's band and renders as exactly nothing - darker than either bow in every photo. The light's own state then grades the result: a sun within a few degrees of the horizon has blue and green scattered away before the drops ever see it (the monochrome red rainbow), and a moonbow is too dim for the cones - the full spectrum is present but the eye reads white, at a fraction of the strength. The gate (ss_rainbow_gate) leaves the stock strip above untouched when the debug setting is down.
vec3 ss_rainbow(float d)
{
    if (moisture_level <= 0.0)
    {
        return vec3(0.0);
    }

    // Stock's remap, unclamped: t sweeps 0.175..0.25 across the band (red outer, violet
    // inner), 0.25..0.425 across the interior stretch, and 0..0.081 across the secondary's
    // angular window.
    float t   = -0.575 - d;
    float rad = (droplet_radius - 5.0f) / 1024.0f;

    // Primary bow: the band clamp, faded at the red edge where the strip hands over to black.
    // The (1 - w) share keeps it off the interior's half of the stretch.
    float w    = smoothstep(0.25, 0.258, t);
    float m_in = smoothstep(0.172, 0.178, t);
    vec3 bow = pow(texture(rainbow_map, vec2(rad + 0.5, clamp(t, 0.175, 0.25))).rgb, vec3(1.8));

    // Interior: the stock stretched lookup, dead until the violet edge has passed.
    vec3 interior = pow(texture(rainbow_map, vec2(rad + 0.5, 0.25 + max(t - 0.25, 0.0) * 4.2857)).rgb, vec3(1.8));

    // Secondary bow: the colour band reversed - s 1 is the red inner edge (t 0.081, 49 deg off
    // the antisolar point), s 0 the violet outer one (t 0.0, ~55 deg) - windowed so neither
    // edge smears into Alexander's band.
    float s     = clamp(t / 0.081, 0.0, 1.0);
    float m_sec = smoothstep(0.0, 0.005, t) * (1.0 - smoothstep(0.076, 0.081, t));
    vec3 secondary = pow(texture(rainbow_map, vec2(rad + 0.5, 0.25 - s * 0.075)).rgb, vec3(1.8));

    vec3 col = bow * (m_in * (1.0 - w)) * 0.30
             + interior * w * 0.08
             + secondary * m_sec * 0.09;

    col *= moisture_level;

    // The light's grade. lightnorm.y is the active light's elevation sine either way;
    // sun_up_factor says whether that light is the sun.
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    if (sun_up_factor == 0)
    {
        // Moonbow: needs a near-full moon to see at all, and the cones stand down - the
        // spectrum is present but reads white, at a quarter strength.
        col = mix(vec3(luma), col, 0.2) * 0.25;
    }
    else
    {
        // Red rainbow: the lower the sun, the longer the light path and the more of the short
        // wavelengths is scattered away before the drops ever see it. Full monochrome inside
        // two degrees of the horizon, gone by seven.
        float mono = 1.0 - smoothstep(1.0, 7.0, degrees(asin(clamp(lightnorm.y, -1.0, 1.0))));
        col = mix(col, vec3(luma) * vec3(0.85, 0.22, 0.07), mono);
    }
    return col;
}
#endif

vec3 halo22(float d)
{
    d       = clamp(d, 0.1, 1.0);
    float v = sqrt(clamp(1 - (d * d), 0, 1));
    return texture(halo_map, vec2(0, v)).rgb * ice_level;
}

#ifdef SS_ATMO
// Halo fringe colour: soft white, warmed toward the ring's inner edge and cooled on the outer -
// the classic red-inward / blue-outward halo tint, kept faint so halos read as clean light.
vec3 ss_optic_color(float rho, float ring, float width)
{
    float off = (rho - ring) / max(width, 1e-4);
    vec3 c = vec3(0.42, 0.45, 0.48);
    c += vec3(0.30, 0.10, -0.02) * (1.0 - smoothstep(-1.0, 0.2, off));
    c += vec3(-0.06, 0.02, 0.26) * smoothstep(-0.2, 1.0, off);
    return c;
}

// <SS:Nexii> A spectral gradient across a phenomenon's angular width - the prismatic colouring of the circumzenithal arc and (more vividly) the parhelic circle: red on the INNER edge through orange/yellow to blue-violet on the OUTER, the classic crystal-optics dispersion. off spans the width of the phenomenon (-.. + .. about the ring).
vec3 ss_prismatic(float off)
{
    vec3 red    = vec3(1.0, 0.35, 0.15);
    vec3 orange = vec3(1.0, 0.62, 0.20);
    vec3 yellow = vec3(1.0, 0.92, 0.45);
    vec3 green  = vec3(0.55, 0.92, 0.55);
    vec3 cyan   = vec3(0.4, 0.75, 1.0);
    vec3 blue   = vec3(0.35, 0.45, 1.0);
    float t = clamp(off * 0.5 + 0.5, 0.0, 1.0);   // -1 (inner,red) -> +1 (outer,blue)
    t = t * t * (3.0 - 2.0 * t);
    if (t < 0.25) return mix(red, orange, t * 4.0);
    if (t < 0.42) return mix(orange, yellow, (t - 0.25) * 5.88);
    if (t < 0.6)  return mix(yellow, green, (t - 0.42) * 5.56);
    if (t < 0.78) return mix(green, cyan, (t - 0.6) * 5.56);
    return mix(cyan, blue, (t - 0.78) * 4.55);
}

// Weather-driven split optics. The view ray and light direction share the sky dome's frame (+Y up,
// light permuted like lightnorm), so each phenomenon lands at its true angular position: the corona
// hugs the light, the 22 deg and 46 deg halos are rings at those radii, sundogs sit where the
// 22 deg small circle crosses the light's altitude plane, the parhelic circle is the THIN
// horizontal arc at the light's own altitude (the line the dogs ride on), the circumzenithal arc
// is a small circle around the zenith passing ~47 deg above the light (brightest with the light
// at 15-25 deg elevation, gone past ~32 deg), and the supralateral arc crowns the 46 deg ring
// while the light rides low. The amplitudes and the elevation gates come from the weather
// uniforms - a given sky may simply not be asking for a phenomenon.
vec3 ss_optics(vec3 view)
{
    if (ss_optic_corona <= 0.001 && ss_optic_halo22 <= 0.001
        && ss_optic_halo46 <= 0.001 && ss_optic_align <= 0.001)
    {
        return vec3(0.0);
    }

    vec3 light = normalize(ss_optic_light);
    const vec3 up = vec3(0.0, 1.0, 0.0);

    float rho  = degrees(acos(clamp(dot(view, light), -1.0, 1.0)));
    float elev = degrees(asin(clamp(light.y, -1.0, 1.0)));

    // The light's own vertical: 0 points up the vertical circle of the light, 90 the horizontal.
    vec3 vertical = normalize(up - light * dot(up, light));
    if (dot(up, light) > 0.998)      // light overhead: no usable vertical circle
    {
        vertical = vec3(0.0, 0.0, 1.0);
    }
    float psid = degrees(acos(clamp(dot(view, vertical), -1.0, 1.0)));

    // <SS:Nexii> The horizon-clip state as a mask: 1 everywhere the dome may draw - clip off, or this fragment above the horizon - and 0 under the clip. Every phenomenon except the sundogs multiplies by (1.0 - ss_below), so halos and arcs never paint below the horizon. The dogs alone reach a little UNDER it (their own block re-carves the margin), because the top of the light is still visible when its centre is just below the horizon.
    float ss_below = (ss_horizon_clip > 0.001 && ss_below_horizon_y < 0.0) ? 1.0 : 0.0;

    // <SS:Nexii> The 22 deg ring falls away as the light sinks toward the horizon: by ~14 deg of light elevation the ring has faded, leaving only the mock-sun sundogs flanking the light - the look of a low winter sun.
    float ring_elev = smoothstep(-1.0, 1.0, elev);

    vec3 col = vec3(0.0);

    // Corona: a thin bluish-white aureole hugging the light plus two faint diffraction rings
    // beyond it (water drops). Kept small and dim - the aureole is half gone by ~0.4 deg and
    // dead by ~1 deg, so a corona reads as a rim around the disc, never a glow that doubles it.
    // Every angle below runs on rho scaled by the drawn disc relative to the stock quad
    // (ss_disc), which is what kept it that rim when the discs shrank 10x off the old quad:
    // the ring radii ride in the disc's own half-angle the way they originally rode in the
    // stock quad's. The crystal halos further down stay at TRUE angles - droplet and ice
    // optics, not disc-relative ones.
    if (ss_optic_corona > 0.001)
    {
        // No drawn disc (active environment, no emitter) keeps the fixed-angle corona rather
        // than letting the 1e-5 floor blow the scale up into a full-sky wash.
        float ss_disc       = (ss_sun_radius > 1e-6) ? ss_sun_radius / 0.05 : 1.0;
        float cor_rho       = rho * ss_disc;
        float aureole = exp(-pow(cor_rho * 2.4, 2.0));
        float ringA   = exp(-pow((cor_rho - 2.4) / 1.0, 2.0));
        float ringB   = exp(-pow((cor_rho - 4.6) / 1.5, 2.0));

        vec3 ccol = vec3(0.42, 0.44, 0.48) * aureole
                  + vec3(0.12, 0.07, 0.04) * ringA
                  + vec3(0.04, 0.07, 0.12) * ringB;
        col += ccol * ss_optic_corona * 0.5 * (1.0 - ss_below);
    }

    // 22 deg halo: the everywhere veil of small platelets. Real halos are faint - a soft ring a
    // few times dimmer than the sun's own glare, so the scales below are kept low; the sundog is
    // the one member of the family that reads as a bright spot.
    if (ss_optic_halo22 > 0.001)
    {
        float w = 1.9;
        col += ss_optic_halo22 * exp(-pow((rho - 22.0) / w, 2.0))
             * (normalize(ss_optic_tint) * 0.8 + ss_optic_color(rho, 22.0, w) * 0.2)
             * 0.048 * (1.0 - ss_below) * ring_elev
             * smoothstep(21.3, 22.0, rho);
    }

    // 46 deg halo family (large plates/columns) - wider and fainter still.
    if (ss_optic_halo46 > 0.001)
    {
        float w = 2.3;
        col += ss_optic_halo46 * exp(-pow((rho - 46.0) / w, 2.0))
             * (normalize(ss_optic_tint) * 0.8 + ss_optic_color(rho, 46.0, w) * 0.2)
             * 0.048 * (1.0 - ss_below);
    }

    // Aligned-plate phenomena: need the plates to settle, not just plenty of crystals.
    if (ss_optic_align > 0.001)
    {
        // <SS:Nexii> The parhelic circle WITH its sundogs embedded - one construct, not two. The band is the locus of points at the SAME elevation as the light (ep = e), which as the light climbs bulges from a near-horizontal line into a small circle (more "circle"-like at high sun). It fades with distance from the light (rho / 55) - never a full closed ring. The SUNDOGS are bright COMPACT peaks embedded in the band where the 22 deg halo circle crosses it: at az = asin( sin(22) / cos(e) ) from the sun - ~22 deg at the horizon, spreading outward as the sun climbs (26 at e=30, 31 at e=40), and shrinking as they spread. Each dog is kept SMALL and tight - the line stays thin and clean around it, so the dog reads as a distinct bright spot ON a fine line, not a comet. The dogs can never drift off the line, because the line IS where they live.
        {
            // Polar coordinates
            float e  = asin(clamp(light.y, -1.0, 1.0)) * 57.2958;
            float ep = asin(clamp(view.y,  -1.0, 1.0)) * 57.2958;
            float dog_elev = smoothstep(-1.0, 3.0, elev)
                           * (1.0 - smoothstep(45.0, 60.0, elev));

            // Azimuth of the sundogs, which spread out from the 22 halo as sun climbs
            float az = asin(clamp(sin(22.0 * 0.0174533) / max(cos(elev * 0.0174533), 1e-4), -1.0, 1.0));
            az *= 57.2958;   // to degrees
            float spread = clamp(az / 22.0, 1.0, 3.5);
            
            float x_l = rho - az; 
            float x_r = -rho - az;
            float x = max(x_l, x_r); // Horizontal distance from the sundogs
            float y = ep - e;        // Vertical distance from parhelic circle line
            
            // Scaling brightness based on sun elevation
            float brightness = smoothstep(61.0, 5.0, elev);
            
            // Tail length stretches aggressively out as spread increases
            float tail_length = 14.0 * pow(spread, 1.7);
            
            // Vertical scale profiles (Varies dramatically based on sun elevation)
            // Low sun = thick vertical pillars; High sun = narrow daggers
            float core_vertical_width = mix(2.8, 0.9, smoothstep(0.0, 35.0, elev)) * spread;
            float tail_vertical_width = mix(1.2, 0.4, smoothstep(0.0, 35.0, elev)) * spread;

            // Glow profile
            float inner_wall = smoothstep(-0.8, 0.4, x);
            float tail_window = max(1.0 - (x / tail_length), 0.0);
            
            // Exponential horizontal sweep that fuels both the core and the tail smoothly
            float horizontal_glow = pow(tail_window, 2.5) * inner_wall;

            // Parhelic Band
            float base_line_width = 0.5 * clamp(spread * 0.5, 1.0, 2.0);
            float band_thickness = base_line_width + (5.0 / spread) * pow(tail_window, 4.0) * inner_wall;
            
            float band = exp(-pow(y / band_thickness, 2.0))
                       * exp(-pow(rho / 55.0, 2.0));

            // Blanket core streak
            float local_thickness = mix(tail_vertical_width, core_vertical_width, pow(tail_window, 3.0));
            
            // Glowing mass of the dogs
            float dog_intensity = (4.0 / spread) * brightness;
            float dogs = horizontal_glow * exp(-pow(y / local_thickness, 2.0)) * dog_intensity;

            // Prismatic gradient tweaks
            vec3 pc_col = normalize(ss_optic_tint) * 0.40
                        + ss_prismatic((x - 0.2) / (7.0 * spread)) * 0.60;

            // Compositing
            band *= 0.6 * (0.5 + inner_wall * 0.5);
            dogs *= 1.8;
            
            float pc = band + dogs;
            col += ss_optic_align * pc_col * pc * dog_elev * 0.12;
        }

    // <SS:Nexii> The circumzenithal arc's REAL geometry and visibility. The arc is a small circle centered on the ZENITH, passing through a point about 47 deg ABOVE the sun in the sun's meridian - its zenith-angle radius is 43 deg minus the sun's elevation, so its summit sits e+47 deg above the horizon. At a low sun (5-15 deg) that circle is wide and low, faint and spread; as the sun climbs toward ~22 deg it tightens and brightens toward its best; past ~32 deg the plate-ray geometry fails and it is gone entirely. The envelope is a triangle peaking at 22 deg, zero at 5 and 32.2. Prismatic: red on the arc's inner (zenith-side) edge, blue-violet outward.
    {
        float cza_env = smoothstep(5.0, 22.0, elev) * (1.0 - smoothstep(22.0, 32.2, elev));
        if (cza_env > 0.002)
        {
            vec3 h_light = normalize(light - up * dot(light, up) + vec3(1e-5));
            vec3 h_view  = normalize(view  - up * dot(view, up)  + vec3(1e-5));
            float az = degrees(acos(clamp(dot(h_light, h_view), -1.0, 1.0)));
            float zd = degrees(acos(clamp(dot(view, up), -1.0, 1.0)));
            float rcz = 43.0 - elev;                 // the arc's zenith-angle radius (43 - e)
            float cza = exp(-pow((zd - rcz) / 2.2, 2.0))
                      * exp(-pow(az / 40.0, 2.0));
            // <SS:Nexii> The CZA is genuinely PRISMATIC - red toward the arc's inner (zenith-side) edge, blue-violet away - the strongest colouring of the crystal halos. The old monotone red-in/blue-out fringe read as a white streak.
            col += ss_optic_align * cza_env * cza
                 * ss_prismatic((zd - rcz) / 2.2)
                 * 0.4 * (1.0 - ss_below);
        }
    }
    }

    // Supralateral arc: the 46 deg ring's tangent arc crowning the light, seen while the light is low.
    if (ss_optic_halo46 > 0.001)
    {
        float low = 1.0 - smoothstep(34.0, 52.0, elev);
        if (low > 0.001)
        {
            float w = 2.3;
            float lateral = exp(-pow((rho - 46.0) / w, 2.0))
                          * exp(-pow(psid / 34.0, 2.0)) * low;
            col += ss_optic_halo46 * lateral
             * (normalize(ss_optic_tint) * 0.8 + ss_optic_color(rho, 46.0, w) * 0.2)
             * 0.16 * (1.0 - ss_below);
        }
    }

    return col * ss_optic_gate;
}
#endif

// Hides the R11F_G11F_B10F emissive attachment's 6/6/5-mantissa banding in this writer's
// smooth gradients. Defined in deferred/globalF.glsl, which every fragment stage attaches.
vec3 ditherEmissive(vec3 v, vec2 frag_px);

void main()
{
#ifdef SS_ATMO
    // <SS:Nexii> Horizon clip's depth write (SSAtmoEnvAtmosphere::mHorizonClip). ss_below_horizon_y says which half
    // of the dome this fragment belongs to (was skyV's vary_ss_below_horizon).
    // PORT-TODO: forward-Z only - 1.0 / LL_SHADER_CONST_HORIZON_DEPTH are far-plane values; under Alchemy's
    // REVERSE_Z the sky's far depth is 0.0 and this write must be mirrored (1.0 - d) before reverse-Z ships on.
    ss_below_horizon_y = pos.y - camPosLocal.y;
    gl_FragDepth = (ss_horizon_clip > 0.0 && ss_below_horizon_y < 0.0) ? LL_SHADER_CONST_HORIZON_DEPTH : 1.0;

    // SKOOMA-PORT: the Atmo sky body below is skyV.glsl's former vertex stage, statement for statement, now
    // evaluated per fragment like Alchemy's stock path (pos is the dome vertex's world position, interpolated
    // exactly). Its former varyings are these locals; the optics globals are declared above ss_optics().
    vec3  ss_haze_color;
    float ss_lightnorm_dot;
    vec3  ss_view_dir;
    vec3  ss_hdri_ray;
    {
        // <SS:Nexii> Under the clip the sun's glow and haze effects stop at the horizon line. The clip already takes the disc and the weather optics with it (skyF.glsl's depth write and ss_clipped_below), but the glow's true-ray hotspot and its capped light would otherwise carry on down past the waterline - the natural continuation the mirror was built to provide. An authored sky that asks for the clip asked for the hard waterline instead, so the directional glow term fades out over SS_SUN_HORIZON_FADE below the line (sine of the angle below eye level - scale-free, the same cut from any height) and only the mirrored AIR - the body terms - continues below. With the clip off the fade stays 1 and the glow keeps its continuation.
        float ss_glow_horizon_fade = 1.0;
        if (ss_horizon_clip > 0.0)
        {
            vec3 ss_dome_ray = pos.xyz - camPosLocal.xyz;
            float ss_below_sin = clamp(-ss_dome_ray.y / max(length(ss_dome_ray), 1e-6), 0.0, 1.0);
            ss_glow_horizon_fade = 1.0 - smoothstep(0.0, SS_SUN_HORIZON_FADE, ss_below_sin);
        }

        // Get relative position
        // <SS:Nexii> The lift rides ss_ray_lift (see the uniform note above): 1 keeps the stock ray bit for bit, 0 aims the glow - and the rainbow dot below - at the true direction the Atmo discs draw at.
        vec3 rel_pos = pos.xyz - camPosLocal.xyz + vec3(0, 50.0 * ss_ray_lift, 0);

        // SKOOMA-PORT: the HDRI preview reads the ray as lifted but BEFORE the mirror below - what vary_rel_pos carried.
        ss_hdri_ray = rel_pos;

        // <SS:Nexii> Below the horizon, mirror the ray instead of collapsing it. Stock stretches a below-horizon ray to 32000 units, and separately the sunlight term below clamps its elevation with max(0., rel_pos_norm.y). Together those make the lower dome black: full extinction over an enormous path, lit by ambient alone. That is invisible as long as land or water covers the lower dome, and it does not. A flat sea of radius R seen from height h ends atan(h/R) below eye level, so there is always a wedge between the water's edge and the true horizon - about two degrees at twenty metres up - with nothing in it but lower dome. Hence the black band under a sunset, widening as you climb, papered over only when cloud coverage is high enough to fill it. Mirroring shades a ray a degree below the horizon exactly like one a degree above, so the haze simply carries on down. Continuous at the horizon, and truer than black: what is actually down there is the same air, seen along the same sort of path. Runtime-gated by ss_horizon_mirror (see the uniform note above): with the mirror off, the stock behaviour below is restored exactly - the -32000 branch stays compiled because the SS_ATMO variant serves both the idle (stock collapse) and active (mirror) cases per frame, and under the mirror it is simply unreachable: the abs keeps y >= 0. The mirror is for the AIR terms only - extinction and haze body, which have no direction of their own. The directional terms (the glow's hotspot, the rainbow and halo strip, the weather optics) scatter from the light at a TRUE angle, so they read the ray captured here before the flip: feeding them the mirrored ray painted a second copy of the sun's glow and corona below the horizon, the mirror image of the one above it.
        vec3 ss_true_dir = vec3(0.0);
        if (ss_horizon_mirror > 0.)
        {
            ss_true_dir = normalize(rel_pos);
            rel_pos.y = abs(rel_pos.y);
        }
        if (rel_pos.y > 0.)
        {
            rel_pos *= (max_y / rel_pos.y);
        }
        if (rel_pos.y < 0.)
        {
            rel_pos *= (-32000. / rel_pos.y);
        }

        // Normalized
        vec3  rel_pos_norm = normalize(rel_pos);
        float rel_pos_len  = length(rel_pos);

        // Grab this value and pass to frag shader for rainbows
        // <SS:Nexii> Under the mirror the rainbow and halo strip read the true ray (see above), so their rings land at true angular distances from the light below the horizon too - never mirrored ones.
        float rel_pos_lightnorm_dot = dot(rel_pos_norm, lightnorm.xyz);
        if (ss_horizon_mirror > 0.)
        {
            rel_pos_lightnorm_dot = dot(ss_true_dir, lightnorm.xyz);
        }
        ss_lightnorm_dot = rel_pos_lightnorm_dot;

        // <SS:Nexii> The view ray, for the weather-driven optics (ssOptics in skyF.glsl) to split into corona, 22/46 halos, sundogs and the aligned-plate arcs by true angular position around the light. Same frame as lightnorm, so the fragment stage compares it against the same light direction uniform and the same +Y up the dome already shades with. Under the mirror this is the TRUE ray (see above): a below-horizon fragment gets only what its real angle from the light scatters - the natural continuation of the phenomena across the horizon line - never the mirrored copy the flipped ray used to paint.
        ss_view_dir = (ss_horizon_mirror > 0.) ? ss_true_dir : rel_pos_norm;

        // Initialize temp variables
        vec3 sunlight = (sun_up_factor == 1) ? sunlight_color : moonlight_color * 0.7; //magic 0.7 to match legacy color

        // <SS:Nexii> The disc sheds light across the horizon band, not the instant its centre clears the horizon: the dome's sunlight is the full day colour from centre-rise up - the condition the authored skies painted against - and walks back down to the night value as the sun sinks through the twilight below the horizon (ss_sun_rise is the horizon-band share). Zero leaves the stock switch untouched - night, idle environments, and the fully-set case.
        if (ss_sun_rise > 0.0)
        {
            sunlight = mix(moonlight_color * 0.7, sunlight_color, ss_sun_rise);
        }

        // <SS:Nexii> THE AIRLIGHT, ONE AUTHORITY (doc/atmo_magic_phase8_show.md section 5b). Everything from this line down to ss_haze_color is a transliteration of indra/newview/ssairlightcore.h: that header holds the formulas, this block spells its function bodies statement for statement in GLSL (a shader cannot include a C++ header, so the transliteration IS the wiring), and V:\Scratch\atmo\tests\twin_airlight.cpp reads this file's text and asserts the core reproduces every intermediate of it bit-for-bit. Each site below names the core function it is. The three guards this file has always carried - the zero-density weight floor, the ambient headroom clamp and the shadow dim clamp - are now the core's spelling and cloudsV.glsl's too; see the notes at those three sites for what each one is worth.
        // Sunlight attenuation effect (hue and brightness) due to atmosphere
        // this is used later for sunlight modulation at various altitudes
        // <SS:Nexii> ssairlightcore.h : lightAtten() - the haze share and the (multiplier * ceiling) product are grouped exactly as the core groups them, which is what makes the twin's equality bit-for-bit rather than algebraic.
        vec3 light_atten = (blue_density + vec3(haze_density * 0.25)) * (density_multiplier * max_y);

        // <SS:Nexii> While the rise band is live, the sun's term in the light path floors at the DISC'S OWN half-angle (ss_sun_radius). Stock feeds the raw (clamped) lightnorm elevation in here, so the moment the disc's CENTRE dips under, every ray near the horizon loses its light path - the max(1e-6, ...) below collapses them to unlit - and the whole sunset band is cut out from under a disc that is still half up. Holding the elevation at the radius is the JUST-CLEARED airmass (1/radius at the horizon line, the same path a sun that has only just cleared gets), so the band stays lit for the whole rise, and the dusk below the horizon keeps that same just-cleared path while the band's share fades it out - the afterglow dies of the fade, never of the airmass. The floor releases continuously once the centre clears the radius, and the gate is stock with it off.
        float sun_elev = (ss_sun_rise > 0.0) ? max(ss_sun_dir.z, ss_sun_radius) : lightnorm.y;

        // Calculate relative weights
        // <SS:Nexii> ssairlightcore.h : hazeSplit(), transliterated. The max() is the core's DENSITY_FLOOR: the weights divide by this sum, and a sky authored with a black blue_density and haze_density 0 - both reachable from the swatch and the slider, both inside EEP's validated ranges - would otherwise divide zero by zero. cloudsV.glsl lacked this guard until the consolidation and produced NaN weights there; it now carries the same line.
        vec3 combined_haze = max(abs(blue_density) + vec3(abs(haze_density)), vec3(1e-6));
        vec3 blue_weight   = blue_density / combined_haze;
        vec3 haze_weight   = haze_density / combined_haze;

        // Compute sunlight from rel_pos & lightnorm (for long rays like sky)
        // <SS:Nexii> ssairlightcore.h : offAxis() - the airmass the beam crosses to reach this point, as a multiple of the vertical path.
        float off_axis = 1.0 / max(1e-6, max(0., rel_pos_norm.y) + sun_elev);
        // The pre-attenuation light, kept for the glow's own extinction below - the glow is
        // scattered light, not the beam, and does not have to take the beam's full fate.
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
        // <SS:Nexii> The glow tracks the disc (ss_sun_dir), not the lightnorm: lightnorm hands the direction to the moon at centre-set, which would swing the whole sunset band across the sky to the moon's azimuth while the disc is still half up. See the ss_sun_dir note above. Frame note: rel_pos and lightnorm live in the ogl frame lightnorm is uploaded in (LLEnvironment::toLightNorm permutes world x,y,z to y,z,x), while ss_sun_dir arrives in world axes - the same raw vector the celestial discs phase against - so the swizzle below puts both directions in one frame. ss_sun_dir.z keeps meaning the true elevation.
        vec3 glow_dir = (ss_sun_rise > 0.0) ? ss_sun_dir.yzx : lightnorm.xyz;
        // <SS:Nexii> Calibration to EEP: the hotspot's shape was EEP-tuned against the stock ~5.7 degree quad. The drawn disc's angular size must NOT rescale it - the glow is the LIGHT the authored sky sheds, and EEP sized the lobe by the stock quad's angular width. Perceived disc size is a look, not a light: the lobe keeps the stock width whatever the Atmo discs draw. The horizon-band share (ss_sun_rise) already ramps the strength; the removed ss_disc * ss_disc term was the only disc-to-light coupling.
        vec3 glow_ray = (ss_horizon_mirror > 0.) ? ss_true_dir : rel_pos_norm;
        float haze_glow = 1.0 - dot(glow_ray, glow_dir);
        // haze_glow is 0 at the sun and increases away from sun
        haze_glow = max(haze_glow, .001);
        // Set a minimum "angle" (smaller glow.y allows tighter, brighter hotspot)
        haze_glow *= glow.x;
        // Higher glow.x gives dimmer glow (because next step is 1 / "angle")
        haze_glow = pow(haze_glow, glow.z);
        // glow.z should be negative, so we're doing a sort of (1 / "angle") function

        // Add "minimum anti-solar illumination"
        // For sun, add to glow.  For moon, remove glow entirely. SL-13768
        // <SS:Nexii> The glow is the light the disc sheds, so while the rise band is live it is built from the RAW angular term and scaled by the horizon-band share - full strength the whole time the disc is up, which is exactly the stock sun line and the condition the authored skies painted against, then easing out across the twilight below the horizon. Stock's factor line cannot be allowed to touch it in the band: below centre-rise the factor belongs to the moon (< 1.0), whose branch zeroes the term entirely (SL-13768 - right for the moon, which must not glow), and ramping on the zeroed term grew a FLAT 0.25 wash with no hotspot at all until the factor snapped to 1.0 at centre-rise - the sunrise horizon simply was not there while the disc poked over. With the gate off, stock.
        if (ss_sun_rise > 0.0)
        {
            haze_glow = ss_sun_rise * (haze_glow + 0.25);
        }
        else
        {
            // <SS:Nexii> ONE SPELLING with cloudsV.glsl, which used to group this as `haze_glow * sun_moon_glow_factor + 0.25` - the same value only at a factor of exactly 1, and the anti-solar floor undimmed at any other. This grouping is the one both files now carry: the 0.25 is part of the glow's light and scales with it. Angular, not air, so ssairlightcore.h does not own it - twin_airlight.cpp pins the two files against each other instead.
            haze_glow = (sun_moon_glow_factor < 1.0) ? 0.0 : (sun_moon_glow_factor * (haze_glow + 0.25));
        }

        // <SS:Nexii> The horizon clip's cut of the sun's effects at the waterline - see the note at ss_glow_horizon_fade above. 1 unless the clip is on and this vertex sits below the line.
        haze_glow *= ss_glow_horizon_fade;

        // <SS:Nexii> The sun's glow and haze get their OWN light, with the beam extinction's crush BOUNDED rather than the beam's. The beam maths above (off_axis 1/elevation) hands horizon rays an effectively infinite airmass, and the density product exp()s the sun's colour to black there - the glow's SHAPE survives but arrives colourless, which is the grey horizon band, the "edge" the authored sunset is supposed to burn through. (A radial fade of the extinction around the disc was tried first and read as a giant ball: the window's inner zone rode the hotspot at full strength, the mid-ring swept through the deepest saturation, and the window's edge popped back to the crushed sky - a bullseye around the sun quad, which is itself correct.) So instead the glow's extinction is CAPPED: its airmass may not exceed the depth at which the densest attenuation channel has shed SS_SUN_GLOW_DEPTH optical depths - scaled uniformly across the channels, so the hue survives and the band deepens TO its colour, never through it and out the other side. Where the beam maths is mild the cap never binds and the stock line stands; it only binds where the crush was total, and a min() has no edge to see - the grey band simply becomes the bright warm gradient a real sunset carries, core to horizon and on down past it. Density keeps every other duty untouched - the dome body, the blue_horizon wash, the distance haze, the (1 - combined_haze) scale. Live only while the rise band is (ss_sun_rise > 0): an idle environment keeps the stock line bit for bit.
        vec3 ss_glow_light = sunlight;
        if (ss_sun_rise > 0.0)
        {
            float ss_max_atten = max(light_atten.r, max(light_atten.g, light_atten.b));
            // <SS:Nexii> ssairlightcore.h : glowAirmass() then glowLight() - the capped airmass, and the RAW light carried through it (never the already attenuated beam, which would extinguish twice).
            float ss_glow_airmass = min(off_axis, SS_SUN_GLOW_DEPTH / max(ss_max_atten, 1e-6));
            ss_glow_light = ss_raw_light * exp(-light_atten * ss_glow_airmass);
        }

        // <SS:Nexii> The weather optics' final light colour (ss_optic_tint) - the light the dome ACTUALLY renders with, evaluated along the light's OWN ray, so it is a per-frame constant the whole halo family wears uniformly. The old tint was bound CPU-side from an uncapped beam replication whose cosecant (1/max(1e-6, sin(elev))) underflowed to zero within a degree of the horizon and fell back to the raw near-white authored sun colour - the white snap. This is the hue the eye actually sees: full warm sun through the rise band, eased toward the night value as the band fades, never white. The airmass cap is the glow's own (SS_SUN_GLOW_DEPTH), so the tint deepens TO the sunset colour instead of through it. During the band the active light for the optics is always the SUN (skyF gates on that band), whatever lightnorm handed to the moon at centre-set, so the sun path uses the sun's TRUE elevation, floored at the disc - the glow's own just-cleared path for a sun below the horizon, which is the whole point: the red rides down past the line while the band fades. While no band is live the optics are the moonlight family and keep their bound faint-white tint (ss_optic_sun_col below) bit for bit. Constant across the dome - it proceeds from uniforms alone - so per-vertex interpolation is a no-op.
        ss_optic_tint = (ss_sun_rise > 0.0)
            ? (ss_raw_light * exp(-light_atten
                * min(1.0 / max(1e-6, max(ss_sun_dir.z, 0.0) + max(ss_sun_dir.z, ss_sun_radius)),
                      SS_SUN_GLOW_DEPTH
                      / max(max(light_atten.r, max(light_atten.g, light_atten.b)), 1e-6))))
            : ss_optic_sun_col;

        // Haze color above cloud
        // <SS:Nexii> ssairlightcore.h : skyColor() - two scattering populations, each taking its share of the beam and the ambient, grouped left to right as the core groups them. Above cloud it takes the RAW ambient and the undimmed beam; the below-cloud call further down takes the lifted ambient and the dimmed beam, and that pair is the whole difference between the dome's two colours.
        vec3 color = (blue_horizon * blue_weight * (sunlight + ambient_color)
                   + (haze_horizon * haze_weight) * (ss_glow_light * haze_glow + ambient_color));

        // Final atmosphere additive
        color *= (1. - combined_haze);

        // Increase ambient when there are more clouds
        // <SS:Nexii> ssairlightcore.h : ambientUnderClouds(), transliterated. The max() is what makes the lift monotone in cover at EVERY ambient: above 1 the headroom goes negative and the unguarded form darkens the sky as cover rises, the opposite of what the line above says it does. That is not an unreachable case - Atmo's ambient swatch is scaled by 3 and EEP validates ambient to [0,3] - and until the consolidation cloudsV.glsl carried the unguarded form, so an HDR-ambient sky put the cirrus band and this dome on different ambients at the rim they are supposed to meet on.
        vec3 ambient = ambient_color + max(vec3(0), (1. - ambient_color)) * cloud_shadow * 0.5;

        // Dim sunlight by cloud shadow percentage
        // <SS:Nexii> ssairlightcore.h : dimByCloudShadow(). The max() is inert for every cloud_shadow the viewer binds ([0,1], validated and dialled) and stops the unguarded form from NEGATING the light above 1; cloudsV.glsl now carries it too.
        sunlight *= max(0.0, (1. - cloud_shadow));
        ss_glow_light *= max(0.0, (1. - cloud_shadow));

        // Haze color below cloud
        // <SS:Nexii> ssairlightcore.h : skyColor() again, with the lifted ambient and the dimmed lights - the same composition cloudsV.glsl ends on as additiveColorBelowCloud and the deck adds as vary_ss_airlight. One formula site, three callers.
        vec3 add_below_cloud = (blue_horizon * blue_weight * (sunlight + ambient)
                             + (haze_horizon * haze_weight) * (ss_glow_light * haze_glow + ambient));

        // Attenuate cloud color by atmosphere
        combined_haze = sqrt(combined_haze);  // less atmos opacity (more transparency) below clouds

        // At horizon, blend high altitude sky color towards the darker color below the clouds
        // <SS:Nexii> ssairlightcore.h : domeHazeColor() - the dome's own blend, and the other half of the rim handoff: as the transmittance goes to zero this weight goes to 1 and the dome lands exactly on the below-cloud colour, which is exactly what cloudsV.glsl's airlightOverPath lands on. The nested root is the shader's own (the sqrt above halves the depth, this one roots the already-rooted value).
        color += (add_below_cloud - color) * (1. - sqrt(combined_haze));

        // Haze color above cloud
        ss_haze_color = color;
    }

    vec3 color;
#ifdef HAS_HDRI
    vec3 frag_coord = vary_position.xyz/vary_position.w;
    if (-frag_coord.x > ((1.0-hdri_split_screen)*2.0-1.0))
    {
        vec3 pos = normalize(ss_hdri_ray);
        pos = env_mat * pos;
        vec2 texCoord = vec2(atan(pos.z, pos.x) + PI, acos(pos.y)) / vec2(2.0 * PI, PI);
        color = textureLod(environmentMap, texCoord.xy, 0).rgb * sky_hdr_scale;
        color = min(color, vec3(8192*8192*16)); // stupidly large value arrived at by binary search -- avoids framebuffer corruption from some HDRIs

        frag_data[2] = vec4(0.0,0.0,0.0,GBUFFER_FLAG_HAS_HDRI);
    }
    else
#endif
    {
        // Potential Fill-rate optimization.  Add cloud calculation
        // back in and output alpha of 0 (so that alpha culling kills
        // the fragment) if the sky wouldn't show up because the clouds
        // are fully opaque.

        color = ss_haze_color;

        float  rel_pos_lightnorm = ss_lightnorm_dot;
        float optic_d = rel_pos_lightnorm;
        // <SS:Nexii> The horizon clip cuts the lower dome at eye level - and the sun with it
        bool ss_clipped_below = (ss_horizon_clip > 0.0) && (ss_below_horizon_y < 0.0);
        if (!ss_clipped_below)
        {
            // <SS:Nexii> The physical rainbow (ss_rainbow above) takes the stock strip's place while the SSAtmoRainbow gate is up; gate down keeps the stock single bow bit for bit.
            color.rgb += (ss_rainbow_gate > 0.0) ? ss_rainbow(optic_d) : rainbow(optic_d);
        }
        if (ss_optic_active > 0.001)
        {
            // <SS:Nexii> Weather-driven optics take over while an active Atmo environment drives the sky (ss_optic_gate): the corona, the 22/46 deg halos, sundogs and the aligned-plate arcs each render at their true angular positions instead of one merged texture strip. When the halo step is switched off the strip is skipped too - an active Atmo sky never draws the old corona-plus-wide-ring halo_map. An IDLE Atmo viewer (boosted master switch, no environment) keeps the stock strip below, so it stays bit-for-bit.
            if (ss_optic_gate > 0.001 && !ss_clipped_below)
            {
                color.rgb += ss_optics(normalize(ss_view_dir));
            }
        }
        else if (!ss_clipped_below)
        {
            color.rgb += halo22(optic_d);
        }
        color.rgb *= 2.;
        // <SS:Nexii> Cap the sky's LUMINANCE, not its channels: a per-channel clamp saturates anything past 5 to white, and the halos/sundogs added just above sit on a bright haze near the sun that easily crosses it - so the light's own red came out white. Scaling the whole colour down to a 5-luminance cap keeps the peak bright for bloom while the sun's tint survives.
        float ss_sky_cmax = max(color.r, max(color.g, color.b));
        if (ss_sky_cmax > 5.0)
        {
            color.rgb *= 5.0 / ss_sky_cmax;
        }

        frag_data[2] = vec4(0.0,0.0,0.0,GBUFFER_FLAG_SKIP_ATMOS);
    }
#else
    // Get relative position
    vec3 rel_pos = pos.xyz - camPosLocal.xyz + vec3(0, 50, 0);

    // Adj position vector to clamp altitude
    if (rel_pos.y > 0.)
    {
        rel_pos *= (max_y / rel_pos.y);
    }
    if (rel_pos.y < 0.)
    {
        rel_pos *= (-32000. / rel_pos.y);
    }

    vec3 color;
#ifdef HAS_HDRI
    vec3 frag_coord = vary_position.xyz/vary_position.w;
    if (-frag_coord.x > ((1.0-hdri_split_screen)*2.0-1.0))
    {
        vec3 pos = normalize(rel_pos);
        pos = env_mat * pos;
        vec2 texCoord = vec2(atan(pos.z, pos.x) + PI, acos(pos.y)) / vec2(2.0 * PI, PI);
        color = textureLod(environmentMap, texCoord.xy, 0).rgb * sky_hdr_scale;
        color = min(color, vec3(8192*8192*16)); // stupidly large value arrived at by binary search -- avoids framebuffer corruption from some HDRIs

        frag_data[2] = vec4(0.0,0.0,0.0,GBUFFER_FLAG_HAS_HDRI);
    }
    else
#endif
    {
        // Normalized
        vec3  rel_pos_norm = normalize(rel_pos);
        float rel_pos_len  = length(rel_pos);

        // Grab this value and pass to frag shader for rainbows
        float rel_pos_lightnorm_dot = dot(rel_pos_norm, lightnorm.xyz);

        // Initialize temp variables
        vec3 sunlight = (sun_up_factor == 1) ? sunlight_color : moonlight_color * 0.7; //magic 0.7 to match legacy color

        // Sunlight attenuation effect (hue and brightness) due to atmosphere
        // this is used later for sunlight modulation at various altitudes
        vec3 light_atten = (blue_density + vec3(haze_density * 0.25)) * (density_multiplier * max_y);

        // Calculate relative weights
        vec3 combined_haze = max(abs(blue_density) + vec3(abs(haze_density)), vec3(1e-6));
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
        float haze_glow = 1.0 - rel_pos_lightnorm_dot;
        // haze_glow is 0 at the sun and increases away from sun
        haze_glow = max(haze_glow, .001);
        // Set a minimum "angle" (smaller glow.y allows tighter, brighter hotspot)
        haze_glow *= glow.x;
        // Higher glow.x gives dimmer glow (because next step is 1 / "angle")
        haze_glow = pow(haze_glow, glow.z);
        // glow.z should be negative, so we're doing a sort of (1 / "angle") function

        // Add "minimum anti-solar illumination"
        // For sun, add to glow.  For moon, remove glow entirely. SL-13768
        haze_glow = (sun_moon_glow_factor < 1.0) ? 0.0 : (sun_moon_glow_factor * (haze_glow + 0.25));

        // Haze color above cloud
        color = (blue_horizon * blue_weight * (sunlight + ambient_color)
                + (haze_horizon * haze_weight) * (sunlight * haze_glow + ambient_color));

        // Final atmosphere additive
        color *= (1. - combined_haze);

        // Increase ambient when there are more clouds
        vec3 ambient = ambient_color + max(vec3(0), (1. - ambient_color)) * cloud_shadow * 0.5;

        // Dim sunlight by cloud shadow percentage
        sunlight *= max(0.0, (1. - cloud_shadow));

        // Haze color below cloud
        vec3 add_below_cloud = (blue_horizon * blue_weight * (sunlight + ambient)
                            + (haze_horizon * haze_weight) * (sunlight * haze_glow + ambient));

        // Attenuate cloud color by atmosphere
        combined_haze = sqrt(combined_haze);  // less atmos opacity (more transparency) below clouds

        // At horizon, blend high altitude sky color towards the darker color below the clouds
        color += (add_below_cloud - color) * (1. - sqrt(combined_haze));

        float optic_d = rel_pos_lightnorm_dot;
        vec3  halo_22 = halo22(optic_d);
        color.rgb += rainbow(optic_d);
        color.rgb += halo_22;
        color.rgb *= 2.;
        color.rgb = clamp(color.rgb, vec3(0), vec3(5));

        frag_data[2] = vec4(0.0,0.0,0.0,GBUFFER_FLAG_SKIP_ATMOS);
    }

#endif

    frag_data[1] = vec4(0);

#if defined(HAS_EMISSIVE)
    frag_data[0] = vec4(0);
    frag_data[3] = vec4(ditherEmissive(color.rgb, gl_FragCoord.xy), 1.0);
#else
    frag_data[0] = vec4(color.rgb, 1.0);
#endif
}

