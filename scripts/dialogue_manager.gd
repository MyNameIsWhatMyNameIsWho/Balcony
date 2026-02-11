extends CanvasLayer

signal dialogue_finished(dialogue_id: String)
signal stop_watching_pressed
signal window_choice_made(choice: String)

@export var character_path: NodePath
@export var continue_action: String = "interact"
@export var prompt_text: String = "Press E to continue"
@export var typing_enabled: bool = true
@export var typing_chars_per_sec: float = 35.0
@export var typing_sound_interval: float = 0.04

var active := false
var current_lines: Array[String] = []
var current_index := 0
var current_id := ""
var queued: Array[Dictionary] = []
var typing_active := false
var typing_progress := 0.0
var current_line_full := ""
var sound_timer := 0.0
var hover_active := false
var external_controls_lock := false

@onready var character := get_node_or_null(character_path)
@onready var panel: Panel = $Root/Panel
@onready var dialogue_label: Label = $Root/Panel/DialogueLabel
@onready var prompt_label: Label = $Root/Panel/PromptLabel
@onready var interact_hint: Label = $Root/InteractHint
@onready var type_sound: AudioStreamPlayer = $Root/TypeSound
@onready var stop_watching_button: Button = $Root/StopWatchingButton
@onready var choice_overlay: Control = $Root/ChoiceOverlay
@onready var choice_left_button: Button = $Root/ChoiceOverlay/LeftButton
@onready var choice_right_button: Button = $Root/ChoiceOverlay/RightButton
@onready var choice_left_label: Label = $Root/ChoiceOverlay/LeftButton/ChoiceLabel
@onready var choice_right_label: Label = $Root/ChoiceOverlay/RightButton/ChoiceLabel

# Choice hover animation state
var choice_hovered: String = "" # "", "A", "B"
var choice_left_base_pos: Vector2
var choice_right_base_pos: Vector2
var choice_left_base_scale: Vector2 = Vector2.ONE
var choice_right_base_scale: Vector2 = Vector2.ONE
var choice_left_float_tween: Tween
var choice_right_float_tween: Tween
var choice_left_style_tween: Tween
var choice_right_style_tween: Tween

func _ready() -> void:
	panel.visible = false
	interact_hint.visible = false

	# Let 3D clicks pass through hover/dialogue panel (window selection uses raycasts).
	# Keep interactive UI (choices/stop button) clickable via their own Button nodes.
	if panel:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dialogue_label:
		dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if prompt_label:
		prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if interact_hint:
		interact_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if stop_watching_button:
		stop_watching_button.visible = false
		stop_watching_button.pressed.connect(_on_stop_watching_pressed)
	if choice_overlay:
		choice_overlay.visible = false
	if choice_left_button:
		choice_left_button.pressed.connect(_on_choice_left_pressed)
		choice_left_button.mouse_entered.connect(_on_choice_left_mouse_entered)
		choice_left_button.mouse_exited.connect(_on_choice_left_mouse_exited)
	if choice_right_button:
		choice_right_button.pressed.connect(_on_choice_right_pressed)
		choice_right_button.mouse_entered.connect(_on_choice_right_mouse_entered)
		choice_right_button.mouse_exited.connect(_on_choice_right_mouse_exited)
	call_deferred("_cache_choice_bases")
	var intro := ContentDB.get_intro_lines()
	if intro.size() > 0:
		# Intro shows in "blocks" separated by an empty line in JSON.
		# Each press advances to the next block (not the next line).
		var blocks := _split_into_blocks(intro)
		if blocks.size() > 0:
			show_dialogue(blocks, "intro", true)

func is_active() -> bool:
	return active

func set_interact_hint(show_hint: bool, text: String = "") -> void:
	if interact_hint == null:
		return
	interact_hint.visible = show_hint
	if show_hint and text != "":
		interact_hint.text = text

func _split_into_blocks(lines: Array[String]) -> Array[String]:
	var blocks: Array[String] = []
	var buffer: Array[String] = []
	for line in lines:
		if line.strip_edges() == "":
			if buffer.size() > 0:
				blocks.append("\n".join(buffer))
				buffer.clear()
			continue
		buffer.append(line)
	if buffer.size() > 0:
		blocks.append("\n".join(buffer))
	return blocks

