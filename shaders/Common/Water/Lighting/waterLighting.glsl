// ============================================================
// ETHERREALITY GENESIS :: DYNAMIC WATER LIGHTING
// ============================================================
//
// FULL-SURFACE WORLD LIGHTING
//
// The ENTIRE water surface responds to:
//
//   sunrise
//   morning
//   noon
//   afternoon
//   sunset
//   night
//   moonlight
//   rain
//
// Wave normals add surface variation on top of the main
// lighting, instead of being the only visible lighting.
//
// ============================================================


// ============================================================
// IRIS WORLD UNIFORMS
// ============================================================

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;

uniform float sunAngle;
uniform float rainStrength;

uniform vec3 skyColor;


// ============================================================
// TRANSFORM
// ============================================================

uniform mat4 gbufferModelViewInverse;


// ============================================================
// LIGHT COLORS
// ============================================================

const vec3 WATER_DAY_LIGHT =
    vec3(
        1.00,
        0.96,
        0.88
    );


const vec3 WATER_SUNSET_LIGHT =
    vec3(
        1.00,
        0.42,
        0.12
    );


const vec3 WATER_MOON_LIGHT =
    vec3(
        0.48,
        0.62,
        0.88
    );


// ============================================================
// AMBIENT COLORS
// ============================================================

const vec3 WATER_DAY_AMBIENT =
    vec3(
        0.22,
        0.31,
        0.42
    );


const vec3 WATER_NIGHT_AMBIENT =
    vec3(
        0.010,
        0.014,
        0.024
    );


// ============================================================
// SUN DIRECTION
// ============================================================

vec3 getWaterSunDirection()
{
    return normalize(
        mat3(
            gbufferModelViewInverse
        )
        *
        normalize(
            sunPosition
        )
    );
}


// ============================================================
// MOON DIRECTION
// ============================================================

vec3 getWaterMoonDirection()
{
    return normalize(
        mat3(
            gbufferModelViewInverse
        )
        *
        normalize(
            moonPosition
        )
    );
}


// ============================================================
// ACTIVE CELESTIAL DIRECTION
// ============================================================

vec3 getWaterActiveLightDirection()
{
    return normalize(
        mat3(
            gbufferModelViewInverse
        )
        *
        normalize(
            shadowLightPosition
        )
    );
}


// ============================================================
// SUN HEIGHT
// ============================================================

float getWaterSunHeight()
{
    return
        getWaterSunDirection().y;
}


// ============================================================
// DAY FACTOR
// ============================================================

float getWaterDayFactor()
{
    float sunHeight =
        getWaterSunHeight();


    return smoothstep(
        -0.10,
        0.16,
        sunHeight
    );
}


// ============================================================
// SUNRISE FACTOR
// ============================================================

float getWaterSunriseFactor()
{
    float sunHeight =
        getWaterSunHeight();


    float horizon =
        1.0 -
        smoothstep(
            0.015,
            0.28,
            max(
                sunHeight,
                0.0
            )
        );


    float morning =
        1.0 -
        smoothstep(
            0.08,
            0.22,
            sunAngle
        );


    return
        horizon *
        morning *
        smoothstep(
            -0.03,
            0.09,
            sunHeight
        );
}


// ============================================================
// SUNSET FACTOR
// ============================================================

float getWaterSunsetFactor()
{
    float sunHeight =
        getWaterSunHeight();


    float horizon =
        1.0 -
        smoothstep(
            0.015,
            0.28,
            max(
                sunHeight,
                0.0
            )
        );


    float evening =
        smoothstep(
            0.30,
            0.50,
            sunAngle
        );


    return
        horizon *
        evening *
        smoothstep(
            -0.03,
            0.09,
            sunHeight
        );
}


// ============================================================
// GOLDEN HOUR
// ============================================================

float getWaterGoldenHour()
{
    float sunrise =
        getWaterSunriseFactor();


    float sunset =
        getWaterSunsetFactor();


    return clamp(
        max(
            sunrise,
            sunset
        ),
        0.0,
        1.0
    );
}


// ============================================================
// FULL SOLAR COLOR
// ============================================================

