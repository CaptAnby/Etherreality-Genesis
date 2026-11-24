// ============================================================
// ETHERREALITY GENESIS :: UNDERWATER FOG
// ============================================================

vec3 underwaterFog(
    vec3 color,
    float dist
) {

    vec3 fogColor =
        vec3(
            0.52,
            0.71,
            0.85
        );


    float fogFactor =
        1.0 -
        exp(
            -dist *
            0.024
        );


    return mix(
        color,
        fogColor,
        fogFactor
    );
}