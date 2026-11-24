#ifndef GRAND_OVERLORD_FOG_RAYMARCH_GLSL
#define GRAND_OVERLORD_FOG_RAYMARCH_GLSL

#include "/Common/Fog/fogConfig.glsl"

// ------------------------------------------------------------
// PERFORMANCE DEFAULTS
// ------------------------------------------------------------
// Define these in fogConfig.glsl to override the defaults.
//
// 0.75 = use up to 75% of the configured maximum step count.
// 1.00 = retain the original maximum step budget.
//
// The far-step scale gradually increases the target step length
// for longer rays, reducing sample demand at distance.
// ------------------------------------------------------------

#ifndef GRAND_FOG_PERFORMANCE_STEP_BUDGET
#define GRAND_FOG_PERFORMANCE_STEP_BUDGET 0.75
#endif

#ifndef GRAND_FOG_PERFORMANCE_FAR_STEP_SCALE
#define GRAND_FOG_PERFORMANCE_FAR_STEP_SCALE 1.25
#endif

#include "/Common/Fog/Density/fogDensity.glsl"
#include "/Common/Fog/Distance/fogDistance.glsl"
#include "/Common/Fog/Lighting/fogLighting.glsl"

// ============================================================
// ETHERREALITY GENESIS :: VOLUMETRIC FOG :: OPTIMIZED RAYMARCH
// ============================================================
// Returns premultiplied in-scattered light in RGB and opacity in A.
// Composite as:
//
//     scene * (1.0 - fog.a) + fog.rgb
//
// Performance improvements:
// - Reject rays that never intersect the fog-height range.
// - March only through the intersecting section of the ray.
// - Cache weather and lighting once per ray.
// - Reduce the maximum active step budget.
// - Use a dynamic loop bound.
// - Stop early when the fog becomes effectively opaque.
// ============================================================

