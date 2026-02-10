extends CharacterBody3D

@export var speed = 4.0
@export var jump_velocity = 3.5
@export var acceleration = 8.0
@export var deceleration = 10.0
@export var air_control = 0.4
@export var breathe_amplitude = 0.03
@export var breathe_speed = 1.2

var look_sensitivity = ProjectSettings.get_setting("player/look_sensitivity")
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var velocity_y = 0
var controls_enabled = true

@onready var camera:Camera3D = $Camera3D
var camera_base_position: Vector3
var breathe_time := 0.0

func _ready() -> void:
 camera_base_position = camera.position
 Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
 _apply_breathing(delta)
 if not controls_enabled:
  velocity = Vector3.ZERO
  velocity_y = 0.0
  move_and_slide()
  return
 var input_dir: Vector2 = Input.get_vector("move_left","move_right","move_forward","move_backward")
 var local_basis: Basis = global_transform.basis
 var target_velocity: Vector3 = (local_basis.x * input_dir.x + local_basis.z * input_dir.y) * speed
 target_velocity = target_velocity.normalized() * (input_dir.length() * speed)
 var accel: float = acceleration if is_on_floor() else acceleration * air_control
 var deccel: float = deceleration if is_on_floor() else deceleration * air_control
 if input_dir.length() > 0.0:
  velocity.x = move_toward(velocity.x, target_velocity.x, accel * delta)
  velocity.z = move_toward(velocity.z, target_velocity.z, accel * delta)
 else:
  velocity.x = move_toward(velocity.x, 0.0, deccel * delta)
  velocity.z = move_toward(velocity.z, 0.0, deccel * delta)
 if is_on_floor():
  velocity_y = jump_velocity if Input.is_action_just_pressed("jump") else 0.0
 else:
  velocity_y -= gravity * delta
 velocity.y = velocity_y

 move_and_slide()
 if Input.is_action_just_pressed("ui_cancel"):
  Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_VISIBLE

func _input(event):
 if not controls_enabled:
  return
 if event is InputEventMouseMotion:
  rotate_y(-event.relative.x * look_sensitivity)
  camera.rotate_x(-event.relative.y * look_sensitivity)
  camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)

func set_controls_enabled(enabled: bool) -> void:
 controls_enabled = enabled
 if controls_enabled:
  Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
 else:
  Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _apply_breathing(delta: float) -> void:
 breathe_time += delta
 var offset: float = sin(breathe_time * TAU * breathe_speed) * breathe_amplitude
 camera.position = camera_base_position + Vector3(0, offset, 0)
