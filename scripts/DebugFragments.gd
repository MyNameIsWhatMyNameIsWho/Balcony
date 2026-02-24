extends Label

func _ready() -> void:
	if GameState and GameState.has_signal("fragments_changed"):
		GameState.fragments_changed.connect(_on_fragments_changed)
	if GameState and GameState.has_signal("exposure_changed"):
		GameState.exposure_changed.connect(_on_exposure_changed)
		set_process(false)
	_on_fragments_changed(GameState.fragments)

func _on_fragments_changed(value: int) -> void:
	_update_text(value)

func _on_exposure_changed(_value: int) -> void:
	_update_text(GameState.fragments)

func _update_text(fragments_value: int) -> void:
	var tier := "?"
	if GameState and GameState.has_method("get_voice_tier"):
		tier = String(GameState.get_voice_tier())
	text = "Fragments: %d (%s)" % [fragments_value, tier]

func _process(_delta: float) -> void:
	# Backward-compatible fallback if the signal is unavailable.
	_update_text(GameState.fragments)