func show_blocked_dialogue(lines: Array[String], dialogue_id: String = "", lock_controls: bool = true) -> void:
	# Same behavior as intro: JSON lines are grouped into blocks separated by empty lines.
	var blocks := _split_into_blocks(lines)
	if blocks.size() > 0:
		show_dialogue(blocks, dialogue_id, lock_controls)

func show_dialogue(lines: Array[String], dialogue_id: String = "", lock_controls: bool = true) -> void:
	if lines.is_empty():
		return
	current_lines = lines
	current_index = 0
	current_id = dialogue_id
	active = true
	hover_active = false
	panel.visible = true
	prompt_label.visible = true
	_start_typing_line(current_lines[current_index])
	prompt_label.text = prompt_text
	if lock_controls and character:
		character.set_controls_enabled(false)

func queue_dialogue(lines: Array[String], dialogue_id: String = "") -> void:
	if lines.is_empty():
		return
	queued.append({"lines": lines, "id": dialogue_id})

func _input(event: InputEvent) -> void:
	if not active:
		# Allow keyboard choice selection even when dialogue is not active.
		if is_choice_open():
			if event.is_action_pressed("move_left"):
				_select_choice("A")
			elif event.is_action_pressed("move_right"):
				_select_choice("B")
		return
	if event.is_action_pressed(continue_action):
		if typing_active:
			_finish_typing_line()
		else:
			_advance()
	elif is_choice_open():
		if event.is_action_pressed("move_left"):
			_select_choice("A")
		elif event.is_action_pressed("move_right"):
			_select_choice("B")

func _process(delta: float) -> void:
	if not active or not typing_active:
		return
	typing_progress += delta * typing_chars_per_sec
	var chars_to_show := clampi(int(typing_progress), 0, current_line_full.length())
	dialogue_label.text = current_line_full.substr(0, chars_to_show)
	sound_timer += delta
	if type_sound and type_sound.stream and sound_timer >= typing_sound_interval:
		if chars_to_show > 0:
			var last_char := current_line_full[chars_to_show - 1]
			if last_char != " " and last_char != "\n":
				type_sound.play()
				sound_timer = 0.0
	if chars_to_show >= current_line_full.length():
		typing_active = false

func _advance() -> void:
	_stop_voiceover()
	if current_index < current_lines.size() - 1:
		current_index += 1
		_start_typing_line(current_lines[current_index])
		return
	_finish_dialogue()

func _finish_dialogue() -> void:
	active = false
	panel.visible = false
	prompt_label.visible = true
	typing_active = false
	_stop_voiceover()
	if character and not external_controls_lock:
		character.set_controls_enabled(true)
	dialogue_finished.emit(current_id)
	if queued.size() > 0:
		var next: Dictionary = queued.pop_front()
		show_dialogue(next["lines"], next["id"], true)

func _start_typing_line(line: String) -> void:
	current_line_full = line
	_start_voiceover_for_line(current_id, current_index, line)
	if typing_enabled:
		typing_active = true
		typing_progress = 0.0
		sound_timer = 0.0
		dialogue_label.text = ""
	else:
		typing_active = false
		dialogue_label.text = line

func show_hover_line(line: String) -> void:
	if active:
		return
	hover_active = true
	panel.visible = true
	prompt_label.visible = false
	typing_active = false
	dialogue_label.text = line

func hide_hover_line() -> void:
	if not hover_active:
		return
	hover_active = false
	panel.visible = false
	prompt_label.visible = true

func set_stop_watching_visible(show: bool) -> void:
	if stop_watching_button:
		stop_watching_button.visible = show

func set_external_controls_lock(locked: bool) -> void:
	# When true, DialogueManager will NOT re-enable player controls on dialogue finish.
	# Used for balcony/window-story flow so mouse cursor stays visible.
	external_controls_lock = locked

func open_choice(choice_a_text: String, choice_b_text: String) -> void:
	if choice_overlay == null:
		return
	choice_left_label.text = choice_a_text
	choice_right_label.text = choice_b_text
	choice_overlay.visible = true
	_set_choice_hover("")

