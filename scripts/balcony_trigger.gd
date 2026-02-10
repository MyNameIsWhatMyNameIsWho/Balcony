extends Area3D

@export var character_path: NodePath
@export var window_selector_path: NodePath
@export var building_camera_path: NodePath
@export var dialogue_manager_path: NodePath
@export var ending_ui_path: NodePath
@export var zoom_distance: float = 0.5
@export var zoom_duration: float = 0.9
@export var focus_duration: float = 0.6
@export var return_duration: float = 0.6
@export var balcony_breathe_amplitude: float = 0.04
@export var balcony_breathe_speed: float = 0.25
@export var selection_pan_max: Vector2 = Vector2(0.8, 0.35)
@export var selection_pan_deadzone: float = 0.04
@export var selection_pan_curve: float = 1.6
@export var selection_pan_smoothing: float = 7.0 # X smoothing
@export var selection_pan_smoothing_y: float = 4.0 # Y smoothing (slower feels more "floaty")

# Pixelization override while selecting windows (PostProcess/Pixelize shader).
@export var pixelize_rect_path: NodePath = NodePath("../PostProcess/Pixelize")
@export var pixel_size_in_selection: float = 28.0

var in_area := false
var selection_active := false
var window_focus_active := false
var cooldown := false

@onready var character := get_node(character_path)
@onready var window_selector := get_node(window_selector_path)
@onready var building_camera: Camera3D = get_node_or_null(building_camera_path) as Camera3D
@onready var dialogue_manager := get_node_or_null(dialogue_manager_path)
@onready var ending_ui := get_node_or_null(ending_ui_path)
@onready var pixelize_rect: ColorRect = get_node_or_null(pixelize_rect_path) as ColorRect

var previous_camera: Camera3D = null
var camera_start_transform: Transform3D
var zoom_tween: Tween = null
var focus_tween: Tween = null
var has_building_camera_home := false
var focus_in_progress := false
var zoom_in_progress := false
var balcony_breathe_time := 0.0
var building_camera_breathe_base: Transform3D
var has_breathe_base := false
var selection_pan: Vector2 = Vector2.ZERO
var pixelize_original_pixel_size: float = -1.0
var pixelize_override_active := false

var story_window_id: String = ""
var story_choice: String = ""
var story_gained_fragment := false
var story_data: Dictionary = {}

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	window_selector.window_selected.connect(_on_window_selected)
	window_selector.window_hovered.connect(_on_window_hovered)
	window_selector.window_unhovered.connect(_on_window_unhovered)
	window_selector.selection_cancelled.connect(_on_selection_cancelled)

	if dialogue_manager and dialogue_manager.has_signal("stop_watching_pressed"):
		dialogue_manager.stop_watching_pressed.connect(_on_stop_watching_pressed)
	if dialogue_manager and dialogue_manager.has_signal("dialogue_finished"):
		dialogue_manager.dialogue_finished.connect(_on_dialogue_finished)
	if dialogue_manager and dialogue_manager.has_signal("window_choice_made"):
		dialogue_manager.window_choice_made.connect(_on_window_choice_made)

	if building_camera_path == NodePath("") or building_camera == null:
		push_warning("BalconyTrigger: building_camera_path is not set or invalid.")

	_cache_pixelize_original()
	_hide_all_story_screens()

func _cache_pixelize_original() -> void:
	if pixelize_rect == null:
		return
	var mat := pixelize_rect.material as ShaderMaterial
	if mat == null:
		return
	var v: Variant = mat.get_shader_parameter("pixel_size")
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		pixelize_original_pixel_size = float(v)

func _set_pixelize_override(active_now: bool) -> void:
	if pixelize_rect == null:
		return
	var mat := pixelize_rect.material as ShaderMaterial
	if mat == null:
		return

	# Capture original lazily if needed.
	if pixelize_original_pixel_size < 0.0:
		_cache_pixelize_original()

	if active_now:
		pixelize_override_active = true
		if pixel_size_in_selection > 0.0:
			mat.set_shader_parameter("pixel_size", pixel_size_in_selection)
	else:
		if not pixelize_override_active:
			return
		pixelize_override_active = false
		if pixelize_original_pixel_size > 0.0:
			mat.set_shader_parameter("pixel_size", pixelize_original_pixel_size)

