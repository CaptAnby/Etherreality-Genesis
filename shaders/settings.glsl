#ifndef GM_SETTINGS_GLSL
#define GM_SETTINGS_GLSL

// ============================================================
// ETHERREALITY GENESIS :: SETTINGS (shown in the in-game Shader Options menu)
// ============================================================

// ---- Image ----
#define FXAA
#define FXAA_STRENGTH 0.85 // [0.0 0.25 0.5 0.75 0.85 1.0]
#define AA_SOFTNESS 0.3 // [0.0 0.15 0.3 0.45 0.6 0.8]
#define DOF
#define DOF_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0]
#define VIBRANCE 0.18 // [0.0 0.1 0.18 0.3 0.45]
#define CONTRAST 1.06 // [0.95 1.0 1.06 1.12 1.2]

// ---- Sky ----
#define CPS001
#define SKY_SUN_SIDE_GLOW 0.6 // [0.2 0.4 0.6 0.8 1.0]
#define SKY_BLUENESS 1.0 // [0.0 0.5 0.75 1.0 1.25 1.5]
#define SKY_BRIGHTNESS 1.0 // [0.7 0.85 1.0 1.15 1.3]
#define SUN_DISC_BRIGHTNESS 0.6 // [0.0 0.5 0.6 0.75 1.0 1.25 1.5]
#define SUN_HALO_STRENGTH 0.6 // [0.0 0.5 0.6 1.0 1.5 2.0]
#define MOON_DISC_BRIGHTNESS 1.0 // [0.0 0.5 0.75 1.0 1.25 1.5]
#define MOON_HALO_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define STAR_BRIGHTNESS 1.0 // [0.0 0.5 0.75 1.0 1.5 2.0 3.0]

// ---- The End ----
#define CPS001_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define CPS001_SWEEP_SPEED 0.6 // [0.2 0.4 0.6 0.8 1.0 1.5 2.0]
#define END_BEAMS   // purple light beams rising from the End pillars
#define END_BEAM_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.5 2.0 3.0]
#define END_BEAM_PULSE   // glowing pulses travelling up the beams
#define END_BEAM_PULSE_SPEED 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define END_PORTAL_FX
#define END_PORTAL_STRENGTH 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]

// ---- Info ----
#define ETHER_INFO 1 // [1]

// ---- Volumetric Fog ----
#define VOL_FOG
#define VOL_FOG_DENSITY 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define VOL_FOG_WISPINESS 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define VOL_FOG_SCALE 1.0 // [0.6 0.8 1.0 1.25 1.6]
#define VOL_FOG_HEIGHT 1.0 // [0.6 0.8 1.0 1.3 1.6]
#define VOL_FOG_BRIGHTNESS 1.0 // [0.7 0.85 1.0 1.15 1.3]
#define VOL_FOG_BIOME_DENSITY
#define VOL_FOG_BIOME_STRENGTH 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define VOL_FOG_TIME_OF_DAY
#define VOL_FOG_WEATHER
#define VOL_FOG_WIND_SPEED 1.0 // [0.0 0.5 1.0 2.0 3.0]

// ---- Atmosphere ----
#define HAZE_VOLUMETRIC
#define HAZE_VOL_STRENGTH 1.0 // [0.0 0.5 0.75 1.0 1.25 1.5]
#define HAZE_STRENGTH 1.0 // [0.0 0.5 0.75 1.0 1.25 1.5 2.0]
#define HAZE_COOLNESS 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define WIND_STREAKS
#define WIND_STREAK_STRENGTH 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define CELESTIALS 1 // [0 1]
#define COLORED_LIGHTS
#define SKY_PHYSICS 0.6 // [0.0 0.3 0.6 0.8 1.0]
#define CAVE_DUST
#define SUNRAYS
#define SUNRAY_STRENGTH 0.4 // [0.2 0.4 0.5 1.0 1.5 2.0]
#define CLOUD_HORIZON_SOFTNESS 0.34 // [0.08 0.14 0.22 0.32 0.45]
#define SKY_PALENESS 1.0 // [0.0 0.5 0.75 1.0 1.25 1.5]
#define SUNSET_STRENGTH 1.0 // [0.5 0.75 1.0 1.25 1.5]
#define SHOOTING_STARS

