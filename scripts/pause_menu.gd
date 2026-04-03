extends CanvasLayer

# Simple pause/menu overlay.
# - Esc toggles it.
# - Return resumes.
# - Quit goes to title scene.

@export var title_scene_path: String = "res://scenes/title.tscn"
@export var dim_alpha: float = 0.55

@onready var root: Control = $Root
@onready var dim: ColorRect = $Root/Dim
@onready var panel: Panel = $Root/Panel
@onready var resume_button: Button = $Root/Panel/VBox/ResumeButton
@onready var quit_button: Button = $Root/Panel/VBox/QuitButton

var previous_mouse_mode: int = Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	# Godot 4: keep UI + input running while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	if dim:
		dim.color.a = clampf(dim_alpha, 0.0, 1.0)

	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("exit"):
		toggle()
		get_viewport().set_input_as_handled()

func is_open() -> bool:
	return root != null and root.visible

func toggle() -> void:
	if is_open():
		close()
	else:
		open()

func open() -> void:
	if root == null:
		return
	if root.visible:
		return
	previous_mouse_mode = Input.mouse_mode
	root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Small soft appear.
	if dim:
		dim.modulate.a = 0.0
	if panel:
		panel.modulate.a = 0.0
	var t := get_tree().create_tween()
	# Ensure the tween still runs while paused.
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.set_parallel(true)
	if dim:
		t.tween_property(dim, "modulate:a", 1.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if panel:
		t.tween_property(panel, "modulate:a", 1.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func close() -> void:
	if root == null:
		return
	if not root.visible:
		return
	root.visible = false
	get_tree().paused = false
	Input.mouse_mode = previous_mouse_mode

func _on_resume_pressed() -> void:
	close()

func _on_quit_pressed() -> void:
	# Ensure game unpauses before switching scenes.
	root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.reset_run()
	SceneLoader.change_scene(title_scene_path)

