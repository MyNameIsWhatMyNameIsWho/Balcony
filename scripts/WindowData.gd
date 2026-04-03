extends Area3D

@export var window_id: String = ""
@export var window_camera_path: NodePath

func _ready() -> void:
	if window_id == "":
		push_warning("WindowData: window_id is empty on %s." % name)
