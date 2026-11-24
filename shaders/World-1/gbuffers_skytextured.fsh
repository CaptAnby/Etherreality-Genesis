#version 330 compatibility

uniform sampler2D gtexture;
uniform float rainStrength;
uniform float thunderStrength;

uniform float alphaTestRef = 0.1;

in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
	color = texture(gtexture, texcoord) * glcolor;
	if (color.a < alphaTestRef) {
		discard;
	}
	// Sun / moon fade behind rain and storm clouds.
	color.rgb *= 1.0 - 0.8 * clamp(max(rainStrength, thunderStrength), 0.0, 1.0);
	color.a *= 1.0 - 0.9 * clamp(rainStrength, 0.0, 1.0);
}
