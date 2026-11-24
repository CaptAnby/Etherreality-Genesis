#include "/Common/Shadows/Sampling/shadowSample.glsl"

float sampleShadow(vec3 shadowPos) {
	if (
		shadowPos.x < 0.0 || shadowPos.x > 1.0 ||
		shadowPos.y < 0.0 || shadowPos.y > 1.0
	) {
		return 1.0;
	}

	float shadow = 0.0;
	float bias = 0.002;

	vec2 texelSize = 1.0 / vec2(textureSize(shadowtex0, 0));

	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 offset = vec2(x, y) * texelSize;

			float shadowDepth = sampleShadowDepth(
				shadowPos.xy + offset
			);

			shadow +=
				shadowPos.z <= shadowDepth + bias
				? 1.0
				: 0.0;
		}
	}

	return shadow / 9.0;
}