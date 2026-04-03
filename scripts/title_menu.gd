extends Control

@export var start_scene_path: String = "res://scenes/flat.tscn"

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_start_pressed() -> void:
	# No save system: always start a fresh run.
	GameState.reset_run()
	SceneLoader.change_scene(start_scene_path)
