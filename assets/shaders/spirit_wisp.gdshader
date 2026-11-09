shader_type spatial;
// Soft camera-facing dot for spirit particles. Colour and fade come from the particle COLOR.
// Mixed (not additive) blending so depth fog dims distant wisps like everything else.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float energy = 3.0;  // > 1 so the core crosses the glow threshold and blooms

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float core = pow(max(1.0 - d, 0.0), 2.5);
	ALBEDO = COLOR.rgb * energy;
	ALPHA = core * COLOR.a;
}
