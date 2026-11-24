#version 330 compatibility
#include "/settings.glsl"
#include "/Common/Wind/globalWind.glsl"

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float thunderStrength;

out vec2 lmcoord;
out vec2 texcoord;
out vec4 glcolor;
out vec3 normal;
out float materialID;
out vec3 puddleWorldPos;
out float puddleUp;
out vec3 puddleRel;

// Smooth wind offset (blocks). Speed drifts via frequency modulation so wind
// comes and goes; rain = stronger + steadier, thunder = fast + violent.
vec2 windSway(vec3 wp) {
	float t = frameTimeCounter * VEG_WIND_SPEED;
	float r = clamp(rainStrength, 0.0, 1.0);
	float th = clamp(thunderStrength, 0.0, 1.0);

	float spd = mix(1.0, 1.5, r);
	spd = mix(spd, 3.2, th);

	// drifting speed: slow lulls, faster gusts
	float drift = 1.6 * sin(t * 0.11) + 0.9 * sin(t * 0.047 + 2.0);
	drift *= (1.0 - 0.7 * r);

	float ph = t * spd * 1.2 + drift + dot(wp.xz, vec2(0.30, 0.22));

	// gust envelope (steadier in rain, strong in storm)
	float env = 0.55 + 0.45 * sin(t * 0.19 + wp.x * 0.04) * sin(t * 0.073 + wp.z * 0.04 + 1.0);
	env = mix(env, 0.30 + 0.70 * glwsGust(frameTimeCounter, r, th), 0.65);   // SmGS shared gust
	float amp = glwsStrength(r, th);

	float s1 = sin(ph) + 0.5 * sin(ph * 2.3 + 1.7);
	float s2 = sin(ph * 0.8 + 3.1 + wp.y * 0.3);

	vec2 dir = glwsDir();
	vec2 perp = vec2(-dir.y, dir.x);
	return (dir * (s1 * 0.6 + 0.35 * env) + perp * s2 * 0.3) * env * amp;
}

void main() {
	vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
	vec3 rel = (gbufferModelViewInverse * viewPos).xyz;

	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
	lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	glcolor = gl_Color;

	normal = gl_NormalMatrix * gl_Normal;

	materialID = mc_Entity.x;

	// vertex height inside its block: -0.5 (bottom) .. +0.5 (top)
	float hRel = -at_midBlock.y / 64.0;

	float w = 0.0;
	float maxMove = 0.0;
	if (abs(materialID - 40.0) < 0.5) {          // leaves
		w = 1.0;
		maxMove = 0.045 * VEG_LEAF_SWAY;
	} else if (abs(materialID - 42.0) < 0.5) {   // grass, flowers, crops
		w = clamp(hRel + 0.5, 0.0, 1.0);
		w *= w;
		maxMove = 0.14 * VEG_GRASS_SWAY;
	} else if (abs(materialID - 41.0) < 0.5) {   // hanging lanterns
		w = clamp(0.5 - hRel, 0.0, 1.0);
		maxMove = 0.05 * VEG_LANTERN_SWAY;
	}

	if (w > 0.0) {
		vec3 wp = rel + cameraPosition;
		vec2 sw = windSway(wp);
#ifdef FUNNEL
		{
			float nearK = 1.0 - smoothstep(6.0, 60.0, length(rel));
			float thK = clamp(thunderStrength, 0.0, 1.0) * nearK;
			float ft2 = frameTimeCounter * VEG_WIND_SPEED;
			vec2 fast = vec2(sin(ft2 * 8.0 + wp.x * 1.3 + wp.z * 0.7), cos(ft2 * 7.0 + wp.z * 1.1 - wp.x * 0.5));
			sw = sw * (1.0 + 0.5 * thK) + fast * 0.12 * thK;
		}
#endif
		rel.xz += sw * w * maxMove * WEATHER_WIND_SWAY;
		if (abs(materialID - 40.0) < 0.5) {
			rel.y += sin(frameTimeCounter * 2.1 + wp.x + wp.z) * 0.01 * dot(sw, sw);
		}
	}

	gl_Position = gl_ProjectionMatrix * (gbufferModelView * vec4(rel, 1.0));

	puddleRel = rel;
	puddleWorldPos = rel + cameraPosition;
	puddleUp = (gbufferModelViewInverse * vec4(normal, 0.0)).y;
}
