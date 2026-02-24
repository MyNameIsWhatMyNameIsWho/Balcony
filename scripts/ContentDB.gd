extends Node

# windows.json: Array[Dictionary] with window_id -> indexed into this Dictionary
var windows: Dictionary = {} # window_id -> Dictionary

# flat.json: Array[Dictionary] with object_id -> indexed into this Dictionary
var flat: Dictionary = {} # object_id -> Dictionary

# intro.json: Array[String]
var intro_lines: Array[String] = []

# balcony_enter.json: Array[String] (blocks separated by empty lines)
var balcony_enter_lines: Array[String] = []

# endings.json: Array[Dictionary]
var endings: Array[Dictionary] = []
const MAX_FRAGMENTS_ANY := 999999

func _ready() -> void:
	_load_windows()
	_load_flat()
	_load_intro()
	_load_balcony_enter()
	_load_endings()

# NOTE: Godot 4's Node already has get_window() -> Window.
# Defining get_window(window_id) here would produce a "signature doesn't match parent" error.
# Use get_window_data(window_id) instead.
func get_window_data(window_id: String) -> Dictionary:
	if not windows.has(window_id):
		push_warning("ContentDB: missing window_id '%s'" % window_id)
		return {}
	return windows[window_id]

func get_flat(object_id: String) -> Dictionary:
	if not flat.has(object_id):
		push_warning("ContentDB: missing object_id '%s'" % object_id)
		return {}
	return flat[object_id]

func get_intro_lines() -> Array[String]:
	return intro_lines

func get_balcony_enter_lines() -> Array[String]:
	return balcony_enter_lines

func find_ending(fragments: int, avoids: int) -> Dictionary:
	# 1) Avoidance endings first (if avoids + fragments range match)
	for ending_v in endings:
		var ending: Dictionary = ending_v
		var trigger_type := str(ending.get("trigger_type", ""))
		if trigger_type != "avoidance":
			continue
		if not _fragments_in_range(ending, fragments):
			continue
		var min_avoids := int(ending.get("min_avoids", 0))
		if avoids >= min_avoids:
			return ending

	# 2) Otherwise: first fragments-range match (ignore trigger_type)
	for ending_v in endings:
		var ending: Dictionary = ending_v
		if _fragments_in_range(ending, fragments):
			return ending

	return {}

func _fragments_in_range(ending: Dictionary, fragments: int) -> bool:
	var min_fragments := int(ending.get("min_fragments", 0))
	var max_fragments := int(ending.get("max_fragments", MAX_FRAGMENTS_ANY))
	return fragments >= min_fragments and fragments <= max_fragments

func _load_windows() -> void:
	windows.clear()
	var data: Variant = _read_json("res://data/windows.json")
	if typeof(data) != TYPE_ARRAY:
		push_warning("ContentDB: windows.json must be an Array of Dictionaries")
		return

	for entry_v in data:
		if typeof(entry_v) != TYPE_DICTIONARY:
			push_warning("ContentDB: windows.json contains a non-Dictionary entry (skipping)")
			continue
		var entry: Dictionary = entry_v

		if not entry.has("window_id"):
			push_warning("ContentDB: windows.json entry missing required key 'window_id' (skipping)")
			continue

		var window_id := str(entry.get("window_id", "")).strip_edges()
		if window_id == "":
			push_warning("ContentDB: windows.json has empty window_id (skipping)")
			continue

		if windows.has(window_id):
			push_warning("ContentDB: duplicate window_id '%s' (skipping duplicate)" % window_id)
			continue

		# Validation warnings for expected keys used by the game.
		_warn_missing_keys(entry, ["hover_line", "vignette_text"], "window '%s'" % window_id)
		_warn_missing_keys(entry, ["choice_a_text", "choice_b_text"], "window '%s'" % window_id)
		_warn_missing_keys(entry, ["outcome_a_text", "outcome_b_text"], "window '%s'" % window_id)
		_warn_missing_keys(entry, ["reflection_a_text", "reflection_b_text"], "window '%s'" % window_id)
		_warn_missing_keys(entry, ["cover_image"], "window '%s' (cover image)" % window_id)

		if not entry.has("fragment_on_a"):
			push_warning("ContentDB: window '%s' missing key 'fragment_on_a' (will default to false)" % window_id)
		if not entry.has("fragment_on_b"):
			push_warning("ContentDB: window '%s' missing key 'fragment_on_b' (will default to false)" % window_id)
		if bool(entry.get("fragment_on_a", false)) or bool(entry.get("fragment_on_b", false)):
			if not entry.has("memory_fragment_text"):
				push_warning("ContentDB: window '%s' can grant fragment but missing key 'memory_fragment_text'" % window_id)

		windows[window_id] = entry

