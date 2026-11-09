extends OmniLight3D
## Fire-like flicker: smooth noise on top of a base energy.

@export var base_energy := 2.0
@export_range(0.0, 1.0) var amount := 0.35
@export var speed := 6.0

var _noise := FastNoiseLite.new()
var _t := 0.0


func _ready() -> void:
	_noise.seed = randi()
	_noise.frequency = 0.4
	_t = randf() * 100.0


func _process(delta: float) -> void:
	_t += delta * speed
	light_energy = base_energy * (1.0 + amount * _noise.get_noise_1d(_t))
