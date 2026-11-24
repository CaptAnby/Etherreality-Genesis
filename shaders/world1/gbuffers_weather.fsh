#version 330 compatibility
#include "/settings.glsl"

uniform sampler2D lightmap;
uniform sampler2D gtexture;
uniform float thunderStrength;

uniform float alphaTestRef = 0.1;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	color *= texture(lightmap, lmcoord);
	if (color.a < alphaTestRef) {
		discard;
	}
	// pale gray water look (stays light for snow)
	float l = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	vec3 tint = mix(vec3(0.78, 0.81, 0.85), vec3(0.62, 0.65, 0.70), thunderStrength);
	color.rgb = vec3(l) * tint * 1.15;
	color.a *= mix(0.55, 0.75, thunderStrength) * RAIN_DROP_OPACITY;
}
