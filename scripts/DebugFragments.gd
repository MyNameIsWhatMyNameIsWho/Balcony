extends Label

func _ready() -> void:
	set_process(false)
	GameState.fragments_changed.connect(_on_fragments_changed)
	GameState.exposure_changed.connect(_on_exposure_changed)
	_update_text(GameState.fragments)

func _on_fragments_changed(value: int) -> void:
	_update_text(value)

func _on_exposure_changed(_value: int) -> void:
	_update_text(GameState.fragments)

func _update_text(fragments_value: int) -> void:
	var tier := String(GameState.get_voice_tier())
	text = "Fragments: %d (%s)" % [fragments_value, tier]