// ---- Lighting ----
#define SUN_BRIGHTNESS 0.8 // [0.5 0.6 0.7 0.8 0.85 1.0 1.15 1.3 1.5]
#define SUN_WARMTH 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0]
#define SUN_CONTRAST 0.8 // [0.5 0.6 0.8 0.75 1.0 1.25 1.5]
#define SUN_GOLDEN_STRENGTH 0.7 // [0.0 0.5 1.0 1.5 2.0]
#define SUN_SOFTNESS 0.8 // [0.0 0.25 0.5 0.75 1.0]
#define NEBULA_FOG_STRENGTH 1.4 // [0.5 1.0 1.4 2.0 3.0]
#define REALTIME_SHADOWS
#define SHADOW_STRENGTH 0.55 // [0.25 0.4 0.55 0.7 0.85 0.95]
#define SHADOW_SOFTNESS 1.0 // [0.5 0.75 1.0 1.5 2.0 3.0]
#define SHADOW_BIAS 1.0 // [0.5 1.0 1.5 2.0 3.0]
#define CLOUD_MODE 1 // [0 1 2 3]
#define CLOUD_SHADOWS
#if CLOUD_MODE == 0 || CLOUD_MODE == 3
#undef CLOUD_SHADOWS
#endif
#define CLOUD_SHADOW_STRENGTH 0.5 // [0.25 0.5 0.75 1.0]
#define SHADOW_COOLNESS 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define SHADOW_WEATHER_FADE 0.82 // [0.0 0.4 0.6 0.82 1.0]
#define AMBIENT_GLOW 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0]
#define RAYLEIGH
#define RAYLEIGH_STRENGTH 1.0 // [0.25 0.5 1.0 1.5 2.0]
#define RAYLEIGH_DENSITY 1.0 // [0.5 1.0 1.5 2.0 3.0]
#define RAYLEIGH_SUNSET 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define RAYLEIGH_BLUE 1.0 // [0.5 0.75 1.0 1.25 1.5]
#define RAYTRACE
#define RT_STEPS 16 // [8 12 16 24 32]
#define RT_DISTANCE 24.0 // [4.0 8.0 16.0 24.0 48.0 96.0]
#define RT_THICKNESS 1.0 // [0.25 0.5 1.0 2.0 4.0]
#define RT_STRENGTH 1.0 // [0.25 0.5 0.65 0.8 1.0]
#define RT_NOISE 0.25 // [0.0 0.25 0.5 1.0]
#define RT_RANGE 96.0 // [32.0 64.0 96.0 160.0]
#define BLOCKLIGHT_STRENGTH 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define EMISSIVE_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define HELD_LIGHT
#define PATH_TRACING   // EXPERIMENTAL hybrid screen-space path tracer: 1-bounce diffuse indirect light + color bleeding
#define PT_STRENGTH 1.0 // [0.5 1.0 1.5 2.0 3.0]
#define PT_RADIUS 6.0 // [3.0 6.0 10.0 16.0]
#define LIGHT_GLARE   // subtle colored glare around torches and light blocks
#define LIGHT_GLARE_STRENGTH 1.0 // [0.5 1.0 1.5 2.0]
#define PBR_NORMAL_STRENGTH 0.85 // [0.0 0.25 0.5 0.85 1.0]
#define PBR_SPECULAR_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define PBR_AO_STRENGTH 0.6 // [0.0 0.3 0.6 1.0]
#define BLOCK_REFLECTION_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define BLOCK_REFLECTION_SOFTNESS 1.0 // [0.5 1.0 1.5]
#define BLOCK_REFLECTIONS   // realtime SSR on reflective blocks (metal, polished materials), strength/softness from material
#define PBR_MATERIALS   // Phase 1: labPBR roughness/metallic (specular texture) -> GGX sun specular. No effect without a PBR resource pack.
#define HELD_LIGHT_STRENGTH 1.0 // [0.5 0.75 1.0 1.5 2.0]

