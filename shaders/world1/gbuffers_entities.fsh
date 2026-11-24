#version 330 compatibility

uniform sampler2D lightmap;
uniform sampler2D gtexture;
uniform vec4 entityColor;

uniform float alphaTestRef = 0.1;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;
in vec3 normal;

/* RENDERTARGETS: 0,1,2,3 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalData;
layout(location = 2) out vec4 materialData;
layout(location = 3) out vec4 lightmapData;

void main() {
	color = texture(gtexture, texcoord) * glcolor;

	color.rgb = mix(
		color.rgb,
		entityColor.rgb,
		entityColor.a
	);


	if (color.a < alphaTestRef) {
		discard;
	}

	color.a = 1.0;

	// Self-lit parts (fire overlay, full-bright layers) are emissive.
	float entLum = dot(color.rgb, vec3(0.3, 0.59, 0.11));
	float entEmissive = step(0.96, lmcoord.x) * smoothstep(0.25, 0.5, entLum);
	materialData = vec4(6.0, entEmissive, 0.0, 1.0);

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