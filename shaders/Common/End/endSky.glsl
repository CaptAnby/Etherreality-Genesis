// PHENYX-style End sky: CPS001 pulsar, nebula belt, nebula clouds, starfield (procedural, world-space)

float esHash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float esNoise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(esHash(i), esHash(i + vec3(1,0,0)), f.x),
                   mix(esHash(i + vec3(0,1,0)), esHash(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(esHash(i + vec3(0,0,1)), esHash(i + vec3(1,0,1)), f.x),
                   mix(esHash(i + vec3(0,1,1)), esHash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float esFbm(vec3 p) {
    float a = 0.5;
    float r = 0.0;
    for (int i = 0; i < 4; i++) {
        r += a * esNoise(p);
        p = p * 2.03 + 11.7;
        a *= 0.5;
    }
    return r;
}

// CPS001 stays (almost) the same distance from you however far you travel: unreachable like the sun,
// with only a tiny bit of parallax (3% of your movement).
#define ES_P_OF(c) (vec3(0.0, 150.0, 700.0) + (c) * 0.97)

// fixed world-space pulsar beam axis (precesses about a rotation axis; sweeps through the map once per turn)
vec3 endAxis(float t, vec3 cam) {
    vec3 Sref = normalize(ES_P_OF(cam) - vec3(0.0, 90.0, 0.0));
    float spin = t * 0.7 * CPS001_SWEEP_SPEED + 0.35 * sin(t * 0.25 * CPS001_SWEEP_SPEED);
    float incl = 1.35;
    float gam = incl - 0.04;
    vec3 Rr = normalize(cross(vec3(0.0, 1.0, 0.0), Sref));
    vec3 Ur = cross(Sref, Rr);
    vec3 Om = normalize(-Sref * cos(gam) + Ur * sin(gam));
    vec3 E1 = normalize(cross(Om, Sref));
    vec3 E2 = cross(Om, E1);
    return normalize(cos(incl) * Om + sin(incl) * (cos(spin) * E1 + sin(spin) * E2));
}

// volumetric beam glow along a view ray, up to maxT (scene distance for terrain pixels, huge for sky)
vec3 endBeamGlow(vec3 dir, vec3 cam, float t, float maxT) {
    vec3 Ax = endAxis(t, cam);
    vec3 wv = cam - ES_P_OF(cam);
    vec3 acc = vec3(0.0);
    for (int bi = 0; bi < 2; bi++) {
        vec3 A = (bi == 0) ? Ax : -Ax;
        float bb = dot(dir, A);
        float den = max(1.0 - bb * bb, 1e-4);
        float dv = dot(dir, wv);
        float ev = dot(A, wv);
        float tv = (bb * ev - dv) / den;
        float sb = (ev - bb * dv) / den;
        if (tv > 0.0 && tv < maxT && sb > 12.0) {
            float dist = length((cam + dir * tv) - (ES_P_OF(cam) + A * sb));
            float wBeam = 3.0 + 0.085 * sb;
            float prof = exp(-(dist * dist) / (wBeam * wBeam));
            float lenFade = exp(-sb / 1000.0) * smoothstep(12.0, 70.0, sb) * (1.0 - smoothstep(1500.0, 2200.0, sb));
            float wide = exp(-(dist * dist) / (wBeam * wBeam * 9.0));   // soft scattered halo around the thin core
            vec3 bc = mix(vec3(0.55, 0.22, 1.0), vec3(0.70, 0.85, 1.0), exp(-sb / 260.0));
            acc += bc * (prof * 1.5 + wide * 0.35) * lenFade * (0.85 + 0.15 * sin(sb * 0.05 - t * 3.0));
        }
    }
    return acc;
}

// light the beam throws onto surfaces it touches (world position X, world normal Nw)
vec3 endBeamLight(vec3 X, vec3 Nw, float t, vec3 cam) {
    vec3 Ax = endAxis(t, cam);
    vec3 tot = vec3(0.0);
    for (int bi = 0; bi < 2; bi++) {
        vec3 A = (bi == 0) ? Ax : -Ax;
        vec3 rel = X - ES_P_OF(cam);
        float s = dot(rel, A);
        if (s > 12.0) {
            float d = length(rel - A * s);
            float w = (7.0 + 0.07 * s) * 1.6;
            float prof = exp(-(d * d) / (w * w));
            float lf = exp(-s / 1200.0) * smoothstep(12.0, 70.0, s);
            float facing = 0.35 + 0.65 * max(dot(Nw, -A), 0.0);
            tot += mix(vec3(0.60, 0.25, 1.0), vec3(0.75, 0.85, 1.0), exp(-s / 300.0)) * prof * lf * facing;
        }
    }
    return tot * 1.8;
}


float esFbm3(vec3 p) {
    float a = 0.5;
    float r = 0.0;
    for (int i = 0; i < 3; i++) {
        r += a * esNoise(p);
        p = p * 2.03 + 11.7;
        a *= 0.5;
    }
    return r;
}

// Nebula Cosmic Clouds: soft volumetric clouds in world space around/above/below the map (reachable).
// returns (accumulated light, transmittance)
vec4 endCosmicClouds(vec3 dir, vec3 cam, float t, float maxT, float dither) {
    float tEnd = min(maxT, 700.0);
    const int STEPS = 10;
    float dt = tEnd / float(STEPS);
    float T = 1.0;
    vec3 acc = vec3(0.0);
    for (int i = 0; i < STEPS; i++) {
        float d = (float(i) + dither) * dt;
        vec3 wp = cam + dir * d;
        vec3 q = wp * 0.011 + vec3(t * 0.004, t * 0.0015, -t * 0.003);
        float n = esFbm3(q);
        float mask = smoothstep(70.0, 240.0, length(wp - vec3(0.0, 70.0, 0.0)));
        float dens = smoothstep(0.50, 0.78, n) * mask;
        if (dens > 0.001) {
            float hueN = esNoise(q * 0.6 + 4.0);
            vec3 c1 = mix(vec3(0.16, 0.26, 0.80), vec3(0.50, 0.20, 0.80), hueN);
            c1 = mix(c1, vec3(0.20, 0.62, 0.82), smoothstep(0.6, 0.9, esNoise(q * 0.4 + 9.0)) * 0.6);
            c1 = mix(c1, vec3(0.9, 0.45, 0.75), smoothstep(0.78, 0.95, hueN) * 0.35);
            // brighter toward the pulsar's side, softer inside dense cores
            float toward = 0.6 + 0.5 * max(dot(normalize(ES_P_OF(cam) - wp), dir), 0.0);
            float a = 1.0 - exp(-dens * dt * 0.035);
            acc += T * a * c1 * toward * 0.65;
            T *= 1.0 - a;
        }
    }
    return vec4(acc, T);
}

// 3D volumetric nebula fog: drifting coloured gas that fills the air around the island (world space, reachable).
// returns (accumulated light, transmittance)
vec4 endNebulaFog(vec3 dir, vec3 cam, float t, float maxT, float dither) {
    float tEnd = min(maxT, 360.0);
    const int FSTEPS = 12;
    float dt = tEnd / float(FSTEPS);
    float T = 1.0;
    vec3 acc = vec3(0.0);
    vec3 Ax = endAxis(t, cam);
    for (int i = 0; i < FSTEPS; i++) {
        float d = (float(i) + dither) * dt;
        vec3 wp = cam + dir * d;
        vec3 q = wp * 0.016 + vec3(t * 0.005, t * 0.0015, -t * 0.004);
        float n = esFbm3(q + 0.35 * esNoise(q * 0.5 + 2.0));       // warped, billowy
        float hf = exp(-abs(wp.y - 80.0) / 85.0);
        float dens = (smoothstep(0.26, 0.72, n) * 0.9 + 0.12) * hf;
        if (dens > 0.001) {
            float hueN = esNoise(q * 0.5 + 4.0);
            vec3 c = mix(vec3(0.16, 0.24, 0.75), vec3(0.50, 0.20, 0.78), hueN);
            c = mix(c, vec3(0.20, 0.60, 0.80), smoothstep(0.6, 0.9, esNoise(q * 0.35 + 9.0)) * 0.5);
            vec3 toP = normalize(ES_P_OF(cam) - wp);
            float lit = 0.55 + 0.45 * max(dot(toP, dir), 0.0);
            float beam = pow(max(abs(dot(toP, Ax)), 0.0), 8.0);   // gas brightens when the pulsar beam sweeps it
            float a = 1.0 - exp(-dens * dt * 0.022 * NEBULA_FOG_STRENGTH);
            c = mix(c, vec3(0.92, 0.45, 0.80), smoothstep(0.65, 0.9, n) * 0.35);   // warm pink cores
            acc += T * a * c * (lit + beam * 1.2) * 0.75;
            T *= 1.0 - a;
        }
    }
    return vec4(acc, T);
}


// Soft cosmic-purple light beams rising from each of the 10 End pillars (vanilla ring: radius 42, every 36 degrees).
// Vertical cylinders of glow that stretch up into the sky and fade out smoothly (no hard end).
vec3 endPillarBeams(vec3 dir, vec3 cam, float t, float maxT) {
    vec3 acc = vec3(0.0);
#ifndef END_BEAMS
    return acc;
#endif
    vec2 dxz = dir.xz;
    float dd = max(dot(dxz, dxz), 1e-4);
    for (int k = 0; k < 10; k++) {
        float fk = float(k);
        float ang = fk * 0.62831853;
        vec2 P = 42.0 * vec2(cos(ang), sin(ang));
        float tm = clamp(dot(P - cam.xz, dxz) / dd, 0.0, maxT);
        vec3 q = cam + dir * tm;
        float dist = length(q.xz - P);
        float h = q.y - 66.0;
        float w = 2.2 + 0.012 * max(h, 0.0);               // beam slowly widens as it climbs
        float core = exp(-(dist * dist) / (w * w));
        float halo = exp(-(dist * dist) / (w * w * 14.0));
        float up = smoothstep(-6.0, 30.0, h);               // soft start around the pillar top / crystal
        float fade = exp(-max(h, 0.0) / 150.0) * (1.0 - smoothstep(250.0, 650.0, h));
        // glowing pulses rise up each beam and fade in/out smoothly (phase-offset per beam)
        float ph1 = fract(t * 0.07 * END_BEAM_PULSE_SPEED + fk * 0.137);
        float ph2 = fract(t * 0.07 * END_BEAM_PULSE_SPEED + fk * 0.137 + 0.5);
        float e1 = sin(3.14159 * ph1); e1 *= e1;
        float e2 = sin(3.14159 * ph2); e2 *= e2;
        float pulse = e1 * exp(-pow((h - ph1 * 420.0) / 26.0, 2.0)) + e2 * exp(-pow((h - ph2 * 420.0) / 26.0, 2.0));
#ifndef END_BEAM_PULSE
        pulse = 0.0;
#endif
        float ball = exp(-(dist * dist) / (w * w * 6.0));
        vec3 c = mix(vec3(0.50, 0.18, 0.95), vec3(0.78, 0.60, 1.0), core);
        acc += c * (core * 0.40 + halo * 0.12) * up * fade * (0.30 + 2.4 * pulse);
        acc += vec3(0.85, 0.70, 1.0) * ball * pulse * 1.0 * up * fade;
    }
    return acc * END_BEAM_BRIGHTNESS;
}

vec3 endSky(vec3 dir, float t, vec3 cam, int part) {
    vec3 col = vec3(0.0);
    if (part == 0) {
    col = mix(vec3(0.010, 0.006, 0.022), vec3(0.020, 0.016, 0.050), 0.5 + 0.5 * dir.y);

    // nebula clouds (soft layered, drifting slowly)
    float n1 = esFbm(dir * 2.2 + vec3(t * 0.004, 0.0, t * 0.003));
    float n2 = esFbm(dir * 4.5 + vec3(5.0, t * 0.006, -t * 0.004));
    float neb = smoothstep(0.42, 0.80, n1) * smoothstep(0.35, 0.75, n2);
    vec3 nc = mix(vec3(0.10, 0.18, 0.55), vec3(0.45, 0.15, 0.62), smoothstep(0.3, 0.8, n2));
    nc = mix(nc, vec3(0.15, 0.55, 0.75), smoothstep(0.55, 0.9, n1) * 0.5);
    col += nc * neb * 0.42;

    // faint cosmic-purple horizon glow: wide gaussian + very wide skirt so it melts smoothly into the void
    {
        float hy = dir.y;
        float hg = exp(-hy * hy / 0.030) * 0.65 + exp(-hy * hy / 0.22) * 0.35;
        float hv = 0.80 + 0.20 * esNoise(vec3(dir.x * 1.6, 0.0, dir.z * 1.6) + vec3(t * 0.004, 0.0, 0.0));
        vec3 hc = mix(vec3(0.34, 0.10, 0.62), vec3(0.20, 0.12, 0.60), 0.5 + 0.5 * dir.x);
        col += hc * hg * hv * 0.20;
    }

    // real-style nebula complexes: big, soft, billowy gas clouds (domain-warped, wispy fine detail),
    // magenta/pink glowing cores -> violet -> teal-blue edges, with dark dust lanes cutting through them
    for (int ni = 0; ni < 3; ni++) {
        float fn = float(ni);
        vec3 cen = normalize(vec3(sin(fn * 2.4 + 0.9), 0.15 + 0.35 * cos(fn * 1.9 + 0.4), cos(fn * 2.4 + 0.9)));
        float cd = dot(dir, cen);
        if (cd > 0.2) {
            vec3 e1 = normalize(cross(cen, vec3(0.0, 1.0, 0.001)));
            vec3 e2 = cross(cen, e1);
            vec2 uv = vec2(dot(dir, e1), dot(dir, e2)) / cd;
            float ra = fn * 1.3 + 0.5;
            uv = mat2(cos(ra), -sin(ra), sin(ra), cos(ra)) * uv;
            float r = length(uv / vec2(1.25 - 0.15 * fn, 0.70 + 0.10 * fn));
            float env = pow(smoothstep(1.0, 0.0, r), 1.6) * smoothstep(0.2, 0.5, cd);
            if (env > 0.002) {
                float sd = fn * 11.3;
                vec2 w = vec2(esFbm(vec3(uv * 1.7, sd + t * 0.003)),
                              esFbm(vec3(uv * 1.7 + 5.2, sd + 1.3 - t * 0.002))) - 0.5;
                vec2 p = uv * 2.3 + w * 1.7;
                float g = smoothstep(0.30, 0.85, esFbm(vec3(p, sd * 0.7)));              // billowy gas
                float fine = esFbm(vec3(p * 3.6 + w * 2.2, sd + 9.0));                    // wispy filaments inside
                float lane = smoothstep(0.50, 0.74, esFbm(vec3(p * 1.4 + 3.0, sd + 4.0))); // dust lanes
                float dns = g * (0.45 + 0.95 * fine) * (1.0 - 0.80 * lane);
                float core = clamp(dns * env * 1.8, 0.0, 1.0);
                vec3 nc2 = mix(vec3(0.08, 0.42, 0.72), vec3(0.42, 0.16, 0.85), smoothstep(0.08, 0.40, core)); // teal-blue -> violet
                nc2 = mix(nc2, vec3(0.92, 0.28, 0.72), smoothstep(0.35, 0.80, core));                       // H-alpha magenta
                nc2 = mix(nc2, vec3(1.0, 0.80, 0.95), smoothstep(0.80, 1.0, core) * 0.5);                  // hot pale core
                vec3 refl = vec3(0.18, 0.32, 0.90) * env * env * 0.22 * (1.0 - 0.8 * lane);                // blue reflection haze
                col += nc2 * dns * env * 0.85 + refl;
            }
        }
    }

    // nebula cosmic belt: tilted luminous band of streaky nebula filaments, dust lanes and a cream-white core
    {
        vec3 bn = normalize(vec3(0.40, 0.78, -0.48));
        vec3 bu = normalize(cross(bn, vec3(0.0, 0.0, 1.0)));
        vec3 bv = cross(bn, bu);
        float v = dot(dir, bn);
        float u = atan(dot(dir, bv), dot(dir, bu));
        float streak = esFbm(vec3(u * 1.6, v * 6.0, t * 0.002));      // long streaks along the belt
        float cloudy = esFbm(dir * 5.0 + vec3(0.0, t * 0.002, 3.0));   // soft nebula clouds
        float lane = smoothstep(0.46, 0.76, esFbm(vec3(u * 2.0, v * 9.0, 7.0)));
        float halo = exp(-v * v / 0.030);
        float core = exp(-v * v / 0.0042);
        vec3 hue = mix(vec3(0.20, 0.30, 0.85), vec3(0.55, 0.28, 0.85), 0.5 + 0.5 * esNoise(dir * 3.0));
        hue = mix(hue, vec3(0.20, 0.60, 0.80), smoothstep(0.55, 0.9, cloudy) * 0.5);
        col += hue * halo * (0.30 + 1.1 * cloudy) * 0.75;
        col += vec3(1.0, 0.92, 0.78) * core * (0.25 + 1.1 * streak) * (0.4 + 0.6 * cloudy) * 0.75;   // cream-white parts
        col *= 1.0 - 0.5 * lane * smoothstep(0.0, 0.6, halo);                                          // dark dust lanes
    }

    // starfield: dense fine stars + bright big stars with soft glow (much more noticeable)
    {
        float sb = STAR_BRIGHTNESS;
        // layer A: many small bright stars
        {
            vec3 p = dir * 150.0;
            vec3 id = floor(p);
            vec3 f = fract(p) - 0.5;
            float h = esHash(id);
            if (h > 0.915) {
                float sz = 0.10 + 0.12 * fract(h * 57.3);
                vec3 off = (vec3(esHash(id + 1.7), esHash(id + 3.1), esHash(id + 5.9)) - 0.5) * 0.4;
                float d = length(f - off);
                float tw = 0.8 + 0.2 * sin(t * 2.0 + h * 100.0);
                col += mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.9, 0.8), fract(h * 13.7))
                     * smoothstep(sz, 0.0, d) * (3.5 + 4.0 * fract(h * 91.0)) * tw * (1.0 - 0.4 * neb) * sb;
            }
        }
        // layer B: fewer, large, very bright stars with a halo
        {
            vec3 p = dir * 62.0 + 31.0;
            vec3 id = floor(p);
            vec3 f = fract(p) - 0.5;
            float h = esHash(id + 40.0);
            if (h > 0.955) {
                vec3 off = (vec3(esHash(id + 7.7), esHash(id + 2.3), esHash(id + 9.1)) - 0.5) * 0.4;
                float d = length(f - off);
                float tw = 0.85 + 0.15 * sin(t * 1.5 + h * 200.0);
                vec3 sc = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.92, 0.78), fract(h * 23.7));
                col += sc * (smoothstep(0.20, 0.0, d) * 9.0 + exp(-d * 11.0) * 0.9) * tw * sb;
            }
        }
    }

    }