vec4 renderGrandVolumetricFog(
    vec3 rayOrigin,
    vec3 rayDirection,
    float maxDistance,
    float dither,
    vec3 lightDirection,
    float time,
    float sunAngleValue
) {
    float rayDistance = min(
        max(maxDistance, 0.0),
        GRAND_FOG_MAX_DISTANCE
    );

    if (rayDistance <= 0.5) {
        return vec4(0.0);
    }

    vec3 direction = normalize(rayDirection);

    // --------------------------------------------------------
    // INTERSECT THE RAY WITH THE EFFECTIVE FOG HEIGHT
    // --------------------------------------------------------
    // Below the lower fade, the density function returns zero.
    // Above this upper bound, its height envelope is negligible.
    // Avoid marching through those empty sections entirely.

    float fogBottom =
        GRAND_FOG_BASE_HEIGHT - GRAND_FOG_GROUND_SOFTNESS;

    float heightFalloff = GRAND_FOG_HEIGHT_FALLOFF;
    float rayEndY = rayOrigin.y + direction.y * rayDistance;

    float fogTop;

    if (heightFalloff > 0.001) {
        fogTop =
            GRAND_FOG_BASE_HEIGHT + 9.22 / heightFalloff;
    } else {
        // With almost no exponential falloff, do not impose an
        // arbitrary upper cutoff on the existing density field.
        fogTop = max(rayOrigin.y, rayEndY) + 1.0;
    }

    float rayMinY = min(rayOrigin.y, rayEndY);
    float rayMaxY = max(rayOrigin.y, rayEndY);

    // The entire ray lies outside the effective fog layer.
    if (rayMaxY < fogBottom || rayMinY > fogTop) {
        return vec4(0.0);
    }

    float marchStart = 0.0;
    float marchEnd = rayDistance;

    if (abs(direction.y) > 0.000001) {
        float tBottom =
            (fogBottom - rayOrigin.y) / direction.y;

        float tTop =
            (fogTop - rayOrigin.y) / direction.y;

        float enterDistance = min(tBottom, tTop);
        float exitDistance = max(tBottom, tTop);

        marchStart = max(enterDistance, 0.0);
        marchEnd = min(exitDistance, rayDistance);
    }

    float marchDistance = marchEnd - marchStart;

    if (marchDistance <= 0.5) {
        return vec4(0.0);
    }

    // --------------------------------------------------------
    // ADAPTIVE SAMPLE BUDGET
    // --------------------------------------------------------
    float maxConfiguredSteps =
        float(GRAND_FOG_RAYMARCH_STEPS);

    float stepBudgetRatio = clamp(
        GRAND_FOG_PERFORMANCE_STEP_BUDGET,
        0.50,
        1.0
    );

    int performanceStepBudget = int(
        maxConfiguredSteps * stepBudgetRatio
    );

    performanceStepBudget = clamp(
        performanceStepBudget,
        GRAND_FOG_MIN_STEPS,
        GRAND_FOG_RAYMARCH_STEPS
    );

    // Increase step length gradually for longer fog segments.
    // Short segments preserve the original sampling density.
    float distanceRatio = clamp(
        marchDistance / max(GRAND_FOG_MAX_DISTANCE, 1.0),
        0.0,
        1.0
    );

    float farStepBlend = smoothstep(
        0.15,
        0.75,
        distanceRatio
    );

    float farStepScale = max(
        GRAND_FOG_PERFORMANCE_FAR_STEP_SCALE,
        1.0
    );

    float targetStepLength =
        max(GRAND_FOG_TARGET_STEP_LENGTH, 1.0) *
        mix(1.0, farStepScale, farStepBlend);

    int requestedSteps = int(ceil(
        marchDistance / targetStepLength
    ));

    int activeSteps = clamp(
        requestedSteps,
        GRAND_FOG_MIN_STEPS,
        performanceStepBudget
    );

    float stepLength =
        marchDistance / float(activeSteps);

    // --------------------------------------------------------
    // CACHE PIXEL-CONSTANT VALUES
    // --------------------------------------------------------
    // Weather x area (forest / sea) x time-of-day, cached once per ray.
    float weatherMultiplier =
        grandFogWeatherMultiplier() *
        grandFogAreaMultiplier() *
        grandFogTimeMultiplier(sunAngleValue);

    if (weatherMultiplier <= 0.0) {
        return vec4(0.0);
    }

    vec3 lighting = grandFogLighting(
        direction,
        lightDirection,
        sunAngleValue
    );

    float pixelJitter = clamp(dither, 0.0, 1.0);

    float transmittance = 1.0;
    vec3 scattered = vec3(0.0);

    // --------------------------------------------------------
    // VOLUMETRIC INTEGRATION
    // --------------------------------------------------------
    // The loop runs only for activeSteps rather than the full
    // configured maximum. Jitter distributes samples within
    // each segment to reduce visible marching bands.

    for (int i = 0; i < activeSteps; ++i) {
        if (
            transmittance <=
            GRAND_FOG_OPAQUE_TRANSMITTANCE
        ) {
            break;
        }

        float segmentJitter = fract(
            pixelJitter + float(i) * 0.61803398875
        );

        float localOffset = mix(
            0.18,
            0.82,
            segmentJitter
        );

        float t =
            marchStart +
            (float(i) + localOffset) * stepLength;

        vec3 samplePosition =
            rayOrigin + direction * t;

        float density = grandFogDensityAtWithWeather(
            samplePosition,
            time,
            weatherMultiplier
        );

        if (density > GRAND_FOG_EMPTY_THRESHOLD) {
            float opticalDepth =
                density *
                GRAND_FOG_EXTINCTION *
                stepLength;

            float stepTransmittance = exp(-opticalDepth);
            float stepAlpha = 1.0 - stepTransmittance;

            float core = clamp(density * 260.0, 0.0, 1.0);

            scattered +=
                lighting * mix(1.0, 0.80, core) *
                stepAlpha * transmittance;

            transmittance *= stepTransmittance;
        }
    }

    return vec4(
        max(scattered, vec3(0.0)),
        clamp(1.0 - transmittance, 0.0, 1.0)
    );
}

#endif