// ---- Glass ----
#define COLORED_GLASS_SHADOWS
#define GLASS_GLINT_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define GLASS_REFLECTION 1.0 // [0.0 0.5 1.0 1.5 2.0]

// ---- Reflections ----
#define REALISTIC_WATER
#define WATER_SHADOW_DARKEN 0.6 // [0.0 0.3 0.6 0.8 1.0]
#define UNDERWATER_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]
#define WATER_TYPE 2 // [0 1 2 3]
#if WATER_TYPE == 0
#define WATER_SIGMA vec3(0.28, 0.050, 0.025)
#define WATER_SCATTER vec3(0.20, 0.50, 0.50)
#elif WATER_TYPE == 1
#define WATER_SIGMA vec3(0.34, 0.070, 0.020)
#define WATER_SCATTER vec3(0.10, 0.28, 0.38)
#elif WATER_TYPE == 2
#define WATER_SIGMA vec3(0.42, 0.085, 0.030)
#define WATER_SCATTER vec3(0.035, 0.15, 0.24)
#else
#define WATER_SIGMA vec3(0.80, 0.450, 0.500)
#define WATER_SCATTER vec3(0.30, 0.34, 0.22)
#endif
#define WATER_PALENESS 0.12 // [0.0 0.12 0.25 0.55 0.75 1.0]
#define WATER_TURBIDITY 0.0 // [0.0 0.5 1.0 2.0 3.0]
#define WATER_FOAM 1.0 // [0.0 0.5 1.0 2.0]
#define WATER_SHALLOW_OPACITY 0.42 // [0.06 0.15 0.30 0.45 0.60]
#define FOAM_EDGES
#define FOAM_EDGE_STRENGTH 1.0 // [0.25 0.5 1.0 1.5 2.0]
#define FOAM_EDGE_WIDTH 1.0 // [0.5 0.75 1.0 1.5 2.0 3.0]
#define FOAM_EDGE_SCALE 1.0 // [0.5 1.0 1.5 2.0]
#define FOAM_EDGE_SPEED 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define WATER_GLINT 1.0 // [0.0 0.5 1.0 2.0]
#define UNDERWATER_ABSORB 1.0 // [0.25 0.5 1.0 1.5 2.0]
#define WATER_CLARITY 1.25 // [0.5 0.75 1.0 1.25 1.5 2.0 3.0]
#define WATER_ABSORPTION 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define WATER_TRANSPARENCY 1.15 // [0.6 0.8 1.0 1.15 1.25 1.5]
#define WATER_BRIGHTNESS 1.0 // [0.6 0.8 1.0 1.25 1.5 2.0]
#define WATER_TINT_R 1.0 // [0.5 0.75 1.0 1.25 1.5]
#define WATER_TINT_G 1.0 // [0.5 0.75 1.0 1.25 1.5]
#define WATER_TINT_B 1.0 // [0.5 0.75 1.0 1.25 1.5]
#define WAVE_INTENSITY 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0]
#define WAVE_SPEED 1.0 // [0.25 0.5 1.0 1.5 2.0 3.0]
#define WAVE_SCALE 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define WAVE_SWELL 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define WAVE_DETAIL 1.0 // [0.0 0.5 1.0 1.5 2.0]
// ---- photoreal water ----
#define PW_WAVE_HEIGHT 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0 2.5]
#define PW_WATER_TINT 1.0 // [0.0 0.5 0.75 1.0 1.25 1.5]
#define PW_CHOPPINESS 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define PW_WIND_ANGLE 35.0 // [0.0 35.0 70.0 110.0 145.0 180.0 215.0 250.0 290.0 325.0]
#define PW_CAPILLARY 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define PW_REFLECTION 1.0 // [0.25 0.5 0.75 1.0 1.25 1.5 2.0]
#define PW_SUN_GLITTER 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define PW_SSS 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define PW_WHITECAPS 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define PW_DEPTH_FADE 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define PW_DISTANCE_HAZE 1.0 // [0.0 0.5 0.75 1.0 1.25 1.5]
#define PW_CINEMATIC 0.5 // [0.0 0.25 0.5 0.75 1.0]
#define PW_UW_SNELL 1.0 // [0.0 0.5 1.0]
#define PW_UW_DEPTH_DARKEN 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define WATER_REFLECTIONS
#define WATER_REFLECTION_STRENGTH 0.8 // [0.05 0.1 0.12 0.2 0.35 0.5 0.65 0.8 1.0]
#define WATER_REFLECTION_HEIGHT 1.5 // [0.0 0.5 1.0 1.5 2.0 3.0]
#define REFLECTION_BLUR 3.0 // [0.0 0.5 1.0 1.5 2.0 3.0]
#define PUDDLE_REFLECTION_STRENGTH 0.7 // [0.03 0.05 0.08 0.1 0.15 0.3 0.4 0.6 1.0]
#define REFLECTION_PALENESS 0.6 // [0.0 0.25 0.5 0.6 0.75 1.0]
#define SUN_GLINT_STRENGTH 0.1 // [0.0 0.1 0.2 0.5 1.0]

