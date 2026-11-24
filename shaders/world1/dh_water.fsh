#version 330 compatibility

in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
	color = vec4(glcolor.rgb * vec3(0.85, 0.95, 1.0), clamp(glcolor.a, 0.55, 0.9));
}
