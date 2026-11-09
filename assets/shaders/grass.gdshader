// Grass blades for GrassField (scripts/environment/grass_field.gd), drawn as MultiMesh chunks.
// Faceted like flat_color: normals are rebuilt per face from screen derivatives, and the base is
// darkened as a cheap contact shade. Colour runs from base_color at the root (UV.y = 0) to
// tip_color at the tip (UV.y = 1).
// INSTANCE_CUSTOM = (tint 0..1, phase 0..1, fade 0..1, unused): tint jitters brightness, phase
// desyncs the flutter, fade is the blade's rank for the distance thinning.
// Wind: blades lean along wind_direction, more inside gusts (wind_gust, shared with the trees)
// and more toward the tip; the root stays planted. Gust patches also brighten the tips.
shader_type spatial;
render_mode cull_disabled, skip_vertex_transform;

#include "res://assets/shaders/wind.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.12, 0.14, 0.10, 1.0);
uniform vec4 tip_color : source_color = vec4(0.30, 0.31, 0.19, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.95;
// Darkens the lower part of each blade (the same contact shade as flat_color, measured along
// the blade so it holds on the mounds too).
uniform float base_darkening : hint_range(0.0, 1.0) = 0.35;
uniform float base_height : hint_range(0.01, 1.0) = 0.4;
// Per-blade brightness jitter from INSTANCE_CUSTOM.r. 0 = off.
uniform float tint_variation : hint_range(0.0, 0.5) = 0.12;

// Tip offset in blade heights at wind_strength 1 inside a full gust.
uniform float bend : hint_range(0.0, 2.0) = 0.9;
// Sideways shimmer of the tips, in blade heights per unit of wind_strength.
uniform float flutter : hint_range(0.0, 0.5) = 0.08;
// Tip brightening at full gust.
uniform float highlight : hint_range(0.0, 1.0) = 0.18;
// Camera distances (m) where blades start thinning out and are all gone.
uniform float fade_start = 25.0;
uniform float fade_end = 45.0;

// How much of the keep fraction a blade shrinks over before it vanishes (no popping line).
const float FADE_BAND = 0.12;

varying float tint;
varying float gust_lit;

void vertex() {
	tint = INSTANCE_CUSTOM.r;
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float height = length(MODEL_MATRIX[1].xyz);

	// Distance fade: blades are ranked by fade_rand; the ones past the keep fraction shrink to
	// nothing around their root, so the thinning has no hard edge.
	float keep = 1.0 - smoothstep(fade_start, fade_end, distance(root, CAMERA_POSITION_WORLD));
	float size = clamp((keep * (1.0 + FADE_BAND) - INSTANCE_CUSTOM.b) / FADE_BAND, 0.0, 1.0);
	world = root + (world - root) * size;

	// Lean along the wind, harder in gusts, zero at the root; flutter across the wind.
	float gust = wind_gust(root.xz);
	float tip = UV.y;
	float lean = wind_strength * (0.35 + 0.65 * gust) * bend * tip * tip * height;
	vec2 across = vec2(-wind_direction.y, wind_direction.x);
	float shimmer = sin(TIME * 7.0 + INSTANCE_CUSTOM.g * 6.283) * flutter * wind_strength * tip * height;
	world.xz += wind_direction * lean * size + across * shimmer * size;
	gust_lit = gust * min(wind_strength, 1.0);

	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_NORMAL_MATRIX * NORMAL));
}

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	float ground = 1.0 - base_darkening * (1.0 - smoothstep(0.0, base_height, UV.y));
	vec3 color = mix(base_color.rgb, tip_color.rgb, UV.y);
	color *= 1.0 + tint_variation * (tint * 2.0 - 1.0);
	color *= 1.0 + highlight * gust_lit * UV.y;
	ALBEDO = color * ground;
	ROUGHNESS = roughness;
}
