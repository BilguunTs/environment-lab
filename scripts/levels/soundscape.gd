class_name Soundscape
extends Node
## The level's sound: wind and eerie loops whose volumes follow the mood, gravel and rock
## footsteps, and thunder. Never music or jump scares. Every file is optional: a missing one
## gives a null stream and stays silent, with no error (checked with ResourceLoader.exists).

const DIR := "res://assets/audio/"
## Volume at linear 0 and below.
const FLOOR_DB := -60.0
const DISTANT_COUNT := 3
const STEP_COUNT := 4

var wind_loop: AudioStreamPlayer
var wind_strong_loop: AudioStreamPlayer
var ambience_eerie_loop: AudioStreamPlayer
## "gravel" or "rock": the kind of the last footstep.
var last_step_kind := ""

var _steps: AudioStreamPlayer3D
var _thunder: AudioStreamPlayer
## The clap has its own voice, so a late distant roll can't cut it off.
var _clap: AudioStreamPlayer
var _last_step_name := ""


func _ready() -> void:
	wind_loop = _make_loop("wind_loop")
	wind_strong_loop = _make_loop("wind_strong_loop")
	ambience_eerie_loop = _make_loop("ambience_eerie_loop")
	_thunder = AudioStreamPlayer.new()
	_thunder.name = "Thunder"
	add_child(_thunder)
	_clap = AudioStreamPlayer.new()
	_clap.name = "Clap"
	add_child(_clap)
	_steps = AudioStreamPlayer3D.new()
	_steps.name = "Footsteps"
	add_child(_steps)


## The stream `DIR + name + ".ogg"`, or null when that file isn't there.
static func load_stream(name: String) -> AudioStream:
	var path := DIR + name + ".ogg"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


## The four file names of a footstep kind ("gravel" or "rock").
static func step_names(kind: String) -> Array:
	var out := []
	for i in STEP_COUNT:
		out.append("footstep_%s_%d" % [kind, i + 1])
	return out


func loop_players() -> Array[AudioStreamPlayer]:
	return [wind_loop, wind_strong_loop, ambience_eerie_loop]


## Puts the footstep voice on `parent` (the girl) so steps sound from her feet.
func attach_footsteps(parent: Node3D) -> void:
	if _steps.get_parent() != parent:
		_steps.reparent(parent, false)
	_steps.position = Vector3.ZERO


## Loop volumes, 0..1 linear each, mapped to dB with a floor at -60 dB.
func set_volumes(vol_wind: float, vol_wind_strong: float, vol_eerie: float) -> void:
	wind_loop.volume_db = _to_db(vol_wind)
	wind_strong_loop.volume_db = _to_db(vol_wind_strong)
	ambience_eerie_loop.volume_db = _to_db(vol_eerie)


## One distant thunder roll, or the clap (on its own player). `file` overrides the file name
## (test seam: a nonexistent name must stay silent).
func play_thunder(clap := false, file := "") -> void:
	if file == "":
		file = "thunder_clap" if clap else "thunder_distant_%d" % (randi() % DISTANT_COUNT + 1)
	_play(_clap if clap else _thunder, load_stream(file))


## Cuts off any thunder roll or clap and footstep still sounding (the level's reset).
func stop_one_shots() -> void:
	_thunder.stop()
	_clap.stop()
	_steps.stop()


## Whether a thunder roll or the clap is sounding.
func thunder_playing() -> bool:
	return _thunder.playing or _clap.playing


## One footstep: gravel on the trail, rock off it. Never the same file twice in a row.
func step(on_trail: bool, file := "") -> void:
	last_step_kind = "gravel" if on_trail else "rock"
	var names := step_names(last_step_kind)
	names.erase(_last_step_name)
	_last_step_name = names[randi() % names.size()]
	_play(_steps, load_stream(file if file != "" else _last_step_name))


func _make_loop(file: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = file.to_pascal_case()
	var s := load_stream(file)
	if s:
		s = s.duplicate()
		if "loop" in s:
			s.loop = true
	p.stream = s
	p.volume_db = FLOOR_DB
	add_child(p)
	if s:
		p.play()
	return p


func _play(p: Node, s: AudioStream) -> void:
	if s == null:
		return
	p.stream = s
	p.play()


static func _to_db(linear: float) -> float:
	if linear <= 0.0001:
		return FLOOR_DB
	return maxf(linear_to_db(linear), FLOOR_DB)
