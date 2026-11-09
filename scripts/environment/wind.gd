@tool
class_name Wind
extends Node
## The scene's wind: a strength, a compass direction and a gust field that travels with it.
## Publishes three global shader uniforms (wind_strength, wind_direction, wind_phase) that
## wind.gdshaderinc reads. The phase is how far the gust pattern has travelled along the wind, in
## pattern space: it is integrated here (never derived from TIME * speed), so changing strength
## can't make the pattern jump, and because it isn't a world-space offset, turning the wind only
## rotates the pattern about the world origin, however long the scene has run.

## Metres per second the gust pattern travels at strength 1.0.
const GUST_SPEED := 4.0
## Size of one gust noise cell along the wind and across it, in metres (wind_gust in the include).
const GUST_CELL_ALONG := 20.0
const GUST_CELL_ACROSS := 40.0
## The phase wraps at this many metres so float32 precision never stalls the scroll. It is a whole
## number of cells of both noise octaves (100 and 230), and wind_gust's noise repeats along the
## wind with exactly this period, so the wrap is invisible.
const PHASE_PERIOD := 2000.0

## 0 = calm, 1 = the Stage 8 look, 2 = storm.
@export_range(0, 2) var strength := 0.6:
	set(value):
		strength = value
		_publish("wind_strength", value)
## Compass angle the wind blows toward: 0 = toward -Z, 90 = toward +X, clockwise from above.
@export_range(0, 360) var direction_degrees := 53.13:
	set(value):
		direction_degrees = value
		_publish("wind_direction", vector())
## How far the gust pattern has travelled downwind, in metres, wrapped to [0, PHASE_PERIOD).
var phase := 0.0


func _ready() -> void:
	_publish("wind_strength", strength)
	_publish("wind_direction", vector())
	_publish("wind_phase", phase)


func _process(delta: float) -> void:
	phase = fposmod(phase + strength * GUST_SPEED * delta, PHASE_PERIOD)
	_publish("wind_phase", phase)


## Unit vector on the ground plane (x, z) the wind blows toward.
static func vector_for(degrees: float) -> Vector2:
	var rad := deg_to_rad(degrees)
	return Vector2(sin(rad), -cos(rad))


## Where a world position samples the gust noise, in noise cells (x along the wind, y across it).
## Mirrors `q` in wind_gust (assets/shaders/wind.gdshaderinc); keep the two in step.
static func pattern_coord(world_xz: Vector2, direction: Vector2, gust_phase: float) -> Vector2:
	var across := Vector2(-direction.y, direction.x)
	return Vector2((world_xz.dot(direction) - gust_phase) / GUST_CELL_ALONG,
			world_xz.dot(across) / GUST_CELL_ACROSS)


func vector() -> Vector2:
	return vector_for(direction_degrees)


## A no-op when the global doesn't exist (a project without the shader_globals entries).
func _publish(global_name: String, value: Variant) -> void:
	if ProjectSettings.has_setting("shader_globals/" + global_name):
		RenderingServer.global_shader_parameter_set(global_name, value)
