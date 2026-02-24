extends Area3D

@export var dialogue_manager_path: NodePath
@export var object_id: String = ""
@export var dialogue_lines: Array[String] = []
@export var followup_lines: Array[String] = []
@export var trigger_once: bool = true
@export var interact_action: String = "interact"
@export var hint_text: String = "Press E"
@export var require_look: bool = true
@export var look_angle_deg: float = 25.0
@export var max_hint_distance: float = 4.0
@export var look_offset: Vector3 = Vector3.ZERO
@export var lines_per_page: int = 2

var player_inside := false
var used := false
var dialogue_id: String = ""
var _hint_visible := false

@onready var dialogue_manager := get_node_or_null(dialogue_manager_path)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var config: Dictionary = ContentDB.get_flat(object_id)
	if config.size() > 0:
		hint_text = str(config.get("hint_text", hint_text))
		var raw_lines: Variant = config.get("lines", [])
		if typeof(raw_lines) == TYPE_ARRAY:
			var typed_lines: Array[String] = []
			for line in raw_lines:
				typed_lines.append(str(line))
			dialogue_lines = typed_lines
		dialogue_id = str(config.get("dialogue_id", name))
	else:
		dialogue_id = name

func _process(_delta: float) -> void:
	if used and trigger_once:
		_hide_hint()
		return
	if not player_inside:
		_hide_hint()
		return
	if dialogue_manager == null:
		_hide_hint()
		return
	if dialogue_manager.is_active():
		_hide_hint()
		return
	if require_look and not _is_looked_at():
		_hide_hint()
		return
	_show_hint()
	if Input.is_action_just_pressed(interact_action):
		_hide_hint()
		dialogue_manager.show_dialogue(_page_lines(dialogue_lines), dialogue_id, true)
		if followup_lines.size() > 0:
			dialogue_manager.queue_dialogue(_page_lines(followup_lines), name + "_followup")
		used = true

func _show_hint() -> void:
	if dialogue_manager == null:
		return
	if _hint_visible:
		return
	dialogue_manager.set_interact_hint(true, hint_text)
	_hint_visible = true

func _hide_hint() -> void:
	if dialogue_manager == null:
		_hint_visible = false
		return
	if not _hint_visible:
		return
	dialogue_manager.set_interact_hint(false)
	_hint_visible = false

func _page_lines(lines: Array[String]) -> Array[String]:
	# If the author inserted empty lines, treat them as explicit page breaks.
	var has_explicit_breaks := false
	for l in lines:
		if l.strip_edges() == "":
			has_explicit_breaks = true
			break
	if has_explicit_breaks:
		var pages: Array[String] = []
		var buffer: Array[String] = []
		for l in lines:
			if l.strip_edges() == "":
				if buffer.size() > 0:
					pages.append("\n".join(buffer))
					buffer.clear()
				continue
			buffer.append(l)
		if buffer.size() > 0:
			pages.append("\n".join(buffer))
		return pages

	# Otherwise, bundle N lines per page.
	var n := maxi(1, lines_per_page)
	var pages: Array[String] = []
	var i := 0
	while i < lines.size():
		var chunk := lines.slice(i, min(i + n, lines.size()))
		pages.append("\n".join(chunk))
		i += n
	return pages

func _on_body_entered(body: Node) -> void:
	if body is CharacterBody3D:
		player_inside = true

func _on_body_exited(body: Node) -> void:
	if body is CharacterBody3D:
		player_inside = false

func _is_looked_at() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var cam_pos := camera.global_transform.origin
	var target_pos := _get_look_target_position()
	if cam_pos.distance_to(target_pos) > max_hint_distance:
		return false
	var forward := -camera.global_transform.basis.z
	var to_target := (target_pos - cam_pos).normalized()
	var cos_limit := cos(deg_to_rad(look_angle_deg))
	return forward.dot(to_target) >= cos_limit

func _get_look_target_position() -> Vector3:
	# Prefer mesh center if this Area is a child of a MeshInstance3D.
	var parent_mesh := get_parent()
	if parent_mesh is MeshInstance3D and parent_mesh.mesh:
		var aabb: AABB = parent_mesh.mesh.get_aabb()
		var local_center: Vector3 = aabb.position + aabb.size * 0.5
		return parent_mesh.global_transform * local_center
	return global_transform.origin + (global_transform.basis * look_offset)
