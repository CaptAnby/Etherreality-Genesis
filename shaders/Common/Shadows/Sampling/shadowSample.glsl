float sampleShadowDepth(vec2 shadowUV) {
	if (isEyeInWater == 1) {
		return texture(shadowtex1, shadowUV).r;
	}
	return texture(shadowtex0, shadowUV).r;
}