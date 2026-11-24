#version 330 compatibility
#include "/settings.glsl"

uniform sampler2D lightmap;
uniform sampler2D gtexture;
uniform float alphaTestRef = 0.1;
uniform int blockEntityId;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;
in vec3 normal;
in vec3 portalWorld;

/* RENDERTARGETS: 0,1,3 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalData;
layout(location = 3) out vec4 lightmapData;

#ifdef END_PORTAL_FX
float epHash(vec2 p) {
    p = mod(p, 509.0);
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float epNoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(epHash(i), epHash(i + vec2(1.0, 0.0)), f.x),
               mix(epHash(i + vec2(0.0, 1.0)), epHash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float epFbm(vec2 p) {
    float a = 0.5, r = 0.0;
    for (int i = 0; i < 4; i++) { r += a * epNoise(p); p = p * 2.03 + 7.1; a *= 0.5; }
    return r;
}

// End portal: black void with true parallax depth. Many star layers sit at different depths below the
// surface (each star has its own slow orbit), plus a few faint, stretched nebula streaks drifting on their own.
vec3 endPortalColor(vec3 wp) {
    vec3 vd = normalize(wp - cameraPosition);
    float t = frameTimeCounter;
    vec3 col = vec3(0.002, 0.0, 0.006);
    // ray travel per block of depth below the portal surface (real parallax)
    float slope = min(1.0 / max(abs(vd.y), 0.05), 4.0);

    // ---- nebula streaks (3 depths, each drifting in its own direction) ----
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float depth = 0.7 + fi * 1.3;
        vec2 uv = wp.xz + vd.xz * slope * depth;
        float ang = 0.6 + fi * 2.1;
        vec2 dir = vec2(cos(ang), sin(ang));
        vec2 perp = vec2(-dir.y, dir.x);
        float sp = 0.010 + fi * 0.006;
        vec2 drift = dir * t * sp + perp * sin(t * 0.03 + fi * 4.0) * 0.4;
        vec2 p = uv + drift;
        // stretch along 'dir' so the clouds become long thin streaks
        vec2 q = vec2(dot(p, dir) * 0.35, dot(p, perp) * 1.6) + vec2(fi * 13.7, fi * 5.3);
        float n = epFbm(q);
        float streak = smoothstep(0.52, 0.80, n);
        // patchy mask so most of the portal stays black
        float mask = smoothstep(0.40, 0.75, epNoise(p * 0.22 + fi * 9.1));
        float cmix = smoothstep(0.35, 0.65, epNoise(p * 0.15 + fi * 3.3 + 50.0));
        vec3 nebCol = mix(vec3(0.12, 0.90, 0.40), vec3(0.58, 0.16, 0.95), cmix);
        col += nebCol * streak * mask * 0.55 / (1.0 + fi * 0.45);
    }

    // ---- stars: 10 depth layers, each star orbits slowly on its own ----
    for (int i = 0; i < 10; i++) {
        float fi = float(i);
        float depth = 0.08 * pow(1.45, fi);          // 0.08 .. ~4.2 blocks deep
        vec2 uv = wp.xz + vd.xz * slope * depth;
        float a = fi * 0.83;
        uv = mat2(cos(a), -sin(a), sin(a), cos(a)) * uv + fi * 31.7;
        float dens = 3.0 + fi * 0.9;                 // deeper = denser and smaller
        vec2 g = uv * dens;
        vec2 cell = floor(g);
        vec2 f = fract(g);
        float h = epHash(cell + fi * 17.0);
        if (h > 0.30) continue;                      // sparse
        float h1 = epHash(cell + 3.1 + fi * 7.0);
        float h2 = epHash(cell + 9.7 + fi * 5.0);
        float h3 = epHash(cell + 21.3 + fi * 2.0);
        // individual slow orbit inside the cell
        vec2 pos = vec2(0.5) + 0.30 * vec2(sin(t * (0.05 + 0.12 * h1) + h2 * 6.283),
                                            cos(t * (0.05 + 0.12 * h2) + h1 * 6.283));
        float size = (0.07 + 0.07 * h3) * (1.0 - fi * 0.04);
        vec2 d = abs(f - pos);
        if (max(d.x, d.y) < size) {                  // blocky square star
            float tw = 0.85 + 0.15 * sin(t * (0.4 + h1) + h2 * 20.0);
            vec3 sc = mix(vec3(0.80, 0.92, 1.0), vec3(1.0, 0.95, 0.78), h3);
            if (h2 > 0.9) sc = mix(sc, vec3(0.7, 1.0, 0.8), 0.6);
            else if (h1 > 0.92) sc = mix(sc, vec3(0.85, 0.7, 1.0), 0.6);
            col += sc * tw * 4.0 * (1.0 - fi * 0.055);   // farther = dimmer
        }
    }
    return col * END_PORTAL_STRENGTH;
}
#endif

void main() {
#ifdef END_PORTAL_FX
    if (blockEntityId == 31900) {
        color = vec4(endPortalColor(portalWorld), 1.0);
        normalData = vec4(normalize(normal) * 0.5 + 0.5, 1.0);
        lightmapData = vec4(1.0, 1.0, 0.0, 1.0);
        return;
    }
#endif
    color = texture(gtexture, texcoord) * glcolor;
    color *= texture(lightmap, lmcoord);

    if (color.a < alphaTestRef) {
        discard;
    }

    normalData = vec4(
        normalize(normal) * 0.5 + 0.5,
        1.0
    );

    lightmapData = vec4(
        lmcoord,
        0.0,
        1.0
    );
}
