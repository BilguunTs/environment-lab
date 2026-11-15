// Terrain replica ground (scripts/replica/replica_terrain.gd). The mesh is a flat grid; each
// vertex reads its height from `heights` (absolute metres, one texel per grid sample, row 0 =
// north = -Z) with texelFetch, so the drawn surface passes exactly through every DEM sample.
// Vertices with mesh y = -1 are skirt vertices and hang `skirt_depth` below the edge (they hide
// LOD and core/ring seams; their triangles have both windings). Faceted normals from screen
// derivatives, like flat_color.gdshader. `palette` and `ring_color` are sRGB (source_color).
// Colour: the surface class map (`classes`, value = class id, 1 m pixels) through `palette`,
// bilinear between pixel centres so class edges are soft at 1 m; or one flat `ring_color`.
// The ring discards everything inside `hole` (the core square), so only the core is seen there.
shader_type spatial;
render_mode cull_back;

uniform sampler2D heights : filter_nearest, repeat_disable;
uniform vec2 origin;          // world xz of sample (0, 0)
uniform float step_m = 1.0;
uniform int grid_n = 1;
uniform float base = 0.0;     // subtracted from every height (manifest base_elevation)
uniform float skirt_depth = 4.0;

uniform bool use_classes = false;
uniform sampler2D classes : filter_nearest, repeat_disable;
uniform vec2 classes_origin;  // world xz of the class map's (0, 0) pixel corner
uniform float classes_m_per_px = 1.0;
uniform int classes_n = 1;
uniform vec4 palette[8] : source_color;  // index = class id
uniform vec4 ring_color : source_color = vec4(0.5, 0.45, 0.3, 1.0);
uniform float hole = 0.0;     // half size of the discarded square (0 = none)
uniform float roughness : hint_range(0.0, 1.0) = 0.95;

varying vec3 world_pos;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX.x, 0.0, VERTEX.z, 1.0)).xyz;
	ivec2 ij = clamp(ivec2(round((w.xz - origin) / step_m)), ivec2(0), ivec2(grid_n - 1));
	float h = texelFetch(heights, ij, 0).r - base;
	VERTEX.y = h + min(VERTEX.y, 0.0) * skirt_depth - MODEL_MATRIX[3].y;
	world_pos = vec3(w.x, h, w.z);
}

vec3 class_color(ivec2 p) {
	p = clamp(p, ivec2(0), ivec2(classes_n - 1));
	int id = int(texelFetch(classes, p, 0).r * 255.0 + 0.5);
	return palette[clamp(id, 0, 7)].rgb;
}

void fragment() {
	if (hole > 0.0 && abs(world_pos.x) < hole && abs(world_pos.z) < hole) {
		discard;
	}
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	vec3 color = ring_color.rgb;
	if (use_classes) {
		vec2 u = (world_pos.xz - classes_origin) / classes_m_per_px - 0.5;
		ivec2 p = ivec2(floor(u));
		vec2 f = u - vec2(p);
		color = mix(mix(class_color(p), class_color(p + ivec2(1, 0)), f.x),
				mix(class_color(p + ivec2(0, 1)), class_color(p + ivec2(1, 1)), f.x), f.y);
	}
	ALBEDO = color;
	ROUGHNESS = roughness;
}
