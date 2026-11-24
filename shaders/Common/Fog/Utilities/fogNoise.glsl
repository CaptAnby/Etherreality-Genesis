#ifndef GRAND_OVERLORD_FOG_NOISE_GLSL
#define GRAND_OVERLORD_FOG_NOISE_GLSL

// Small arithmetic hash. Requires no extra texture samplers.
float grandFogHash3(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

// Smooth trilinear value noise in absolute world space.
// The output remains stable as the camera moves through the fog.
float grandFogValueNoise3D(vec3 p) {
    vec3 cell = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float n000 = grandFogHash3(cell + vec3(0.0, 0.0, 0.0));
    float n100 = grandFogHash3(cell + vec3(1.0, 0.0, 0.0));
    float n010 = grandFogHash3(cell + vec3(0.0, 1.0, 0.0));
    float n110 = grandFogHash3(cell + vec3(1.0, 1.0, 0.0));
    float n001 = grandFogHash3(cell + vec3(0.0, 0.0, 1.0));
    float n101 = grandFogHash3(cell + vec3(1.0, 0.0, 1.0));
    float n011 = grandFogHash3(cell + vec3(0.0, 1.0, 1.0));
    float n111 = grandFogHash3(cell + vec3(1.0, 1.0, 1.0));

    float z0 = mix(
        mix(n000, n100, f.x),
        mix(n010, n110, f.x),
        f.y
    );

    float z1 = mix(
        mix(n001, n101, f.x),
        mix(n011, n111, f.x),
        f.y
    );

    return mix(z0, z1, f.z);
}

#endif
