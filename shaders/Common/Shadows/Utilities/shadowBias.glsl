float getShadowBias(vec3 normal, vec3 lightDir) {
	float NdotL = max(dot(normal, lightDir), 0.0);

	float baseBias = 0.0008 * SHADOW_BIAS;
	float slopeBias = 0.0025 * SHADOW_BIAS;

	return baseBias +
		(1.0 - NdotL) * slopeBias;
}

vec4 applyShadowBias(
	vec4 shadowClipPos,
	vec3 normal,
	vec3 lightDir
) {
	float bias = getShadowBias(
		normal,
		lightDir
	);

	shadowClipPos.z -= bias;

	return shadowClipPos;
}