func _on_body_entered(body: Node) -> void:
	if body != character:
		return
	in_area = true
	if cooldown or selection_active:
		return
	_activate_selection()

func _on_body_exited(body: Node) -> void:
	if body != character:
		return
	in_area = false
	cooldown = false

func _activate_selection() -> void:
	selection_active = true
	window_focus_active = false
	character.set_controls_enabled(false)
	_set_pixelize_override(true)
	if dialogue_manager and dialogue_manager.has_method("set_external_controls_lock"):
		dialogue_manager.set_external_controls_lock(true)
	_focus_camera()
	window_selector.set_enabled(true)
	_update_stop_watching_visibility()

func _deactivate_selection() -> void:
	selection_active = false
	window_selector.set_enabled(false)
	_hide_hover_text()
	_hide_all_story_screens()
	_set_pixelize_override(false)
	_restore_camera()
	if dialogue_manager and dialogue_manager.has_method("set_external_controls_lock"):
		dialogue_manager.set_external_controls_lock(false)
	character.set_controls_enabled(true)
	cooldown = in_area

	if dialogue_manager and dialogue_manager.has_method("set_stop_watching_visible"):
		dialogue_manager.set_stop_watching_visible(false)

func _focus_camera() -> void:
	if building_camera == null:
		return

	# Capture authored "home" transform once.
	if not has_building_camera_home:
		camera_start_transform = building_camera.global_transform
		has_building_camera_home = true

	var current_cam: Camera3D = get_viewport().get_camera_3d()

	# If we're already on building camera, do not recapture previous camera.
	if current_cam == building_camera:
		return

	# Capture the previous (player) camera only once per balcony session.
	if previous_camera == null and current_cam != null:
		previous_camera = current_cam

	# Start transition from current camera pose into authored home pose.
	if current_cam:
		building_camera.global_transform = current_cam.global_transform

	building_camera.make_current()

	if focus_tween:
		focus_tween.kill()

	focus_tween = get_tree().create_tween()
	focus_in_progress = true
	focus_tween.tween_property(building_camera, "global_transform", camera_start_transform, focus_duration)
	focus_tween.finished.connect(_on_focus_arrived, Object.CONNECT_ONE_SHOT)

func _on_focus_arrived() -> void:
	focus_in_progress = false
	_set_breathe_base(camera_start_transform)

func _set_breathe_base(t: Transform3D) -> void:
	building_camera_breathe_base = t
	has_breathe_base = true
	balcony_breathe_time = 0.0

func _restore_camera() -> void:
	if focus_tween:
		focus_tween.kill()
	if zoom_tween:
		zoom_tween.kill()
	focus_in_progress = false
	zoom_in_progress = false

	# Put building camera back to its authored transform.
	if building_camera and has_building_camera_home:
		building_camera.global_transform = camera_start_transform

	# Restore previous camera if valid.
	if previous_camera and is_instance_valid(previous_camera):
		previous_camera.make_current()

	previous_camera = null

func _on_window_selected(window: Area3D) -> void:
	var window_id := _get_window_id(window)
	if window_id == "":
		return

	if GameState.is_resolved(window_id):
		return

	selection_active = false
	window_focus_active = true
	window_selector.set_enabled(false)
	_hide_hover_text()
	selection_pan = Vector2.ZERO

	if dialogue_manager and dialogue_manager.has_method("set_stop_watching_visible"):
		dialogue_manager.set_stop_watching_visible(false)
	if dialogue_manager and dialogue_manager.has_method("close_choice"):
		dialogue_manager.close_choice()

	_show_story_screen(window)

	story_window_id = window_id
	story_choice = ""
	story_gained_fragment = false

	# Use your ContentDB API name here.
	story_data = ContentDB.get_window_data(window_id)

	_ease_to_window_camera(window)
	_start_story_after_camera(window_id)

