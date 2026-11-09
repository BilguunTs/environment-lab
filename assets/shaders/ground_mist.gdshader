// Low drifting mist for a FogVolume. Patchy noise, thickest at ground level, fading out
// toward the volume's edges. `offset` is advanced by the playground from wind each frame
// (so changing wind speed never makes the mist jump).
shader_type fog;

uniform sampler3D noise_tex : repeat_enable;
uniform float density : hint_range(0.0, 4.0) = 0.5;
uniform float mist_height = 2.0;
// World height the mist is thickest at and below (0 = the playground's ground plane).
uniform float base_height = 0.0;
uniform float noise_scale = 0.035;
uniform vec3 offset = vec3(0.0);
uniform vec4 albedo : source_color = vec4(1.0);

void fog() {
	vec3 p = WORLD_POSITION * noise_scale + offset;
	float n = texture(noise_tex, p).r;
	float patches = smoothstep(0.45, 0.8, n);
	float height = 1.0 - smoothstep(base_height, base_height + mist_height, WORLD_POSITION.y);
	vec3 edge = smoothstep(vec3(0.0), vec3(0.08), UVW) * smoothstep(vec3(1.0), vec3(0.92), UVW);
	DENSITY = density * patches * height * edge.x * edge.z;
	ALBEDO = albedo.rgb;
}
