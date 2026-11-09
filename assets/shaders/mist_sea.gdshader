// The Heavens call mist sea (scripts/levels/vista.gd): a huge flat layer read as a slab of mist.
// Its opacity is the slab's optical depth along the view ray, thickness / cos(view angle), so it
// is a thin veil straight down and a solid white sea toward the horizon, which hides the steppe's
// far edge. Patchy drifting noise breaks it into banks, and it blends into the horizon colour
// with distance. It fades out as the ground behind it comes up to meet it: by the slab's height
// above that ground (measured along the view ray, then vertically), over `soft` metres. So it
// lies thick over the low valleys, thins over the rises and never shows a hard intersection line.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.72, 0.74, 0.78, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.5, 0.5, 0.52, 1.0);
// Vertical optical depth of the slab where the noise is average.
uniform float thickness = 0.4;
// Height (m) of the slab above the ground behind it over which the mist fades in.
uniform float soft = 30.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float noise_scale = 0.0012;
uniform vec2 offset = vec2(0.0);
// Distance (m) over which the mist's own colour gives way to the horizon colour.
uniform vec2 horizon_fade = vec2(900.0, 4000.0);
// Optical depth range from thin gaps to thick banks.
uniform vec2 banks_range = vec2(0.08, 2.2);
// The layer fades out between these radii from its centre (a cloud deck, whose rim would
// otherwise cut a line across the sky).
uniform vec2 rim_fade = vec2(1e6, 2e6);
// Overall opacity: the vista fades the whole layer in with it (Vista.far_fade).
uniform float opacity = 1.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 world_pos;
varying float rim;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	rim = length(VERTEX.xz);
}

void fragment() {
	vec3 to_cam = CAMERA_POSITION_WORLD - world_pos;
	float dist = length(to_cam);
	float cos_view = abs(to_cam.y) / max(dist, 0.001);
	vec2 p = world_pos.xz * noise_scale;
	float n = texture(noise_tex, p + offset).r * 0.65 + texture(noise_tex, p * 3.3 - offset * 1.7).r * 0.35;
	float banks = mix(banks_range.x, banks_range.y, smoothstep(0.38, 0.7, n));
	float tau = thickness * banks / max(cos_view, 0.01);
	float alpha = 1.0 - exp(-tau);
	// Thin where the ground behind comes up to the slab: the ray's length behind this fragment,
	// times its vertical part, is the slab's height above (or below, seen from under) the ground.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float behind = length(view.xyz / view.w) - length(VERTEX);
	float gap = depth <= 0.0 ? 1e6 : behind * cos_view;
	alpha *= smoothstep(0.0, 1.0, clamp(gap / soft, 0.0, 1.0));
	ALBEDO = mix(color.rgb, horizon_color.rgb, smoothstep(horizon_fade.x, horizon_fade.y, dist));
	alpha *= 1.0 - smoothstep(rim_fade.x, rim_fade.y, rim);
	ALPHA = clamp(alpha, 0.0, 1.0) * opacity;
}
