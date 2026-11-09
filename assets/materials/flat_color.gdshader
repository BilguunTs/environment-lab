// Faceted, single-colour stylized surface.
// Normals are rebuilt per-face from screen derivatives, so smooth primitives
// (spheres, cylinders) read as low-poly facets without custom meshes.
// Optional wind sway: displacement grows with height above the ground, so trunks stay
// planted while crowns move. Gusts travel across the world, not per object.
// Kit instances on high ground (the Heavens call mountain) set the instance uniform
// height_from_origin (kit_asset.gd does it): sway and the contact shade then use height above the
// object's origin instead of world height. Off by default, so other scenes are unchanged.
shader_type spatial;

#include "res://assets/shaders/wind.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.95;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;
// Darkens surfaces near the ground to visually anchor objects (cheap fake contact shade).
uniform float base_darkening : hint_range(0.0, 1.0) = 0.35;
uniform float base_height = 1.5;
// 0 = rigid. Parts of one object must share the same value or they drift apart.
uniform float sway : hint_range(0.0, 2.0) = 0.0;
uniform float sway_frequency : hint_range(0.1, 10.0) = 1.0;
// Per-object brightness/temperature jitter (seeded by the object's world position), so
// repeated instances of one asset don't read as copies. 0 = off.
uniform float tint_variation : hint_range(0.0, 0.5) = 0.0;
// Per instance: measure height from the node's origin, not from world y = 0 (see the header).
instance uniform bool height_from_origin = false;

varying float world_y;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_y = world.y;
	if (height_from_origin) {
		world_y -= NODE_POSITION_WORLD.y;
	}
	if (sway > 0.0) {
		float phase = dot(world.xz, wind_direction) * 0.12;
		float gust = 0.1 + 0.9 * wind_gust(world.xz);  // patchy gusts travel downwind (avg ~0.55, as before)
		float t = TIME * sway_frequency;
		float wave = sin(t * 1.3 - phase) + 0.3 * sin(t * 3.7 - phase * 2.3);
		float bend = sway * wind_strength * gust * wave * world.y * world.y * 0.006;
		if (height_from_origin) {
			float h = max(world.y - NODE_POSITION_WORLD.y, 0.0);
			bend = sway * wind_strength * gust * wave * h * h * 0.006;
		}
		world.xz += wind_direction * bend;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	}
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	float ground = 1.0 - base_darkening * (1.0 - smoothstep(0.0, base_height, world_y));
	vec3 color = albedo.rgb;
	if (tint_variation > 0.0) {
		vec2 seed = floor(NODE_POSITION_WORLD.xz * 4.0);
		float v = hash(seed) * 2.0 - 1.0;          // brightness
		float w = hash(seed + 17.0) * 2.0 - 1.0;   // warm / cool
		color *= 1.0 + tint_variation * v;
		color *= vec3(1.0 + 0.5 * tint_variation * w, 1.0, 1.0 - 0.5 * tint_variation * w);
	}
	ALBEDO = color * ground;
	ROUGHNESS = roughness;
	EMISSION = emission.rgb * emission_energy;
}
