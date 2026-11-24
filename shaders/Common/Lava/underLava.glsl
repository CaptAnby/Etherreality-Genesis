// ============================================================
// ETHERREALITY GENESIS :: UNDER LAVA (vanilla-style)
// Needs (declared by the including file): colortex0, depthtex0,
// gbufferProjectionInverse, viewWidth, viewHeight.
// ============================================================

vec3 underLava(vec2 uv) {
    vec3 c = texture(colortex0, uv).rgb;

    float d = texture(depthtex0, uv).r;
    float dist = 6.0;
    if (d < 0.999999) {
        vec4 v = gbufferProjectionInverse * vec4(vec3(uv, d) * 2.0 - 1.0, 1.0);
        dist = min(length(v.xyz / v.w), 6.0);
    }
    // vanilla: very short visibility, flat orange
    float fog = clamp(0.7 + 0.3 * (1.0 - exp(-dist * 1.2)), 0.0, 1.0);
    return mix(c * vec3(1.0, 0.45, 0.15), vec3(0.85, 0.32, 0.04), fog);
}
