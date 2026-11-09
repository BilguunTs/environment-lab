class_name Viewpoint
extends Camera3D
## A fixed cinematic viewpoint. Frame it in the editor with the viewport's "Preview" checkbox.
## `intent` is shown on screen at runtime as a reminder of what the shot is meant to do.

@export_multiline var intent := ""
## Layout views read the plan, not the mood: render them without fog.
@export var ignore_fog := false
