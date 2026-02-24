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
@export var selection_pan_y_reach: float = 0.5 # normalized Y where we hit max pan (0.5 ~= 1/4 from top/bottom)

# Pixelization override while selecting windows (PostProcess/Pixelize shader).
@export var pixelize_rect_path: NodePath = NodePath("../PostProcess/Pixelize")
@export var pixel_size_in_selection: float = 28.0

# Pixelation for StoryScreen only (building stays at selection pixel size).
@export var storyscreen_pixel_size_during_camera_move: float = 64.0
@export var storyscreen_pixel_size_in_focus: float = 8.0
@export var storyscreen_pixel_pulse_peak_time: float = 0.55 # 0..1, portion of zoom to stay pixelated before clearing

# DEBUG: press E during zoom-in to instantly snap camera to target.
@export var debug_skip_zoom_on_interact: bool = true
# DEBUG: for fast ending iteration, expose Stop Watching immediately on balcony enter.
@export var debug_show_stop_watching_on_enter: bool = true

@export var window_base_texture: Texture2D
# Window cover image shown on StoryScreen during zoom-in.
@export var window_cover_texture: Texture2D
@export var window_seen_texture: Texture2D

# Per-window cover images (loaded from `data/windows.json` via ContentDB key `cover_image`).
# Cache by window_id and by path so we don’t repeatedly load resources.
var _cover_texture_cache: Dictionary = {} # window_id -> Texture2D
var _texture_path_cache: Dictionary = {} # path -> Texture2D


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
var zoom_target_transform: Transform3D
var has_zoom_target := false
var balcony_breathe_time := 0.0
var building_camera_breathe_base: Transform3D
var has_breathe_base := false
var selection_pan: Vector2 = Vector2.ZERO
var pixelize_original_pixel_size: float = -1.0
var pixelize_override_active := false
var pixelize_tween: Tween = null

var story_window_id: String = ""
var story_window_node: Area3D = null
var story_choice: String = ""
var story_gained_fragment := false
var story_fragment_was_available := false
var story_data: Dictionary = {}
var storyscreen_pixel_tween: Tween = null
var last_seen_window_node: Area3D = null

var balcony_intro_active := false
var balcony_intro_done := false
var balcony_focus_done := false

@onready var storyscreen_pixelate_shader: Shader = load("res://assets/storyscreen_pixelate.gdshader") as Shader

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_cover_texture_cache.clear()
	_texture_path_cache.clear()

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
	# Make windows look correct from the start (base/seen textures).
	_prime_story_screens()
	_set_all_story_screens_visible(true)

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

func _tween_pixel_size(from_px: float, to_px: float, duration: float) -> void:
	if pixelize_rect == null:
		return
	var mat := pixelize_rect.material as ShaderMaterial
	if mat == null:
		return
	if pixelize_tween:
		pixelize_tween.kill()
		pixelize_tween = null
	mat.set_shader_parameter("pixel_size", maxf(from_px, 0.0))
	pixelize_tween = get_tree().create_tween()
	pixelize_tween.tween_property(mat, "shader_parameter/pixel_size", maxf(to_px, 0.0), maxf(duration, 0.01))\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)

func _on_body_entered(body: Node) -> void:
	if body != character:
		return
	in_area = true
	if _should_force_stop_watching_visible():
		_set_stop_watching_visible(true)
	if cooldown or selection_active or balcony_intro_active:
		return
	_start_balcony_intro()

func _on_body_exited(body: Node) -> void:
	if body != character:
		return
	in_area = false
	_set_stop_watching_visible(false)
	cooldown = false

func _activate_selection() -> void:
	selection_active = true
	window_focus_active = false
	# Selection mode: movement off, cursor visible.
	character.set_controls_enabled(false, true)
	_set_pixelize_override(true)
	if dialogue_manager and dialogue_manager.has_method("set_external_controls_lock"):
		dialogue_manager.set_external_controls_lock(true)
	_focus_camera()
	window_selector.set_enabled(true)
	_prime_story_screens()
	_set_all_story_screens_visible(true)
	_update_stop_watching_visibility()

