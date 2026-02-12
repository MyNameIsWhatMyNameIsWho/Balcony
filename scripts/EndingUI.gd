extends CanvasLayer

@export var start_scene_path: String = "res://scenes/flat.tscn"
@export var menu_scene_path: String = "res://scenes/title.tscn"

@onready var panel: Panel = $Root/Panel
@onready var lines_container: VBoxContainer = $Root/Panel/Lines
@onready var restart_button: Button = $Root/Panel/Buttons/RestartButton
@onready var quit_button: Button = $Root/Panel/Buttons/QuitButton

func _ready() -> void:
	panel.visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func open() -> void:
	_clear_lines()
	var ending: Dictionary = GameState.resolve_ending()
	var lines: Array = ending.get("lines", [])
	if ending.is_empty() or lines.is_empty():
		_add_line("Your story ended, but no ending text was configured for this path.")
	else:
		for line in lines:
			_add_line(str(line))
	panel.visible = true

func _clear_lines() -> void:
	for child in lines_container.get_children():
		child.queue_free()

func _add_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	lines_container.add_child(label)

func _on_restart_pressed() -> void:
	GameState.reset_run()
	get_tree().change_scene_to_file(start_scene_path)

func _on_quit_pressed() -> void:
	# Ensure a fresh run when returning to menu.
	GameState.reset_run()
	get_tree().change_scene_to_file(menu_scene_path)
