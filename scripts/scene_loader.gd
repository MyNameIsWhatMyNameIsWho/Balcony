extends CanvasLayer

# Minimal async scene loader (threaded).
# Goal: only switch scenes once the next scene resource is fully loaded.

@export var dim_color: Color = Color(0, 0, 0, 0.85)
@export var show_progress: bool = true

var _loading_path: String = ""
var _loading: bool = false

@onready var _root: Control = Control.new()
@onready var _dim: ColorRect = ColorRect.new()
@onready var _vbox: VBoxContainer = VBoxContainer.new()
@onready var _label: Label = Label.new()
@onready var _progress: ProgressBar = ProgressBar.new()

func _ready() -> void:
	# Keep loader updating even if game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 1000

	_build_ui()
	_set_visible(false)
	set_process(false)

func change_scene(path: String) -> void:
	if path.strip_edges() == "":
		push_warning("SceneLoader: change_scene called with empty path")
		return
	if _loading:
		# Ignore spam clicks.
		return

	_loading = true
	_loading_path = path

	_label.text = "Loading…"
	_progress.value = 0
	_progress.visible = show_progress

	_set_visible(true)
	set_process(true)

	var err := ResourceLoader.load_threaded_request(_loading_path)
	if err != OK:
		push_error("SceneLoader: threaded request failed for %s (err=%s)" % [_loading_path, str(err)])
		_fail_and_hide()

func _process(_delta: float) -> void:
	if not _loading:
		return

	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_loading_path, progress)

	if show_progress and progress.size() > 0 and typeof(progress[0]) == TYPE_FLOAT:
		_progress.value = clampf(float(progress[0]) * 100.0, 0.0, 100.0)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		ResourceLoader.THREAD_LOAD_LOADED:
			var res := ResourceLoader.load_threaded_get(_loading_path)
			var packed := res as PackedScene
			if packed == null:
				push_error("SceneLoader: resource is not a PackedScene: %s" % _loading_path)
				_fail_and_hide()
				return

			_loading = false
			_loading_path = ""
			_set_visible(false)
			set_process(false)

			get_tree().change_scene_to_packed(packed)
		ResourceLoader.THREAD_LOAD_FAILED:
			push_error("SceneLoader: threaded load failed for %s" % _loading_path)
			_fail_and_hide()
		_:
			# Unknown / invalid status.
			_fail_and_hide()

func _build_ui() -> void:
	add_child(_root)
	_root.name = "Root"
	_root.anchors_preset = Control.PRESET_FULL_RECT
	_root.mouse_filter = Control.MOUSE_FILTER_STOP

	_dim.name = "Dim"
	_dim.anchors_preset = Control.PRESET_FULL_RECT
	_dim.color = dim_color
	_root.add_child(_dim)

	_vbox.name = "VBox"
	_vbox.anchor_left = 0.5
	_vbox.anchor_top = 0.5
	_vbox.anchor_right = 0.5
	_vbox.anchor_bottom = 0.5
	_vbox.offset_left = -260
	_vbox.offset_top = -60
	_vbox.offset_right = 260
	_vbox.offset_bottom = 60
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_theme_constant_override("separation", 12)
	_root.add_child(_vbox)

	_label.name = "Label"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.text = "Loading…"
	_label.add_theme_font_size_override("font_size", 34)
	_vbox.add_child(_label)

	_progress.name = "Progress"
	_progress.custom_minimum_size = Vector2(0, 18)
	_progress.max_value = 100
	_progress.value = 0
	_vbox.add_child(_progress)

func _set_visible(v: bool) -> void:
	_root.visible = v
	visible = v

func _fail_and_hide() -> void:
	_loading = false
	_loading_path = ""
	_set_visible(false)
	set_process(false)