func _load_flat() -> void:
	flat.clear()
	var data: Variant = _read_json("res://data/flat.json")
	if typeof(data) != TYPE_ARRAY:
		push_warning("ContentDB: flat.json must be an Array of Dictionaries")
		return

	for entry_v in data:
		if typeof(entry_v) != TYPE_DICTIONARY:
			push_warning("ContentDB: flat.json contains a non-Dictionary entry (skipping)")
			continue
		var entry: Dictionary = entry_v

		if not entry.has("object_id"):
			push_warning("ContentDB: flat.json entry missing required key 'object_id' (skipping)")
			continue

		var object_id := str(entry.get("object_id", "")).strip_edges()
		if object_id == "":
			push_warning("ContentDB: flat.json has empty object_id (skipping)")
			continue

		if flat.has(object_id):
			push_warning("ContentDB: duplicate object_id '%s' (skipping duplicate)" % object_id)
			continue

		_warn_missing_keys(entry, ["hint_text", "dialogue_id", "lines"], "flat object '%s'" % object_id)

		var lines_v: Variant = entry.get("lines", null)
		if lines_v != null and typeof(lines_v) != TYPE_ARRAY:
			push_warning("ContentDB: flat object '%s' key 'lines' is not an Array" % object_id)

		flat[object_id] = entry

func _load_intro() -> void:
	intro_lines.clear()
	var data: Variant = _read_json("res://data/intro.json")
	if typeof(data) != TYPE_ARRAY:
		push_warning("ContentDB: intro.json must be an Array of Strings")
		return
	for line in data:
		intro_lines.append(str(line))

func _load_balcony_enter() -> void:
	balcony_enter_lines.clear()
	var data: Variant = _read_json("res://data/balcony_enter.json")
	if data == null:
		# Optional file.
		return
	if typeof(data) != TYPE_ARRAY:
		push_warning("ContentDB: balcony_enter.json must be an Array of Strings")
		return
	for line in data:
		balcony_enter_lines.append(str(line))

func _load_endings() -> void:
	endings.clear()
	var data: Variant = _read_json("res://data/endings.json")
	if typeof(data) != TYPE_ARRAY:
		push_warning("ContentDB: endings.json must be an Array of Dictionaries")
		return

	for entry_v in data:
		if typeof(entry_v) != TYPE_DICTIONARY:
			push_warning("ContentDB: endings.json contains a non-Dictionary entry (skipping)")
			continue
		var entry: Dictionary = entry_v

		_warn_missing_keys(entry, ["ending_id", "min_fragments", "max_fragments", "lines"], "ending entry")

		var trigger_type := str(entry.get("trigger_type", ""))
		if trigger_type == "avoidance" and not entry.has("min_avoids"):
			push_warning("ContentDB: avoidance ending '%s' missing key 'min_avoids' (defaults to 0)" % str(entry.get("ending_id", "")))

		var lines_v: Variant = entry.get("lines", null)
		if lines_v != null and typeof(lines_v) != TYPE_ARRAY:
			push_warning("ContentDB: ending '%s' key 'lines' is not an Array" % str(entry.get("ending_id", "")))

		endings.append(entry)

func _warn_missing_keys(data_dict: Dictionary, keys: Array[String], context: String) -> void:
	for k in keys:
		if not data_dict.has(k):
			push_warning("ContentDB: %s missing key '%s'" % [context, k])

func _read_json(path: String) -> Variant:
	var raw: String = FileAccess.get_file_as_string(path)
	if raw == "":
		push_warning("ContentDB: failed to read %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(raw)
	if parsed == null:
		push_warning("ContentDB: invalid JSON in %s" % path)
		return null
	return parsed
