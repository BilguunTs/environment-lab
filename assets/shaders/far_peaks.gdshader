// The Heavens call Altai peaks (scripts/levels/vista.gd): faceted, vertex-coloured, lit like the
// rest of the far world, but out of the scene's depth fog, which at 3-4 km would swallow them
// whole. Instead they take their own veil: `haze` (0..1), which Vista sets each frame from the
// mood's fog, so they stay small, pale and distant, yet faintly there. Below `veil.y` (world
// height) the veil thickens to all haze at `veil.x`, so their lower slopes melt away and only the
// snowy tops stand clear. Up to TINT the veil tints them toward the horizon colour; past it they
// fade out instead (alpha), so at haze 1 they are gone into whatever lies behind (sky, mist,
// hills), exactly. Vista fades them in that way.
shader_type spatial;
render_mode blend_mix, depth_draw_always, fog_disabled, cull_back, shadows_disabled;

const float TINT = 0.7;

uniform vec4 haze_color : source_color = vec4(0.56, 0.6, 0.67, 1.0);
uniform float haze : hint_range(0.0, 1.0) = 0.6;
uniform vec2 veil = vec2(60.0, 330.0);

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float h = mix(1.0, haze, smoothstep(veil.x, veil.y, world_y));
	float tint = min(h, TINT);
	// Vertex colours are stored as sRGB.
	vec3 albedo = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = albedo * (1.0 - tint);
	EMISSION = haze_color.rgb * tint;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
	ALPHA = 1.0 - smoothstep(TINT, 1.0, h);
}