func _on_selection_cancelled() -> void:
	_deactivate_selection()

func _on_window_hovered(window: Area3D) -> void:
	if window_focus_active or not selection_active:
		return
	_show_hover_text(window)

func _on_window_unhovered(_window: Area3D) -> void:
	if window_focus_active:
		return
	_hide_hover_text()

func _show_hover_text(window: Area3D) -> void:
	if dialogue_manager == null:
		return

	var window_id := _get_window_id(window)
	if window_id == "":
		return

	var data: Dictionary = ContentDB.get_window_data(window_id)
	var line_key := "post_hover_line" if GameState.is_resolved(window_id) else "hover_line"
	var line := str(data.get(line_key, "")).strip_edges()
	if line == "":
		return

	dialogue_manager.show_hover_line(line)

func _hide_hover_text() -> void:
	if dialogue_manager:
		dialogue_manager.hide_hover_line()

func _input(event: InputEvent) -> void:
	if not window_focus_active:
		return

	if event.is_action_pressed("ui_cancel"):
		# If we're inside the window story flow:
		if dialogue_manager:
			if dialogue_manager.has_method("is_choice_open") and dialogue_manager.is_choice_open():
				_cancel_window_story()
				return
			if dialogue_manager.has_method("is_active") and dialogue_manager.is_active():
				if dialogue_manager.has_method("request_continue"):
					dialogue_manager.request_continue()
				return

		# If camera is tweening in, cancel back to selection.
		if zoom_tween:
			_cancel_window_story()
			return

		window_focus_active = false
		_deactivate_selection()

func _ease_to_window_camera(window: Area3D) -> void:
	if building_camera == null:
		return

	if zoom_tween:
		zoom_tween.kill()

	# Optional per-window authored camera target (if you use it).
	var target_camera: Camera3D = null
	var cam_path: NodePath = NodePath("")

	if window != null:
		cam_path = window.get("window_camera_path")

	if cam_path != NodePath(""):
		target_camera = window.get_node_or_null(cam_path) as Camera3D
		if target_camera == null:
			target_camera = get_node_or_null(cam_path) as Camera3D

	if target_camera:
		zoom_tween = get_tree().create_tween()
		zoom_in_progress = true
		zoom_tween.tween_property(building_camera, "global_transform", target_camera.global_transform, zoom_duration)
		zoom_tween.finished.connect(Callable(self, "_on_zoom_arrived").bind(target_camera.global_transform), Object.CONNECT_ONE_SHOT)
		return

	# Fallback: computed zoom towards window.
	var window_pos := window.global_transform.origin
	var dir := (building_camera.global_transform.origin - window_pos).normalized()
	var target_pos := window_pos + dir * zoom_distance
	var target_transform := building_camera.global_transform.looking_at(window_pos, Vector3.UP)
	target_transform.origin = target_pos

	zoom_tween = get_tree().create_tween()
	zoom_in_progress = true
	zoom_tween.tween_property(building_camera, "global_transform", target_transform, zoom_duration)
	zoom_tween.finished.connect(Callable(self, "_on_zoom_arrived").bind(target_transform), Object.CONNECT_ONE_SHOT)

func _on_zoom_arrived(target_t: Transform3D) -> void:
	zoom_in_progress = false
	selection_pan = Vector2.ZERO
	_set_breathe_base(target_t)