vec3 getWaterSolarColor()
{
    float goldenHour =
        getWaterGoldenHour();


    /*
        Normal daytime sunlight.
    */
    vec3 solarColor =
        WATER_DAY_LIGHT;


    /*
        Smoothly move the ENTIRE solar illumination
        toward warm orange near sunrise / sunset.
    */
    solarColor =
        mix(
            solarColor,
            WATER_SUNSET_LIGHT,
            goldenHour
        );


    /*
        Rain/clouds reduce saturation.
    */
    solarColor =
        mix(
            solarColor,
            vec3(
                0.78,
                0.84,
                0.91
            ),
            rainStrength *
            0.30
        );


    return solarColor;
}


// ============================================================
// ACTIVE CELESTIAL COLOR
// ============================================================

vec3 getWaterCelestialColor()
{
    float day =
        getWaterDayFactor();


    vec3 solarColor =
        getWaterSolarColor();


    return mix(
        WATER_MOON_LIGHT,
        solarColor,
        day
    );
}


// ============================================================
// FULL-SURFACE AMBIENT
// ============================================================

vec3 getWaterAmbientLight()
{
    float day =
        getWaterDayFactor();


    vec3 ambient =
        mix(
            WATER_NIGHT_AMBIENT,
            WATER_DAY_AMBIENT,
            day
        );


    /*
        Actual sky contributes to the entire water body.
    */
    ambient +=
        skyColor *
        0.16;


    /*
        Rain/cloud cover reduces brightness.
    */
    ambient *=
        mix(
            1.0,
            0.72,
            rainStrength
        );


    return ambient;
}


// ============================================================
// FULL-SURFACE DIRECT LIGHT
// ============================================================
//
// The water receives broad illumination from the active
// celestial source.
//
// This is intentionally NOT dependent on a tiny specular
// highlight.
//

float getWaterDirectLight(
    vec3 normal
)
{
    vec3 lightDirection =
        getWaterActiveLightDirection();


    float ndotl =
        max(
            dot(
                normal,
                lightDirection
            ),
            0.0
        );


    /*
        Start with broad ambient-like exposure so the
        entire illuminated water body responds.
    */
    float broadLight =
        0.42 +
        ndotl *
        0.58;


    broadLight =
        smoothstep(
            0.20,
            1.0,
            broadLight
        );


    /*
        Clouds/rain soften direct illumination.
    */
    broadLight *=
        mix(
            1.0,
            0.58,
            rainStrength
        );


    return broadLight;
}


// ============================================================
// FULL WATER SOLAR EXPOSURE
// ============================================================
//
// Broad sunlight across the whole water surface.
//
// Near the sun-facing reflection direction the water becomes
// brighter, but the rest of the surface still receives light.
//

float getWaterSolarExposure(
    vec3 normal,
    vec3 viewDirection
)
{
    vec3 sunDirection =
        getWaterSunDirection();


    vec3 reflectionDirection =
        reflect(
            -viewDirection,
            normal
        );


    float sunAlignment =
        max(
            dot(
                reflectionDirection,
                sunDirection
            ),
            0.0
        );


    /*
        Very broad falloff.
    */
    float broadGlow =
        pow(
            sunAlignment,
            3.5
        );


    /*
        Broad surface exposure.
    */
    float exposure =
        0.35 +
        broadGlow *
        0.65;


    /*
        Only active while the sun is above the horizon.
    */
    exposure *=
        getWaterDayFactor();


    /*
        Rain softens the response.
    */
    exposure *=
        mix(
            1.0,
            0.55,
            rainStrength
        );


    return clamp(
        exposure,
        0.0,
        1.0
    );
}


// ============================================================
// SUNSET WARMTH
// ============================================================
//
// This affects the WHOLE illuminated water surface.
//

float getWaterWarmth(
    vec3 normal
)
{
    float goldenHour =
        getWaterGoldenHour();


    float direct =
        getWaterDirectLight(
            normal
        );


    /*
        Warmth does not disappear when the surface isn't
        facing perfectly toward the sun.
    */
    return clamp(
        goldenHour *
        (
            0.55 +
            direct *
            0.45
        ),
        0.0,
        1.0
    );
}


// ============================================================
// MOON EXPOSURE
// ============================================================

