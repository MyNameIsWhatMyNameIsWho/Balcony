extends Node

signal fragments_changed(value: int)
signal avoids_changed(value: int)
signal resolved_windows_changed(total: int)
signal exposure_changed(value: int)
signal distortion_changed(value: int)

var fragments: int = 0
var avoids: int = 0
var exposure: int = 0
var distortion: int = 0
var resolved_windows: Dictionary = {}
var fragment_windows: Dictionary = {}

func _ready() -> void:
	reset_run()

func reset_run() -> void:
	fragments = 0
	avoids = 0
	exposure = 0
	distortion = 0
	resolved_windows.clear()
	fragment_windows.clear()
	if OS.is_debug_build():
		print("GameState: reset run")
	fragments_changed.emit(fragments)
	avoids_changed.emit(avoids)
	exposure_changed.emit(exposure)
	distortion_changed.emit(distortion)
	resolved_windows_changed.emit(resolved_windows.size())

func is_resolved(window_id: String) -> bool:
	return resolved_windows.has(window_id)

func mark_resolved(window_id: String) -> void:
	if window_id == "":
		push_warning("GameState: window_id is empty")
		return
	resolved_windows[window_id] = true
	resolved_windows_changed.emit(resolved_windows.size())

func add_fragment_once(window_id: String) -> void:
	if window_id == "":
		push_warning("GameState: window_id is empty")
		return
	if fragment_windows.has(window_id):
		return
	fragment_windows[window_id] = true
	fragments += 1
	fragments_changed.emit(fragments)

func add_avoid() -> void:
	avoids += 1
	avoids_changed.emit(avoids)

func add_exposure(amount: int = 1) -> void:
	exposure = maxi(0, exposure + amount)
	exposure_changed.emit(exposure)

func add_distortion(amount: int = 1) -> void:
	distortion = maxi(0, distortion + amount)
	distortion_changed.emit(distortion)

func get_voice_tier() -> StringName:
	# Tiering for text tone (minimal and easy to tune).
	# 0–1: numb, 2–4: grounded, 5+: raw
	if exposure <= 1:
		return &"numb"
	if exposure <= 4:
		return &"grounded"
	return &"raw"

func get_insight_score() -> int:
	# Effective fragments used for endings: fragments minus distortion penalty.
	# Clamp to keep ending logic stable.
	var score := fragments - int(floor(float(distortion) / 2.0))
	return maxi(0, score)

func resolve_ending() -> Dictionary:
	return ContentDB.find_ending(get_insight_score(), avoids)
