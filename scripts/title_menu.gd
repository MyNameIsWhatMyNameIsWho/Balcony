extends Control

@export var start_scene_path: String = "res://scenes/flat.tscn"

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_start_pressed() -> void:
	# No save system: always start a fresh run.
	GameState.reset_run()
	# Load the game scene fully before switching to it.
	if SceneLoader != null:
		SceneLoader.change_scene(start_scene_path)
	else:
		get_tree().change_scene_to_file(start_scene_path)