func _process(delta: float) -> void:
	if building_camera == null:
		return
	if get_viewport().get_camera_3d() != building_camera:
		return
	if not in_area:
		return
	if focus_in_progress or zoom_in_progress:
		return
	if not has_breathe_base:
		_set_breathe_base(building_camera.global_transform)
	balcony_breathe_time += delta
	var breathe_offset: float = sin(balcony_breathe_time * TAU * balcony_breathe_speed) * balcony_breathe_amplitude

	# Mouse-follow "screen floating" during window selection only.
	var target_pan := Vector2.ZERO
	if selection_active and not window_focus_active:
		var vp := get_viewport()
		var size := vp.get_visible_rect().size
		if size.x > 1.0 and size.y > 1.0:
			var m := vp.get_mouse_position()
			var nx := (m.x / size.x) * 2.0 - 1.0
			var ny := -((m.y / size.y) * 2.0 - 1.0) # top = +1
			nx = _apply_deadzone(nx, selection_pan_deadzone)
			ny = _apply_deadzone(ny, selection_pan_deadzone)
			nx = _apply_curve(nx, selection_pan_curve)
			ny = _apply_curve(ny, selection_pan_curve)
			target_pan = Vector2(nx * selection_pan_max.x, ny * selection_pan_max.y)

		# Smooth pan so it feels cinematic, not snappy.
		var alpha_x := clampf(selection_pan_smoothing * delta, 0.0, 1.0)
		var alpha_y := clampf(selection_pan_smoothing_y * delta, 0.0, 1.0)
		selection_pan.x = lerpf(selection_pan.x, target_pan.x, alpha_x)
		selection_pan.y = lerpf(selection_pan.y, target_pan.y, alpha_y)
	else:
		# Relax back to center when not selecting.
		var alpha_x := clampf(selection_pan_smoothing * delta, 0.0, 1.0)
		var alpha_y := clampf(selection_pan_smoothing_y * delta, 0.0, 1.0)
		selection_pan.x = lerpf(selection_pan.x, 0.0, alpha_x)
		selection_pan.y = lerpf(selection_pan.y, 0.0, alpha_y)

	var t := building_camera_breathe_base
	t.origin = building_camera_breathe_base.origin \
		+ (building_camera_breathe_base.basis.x * selection_pan.x) \
		+ (building_camera_breathe_base.basis.y * (selection_pan.y + breathe_offset))
	building_camera.global_transform = t

func _apply_deadzone(v: float, dz: float) -> float:
	var d := clampf(dz, 0.0, 0.95)
	var av := absf(v)
	if av <= d:
		return 0.0
	var t := (av - d) / (1.0 - d)
	return signf(v) * clampf(t, 0.0, 1.0)

func _apply_curve(v: float, curve: float) -> float:
	# curve > 1.0 => softer near center, still reaches edges.
	var c := maxf(curve, 1.0)
	return signf(v) * pow(absf(v), c)

func _start_story_after_camera(window_id: String) -> void:
	if dialogue_manager == null:
		return

	# If tween exists, wait until it's finished, then open story (one-shot).
	if zoom_tween:
		var cb := Callable(self, "_on_camera_arrived").bind(window_id)
		zoom_tween.finished.connect(cb, Object.CONNECT_ONE_SHOT)
	else:
		_on_camera_arrived(window_id)

func _on_camera_arrived(window_id: String) -> void:
	if not window_focus_active:
		return
	if story_window_id != window_id:
		return

	var vignette_text := str(story_data.get("vignette_text", "")).strip_edges()
	if vignette_text == "":
		vignette_text = "..."

	var vignette_lines: Array[String] = [vignette_text]
	dialogue_manager.show_dialogue(vignette_lines, "window_vignette:" + window_id, true)

func _on_dialogue_finished(dialogue_id: String) -> void:
	if story_window_id == "":
		return

	if dialogue_id == "window_vignette:" + story_window_id:
		if dialogue_manager and dialogue_manager.has_method("open_choice"):
			var a_text := str(story_data.get("choice_a_text", "Engage"))
			var b_text := str(story_data.get("choice_b_text", "Look away"))
			dialogue_manager.open_choice(a_text, b_text)
		return

	if dialogue_id == "window_outcome:" + story_window_id:
		_resolve_window_and_return()

