extends Label

func _ready() -> void:
	if GameState and GameState.has_signal("fragments_changed"):
		GameState.fragments_changed.connect(_on_fragments_changed)
		set_process(false)
	_on_fragments_changed(GameState.fragments)

func _on_fragments_changed(value: int) -> void:
	text = "Fragments: %d" % value

func _process(_delta: float) -> void:
	# Backward-compatible fallback if the signal is unavailable.
	text = "Fragments: %d" % GameState.fragments
