// Minimal stylized sky: horizon -> zenith gradient plus a soft glow around the sun.
// The horizon colour is kept equal to the fog colour so distant forms dissolve into it.
shader_type sky;

uniform vec4 horizon_color : source_color = vec4(0.66, 0.64, 0.6, 1.0);
uniform vec4 zenith_color : source_color = vec4(0.36, 0.42, 0.5, 1.0);
// Larger = wider halo.
uniform float glow_size : hint_range(0.01, 1.0) = 0.25;
uniform float glow_energy : hint_range(0.0, 4.0) = 0.8;

void sky() {
	float h = clamp(EYEDIR.y, 0.0, 1.0);
	vec3 c = mix(horizon_color.rgb, zenith_color.rgb, pow(h, 0.55));
	if (LIGHT0_ENABLED) {
		float d = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
		c += LIGHT0_COLOR * glow_energy * pow(d, 2.0 / glow_size);
	}
	COLOR = c;
}
