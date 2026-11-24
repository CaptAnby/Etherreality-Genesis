#version 330 compatibility

uniform sampler2D gtexture;
#include "/settings.glsl"
uniform float sunAngle;
uniform float rainStrength;
uniform float thunderStrength;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform int moonPhase;
uniform vec3 cameraPosition;
uniform mat4 gbufferModelViewInverse;
#include "/Common/Cloud/stormEye.glsl"

uniform float alphaTestRef = 0.1;

in vec2 texcoord;
in vec4 glcolor;
in vec3 vViewDir;
in float vIsSun;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

float cHash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 cHash2(vec2 p) { return vec2(cHash(p), cHash(p + 19.19)); }
float cNoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(cHash(i), cHash(i + vec2(1, 0)), f.x), mix(cHash(i + vec2(0, 1)), cHash(i + vec2(1, 1)), f.x), f.y);
}
float cCrater(vec2 p, float s) {
	vec2 q = p * s;
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	float d = length(f - (cHash2(id) - 0.5) * 0.5);
	float on = step(0.55, cHash(id + 7.0));
	return on * (-0.20 * smoothstep(0.26, 0.17, d) + 0.13 * (smoothstep(0.31, 0.25, d) - smoothstep(0.25, 0.21, d)));
}

void main() {
#if CELESTIALS == 1
	// ---- Realistic Celestials: discs built from view direction (independent of the sky quad's UVs) ----
	vec3 D = normalize(vViewDir);
	vec3 Sd = normalize(sunPosition);
	vec3 Md = normalize(moonPosition);
	color = vec4(0.0);

	// sun: blinding white core, subtle limb darkening, smooth continuous glow (no hard edge, so no outline)
	{
		float ang = acos(clamp(dot(D, Sd), -1.0, 1.0));
		float Rs = 0.046;
		float r = ang / Rs;
		float limb = 0.80 + 0.20 * sqrt(max(1.0 - min(r * r, 1.0), 0.0));
		float core = exp(-pow(r, 7.0));
		float glow = (0.30 * exp(-1.6 * r) + 0.06 * exp(-0.5 * r)) * (1.0 - smoothstep(3.0, 5.0, r));
		float sa = clamp(core + glow, 0.0, 1.0);
		vec3 sc = mix(vec3(1.0, 0.82, 0.60), vec3(1.0, 0.97, 0.90), clamp(core * 1.2, 0.0, 1.0));
		color = vec4(sc * limb * 1.9, sa);
	}

	// moon: phase, maria, craters. Colour is NOT darkened toward the edge/terminator (alpha handles
	// that), because dark colour at partial alpha is what draws a dark outline ring.
	{
		vec3 Up = normalize(upPosition);
		vec3 ax = normalize(cross(Md, Up));
		vec3 ay = cross(ax, Md);
		float Rm = 0.052;
		vec2 p = vec2(dot(D, ax), dot(D, ay)) / Rm;
		float r = length(p);
		if (r < 1.15 && dot(D, Md) > 0.0) {
			float rc = min(r, 1.0);
			float z = sqrt(max(1.0 - rc * rc, 0.0));
			float a = float(moonPhase) * 0.785398;
			vec3 Ld = normalize(vec3(-sin(a), 0.0, cos(a)));
			float lit = smoothstep(-0.05, 0.10, dot(vec3(p, z), Ld));
			float mar = cNoise(p * 2.1 + 3.7) * 0.60 + cNoise(p * 4.3 + 1.1) * 0.30 + cNoise(p * 9.0 + 5.0) * 0.10;
			float maria = smoothstep(0.48, 0.66, mar);
			float alb = mix(0.92, 0.50, maria) * (0.90 + 0.20 * cNoise(p * 13.0) + 0.06 * cNoise(p * 31.0));
			alb += cCrater(p, 5.0) + cCrater(p + 3.3, 9.0) * 0.8 + cCrater(p + 7.1, 15.0) * 0.5 + cCrater(p + 1.7, 27.0) * 0.3;
			vec3 mc = mix(vec3(0.90, 0.92, 0.97), vec3(1.0, 0.97, 0.90), 0.5) * alb;
			// opposition-surge style flat lighting: the lit face stays bright out to the limb
			mc *= 1.55 * (0.94 + 0.06 * z);
			// unlit side: faint blue earthshine, carried by colour tint and low alpha
			vec3 earth = vec3(0.10, 0.14, 0.22) * alb;
			vec3 moonCol = mix(earth, mc, lit);
			float edge = 1.0 - smoothstep(0.96, 1.08, r);
			float ma = edge * mix(0.12, 1.0, lit);
			color = vec4(mix(color.rgb, moonCol, step(color.a, ma)), max(color.a, ma));
		}
	}
	color *= glcolor;
	if (color.a < 0.004) {
		discard;
	}
#else
	color = texture(gtexture, texcoord) * glcolor;
	if (color.a < alphaTestRef) {
		discard;
	}
#endif
	color.rgb *= (vIsSun > 0.5) ? SUN_DISC_BRIGHTNESS : MOON_DISC_BRIGHTNESS;
	if (vIsSun > 0.5) {
		float sunH = normalize(mat3(gbufferModelViewInverse) * sunPosition).y;
		float lowSun = 1.0 - smoothstep(0.05, 0.40, sunH);
		float cl = dot(color.rgb, vec3(0.3333));
		color.rgb = mix(color.rgb, vec3(1.0, 0.55, 0.22) * cl * 1.1, lowSun * 0.7);
	}
	// Sun / moon fade behind rain and storm clouds.
	float eyeSky = stormEyeSkyHole(cameraPosition, normalize(mat3(gbufferModelViewInverse) * vViewDir),
	                               normalize(mat3(gbufferModelViewInverse) * sunPosition), thunderStrength);
	color.rgb *= 1.0 - 0.8 * clamp(max(rainStrength, thunderStrength), 0.0, 1.0) * (1.0 - eyeSky);
	color.a *= 1.0 - 0.9 * clamp(rainStrength, 0.0, 1.0) * (1.0 - eyeSky);
}
