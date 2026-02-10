extends Label

func _process(_delta: float) -> void:
	text = "Fragments: %d" % GameState.fragments
