vec3 projectAndDivide(mat4 matrix, vec3 position) {
	vec4 homPos = matrix * vec4(position, 1.0);
	return homPos.xyz / homPos.w;
}

vec3 getShadowScreenPosition(vec2 uv, float depth) {
	vec3 ndcPos = vec3(uv, depth) * 2.0 - 1.0;

	vec3 viewPos = projectAndDivide(
		gbufferProjectionInverse,
		ndcPos
	);

	vec3 playerPos = (
		gbufferModelViewInverse *
		vec4(viewPos, 1.0)
	).xyz;

	vec3 shadowViewPos = (
		shadowModelView *
		vec4(playerPos, 1.0)
	).xyz;

	vec4 shadowClipPos = shadowProjection *
		vec4(shadowViewPos, 1.0);

	vec3 shadowNDCPos =
		shadowClipPos.xyz /
		shadowClipPos.w;

	return shadowNDCPos * 0.5 + 0.5;
}