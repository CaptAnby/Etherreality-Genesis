// THE END: CPS001 directional-light shadow projection (shared by shadow pass + deferred)
#define END_LIGHT_DIR normalize(vec3(0.0, 0.20, 0.98))
#define END_SHADOW_RANGE 128.0
vec3 endShadowClip(vec3 pp) {
    vec3 L = END_LIGHT_DIR;
    vec3 r = normalize(cross(vec3(0.0, 1.0, 0.0), L));
    vec3 u = cross(L, r);
    return vec3(dot(pp, r), dot(pp, u), -dot(pp, L) * 0.5) / END_SHADOW_RANGE;
}
