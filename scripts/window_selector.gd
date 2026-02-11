extends Node

signal window_selected(window: Area3D)
signal window_hovered(window: Area3D)
signal window_unhovered(window: Area3D)
signal selection_cancelled

@export var camera_path: NodePath
@export var highlight_material: Material
@export var window_collision_mask := 1 << 1

var enabled := false
var current_window: Area3D
var windows: Array[Node] = []
var original_materials := {}

@onready var camera: Camera3D = get_node(camera_path)
@onready var storyscreen_shader: Shader = preload("res://assets/storyscreen_pixelate.gdshader")

func _ready() -> void:
 windows = get_tree().get_nodes_in_group("selectable_window")

func set_enabled(value: bool) -> void:
 enabled = value
 if not enabled:
  _set_highlight(null)

func _process(_delta: float) -> void:
 if not enabled:
  return
 if Input.is_action_just_pressed("ui_cancel"):
  selection_cancelled.emit()
  return
 _update_hover()

func _unhandled_input(event: InputEvent) -> void:
 if not enabled:
  return
 if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
  if current_window:
   window_selected.emit(current_window)

func _update_hover() -> void:
 var viewport := get_viewport()
 var mouse_pos := viewport.get_mouse_position()
 var ray_origin := camera.project_ray_origin(mouse_pos)
 var ray_dir := camera.project_ray_normal(mouse_pos)
 var ray_end := ray_origin + ray_dir * 200.0
 var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
 query.collide_with_areas = true
 query.collide_with_bodies = false
 query.collision_mask = window_collision_mask
 var result := camera.get_world_3d().direct_space_state.intersect_ray(query)
 var hit_area: Area3D = result.get("collider") if result.has("collider") else null
 if hit_area != current_window:
  _set_highlight(hit_area)

func _set_highlight(target: Area3D) -> void:
 if current_window:
  var prev_mesh := current_window.get_node("WindowMesh") as MeshInstance3D
  if original_materials.has(current_window):
   prev_mesh.material_override = original_materials[current_window]
  _set_storyscreen_hover(current_window, false)
  window_unhovered.emit(current_window)
 current_window = target
 if current_window and highlight_material:
  var mesh := current_window.get_node("WindowMesh") as MeshInstance3D
  if not original_materials.has(current_window):
   original_materials[current_window] = mesh.material_override
  mesh.material_override = highlight_material
  _set_storyscreen_hover(current_window, true)
  window_hovered.emit(current_window)

func _set_storyscreen_hover(window: Area3D, hovered: bool) -> void:
 if window == null:
  return
 var screen := window.get_node_or_null("StoryScreen") as MeshInstance3D
 if screen == null:
  return
 var mat := screen.material_override as ShaderMaterial
 if mat == null:
  return
 if mat.shader != storyscreen_shader:
  return
 mat.set_shader_parameter("hover", 1.0 if hovered else 0.0)
