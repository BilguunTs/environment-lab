class_name Storm
extends Node
## The distant storm: soft lightning flickers far off in the fog, never a strike near her.
## Flashes come at random (Poisson) times at `rate_per_min`, which the MoodDirector sets from the
## mood. A flash only brightens the light the scene already has: a little sun and ambient energy
## and a paler sky and fog for 0.15-0.35 s, with no bolt, no light near her and no sound of its
## own. It emits `flashed` with the delay until its thunder, which the soundscape plays later.
##
## The flicker reaches the lights through `light()`, which the MoodDirector calls after it has
## set the mood's values each frame, so the flash adds to the mood instead of fighting it.

## Emitted at each flash with the seconds until its thunder (2.5-6.0: a few km away).
signal flashed(delay_s: float)

const THUNDER_MIN := 2.5
const THUNDER_MAX := 6.0
## Shortest and longest flicker, in seconds.
const FLASH_MIN := 0.15
const FLASH_MAX := 0.35
## What a flash adds at full glow. Kept small: lightning seen through fog from far away.
const SUN_BOOST := 0.45
const AMBIENT_BOOST := 0.5
## How far the sky horizon and the fog colour move toward FLASH_SKY at full glow.
const SKY_MIX := 0.35
const FLASH_SKY := Color(0.86, 0.89, 0.96)

## Mean flashes per minute (0 = no lightning). Set by the MoodDirector.
var rate_per_min := 0.0
## Flashes since the last reset.
var flash_count := 0
## The flicker's current brightness, 0..1 (0 between flashes).
var glow := 0.0

var _t := -1.0  # seconds into the current flash; < 0 when no flash is running
var _length := 0.0
var _flickers := 2.0
var _peak := 1.0


func _process(delta: float) -> void:
	if _t >= 0.0:
		_t += delta
		if _t >= _length:
			_t = -1.0
			glow = 0.0
		else:
			# A decaying flicker: 2-3 bright pulses fading over the flash.
			var k := _t / _length
			glow = _peak * (1.0 - k) * (0.5 + 0.5 * absf(cos(k * PI * _flickers)))
	elif rate_per_min > 0.0 and randf() < rate_per_min / 60.0 * delta:
		flash()


## One distant flash now; emits `flashed` with the thunder delay.
func flash() -> void:
	flash_count += 1
	_length = randf_range(FLASH_MIN, FLASH_MAX)
	_flickers = float(randi_range(2, 3))
	_peak = randf_range(0.7, 1.0)
	_t = 0.0
	glow = _peak
	flashed.emit(randf_range(THUNDER_MIN, THUNDER_MAX))


## Adds the current flicker on top of the lights the mood has just set. Call after the mood.
func light(sun: DirectionalLight3D, env: Environment, sky: ShaderMaterial) -> void:
	if glow <= 0.0:
		return
	if sun:
		sun.light_energy += glow * SUN_BOOST
	if env:
		env.ambient_light_energy += glow * AMBIENT_BOOST
		env.fog_light_color = env.fog_light_color.lerp(FLASH_SKY, glow * SKY_MIX)
	if sky:
		var horizon: Color = sky.get_shader_parameter("horizon_color")
		sky.set_shader_parameter("horizon_color", horizon.lerp(FLASH_SKY, glow * SKY_MIX))


## Back to a silent sky: no running flash, no rate, count cleared.
func reset() -> void:
	rate_per_min = 0.0
	flash_count = 0
	glow = 0.0
	_t = -1.0
