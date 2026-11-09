class_name MoodDirector
extends Node
## The level's mood: four keys, one per stretch, blended by her FURTHEST progress along the trail
## (never by time), so a slow or wandering player still gets the whole build-up and walking back
## down never undoes it. HeavensCall calls `apply(MoodDirector.sample(furthest_progress))` each
## frame; `apply` drives the Wind node, the fog, the mist, the sun, the sky, the storm's lightning
## rate and (once it exists) the soundscape's volumes.
##
## Blending: between two keys every value follows a smoothstep from one key to the next, so the
## mood builds through each stretch. The GATED values (lightning, eerie ambience) are the
## exception: they belong to a stretch and switch in over GATE_RAMP after its start instead of
## creeping in ahead of it, so there is no lightning and no eerie sound before EERIE.
##
## Key table (tuned by eye; see the captures in the Task 3 report):
##
## | key              | ASCENT 0.00      | DISCOVERY 0.28   | EERIE 0.57       | SUMMIT 0.86      |
## |------------------|------------------|------------------|------------------|------------------|
## | wind             | 0.70             | 0.85             | 1.15             | 1.45             |
## | wind_swing_deg   | 4                | 5                | 6                | 6                |
## | fog_density      | 0.014            | 0.017            | 0.028            | 0.011            |
## | mist             | 0.35             | 0.45             | 0.80             | 0.30             |
## | lightning_per_min| 0                | 0                | 2.0              | 0                |
## | sun_energy       | 1.30             | 1.10             | 0.80             | 1.00             |
## | sun_color        | (1.00,0.88,0.74) | (0.95,0.86,0.76) | (0.80,0.82,0.88) | (0.95,0.84,0.70) |
## | ambient          | 0.45             | 0.50             | 0.75             | 1.15             |
## | sky_color        | (0.56,0.58,0.60) | (0.52,0.54,0.56) | (0.42,0.45,0.49) | (0.50,0.50,0.52) |
## | zenith_color     | (0.34,0.39,0.46) | (0.31,0.35,0.41) | (0.23,0.26,0.32) | (0.28,0.30,0.36) |
## | vol_wind         | 0.70             | 0.75             | 0.60             | 0.50             |
## | vol_wind_strong  | 0.10             | 0.25             | 0.60             | 0.90             |
## | vol_eerie        | 0                | 0                | 0.70             | 0.30             |
##
## sky_color is the sky's horizon and also the fog, background and ambient light colour: distant
## forms dissolve into it and shadows take the pale overcast light. zenith_color is the sky's top.
## `ambient` (ambient energy) and `sun_color` are extras beyond the brief's list, there to keep the
## shadowed late climb (0.8-0.95, on the side away from the low sun) readable.

const KEYS := [
	{
		"at": 0.0,  # ASCENT: quiet, lonely, heavy wind, thick fog
		"wind": 0.7, "wind_swing_deg": 4.0, "fog_density": 0.014, "mist": 0.35,
		"lightning_per_min": 0.0, "sun_energy": 1.3, "sun_color": Color(1.0, 0.88, 0.74),
		"ambient": 0.45, "sky_color": Color(0.56, 0.58, 0.6), "zenith_color": Color(0.34, 0.39, 0.46),
		"vol_wind": 0.7, "vol_wind_strong": 0.1, "vol_eerie": 0.0,
	},
	{
		"at": 0.28,  # DISCOVERY: the war debris; greyer, a little thicker
		"wind": 0.85, "wind_swing_deg": 5.0, "fog_density": 0.017, "mist": 0.45,
		"lightning_per_min": 0.0, "sun_energy": 1.1, "sun_color": Color(0.95, 0.86, 0.76),
		"ambient": 0.5, "sky_color": Color(0.52, 0.54, 0.56), "zenith_color": Color(0.31, 0.35, 0.41),
		"vol_wind": 0.75, "vol_wind_strong": 0.25, "vol_eerie": 0.0,
	},
	{
		"at": 0.57,  # EERIE: thickest fog, cold light, shifting wind, distant lightning
		"wind": 1.15, "wind_swing_deg": 6.0, "fog_density": 0.028, "mist": 0.8,
		"lightning_per_min": 2.0, "sun_energy": 0.8, "sun_color": Color(0.8, 0.82, 0.88),
		"ambient": 0.75, "sky_color": Color(0.42, 0.45, 0.49), "zenith_color": Color(0.23, 0.26, 0.32),
		"vol_wind": 0.6, "vol_wind_strong": 0.6, "vol_eerie": 0.7,
	},
	{
		"at": 0.86,  # SUMMIT: wind surges, fog thinning before it parts; the sequence owns the clap
		"wind": 1.45, "wind_swing_deg": 6.0, "fog_density": 0.011, "mist": 0.3,
		"lightning_per_min": 0.0, "sun_energy": 1.0, "sun_color": Color(0.95, 0.84, 0.7),
		"ambient": 1.15, "sky_color": Color(0.5, 0.5, 0.52), "zenith_color": Color(0.28, 0.3, 0.36),
		"vol_wind": 0.5, "vol_wind_strong": 0.9, "vol_eerie": 0.3,
	},
]
## Values that belong to their stretch: they change only after a key, over GATE_RAMP.
const GATED := ["lightning_per_min", "vol_eerie"]
## Progress over which a gated value moves to its new key (0.05 is about 35 m of trail).
const GATE_RAMP := 0.05
## Seconds for one slow swing of the wind direction. Wind turns the gust field about the world
## origin, so at the trail's 150 m radius the gusts slide sideways at
## 150 * deg_to_rad(wind_swing_deg) * TAU / SWING_PERIOD m/s at most: 0.5-0.8 m/s with these keys,
## under a fifth of their own downwind travel (Wind.GUST_SPEED * strength, 2.8-5.8 m/s).
const SWING_PERIOD := 120.0
## Mist noise drift in noise-space units per second at wind 1.0 (as in the playground).
const MIST_DRIFT := 0.05
## The volumetric fog density per unit of depth-fog density (the playground's 0.004 / 0.009).
const VOLUMETRIC_RATIO := 0.45
## The mist is thickest from this far below her feet and thins out over the shader's mist_height,
## so it pools in the drops and hollows around her and only wisps about her ankles.
const MIST_BASE_BELOW := 4.0
## Wind strength added at full wind_surge (the SUMMIT key's 1.45 rises to 1.8).
const SURGE_STRENGTH := 0.35

