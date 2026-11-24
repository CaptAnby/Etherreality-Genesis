#version 330 compatibility

uniform vec3 skyColor;

in vec4 glcolor;
in float vDist;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
	// distant water: drop the flat biome blue, match the muted grey-teal of the near sea,
	// then fade smoothly into a soft hazy sky tone toward the horizon
	vec3 c = glcolor.rgb * vec3(0.85, 0.95, 1.0);
	float l = dot(c, vec3(0.3333));
	c = mix(vec3(l), c, 0.30) * 0.80;
	vec3 haze = mix(skyColor, vec3(0.62, 0.68, 0.74), 0.55) * 0.85;
	c = mix(c, haze, smoothstep(150.0, 1200.0, vDist) * 0.85);
	color = vec4(c, clamp(glcolor.a, 0.55, 0.9));
}