func _activate_selection_after_intro() -> void:
	# Same as _activate_selection, but assumes building camera focus already started.
	selection_active = true
	window_focus_active = false
	# Selection mode: movement off, cursor visible.
	character.set_controls_enabled(false, true)
	_set_pixelize_override(true)
	if dialogue_manager and dialogue_manager.has_method("set_external_controls_lock"):
		dialogue_manager.set_external_controls_lock(true)
	window_selector.set_enabled(true)
	_prime_story_screens()
	_set_all_story_screens_visible(true)
	_update_stop_watching_visibility()

func _start_balcony_intro() -> void:
	balcony_intro_active = true
	balcony_intro_done = false
	balcony_focus_done = false

	selection_active = false
	window_focus_active = false
	window_selector.set_enabled(false)
	_hide_hover_text()
	_prime_story_screens()
	_set_all_story_screens_visible(true)

	# Lock movement immediately but keep cursor hidden/captured during intro.
	character.set_controls_enabled(false, false)
	if dialogue_manager and dialogue_manager.has_method("set_external_controls_lock"):
		dialogue_manager.set_external_controls_lock(true)

	# Start camera transition and intro text at the same time.
	_focus_camera()
	_set_pixelize_override(true)
	# Smooth pixelization during focus-in (e.g. 16 -> 8).
	if pixelize_original_pixel_size < 0.0:
		_cache_pixelize_original()
	if pixelize_original_pixel_size > 0.0 and pixel_size_in_selection > 0.0:
		_tween_pixel_size(pixelize_original_pixel_size, pixel_size_in_selection, focus_duration)

	var enter_lines: Array[String] = ContentDB.get_balcony_enter_lines()
	if dialogue_manager and dialogue_manager.has_method("show_blocked_dialogue") and enter_lines.size() > 0:
		dialogue_manager.show_blocked_dialogue(enter_lines, "balcony_enter", false)
	else:
		balcony_intro_done = true
		_maybe_finish_balcony_intro()

func _maybe_finish_balcony_intro() -> void:
	if not balcony_intro_active:
		return
	if not balcony_intro_done:
		return
	if not balcony_focus_done:
		return
	balcony_intro_active = false
	if in_area:
		_activate_selection_after_intro()
	else:
		_deactivate_selection()

func _prime_story_screens() -> void:
	# Assign base picture (and seen picture for resolved windows) up front,
	# so every StoryScreen is ready when it becomes visible.
	if window_base_texture == null and window_cover_texture == null and window_seen_texture == null:
		return
	# From the moment you enter the balcony trigger zone, covers should already feel “unclear”.
	# Keep the same chunky pixel size used during camera movement to avoid a sudden jump on click.
	var in_balcony_mode := in_area or balcony_intro_active or selection_active
	var px := storyscreen_pixel_size_during_camera_move if in_balcony_mode else storyscreen_pixel_size_in_focus
	for node in get_tree().get_nodes_in_group("selectable_window"):
		var w := node as Area3D
		if w == null:
			continue
		var id := _get_window_id(w)
		var tex: Texture2D = null
		if id != "" and GameState.is_resolved(id):
			tex = window_seen_texture
		else:
			# Unresolved windows show their own cover image.
			tex = _get_window_cover_texture(id)
			if tex == null:
				tex = window_base_texture
		if tex != null:
			_apply_story_texture(w, tex)
			_set_storyscreen_pixel_size(w, px)

func _load_texture_cached(path: String) -> Texture2D:
	var p := path.strip_edges()
	if p == "":
		return null
	if _texture_path_cache.has(p):
		return _texture_path_cache[p] as Texture2D
	var res := load(p)
	var tex := res as Texture2D
	if tex == null:
		push_warning("BalconyTrigger: cover_image is not a Texture2D: %s" % p)
	_texture_path_cache[p] = tex
	return tex

func _get_window_cover_texture(window_id: String) -> Texture2D:
	var id := window_id.strip_edges()
	if id != "" and _cover_texture_cache.has(id):
		return _cover_texture_cache[id] as Texture2D

	var tex: Texture2D = null
	if id != "":
		var data: Dictionary = ContentDB.get_window_data(id)
		var path := str(data.get("cover_image", "")).strip_edges()
		if path != "":
			tex = _load_texture_cached(path)

	# Fallbacks (old behavior).
	if tex == null:
		tex = window_cover_texture if window_cover_texture != null else window_base_texture

	if id != "":
		_cover_texture_cache[id] = tex
	return tex

