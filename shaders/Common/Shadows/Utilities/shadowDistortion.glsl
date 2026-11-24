vec3 distortShadowClipPos(vec3 shadowClipPos) {
	float distanceFromCenter = length(
		shadowClipPos.xy
	);

	float distortionFactor =
		distanceFromCenter;

	distortionFactor += 0.1;

	shadowClipPos.xy /=
		distortionFactor;

	shadowClipPos.z *= 0.5;

	return shadowClipPos;
}