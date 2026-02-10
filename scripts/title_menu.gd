extends Control

@export var start_scene_path: String = "res://scenes/flat.tscn"

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(start_scene_path)
