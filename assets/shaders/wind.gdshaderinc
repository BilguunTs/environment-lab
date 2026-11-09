// Shared wind: the three globals published by scripts/environment/wind.gd, and the gust field
// every wind-driven shader samples, so trees and grass lean in the same patches.
global uniform float wind_strength;
global uniform vec2 wind_direction;
global uniform float wind_phase;  // metres the gusts have travelled downwind, wrapped at 2000

float wind_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise that repeats every `period` cells along x, so wrapping wind_phase is invisible.
float wind_value_noise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, period);
	float x1 = mod(i.x + 1.0, period);
	return mix(mix(wind_hash(vec2(x0, i.y)), wind_hash(vec2(x1, i.y)), f.x),
			mix(wind_hash(vec2(x0, i.y + 1.0)), wind_hash(vec2(x1, i.y + 1.0)), f.x), f.y);
}

// Gust strength 0..1 at a world position: irregular patches (~20 m along the wind, ~40 m across
// it, so fronts run across the wind) that travel downwind as wind_phase grows. The scroll lives in
// pattern space (not a world offset), so turning the wind only rotates the pattern about the
// origin. q mirrors Wind.pattern_coord; the octave periods (100 and 230 cells) are the 2000 m
// phase period in each octave's cells.
float wind_gust(vec2 world_xz) {
	vec2 along = wind_direction;
	vec2 across = vec2(-along.y, along.x);
	vec2 q = vec2((dot(world_xz, along) - wind_phase) / 20.0, dot(world_xz, across) / 40.0);
	float g = wind_value_noise(q, 100.0) * 0.65 + wind_value_noise(q * 2.3 + vec2(7.3, 1.7), 230.0) * 0.35;
	return clamp((g - 0.2) / 0.6, 0.0, 1.0);
}