#ifdef CPS001
    // CPS001: a real 3D object at a FIXED world position (south of the map, slightly above, unreachable).
    // Rings, beams and the shockwave live in world space and are ray-traced from the camera -> true parallax.
    if (part == 1) {
        vec3 P = ES_P_OF(cam);
        vec3 toP = P - cam;
        float distP = length(toP);
        vec3 S = toP / distP;
        vec3 Sref = normalize(P - vec3(0.0, 90.0, 0.0));
        vec3 R = normalize(cross(vec3(0.0, 1.0, 0.0), S));
        vec3 U = cross(S, R);
        float cz = dot(dir, S);

        vec3 Ax = endAxis(t, cam);
        vec3 toCam = -S;
        float pulse = exp(-(1.0 - dot(Ax, toCam)) * 120.0) + 0.3 * exp(-(1.0 - dot(-Ax, toCam)) * 14.0);
        col += endBeamGlow(dir, cam, t, 1.0e9);

        if (cz > 0.05) {
            vec2 p = vec2(dot(dir, R), dot(dir, U)) / cz * 0.32;
            float r = length(p);
            float flick = (1.0 + 0.04 * sin(t * 5.0)) * (1.0 + 1.6 * pulse);

            col += vec3(0.45, 0.55, 1.0) * exp(-r * 6.0) * 0.82 * CPS001_BRIGHTNESS * flick;
            col += vec3(0.75, 0.85, 1.0) * exp(-r * 22.0) * 1.12 * CPS001_BRIGHTNESS;
            col += vec3(0.85, 0.92, 1.0) * smoothstep(0.045, 0.030, r) * 1.85 * CPS001_BRIGHTNESS;
            col += vec3(0.65, 0.25, 1.0) * smoothstep(0.024, 0.0, r) * 2.0 * CPS001_BRIGHTNESS;
            col += vec3(0.80, 0.70, 1.0) * exp(-r * 12.0) * pulse * 1.9 * CPS001_BRIGHTNESS;

            // cosmic glare (like the reference photo): two thin, near-horizontal, slightly tilted streaks
            // that start at the star's rim (nothing across the middle) and shimmer independently
            float rim = smoothstep(0.034, 0.047, r);
            float tiltA = 0.13 + 0.05 * sin(t * 0.7);
            float tiltB = -0.22 + 0.05 * sin(t * 0.9 + 1.3);
            vec2 pA = vec2(cos(tiltA) * p.x + sin(tiltA) * p.y, -sin(tiltA) * p.x + cos(tiltA) * p.y);
            vec2 pB = vec2(cos(tiltB) * p.x + sin(tiltB) * p.y, -sin(tiltB) * p.x + cos(tiltB) * p.y);
            float fA = 0.75 + 0.25 * sin(t * 1.7) + 0.10 * sin(t * 5.3 + 2.0);
            float fB = 0.70 + 0.30 * sin(t * 2.3 + 0.8) + 0.10 * sin(t * 6.1);
            float stA = exp(-abs(pA.y) * 150.0) * exp(-abs(pA.x) * 1.3);
            float stB = exp(-abs(pB.y) * 190.0) * exp(-abs(pB.x) * 2.6);
            vec3 gA = mix(vec3(0.75, 0.85, 1.0), vec3(0.65, 0.35, 1.0), smoothstep(0.05, 0.5, abs(pA.x)));
            vec3 gB = mix(vec3(0.85, 0.90, 1.0), vec3(0.60, 0.40, 1.0), smoothstep(0.05, 0.4, abs(pB.x)));
            col += (gA * stA * fA * 1.1 + gB * stB * fB * 0.65) * rim * (1.0 + 0.8 * pulse) * CPS001_BRIGHTNESS;
        }

        // photoreal pulsar extras: chromatic corona, 4 fine diffraction spikes, magnetic-pole lobes
        if (cz > 0.05) {
            vec2 p = vec2(dot(dir, R), dot(dir, U)) / cz * 0.32;
            float r = length(p) + 1e-4;
            float rim = smoothstep(0.03, 0.06, r);
            col += vec3(0.30, 0.50, 1.0) * exp(-r * 3.2) * 0.22 * CPS001_BRIGHTNESS;           // blue scattering veil
            col += vec3(1.0, 0.55, 0.85) * exp(-pow((r - 0.07) / 0.02, 2.0)) * 0.10 * CPS001_BRIGHTNESS; // faint chromatic ring
            float sp = exp(-abs(p.x) * 260.0) * exp(-abs(p.y) * 5.0) + exp(-abs(p.y) * 260.0) * exp(-abs(p.x) * 5.0);
            vec2 pd = vec2(p.x + p.y, p.x - p.y) * 0.7071;
            sp += 0.5 * (exp(-abs(pd.x) * 300.0) * exp(-abs(pd.y) * 8.0) + exp(-abs(pd.y) * 300.0) * exp(-abs(pd.x) * 8.0));
            col += vec3(0.80, 0.88, 1.0) * sp * rim * 0.55 * (1.0 + 0.6 * pulse) * CPS001_BRIGHTNESS;
            vec2 ap = normalize(vec2(dot(Ax, R), dot(Ax, U)) + 1e-4);
            float al = abs(dot(p, ap)), ac = abs(p.x * ap.y - p.y * ap.x);
            col += vec3(0.55, 0.40, 1.0) * exp(-ac * 55.0) * exp(-al * 7.0) * rim * 0.30 * CPS001_BRIGHTNESS;
        }

        // ---- three dusty nebula rings: tilted discs in world space (perspective-correct) ----
        {
            vec3 Nr = normalize(vec3(0.35, 1.0, 0.25));
            float dn = dot(dir, Nr);
            if (abs(dn) > 1e-3) {
                float tR = dot(P - cam, Nr) / dn;
                if (tR > 0.0) {
                    vec3 rel = cam + dir * tR - P;
                    vec3 e1 = normalize(cross(Nr, vec3(0.0, 0.0, 1.0)));
                    vec3 e2 = cross(Nr, e1);
                    vec2 pl = vec2(dot(rel, e1), dot(rel, e2));
                    float rr = length(pl);
                    float dust = esFbm(vec3(pl * 0.012, t * 0.01));
                    float q1 = (rr - 240.0) / 55.0;
                    float q2 = (rr - 420.0) / 95.0;
                    float q3 = (rr - 640.0) / 150.0;
                    float rings = exp(-q1 * q1) + exp(-q2 * q2) * 0.6 + exp(-q3 * q3) * 0.4;
                    rings *= smoothstep(0.30, 0.75, dust);
                    col += mix(vec3(0.45, 0.25, 0.95), vec3(0.35, 0.70, 1.0), smoothstep(240.0, 640.0, rr)) * rings * 0.55;
                }
            }
        }

        // ---- expanding spherical shockwave shell (world space, limb-brightened) ----
        {
            float sp = fract(t * 0.05);
            float Rs = 60.0 + 800.0 * sp;
            float tc = dot(P - cam, dir);
            float dc = (tc > 0.0) ? length(cross(dir, P - cam)) : distP;
            float sq = (dc - Rs) / (30.0 + 60.0 * sp);
            col += vec3(0.60, 0.35, 1.0) * exp(-sq * sq) * sin(3.14159 * sp) * 0.30;
        }
    }
#endif

    return col;
}