@export var wind: Wind
@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
## A FogVolume with the ground_mist shader; it is kept centred on `follow`.
@export var mist: FogVolume
@export var storm: Storm
## Who the mist follows (the girl).
@export var follow: Node3D
## The Soundscape (Task 4). Optional: without it the mood is silent.
@export var soundscape: Node
## The summit Vista (Task 6). Optional. Its `reveal` opens the view on top of the mood: the fog
## is scaled by vista.fog_scale() and the ground mist by vista.mist_scale() (both 1 at reveal 0),
## and its sky colours by vista.horizon_tint()/zenith_tint() (identity at reveal 0), so the mood
## keeps driving everything and `current` stays the mood's own values.
@export var vista: Vista

## The summit sequence's wind surge (0..1, Task 7), composed on top of the mood in every apply():
## wind_strong's volume rises from the mood's value toward 1 and the wind's strength by
## SURGE_STRENGTH, so the surge is never overwritten by the next frame's mood.
var wind_surge := 0.0

## The mood applied last (the mood's own values, without the surge).
var current: Dictionary = {}

var _time := 0.0
var _mist_offset := Vector3.ZERO
var _base_direction := 0.0


func _ready() -> void:
	if wind:
		_base_direction = wind.direction_degrees


func _process(delta: float) -> void:
	_time += delta
	if mist == null:
		return
	if follow:
		mist.global_position = follow.global_position
		mist.material.set_shader_parameter("base_height", follow.global_position.y - MIST_BASE_BELOW)
	if wind:
		# Integrated, not TIME * speed, so a change of wind never makes the mist jump.
		var drift := wind.vector() * wind.strength * MIST_DRIFT * delta
		_mist_offset -= Vector3(drift.x, 0.0, drift.y)
		mist.material.set_shader_parameter("offset", _mist_offset)


## The mood at `progress` (0..1): a smoothstep blend of the two keys around it, colours lerped;
## the GATED values switch in after their key (see the class comment).
static func sample(progress: float) -> Dictionary:
	var p := clampf(progress, 0.0, 1.0)
	var i := 0
	while i < KEYS.size() - 1 and p >= KEYS[i + 1].at:
		i += 1
	var a: Dictionary = KEYS[i]
	var out := a.duplicate()
	out.at = p
	if i < KEYS.size() - 1:
		var b: Dictionary = KEYS[i + 1]
		var t := smoothstep(a.at, b.at, p)
		for key: String in a:
			if key != "at" and key not in GATED:
				out[key] = _mix(a[key], b[key], t)
	if i > 0:
		var before: Dictionary = KEYS[i - 1]
		var g := smoothstep(a.at, a.at + GATE_RAMP, p)
		for key: String in GATED:
			out[key] = lerpf(before[key], a[key], g)
	return out


## Drives every system from `mood` (a `sample()` result) and remembers it as `current`.
func apply(mood: Dictionary) -> void:
	current = mood
	if wind:
		wind.strength = mood.wind + SURGE_STRENGTH * wind_surge
		var swing := sin(_time * TAU / SWING_PERIOD)
		wind.direction_degrees = fposmod(_base_direction + mood.wind_swing_deg * swing, 360.0)
	if sun:
		sun.light_energy = mood.sun_energy
		sun.light_color = mood.sun_color
	var open_fog := vista.fog_scale() if vista else 1.0
	var open_mist := vista.mist_scale() if vista else 1.0
	var sky_color: Color = vista.horizon_tint(mood.sky_color) if vista else mood.sky_color
	var zenith_color: Color = vista.zenith_tint(mood.zenith_color) if vista else mood.zenith_color
	var env: Environment = world_environment.environment if world_environment else null
	var sky: ShaderMaterial = null
	if env:
		env.fog_density = mood.fog_density * open_fog
		env.volumetric_fog_density = env.fog_density * VOLUMETRIC_RATIO
		env.fog_light_color = sky_color
		env.background_color = sky_color
		env.ambient_light_color = sky_color
		env.ambient_light_energy = mood.ambient
		if env.sky and env.sky.sky_material is ShaderMaterial:
			sky = env.sky.sky_material
			sky.set_shader_parameter("horizon_color", sky_color)
			sky.set_shader_parameter("zenith_color", zenith_color)
	if mist:
		mist.material.set_shader_parameter("density", mood.mist * open_mist)
	if storm:
		storm.rate_per_min = mood.lightning_per_min
		storm.light(sun, env, sky)
	if soundscape and soundscape.has_method("set_volumes"):
		var strong := lerpf(mood.vol_wind_strong, 1.0, wind_surge)
		soundscape.set_volumes(mood.vol_wind, strong, mood.vol_eerie)


static func _mix(a: Variant, b: Variant, t: float) -> Variant:
	if a is Color:
		return (a as Color).lerp(b, t)
	return lerpf(a, b, t)
