// Full-screen "value study" filter for judging composition without colour.
// mode 0: colour (only the squint blur applies)
// mode 1: grayscale
// mode 2: three values: dark < split - mid_band <= mid < split <= light
//         (in a fogged scene this roughly separates near / middle / far planes)
// mode 3: notan (two values): everything darker than `split` becomes figure
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform int mode = 0;
// Mip level used to blur the frame - the digital version of squinting at a scene.
uniform float squint : hint_range(0.0, 6.0) = 0.0;
// Luminance where figure turns into sky/background.
uniform float split : hint_range(0.0, 1.0) = 0.62;
// Width of the mid band below `split` in 3-value mode.
uniform float mid_band : hint_range(0.05, 0.6) = 0.22;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, squint).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	if (mode == 1) {
		c = vec3(l);
	} else if (mode == 2) {
		c = vec3(l < split - mid_band ? 0.08 : (l < split ? 0.45 : 0.9));
	} else if (mode == 3) {
		c = vec3(l < split ? 0.06 : 0.92);
	}
	COLOR = vec4(c, 1.0);
}