func close_choice() -> void:
	if choice_overlay:
		_set_choice_hover("")
		choice_overlay.visible = false

func is_choice_open() -> bool:
	return choice_overlay != null and choice_overlay.visible

func request_continue() -> void:
	# Used by Balcony window story flow (and for future voice-over behavior).
	if not active:
		return
	if typing_active:
		_finish_typing_line()
	else:
		_advance()

func _on_choice_left_pressed() -> void:
	_select_choice("A")

func _on_choice_right_pressed() -> void:
	_select_choice("B")

func _select_choice(choice: String) -> void:
	close_choice()
	window_choice_made.emit(choice)

func _cache_choice_bases() -> void:
	# Runs deferred so UI layout has computed sizes/positions.
	if choice_left_label:
		choice_left_base_pos = choice_left_label.position
		choice_left_base_scale = choice_left_label.scale
		choice_left_label.pivot_offset = choice_left_label.size * 0.5
	if choice_right_label:
		choice_right_base_pos = choice_right_label.position
		choice_right_base_scale = choice_right_label.scale
		choice_right_label.pivot_offset = choice_right_label.size * 0.5

func _on_choice_left_mouse_entered() -> void:
	_set_choice_hover("A")

func _on_choice_left_mouse_exited() -> void:
	_set_choice_hover("")

func _on_choice_right_mouse_entered() -> void:
	_set_choice_hover("B")

func _on_choice_right_mouse_exited() -> void:
	_set_choice_hover("")

func _set_choice_hover(new_hover: String) -> void:
	if choice_hovered == new_hover:
		return
	choice_hovered = new_hover
	_apply_choice_style("A", choice_hovered == "A")
	_apply_choice_style("B", choice_hovered == "B")

func _apply_choice_style(which: String, hovered_now: bool) -> void:
	var label: Label = choice_left_label if which == "A" else choice_right_label
	if label == null:
		return

	var base_pos: Vector2 = choice_left_base_pos if which == "A" else choice_right_base_pos
	var base_scale: Vector2 = choice_left_base_scale if which == "A" else choice_right_base_scale
	var tilt: float = -0.08 if which == "A" else 0.08

	var style_tween: Tween = choice_left_style_tween if which == "A" else choice_right_style_tween
	if style_tween:
		style_tween.kill()

	var float_tween: Tween = choice_left_float_tween if which == "A" else choice_right_float_tween
	if float_tween:
		float_tween.kill()

	# Style tween (scale/rotation/brighten + small lift)
	style_tween = get_tree().create_tween()
	style_tween.set_parallel(true)
	if hovered_now:
		style_tween.tween_property(label, "scale", base_scale * 1.25, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		style_tween.tween_property(label, "rotation", tilt, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		style_tween.tween_property(label, "position", base_pos + Vector2(0, -10), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		style_tween.tween_property(label, "self_modulate", Color(1.0, 0.97, 0.88, 1.0), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		style_tween.tween_property(label, "scale", base_scale, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		style_tween.tween_property(label, "rotation", 0.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		style_tween.tween_property(label, "position", base_pos, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		style_tween.tween_property(label, "self_modulate", Color(1, 1, 1, 1), 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Gentle floating loop while hovered.
	if hovered_now:
		float_tween = get_tree().create_tween()
		float_tween.set_loops()
		float_tween.tween_property(label, "position", base_pos + Vector2(0, -12), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		float_tween.tween_property(label, "position", base_pos + Vector2(0, -8), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if which == "A":
		choice_left_style_tween = style_tween
		choice_left_float_tween = float_tween
	else:
		choice_right_style_tween = style_tween
		choice_right_float_tween = float_tween

func _on_stop_watching_pressed() -> void:
	stop_watching_pressed.emit()

# --- Voice-over hooks (stubbed for now) ---
# When you add VO later, implement these to play/stop audio per line/page.
func _start_voiceover_for_line(_dialogue_id: String, _index: int, _text: String) -> void:
	pass

func _stop_voiceover() -> void:
	pass

func _finish_typing_line() -> void:
	typing_active = false
	dialogue_label.text = current_line_full