float getWaterMoonExposure(
    vec3 normal,
    vec3 viewDirection
)
{
    vec3 moonDirection =
        getWaterMoonDirection();


    vec3 reflectionDirection =
        reflect(
            -viewDirection,
            normal
        );


    float alignment =
        max(
            dot(
                reflectionDirection,
                moonDirection
            ),
            0.0
        );


    float exposure =
        pow(
            alignment,
            5.0
        );


    /*
        Keep moonlight broad.
    */
    exposure =
        0.25 +
        exposure *
        0.75;


    exposure *=
        1.0 -
        getWaterDayFactor();


    return clamp(
        exposure,
        0.0,
        1.0
    );
}


// ============================================================
// CELESTIAL SPECULAR
// ============================================================

float getWaterSpecular(
    vec3 normal,
    vec3 viewDirection
)
{
    vec3 lightDirection =
        getWaterActiveLightDirection();


    vec3 halfVector =
        normalize(
            lightDirection +
            viewDirection
        );


    float highlight =
        max(
            dot(
                normal,
                halfVector
            ),
            0.0
        );


    /*
        Broad, smooth highlight.
    */
    float specular =
        pow(
            highlight,
            30.0
        );


    specular *=
        mix(
            1.0,
            0.48,
            rainStrength
        );


    return specular;
}


// ============================================================
// SKY / BACKGROUND SPECULAR
// ============================================================

float getWaterSkySpecular(
    vec3 normal,
    vec3 viewDirection
)
{
    vec3 reflectionDirection =
        reflect(
            -viewDirection,
            normal
        );


    float skyFactor =
        clamp(
            reflectionDirection.y *
            0.5 +
            0.5,
            0.0,
            1.0
        );


    skyFactor =
        pow(
            skyFactor,
            2.2
        );


    float grazing =
        1.0 -
        clamp(
            dot(
                normal,
                viewDirection
            ),
            0.0,
            1.0
        );


    grazing =
        grazing *
        grazing;


    return
        skyFactor *
        grazing;
}


// ============================================================
// COMPLETE WATER LIGHTING
// ============================================================

vec3 getDynamicWaterLighting(
    vec3 normal,
    vec3 worldPosition
)
{
    normal =
        normalize(
            normal
        );


    vec3 viewDirection =
        normalize(
            cameraPosition -
            worldPosition
        );


    float day =
        getWaterDayFactor();


    vec3 celestialColor =
        getWaterCelestialColor();


    vec3 solarColor =
        getWaterSolarColor();


    vec3 ambient =
        getWaterAmbientLight();


    float direct =
        getWaterDirectLight(
            normal
        );


    float solarExposure =
        getWaterSolarExposure(
            normal,
            viewDirection
        );


    float warmth =
        getWaterWarmth(
            normal
        );


    float moonExposure =
        getWaterMoonExposure(
            normal,
            viewDirection
        );


    float specular =
        getWaterSpecular(
            normal,
            viewDirection
        );


    float skySpecular =
        getWaterSkySpecular(
            normal,
            viewDirection
        );


    // ========================================================
    // START WITH FULL-SURFACE AMBIENT
    // ========================================================

    vec3 lighting =
        ambient;


    // ========================================================
    // DAY / NIGHT DIRECT LIGHT
    // ========================================================

    lighting +=
        celestialColor *
        direct *
        mix(0.14, 0.88, day);


    // ========================================================
    // BROAD SOLAR EXPOSURE
    // ========================================================

    lighting +=
        solarColor *
        solarExposure *
        0.42;


    // ========================================================
    // WHOLE-SURFACE SUNSET WARMTH
    // ========================================================

    lighting +=
        WATER_SUNSET_LIGHT *
        warmth *
        0.68;


    // ========================================================
    // MOONLIGHT
    // ========================================================

    lighting +=
        WATER_MOON_LIGHT *
        moonExposure *
        0.08;


    // ========================================================
    // CELESTIAL HIGHLIGHT
    // ========================================================

    lighting +=
        celestialColor *
        specular *
        0.45;


    // ========================================================
    // SKY HIGHLIGHT
    // ========================================================

    lighting +=
        skyColor *
        skySpecular *
        0.16;


    // ========================================================
    // NIGHT FLOOR
    // ========================================================

    lighting +=
        vec3(
            0.002,
            0.003,
            0.005
        )
        *
        (
            1.0 -
            day
        );


    return lighting;
}