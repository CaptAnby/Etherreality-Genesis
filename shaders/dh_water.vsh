#version 330 compatibility

out vec4 glcolor;
out float vDist;

void main() {
	glcolor = gl_Color;
	vec4 vp = gl_ModelViewMatrix * gl_Vertex;
	vDist = length(vp.xyz);
	gl_Position = gl_ProjectionMatrix * vp;
}
