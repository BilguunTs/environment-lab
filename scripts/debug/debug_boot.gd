extends Node
## Autoload. Wireframe debug draw only works for meshes created after this flag is set, so it
## has to run before the main scene loads. `--no-wireframes` (user args) skips it, for profiling.


func _init() -> void:
	if "--no-wireframes" in OS.get_cmdline_user_args():
		return
	RenderingServer.set_debug_generate_wireframes(true)
