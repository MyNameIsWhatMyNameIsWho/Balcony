extends Node

signal fragments_changed(value: int)
signal avoids_changed(value: int)
signal resolved_windows_changed(total: int)

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
	if OS.is_debug_build():
		print("GameState: reset run")
	fragments_changed.emit(fragments)
	avoids_changed.emit(avoids)
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

func resolve_ending() -> Dictionary:
	return ContentDB.find_ending(fragments, avoids)
