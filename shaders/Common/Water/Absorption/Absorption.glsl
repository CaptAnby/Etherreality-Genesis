// ============================================================
// ETHERREALITY GENESIS :: CLEAR PALE-BLUE WATER ABSORPTION
// ============================================================

uniform float waterClarity =
    0.98;


uniform vec3 waterColor =
    vec3(
        0.45,
        0.68,
        0.86
    );


vec3 applyAbsorption(
    vec3 baseColor,
    float depth
) {

    /*
        Very low absorption = clearer water.
    */
    float clarityFactor =
        mix(
            0.035,
            0.0025,
            waterClarity
        );


    vec3 absorbCoeff =
        vec3(
            clarityFactor * 0.80,
            clarityFactor * 0.92,
            clarityFactor
        );


    vec3 transmittance =
        exp(
            -absorbCoeff *
            depth
        );


    vec3 result =
        mix(
            waterColor * gmDay(),
            baseColor,
            transmittance
        );


    /*
        Keep the water color clean.
    */
    float luminance =
        dot(
            result,
            vec3(
                0.299,
                0.587,
                0.114
            )
        );


    result =
        mix(
            result,
            vec3(
                luminance
            ),
            0.025
        );


    return result;
}