func _set_all_story_screens_visible(show: bool) -> void:
	for node in get_tree().get_nodes_in_group("selectable_window"):
		var w := node as Area3D
		if w == null:
			continue
		var screen := _get_story_screen(w)
		if screen:
			screen.visible = show

func _deactivate_selection() -> void:
	selection_active = false
	window_selector.set_enabled(false)
	_hide_hover_text()
	# Keep windows visible outside of balcony mode too (no sudden pop-in).
	_prime_story_screens()
	_set_all_story_screens_visible(true)
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
	if balcony_intro_active:
		balcony_focus_done = true
		_maybe_finish_balcony_intro()

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
	# Special windows gating (earned discomfort).
	if _is_window_locked(window_id):
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
	# Pixelate StoryScreen gradually while camera is moving in (pulse).
	_start_storyscreen_pixel_pulse(window, zoom_duration)

	story_window_id = window_id
	story_window_node = window
	story_choice = ""
	story_gained_fragment = false
	story_fragment_was_available = false

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
	if _is_window_locked(window_id):
		var locked_line := str(data.get("locked_hover_line", "")).strip_edges()
		if locked_line == "":
			locked_line = "Not yet."
		dialogue_manager.show_hover_line(locked_line)
		return
	var line_key := "post_hover_line" if GameState.is_resolved(window_id) else "hover_line"
	var line := str(data.get(line_key, "")).strip_edges()
	if line == "":
		return

	dialogue_manager.show_hover_line(line)

func _is_window_locked(window_id: String) -> bool:
	# Curtains unlock after you’ve been dodging (avoidance).
	if window_id == "curtains_01":
		return GameState.avoids < 3
	# Noticed unlocks after you’ve stared long enough (exposure).
	if window_id == "noticed_01":
		return GameState.exposure < 3
	return false

func _tiered_text(value: Variant) -> String:
	# Supports either a plain string, or a dict: { "numb": "...", "grounded": "...", "raw": "..." }.
	if typeof(value) == TYPE_DICTIONARY:
		var d: Dictionary = value
		var tier := String(GameState.get_voice_tier())
		var s := str(d.get(tier, "")).strip_edges()
		if s != "":
			return s
		# Fallbacks.
		for k in ["grounded", "numb", "raw"]:
			s = str(d.get(k, "")).strip_edges()
			if s != "":
				return s
		return ""
	return str(value).strip_edges()

func _can_access_fragment_now() -> bool:
	# “Tolerable band” for accessing memory: 2–6.
	# Above that (raw), we still allow it, but tiered text will shift to “raw”.
	return GameState.exposure >= 2

func _hide_hover_text() -> void:
	if dialogue_manager:
		dialogue_manager.hide_hover_line()

func _ease_to_window_camera(window: Area3D) -> void:
	if building_camera == null:
		return

	if zoom_tween:
		zoom_tween.kill()
	has_zoom_target = false

	# Optional per-window authored camera target (if you use it).
	var target_camera: Camera3D = null
	var cam_path := NodePath("")

	if window != null:
		var window_camera_path: Variant = window.get("window_camera_path")
		if typeof(window_camera_path) == TYPE_NODE_PATH:
			cam_path = window_camera_path as NodePath

	if cam_path != NodePath(""):
		target_camera = window.get_node_or_null(cam_path) as Camera3D
		if target_camera == null:
			target_camera = get_node_or_null(cam_path) as Camera3D

	if target_camera:
		zoom_target_transform = target_camera.global_transform
		has_zoom_target = true
		zoom_tween = get_tree().create_tween()
		zoom_in_progress = true
		zoom_tween.tween_property(building_camera, "global_transform", zoom_target_transform, zoom_duration)
		zoom_tween.finished.connect(Callable(self, "_on_zoom_arrived").bind(zoom_target_transform), Object.CONNECT_ONE_SHOT)
		return

	# Fallback: computed zoom towards window.
	var window_pos := window.global_transform.origin
	var dir := (building_camera.global_transform.origin - window_pos).normalized()
	var target_pos := window_pos + dir * zoom_distance
	var target_transform := building_camera.global_transform.looking_at(window_pos, Vector3.UP)
	target_transform.origin = target_pos
	zoom_target_transform = target_transform
	has_zoom_target = true

	zoom_tween = get_tree().create_tween()
	zoom_in_progress = true
	zoom_tween.tween_property(building_camera, "global_transform", zoom_target_transform, zoom_duration)
	zoom_tween.finished.connect(Callable(self, "_on_zoom_arrived").bind(zoom_target_transform), Object.CONNECT_ONE_SHOT)

