extends Node

var fragments: int = 0
var avoids: int = 0
var resolved_windows: Dictionary = {}
var fragment_windows: Dictionary = {}

func _ready() -> void:
	reset_run()

func reset_run() -> void:
	fragments = 0
	avoids = 0
	resolved_windows.clear()
	fragment_windows.clear()
	print("GameState: reset run")

func is_resolved(window_id: String) -> bool:
	return resolved_windows.has(window_id)

func mark_resolved(window_id: String) -> void:
	if window_id == "":
		push_warning("GameState: window_id is empty")
		return
	resolved_windows[window_id] = true

func add_fragment_once(window_id: String) -> void:
	if window_id == "":
		push_warning("GameState: window_id is empty")
		return
	if fragment_windows.has(window_id):
		return
	fragment_windows[window_id] = true
	fragments += 1

func add_avoid() -> void:
	avoids += 1

func resolve_ending() -> Dictionary:
	return ContentDB.find_ending(fragments, avoids)