// ---- Underwater ----
#define UNDERWATER_FOG
#define UNDERWATER_FOG_STRENGTH 2.0 // [0.5 0.75 1.0 1.5 2.0 3.0]
#define UNDERWATER_RAYS
#define UNDERWATER_RAY_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define UNDERWATER_FOAM
#define UNDERWATER_FOAM_STRENGTH 0.6 // [0.2 0.4 0.6 0.8 1.0 1.5]
#define UNDERWATER_FOAM_SCALE 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define UNDERWATER_CAUSTICS
#define CAUSTIC_STRENGTH 0.3 // [0.25 0.5 1.0 1.5 2.0 3.0]
#define CAUSTIC_SCALE 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define CAUSTIC_SPEED 1.0 // [0.25 0.5 1.0 1.5 2.0]
#define UNDERWATER_SURFACE_Y 62.9 // [50.0 55.0 58.0 60.0 62.9 64.0 66.0 70.0]
#define UNDERWATER_WOBBLE 0.6 // [0.0 0.25 0.6 1.0 1.5]
#define UNDERWATER_BLUR 2.0 // [0.0 0.5 1.0 1.5 2.0]
//#define SCREEN_RAIN_DROPS   // rain / thunder water droplets on the screen that slide down
#define RAIN_LENS_STRENGTH 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define RAIN_LENS_DENSITY 1.0 // [0.4 0.6 0.8 1.0 1.3 1.6]
#define RAIN_LENS_SIZE 1.0 // [0.6 0.8 1.0 1.3 1.6]
#define RAIN_LENS_SPEED 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define LENS_DROP_STRENGTH 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define LENS_DROP_SIZE 1.0 // [0.6 0.8 1.0 1.3 1.6]
#define LENS_DROP_SPEED 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define LENS_DROP_DENSITY 1.0 // [0.4 0.6 0.8 1.0 1.2]

#define CAVE_FOG
#define CAVE_FOG_DENSITY 0.4 // [0.2 0.4 0.75 1.0 1.5 2.0 3.0]

// ---- Weather ----
#define RAIN_FOG_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define STORM_DARKNESS 1.0 // [0.0 0.5 1.0 1.5]
#define RAIN_DROP_OPACITY 1.0 // [0.5 0.75 1.0 1.25 1.5]
#define RAIN_SLANT 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define STORM_EYE
#define STORM_EYE_SIZE 1.25 // [0.7 0.85 1.0 1.25 1.5]
#define STORM_EYE_LIGHT 0.4 // [0.0 0.5 1.0 1.5 2.0]
#define WEATHER_WIND_SWAY 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define PUDDLES
#define PUDDLE_RIPPLES

// ---- Camera ----
#define SUN_GLARE
#define SUN_FLARE
#define SUN_FLARE_STRENGTH 0.3 // [0.2 0.3 0.4 0.6 0.8 1.0 1.5]
#define SUN_GLARE_STRENGTH 0.25 // [0.25 0.5 0.75 1.0 1.5 2.0]

