shader_type spatial;
// Soft camera-facing halo around a supernatural light. A halo *is* the air scattering that
// light, so depth fog must not erase it: fog_disabled, unlike the spirit wisps.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.62, 0.78, 1.0, 0.5);
uniform float energy = 1.5;
uniform float falloff = 3.0;  // higher = tighter halo
uniform float toward_camera = 1.2;  // m; lifts the halo out of the stone it sits in

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_MATRIX[3].z += toward_camera;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	ALBEDO = tint.rgb * energy;
	ALPHA = pow(max(1.0 - d, 0.0), falloff) * tint.a;
}