func _on_window_choice_made(choice: String) -> void:
	if story_window_id == "":
		return

	story_choice = choice
	story_gained_fragment = (bool(story_data.get("fragment_on_a", false)) if choice == "A" else bool(story_data.get("fragment_on_b", false)))

	var outcome := str(story_data.get("outcome_a_text", "")) if choice == "A" else str(story_data.get("outcome_b_text", ""))
	var result := ""

	if story_gained_fragment:
		result = str(story_data.get("memory_fragment_text", ""))
	else:
		result = str(story_data.get("reflection_a_text", "")) if choice == "A" else str(story_data.get("reflection_b_text", ""))

	var outcome_lines: Array[String] = [outcome, result]
	dialogue_manager.show_dialogue(outcome_lines, "window_outcome:" + story_window_id, true)

func _cancel_window_story() -> void:
	story_window_id = ""
	story_choice = ""
	story_gained_fragment = false
	story_data = {}

	if dialogue_manager and dialogue_manager.has_method("close_choice"):
		dialogue_manager.close_choice()

	_update_stop_watching_visibility()
	_return_to_selection()

func _resolve_window_and_return() -> void:
	if story_window_id != "":
		GameState.mark_resolved(story_window_id)
		if story_gained_fragment:
			GameState.add_fragment_once(story_window_id)
		if story_choice == "B":
			GameState.add_avoid()

	story_window_id = ""
	story_choice = ""
	story_gained_fragment = false
	story_data = {}

	_update_stop_watching_visibility()
	_return_to_selection()

func _on_stop_watching_pressed() -> void:
	if ending_ui:
		window_selector.set_enabled(false)
		_hide_hover_text()
		if dialogue_manager and dialogue_manager.has_method("set_stop_watching_visible"):
			dialogue_manager.set_stop_watching_visible(false)
		ending_ui.open()

func _update_stop_watching_visibility() -> void:
	if dialogue_manager == null or not dialogue_manager.has_method("set_stop_watching_visible"):
		return

	if not selection_active or window_focus_active:
		dialogue_manager.set_stop_watching_visible(false)
		return

	# Count total windows. ContentDB exposes `windows` (Dictionary keyed by window_id).
	# Fall back to counting scene windows if something is off.
	var total: int = 0
	if ContentDB != null and "windows" in ContentDB:
		var w: Variant = ContentDB.windows
		if typeof(w) == TYPE_DICTIONARY:
			total = (w as Dictionary).size()
	if total <= 0:
		total = get_tree().get_nodes_in_group("selectable_window").size()

	if total <= 0:
		dialogue_manager.set_stop_watching_visible(false)
		return

	var resolved: int = GameState.resolved_windows.size()
	dialogue_manager.set_stop_watching_visible(resolved >= total)

func _return_to_selection() -> void:
	window_focus_active = false
	selection_active = false
	window_selector.set_enabled(false)
	_hide_hover_text()

	if building_camera and has_building_camera_home:
		if zoom_tween:
			zoom_tween.kill()

		zoom_tween = get_tree().create_tween()
		zoom_in_progress = true
		zoom_tween.tween_property(building_camera, "global_transform", camera_start_transform, return_duration)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_IN_OUT)
		zoom_tween.finished.connect(_on_return_arrived, Object.CONNECT_ONE_SHOT)
		return

	_on_return_arrived()

func _on_return_arrived() -> void:
	zoom_in_progress = false
	if building_camera and has_building_camera_home:
		_set_breathe_base(camera_start_transform)

	if in_area:
		_activate_selection()
	else:
		_deactivate_selection()

func _get_window_id(window: Area3D) -> String:
	if window == null:
		return ""
	var v = window.get("window_id")
	if v == null:
		return ""
	var s := str(v).strip_edges()
	if s.to_lower() == "null":
		return ""
	return s

func _show_story_screen(window: Area3D) -> void:
	_hide_all_story_screens()
	var screen := window.get_node_or_null("StoryScreen") as MeshInstance3D
	if screen:
		screen.visible = true

func _hide_all_story_screens() -> void:
	for node in get_tree().get_nodes_in_group("selectable_window"):
		var screen := node.get_node_or_null("StoryScreen") as MeshInstance3D
		if screen:
			screen.visible = false