// ---- Nether ----
#define NETHER_FOG
#define NETHER_BRIGHTNESS 0.4 // [0.4 0.5 0.65 0.8 1.0]
#define LAVA_SHADOWS   // realtime screen-space shadows cast by lava light (Nether)
#define LAVA_SHADOW_STRENGTH 0.7 // [0.3 0.5 0.7 0.9 1.0]
#define LAVA_BRIGHTNESS 1.2 // [0.5 1.0 1.5 2.0 3.0]
#define NETHER_FOG_DENSITY 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define NETHER_FOG_VARIATION
#define NETHER_MIST
#define NETHER_EMBERS
#define NETHER_ASH
#define NETHER_HOT_EDGES
#define UNDER_LAVA_FX   // custom molten look when the camera is inside lava
#define LAVA_STEAM   // subtle volumetric steam drifting above lava lakes (Nether)
#define LAVA_STEAM_STRENGTH 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define LAVA_HEAT_DISTORTION   // hot, flame-like screen distortion around lava (Nether)
#define LAVA_HEAT_STRENGTH 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define NETHER_LAVA_FLICKER
//#define NETHER_WIND

// ---- Camera effects ----
#define EYE_ADAPTATION
#define EYE_ADAPTATION_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define MOTION_BLUR
#define MOTION_BLUR_STRENGTH 0.75 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define VIGNETTE_STRENGTH 0.0 // [0.0 0.15 0.3 0.45 0.6]
#define CHROMATIC_ABERRATION 0.0 // [0.0 0.5 1.0 1.5 2.0]
#define FILM_GRAIN 0.0 // [0.0 0.25 0.5 1.0]

// ---- Vegetation ----
#define VEG_LEAF_SWAY 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define VEG_GRASS_SWAY 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define VEG_LANTERN_SWAY 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define VEG_WIND_SPEED 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]

// ---- Clouds ----
#define VOLUMETRIC_CLOUDS
#define CLOUD_QUALITY 1 // [0 1 2]
#define CLOUD_BRIGHTNESS 0.95 // [0.6 0.7 0.85 0.95 1.0 1.2 1.4]
#define CLOUD_OPACITY 1.0 // [0.4 0.6 0.8 1.0]
#define CLOUD_ALTITUDE 340.0 // [160.0 200.0 230.0 280.0 340.0]
#define CLOUD_THICKNESS 110.0 // [60.0 90.0 110.0 140.0 180.0]
#define CLOUD_COVERAGE 0.45 // [0.2 0.3 0.45 0.6 0.75]
#define CLOUD_SIZE 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define CLOUD_DENSITY 1.0 // [0.6 0.8 1.0 1.3 1.6]
#define CLOUD_EROSION 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define CLOUD_SPEED 1.0 // [0.25 0.5 1.0 1.5 2.0 3.0]
#define CLOUD_WIND_ANGLE 15.0 // [0.0 15.0 45.0 90.0 135.0 180.0 225.0 270.0 315.0]
#define HORIZON_CIRRUS
#define HORIZON_CIRRUS_STRENGTH 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define CLOUD_CIRRUS 0.35 // [0.0 0.5 0.8 1.0 1.5]
#define CLOUD_DROPLETS
#define CLOUD_SILVER 1.0 // [0.0 0.5 1.0 1.5 2.0]
#define CLOUD_AMBIENT 1.0 // [0.6 0.8 1.0 1.2 1.5]


// ---- Experimental ----
#define ORE_GLOW
#define ORE_GLOW_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
#define COLOR_GRADE 0 // [0 1 2 3]
//#define CONSTELLATIONS
#define CONSTELLATION_STRENGTH 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define CONSTELLATION_SEASONS
#define NEBULA_SKY
#define NEBULA_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]
//#define FUNNEL
#define FUNNEL_SIZE 1.0 // [0.5 0.75 1.0 1.5 2.0 3.0]
#define FUNNEL_SPEED 1.0 // [0.25 0.5 1.0 1.5 2.0]
#define FUNNEL_BRIGHTNESS 1.0 // [0.5 0.75 1.0 1.5 2.0]
#define FUNNEL_DEBRIS
#define FUNNEL_DUST
#define FUNNEL_DUST_AMOUNT 1.0 // [0.5 1.0 1.5 2.0 3.0]

#endif
