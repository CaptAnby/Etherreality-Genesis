uniform float frameTimeCounter;

vec3 refractionColor(sampler2D colortex, vec2 uv, vec3 normal, float waterDepth) {
    float distortStrength = clamp(waterDepth * 0.5, 0.0, 1.0) * 0.012;
    // travelling wave refraction: blocks below ripple like real moving water
    float wt = frameTimeCounter;
    float wobAmt = clamp(0.45 + waterDepth * 0.35, 0.0, 1.0) * 0.0025;
    float w1 = sin(dot(uv, vec2(38.0, 21.0)) + wt * 1.9);
    float w2 = sin(dot(uv, vec2(-27.0, 44.0)) - wt * 1.5);
    float w3 = sin(dot(uv, vec2(71.0, -33.0)) + wt * 2.6) * 0.5;
    float w4 = sin(dot(uv, vec2(18.0, 63.0)) - wt * 2.1) * 0.5;
    vec2 wobble = vec2(w1 + w3 + w2 * 0.4, w2 + w4 + w1 * 0.4) * wobAmt;

    // wave distortion only (follows the wave normals; no screen-space wobble that could glitch)
    vec2 distortedUV = uv + normal.xz * distortStrength * 1.6;

    // clamp so we never sample outside screen (prevents black edge artifacts)
    distortedUV = clamp(distortedUV, vec2(0.001), vec2(0.999));

    // reject samples that land on a foreground block (stops edge warping)
    float surfD = texture(depthtex0, uv).r;
    float hitD = texture(depthtex1, distortedUV).r;
    if (hitD < surfD - 0.00005) {
        distortedUV = uv;
    }
    vec3 refracted = texture(colortex, distortedUV).rgb;

    // slight chromatic aberration for realism
    vec3 refractedCA;
    refractedCA.r = texture(colortex, distortedUV + normal.xz * 0.0005).r;
    refractedCA.g = refracted.g;
    refractedCA.b = texture(colortex, distortedUV - normal.xz * 0.0005).b;

    return refractedCA;
}