func _debug_finish_zoom_now() -> void:
	if building_camera == null:
		return
	if not zoom_in_progress:
		return
	if not has_zoom_target:
		return
	if zoom_tween:
		zoom_tween.kill()
		zoom_tween = null
	building_camera.global_transform = zoom_target_transform
	_on_zoom_arrived(zoom_target_transform)
	_on_camera_arrived(story_window_id)
	# Prevent accidental reuse (e.g. during return tween).
	has_zoom_target = false

func _on_zoom_arrived(target_t: Transform3D) -> void:
	zoom_in_progress = false
	selection_pan = Vector2.ZERO
	_set_breathe_base(target_t)
	# Once zoom arrived, show StoryScreen in clearer resolution.
	if storyscreen_pixel_tween:
		storyscreen_pixel_tween.kill()
		storyscreen_pixel_tween = null
	if is_instance_valid(story_window_node):
		_set_storyscreen_pixel_size(story_window_node, storyscreen_pixel_size_in_focus)

func _reset_story_state() -> void:
	story_window_id = ""
	story_window_node = null
	story_choice = ""
	story_gained_fragment = false
	story_data = {}
	if storyscreen_pixel_tween:
		storyscreen_pixel_tween.kill()
		storyscreen_pixel_tween = null

	if dialogue_manager and dialogue_manager.has_method("close_choice"):
		dialogue_manager.close_choice()

func _get_story_screen(window: Area3D) -> MeshInstance3D:
	if window == null:
		return null
	return window.get_node_or_null("StoryScreen") as MeshInstance3D

func _get_or_create_storyscreen_material(screen: MeshInstance3D) -> ShaderMaterial:
	if screen == null or storyscreen_pixelate_shader == null:
		return null
	var existing := screen.material_override as ShaderMaterial
	if existing != null and existing.shader == storyscreen_pixelate_shader:
		return existing
	var mat := ShaderMaterial.new()
	mat.shader = storyscreen_pixelate_shader
	mat.set_shader_parameter("opacity", 1.0)
	mat.set_shader_parameter("pixel_size", storyscreen_pixel_size_in_focus)
	screen.material_override = mat
	return mat

func _set_storyscreen_pixel_size(window: Area3D, px: float) -> void:
	var screen := _get_story_screen(window)
	if screen == null:
		return
	var mat := _get_or_create_storyscreen_material(screen)
	if mat == null:
		return
	mat.set_shader_parameter("pixel_size", maxf(px, 1.0))

func _start_storyscreen_pixel_pulse(window: Area3D, duration: float) -> void:
	# Start chunky immediately, then clear smoothly across the camera tween.
	# Important: pixel_size should start changing immediately (no "hold").
	if storyscreen_pixel_tween:
		storyscreen_pixel_tween.kill()
		storyscreen_pixel_tween = null

	var screen := _get_story_screen(window)
	if screen == null:
		return
	var mat := _get_or_create_storyscreen_material(screen)
	if mat == null:
		return

	var d := maxf(duration, 0.01)
	var peak_t := clampf(storyscreen_pixel_pulse_peak_time, 0.05, 0.95)
	var t_soft := maxf(d * peak_t, 0.01)
	var t_clear := maxf(d - t_soft, 0.01)

	var focus_px := maxf(storyscreen_pixel_size_in_focus, 1.0)
	var peak_px := maxf(storyscreen_pixel_size_during_camera_move, 1.0)
	# Important: make it unclear immediately on click.
	mat.set_shader_parameter("pixel_size", peak_px)

	# First phase: barely starts clearing (still unclear, but changing).
	var mid_px := lerpf(peak_px, focus_px, 0.15)

	storyscreen_pixel_tween = get_tree().create_tween()
	storyscreen_pixel_tween.tween_property(mat, "shader_parameter/pixel_size", mid_px, t_soft)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)
	storyscreen_pixel_tween.tween_property(mat, "shader_parameter/pixel_size", focus_px, t_clear)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)

