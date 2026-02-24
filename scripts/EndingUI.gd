extends CanvasLayer

@export var start_scene_path: String = "res://scenes/flat.tscn"
@export var menu_scene_path: String = "res://scenes/title.tscn"

@export var fade_to_black_duration: float = 2.4
@export var exhale_pause: float = 0.9
@export var block_slide_duration: float = 0.8
@export var block_slide_offset: float = 38.0
@export var block_fade_out_duration: float = 0.45
@export var block_chars_per_sec: float = 11.0
@export var block_min_hold: float = 2.2
@export var block_max_hold: float = 5.5
@export var post_last_block_pause: float = 1.2
@export var buttons_fade_duration: float = 0.9

@export_group("Ending SFX")
@export var inhale_exhale_sfx: AudioStream = preload("res://assets/kenney_rpg-audio/Audio/amber2023-inhale-exhale-230173.mp3")
@export var inhale_exhale_bus: StringName = &"Foley"
@export var inhale_exhale_volume_db: float = 0.0
@export var inhale_exhale_pitch_scale: float = 1.0

@onready var overlay: ColorRect = $Root/Overlay
@onready var ending_label: Label = $Root/EndingLabel
@onready var buttons_container: VBoxContainer = $Root/ButtonsContainer
@onready var restart_button: Button = $Root/ButtonsContainer/RestartButton
@onready var quit_button: Button = $Root/ButtonsContainer/QuitButton
@onready var sfx_player: AudioStreamPlayer = get_node_or_null("SFXPlayer") as AudioStreamPlayer

var _label_center_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.modulate.a = 0.0
	ending_label.visible = false
	ending_label.modulate.a = 0.0
	buttons_container.visible = false
	buttons_container.modulate.a = 0.0
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func open() -> void:
	var ending: Dictionary = GameState.resolve_ending()
	var raw_lines: Array = ending.get("lines", [])
	var blocks := _split_into_blocks(raw_lines)
	if blocks.is_empty():
		blocks = ["Your story ended here."]
	_run_cinematic(blocks)

func _split_into_blocks(lines: Array) -> Array[String]:
	var blocks: Array[String] = []
	var buffer: Array[String] = []
	for line in lines:
		if str(line).strip_edges() == "":
			if buffer.size() > 0:
				blocks.append("\n".join(buffer))
				buffer.clear()
		else:
			buffer.append(str(line))
	if buffer.size() > 0:
		blocks.append("\n".join(buffer))
	return blocks

func _run_cinematic(blocks: Array[String]) -> void:
	# 1. Start inhale/exhale sound and fade to black together.
	_play_inhale_exhale()
	var ft := create_tween()
	ft.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ft.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	ft.tween_property(overlay, "modulate:a", 1.0, fade_to_black_duration)
	await ft.finished

	# 2. Extra beat before anything appears.
	await get_tree().create_timer(exhale_pause, true, false, true).timeout

	# 3. Prepare the label and show blocks one by one.
	_setup_label_position()
	ending_label.visible = true

	for i in blocks.size():
		await _show_block(blocks[i], i == blocks.size() - 1)

	# 4. Brief pause after the last block settles.
	await get_tree().create_timer(post_last_block_pause, true, false, true).timeout

	# 5. Fade the buttons up from nothing.
	buttons_container.visible = true
	var bt := create_tween()
	bt.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	bt.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	bt.tween_property(buttons_container, "modulate:a", 1.0, buttons_fade_duration)

func _play_inhale_exhale() -> void:
	var p := _get_sfx_player()
	if p == null or inhale_exhale_sfx == null:
		return
	p.stop()
	p.stream = inhale_exhale_sfx
	p.bus = inhale_exhale_bus if AudioServer.get_bus_index(inhale_exhale_bus) != -1 else &"Master"
	p.volume_db = inhale_exhale_volume_db
	p.pitch_scale = inhale_exhale_pitch_scale
	p.play()

func _setup_label_position() -> void:
	var vp := get_viewport().get_visible_rect().size
	var label_w := ending_label.custom_minimum_size.x
	if label_w <= 0.0:
		label_w = vp.x * 0.75
	var x := (vp.x - label_w) * 0.5
	var y := vp.y * 0.5 - 80.0
	_label_center_pos = Vector2(x, y)
	ending_label.position = _label_center_pos

func _show_block(text: String, is_last: bool) -> void:
	ending_label.text = text
	ending_label.modulate.a = 0.0
	ending_label.position = _label_center_pos + Vector2(0.0, -block_slide_offset)

	var in_t := create_tween().set_parallel(true)
	in_t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	in_t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	in_t.tween_property(ending_label, "modulate:a", 1.0, block_slide_duration)
	in_t.tween_property(ending_label, "position", _label_center_pos, block_slide_duration)
	await in_t.finished

	await get_tree().create_timer(_estimate_hold(text), true, false, true).timeout

	if not is_last:
		var out_t := create_tween()
		out_t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		out_t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		out_t.tween_property(ending_label, "modulate:a", 0.0, block_fade_out_duration)
		await out_t.finished

func _estimate_hold(text: String) -> float:
	var d := float(text.length()) / maxf(1.0, block_chars_per_sec)
	return clampf(d, block_min_hold, block_max_hold)

func _get_sfx_player() -> AudioStreamPlayer:
	if sfx_player != null:
		return sfx_player
	var p := AudioStreamPlayer.new()
	p.name = "SFXPlayerRuntime"
	add_child(p)
	sfx_player = p
	return p

func _on_restart_pressed() -> void:
	GameState.reset_run()
	if SceneLoader != null:
		SceneLoader.change_scene(start_scene_path)
	else:
		get_tree().change_scene_to_file(start_scene_path)

func _on_quit_pressed() -> void:
	GameState.reset_run()
	if SceneLoader != null:
		SceneLoader.change_scene(menu_scene_path)
	else:
		get_tree().change_scene_to_file(menu_scene_path)
