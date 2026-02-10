extends Area3D

@export var window_id: String = ""
@export var hover_lines: Array[String] = []
@export var vignette_text: String = ""
@export var choice_a_text: String = "Engage"
@export var choice_b_text: String = "Look away"
@export var fragment_on_a: bool = true
@export var fragment_on_b: bool = false
@export var window_camera_path: NodePath

func _ready() -> void:
	validate()

func validate() -> void:
	if window_id == "":
		push_warning("WindowData: window_id is empty on %s." % name)