func _start_storyscreen_pixel_return(window: Area3D, duration: float) -> void:
	# Return tween: crisp -> chunky while camera pulls back.
	if storyscreen_pixel_tween:
		storyscreen_pixel_tween.kill()
		storyscreen_pixel_tween = null

	var screen := _get_story_screen(window)
	if screen == null:
		return
	var mat := _get_or_create_storyscreen_material(screen)
	if mat == null:
		return

	var d := maxf(duration, 0.01)
	var focus_px := maxf(storyscreen_pixel_size_in_focus, 1.0)
	var start_px := maxf(storyscreen_pixel_size_during_camera_move, 1.0)

	mat.set_shader_parameter("pixel_size", focus_px)

	storyscreen_pixel_tween = get_tree().create_tween()
	storyscreen_pixel_tween.tween_property(mat, "shader_parameter/pixel_size", start_px, d)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN)

func _apply_story_texture(window: Area3D, tex: Texture2D) -> void:
	var screen := _get_story_screen(window)
	if screen == null:
		push_warning("BalconyTrigger: No StoryScreen under window: " + str(window.name))
		return
	if tex == null:
		push_warning("BalconyTrigger: story texture is null (assign it in inspector).")
		return

	var mat := _get_or_create_storyscreen_material(screen)
	if mat == null:
		return
	mat.set_shader_parameter("story_tex", tex)
	var sz := tex.get_size()
	if sz.x > 0 and sz.y > 0:
		mat.set_shader_parameter("tex_size", Vector2(float(sz.x), float(sz.y)))

func _process(delta: float) -> void:
	if building_camera == null:
		return
	if get_viewport().get_camera_3d() != building_camera:
		return
	if not in_area:
		return
	# DEBUG: only skip the *zoom-in* (not the return to selection).
	if OS.is_debug_build() and debug_skip_zoom_on_interact and zoom_in_progress and window_focus_active and story_window_id != "" and Input.is_action_just_pressed("interact"):
		_debug_finish_zoom_now()
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
			# Make vertical reach easier: hit max pan earlier, then clamp.
			ny = _apply_reach(ny, selection_pan_y_reach)
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

func _apply_reach(v: float, reach: float) -> float:
	# If reach = 0.5, then v=0.5 maps to 1.0 (max), i.e. you don't need to hit screen edge.
	var r := clampf(reach, 0.05, 1.0)
	return clampf(v / r, -1.0, 1.0)

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
	if balcony_intro_active and dialogue_id == "balcony_enter":
		balcony_intro_done = true
		_maybe_finish_balcony_intro()
		return

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
	# New system:
	# - Exposure increases on Engage (A).
	# - Avoidance increases on Look away (B) (already).
	# - Distortion increases when you Look away (B) while a fragment was available to Engage.
	# - Fragments are “exposure-dependent”: you can only access them once exposure >= 2.

	var fragment_on_a := bool(story_data.get("fragment_on_a", false))
	var fragment_on_b := bool(story_data.get("fragment_on_b", false))

	if choice == "A":
		GameState.add_exposure(1)
	else:
		GameState.add_avoid()

	# Track whether this window *could* offer a fragment if you engaged.
	story_fragment_was_available = fragment_on_a
	if choice == "B" and story_fragment_was_available and _can_access_fragment_now():
		GameState.add_distortion(1)

	var wants_fragment := (fragment_on_a if choice == "A" else fragment_on_b)
	story_gained_fragment = wants_fragment and _can_access_fragment_now()

	var outcome_v: Variant = story_data.get("outcome_a_text", "") if choice == "A" else story_data.get("outcome_b_text", "")
	var outcome := _tiered_text(outcome_v)
	var result := ""

	if story_gained_fragment:
		result = _tiered_text(story_data.get("memory_fragment_text", ""))
	else:
		var refl_v: Variant = story_data.get("reflection_a_text", "") if choice == "A" else story_data.get("reflection_b_text", "")
		result = _tiered_text(refl_v)

	var outcome_lines: Array[String] = [outcome, result]
	dialogue_manager.show_dialogue(outcome_lines, "window_outcome:" + story_window_id, true)

