shader_type particles;
// Spirit stream: every wisp travels one quadratic Bezier (source -> apex -> target) over its
// lifetime. The path is art-directed, not simulated, so moving the end nodes reshapes the
// stream predictably. Uniforms are world space; spirit_stream.gd keeps them in sync.

uniform vec3 source;
uniform vec3 apex;
uniform vec3 target;
uniform float spread = 1.6;  // m, widest sideways scatter of the lanes (mid-flight)
uniform float wobble = 0.5;  // m, slow drift amplitude around each lane
uniform float size = 0.3;  // m, wisp diameter
uniform vec4 tint : source_color = vec4(0.62, 0.78, 1.0, 1.0);

float hash(uint n) {
	n = (n << 13u) ^ n;
	n = n * (n * n * 15731u + 789221u) + 1376312589u;
	return float(n & 0x7fffffffu) / float(0x7fffffff);
}

vec3 bezier(float t) {
	float u = 1.0 - t;
	return u * u * source + 2.0 * u * t * apex + t * t * target;
}

void start() {
	CUSTOM.w = 0.0;  // age along the path, 0..1
	COLOR = vec4(tint.rgb, 0.0);
	TRANSFORM = mat4(vec4(0.0), vec4(0.0), vec4(0.0), vec4(source, 1.0));
}

void process() {
	// NUMBER is unique per spawn, so each wisp gets its own lane, phase and pace.
	uint n = NUMBER * 4u;
	vec2 lane = vec2(hash(n), hash(n + 1u)) * 2.0 - 1.0;
	float ph = hash(n + 2u) * 6.2832;
	// pace >= 1 so every wisp reaches the ember (and fades) before LIFETIME would cut it off.
	float pace = mix(1.0, 1.4, hash(n + 3u));
	CUSTOM.w += DELTA / LIFETIME * pace;
	float t = clamp(CUSTOM.w, 0.0, 1.0);
	// Lanes pinch to a point at both ends: spirits leave the hole and enter the ember.
	float body = sin(t * PI);
	vec3 along = normalize(target - source);
	vec3 side = normalize(cross(along, vec3(0.0, 1.0, 0.0)));
	vec3 lift = cross(side, along);
	vec3 drift = side * sin(TIME * 0.7 + ph) + lift * sin(TIME * 0.5 + ph * 1.7);
	vec3 pos = bezier(t) + (side * lane.x + lift * lane.y * 0.5) * spread * body + drift * wobble * body;

	float fade = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.88, 1.0, t));
	float twinkle = 0.75 + 0.25 * sin(TIME * 2.3 + ph * 3.0);
	COLOR = vec4(tint.rgb, fade * twinkle);
	float s = size * (0.7 + 0.6 * hash(n + 5u)) * (0.5 + 0.5 * body);
	TRANSFORM = mat4(vec4(s, 0, 0, 0), vec4(0, s, 0, 0), vec4(0, 0, s, 0), vec4(pos, 1.0));
	if (CUSTOM.w >= 1.0) {
		ACTIVE = false;
	}
}