func _cancel_window_story() -> void:
	_reset_story_state()
	_update_stop_watching_visibility()
	_return_to_selection()

func _resolve_window_and_return() -> void:
	if story_window_id != "":
		GameState.mark_resolved(story_window_id)
		if story_gained_fragment:
			GameState.add_fragment_once(story_window_id)

	# Remember which window was just seen so we can swap its StoryScreen on return.
	last_seen_window_node = story_window_node

	_reset_story_state()

	_update_stop_watching_visibility()
	_return_to_selection()

func _on_stop_watching_pressed() -> void:
	if ending_ui:
		_reset_story_state()
		selection_active = false
		window_focus_active = false
		window_selector.set_enabled(false)
		_hide_hover_text()
		character.set_controls_enabled(false, true)
		if dialogue_manager and dialogue_manager.has_method("set_external_controls_lock"):
			dialogue_manager.set_external_controls_lock(false)
		if dialogue_manager and dialogue_manager.has_method("set_stop_watching_visible"):
			dialogue_manager.set_stop_watching_visible(false)
		ending_ui.open()

func _update_stop_watching_visibility() -> void:
	if _should_force_stop_watching_visible():
		_set_stop_watching_visible(in_area and not window_focus_active)
		return
	if dialogue_manager == null or not dialogue_manager.has_method("set_stop_watching_visible"):
		return

	if not selection_active or window_focus_active:
		dialogue_manager.set_stop_watching_visible(false)
		return

	# Show Stop Watching when there are no actionable windows left:
	# i.e. every remaining unresolved window is currently locked by the “special windows” rules.
	# This prevents softlocks where the last remaining windows are gated behind state you can no longer change.
	var actionable := 0
	for node in get_tree().get_nodes_in_group("selectable_window"):
		var w := node as Area3D
		if w == null:
			continue
		var id := _get_window_id(w)
		if id == "":
			continue
		if GameState.is_resolved(id):
			continue
		if _is_window_locked(id):
			continue
		actionable += 1
		if actionable > 0:
			break

	dialogue_manager.set_stop_watching_visible(actionable == 0)

func _should_force_stop_watching_visible() -> bool:
	return OS.is_debug_build() and debug_show_stop_watching_on_enter

func _set_stop_watching_visible(show: bool) -> void:
	if dialogue_manager and dialogue_manager.has_method("set_stop_watching_visible"):
		dialogue_manager.set_stop_watching_visible(show)

func _return_to_selection() -> void:
	window_focus_active = false
	selection_active = false
	window_selector.set_enabled(false)
	_hide_hover_text()
	# Avoid debug "skip zoom" from interfering with the return tween.
	has_zoom_target = false

	# While the camera moves back out, keep other windows showing base/seen
	# (so they don't flash gray).
	_prime_story_screens()
	_set_all_story_screens_visible(true)

	if building_camera and has_building_camera_home:
		# While returning, transition StoryScreen pixels back smoothly (64 -> 8).
		if last_seen_window_node != null:
			# Keep the just-opened window on the cover during the return move.
			var last_id := _get_window_id(last_seen_window_node)
			var cover := _get_window_cover_texture(last_id)
			if cover != null:
				_apply_story_texture(last_seen_window_node, cover)
			_start_storyscreen_pixel_return(last_seen_window_node, return_duration)

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

	# Once we're back in selection, swap the last seen window's StoryScreen image.
	if last_seen_window_node != null and window_seen_texture != null:
		if storyscreen_pixel_tween:
			storyscreen_pixel_tween.kill()
			storyscreen_pixel_tween = null
		_apply_story_texture(last_seen_window_node, window_seen_texture)
		# Back in selection: keep it chunky/unclear like the other windows.
		_set_storyscreen_pixel_size(last_seen_window_node, storyscreen_pixel_size_during_camera_move)
		last_seen_window_node = null

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
	# During zoom-in, keep other windows on base/seen; only the selected window switches to cover.
	_prime_story_screens()
	_set_all_story_screens_visible(true)
	var screen := window.get_node_or_null("StoryScreen") as MeshInstance3D
	if screen:
		screen.visible = true
		var id := _get_window_id(window)
		_apply_story_texture(window, _get_window_cover_texture(id))
