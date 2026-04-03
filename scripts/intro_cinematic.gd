extends CanvasLayer

@export var sequence: CutsceneSequence
@export var character_path: NodePath
@export var dialogue_manager_path: NodePath = NodePath("../DialogueUI")

@onready var overlay: ColorRect = $Root/Overlay
@onready var subtitle_label: Label = $Root/Subtitles
@onready var player: CutscenePlayer = $CutscenePlayer

var _character: Node
var _dialogue: Node
var _block_input := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	_character = get_node_or_null(character_path)
	_dialogue = get_node_or_null(dialogue_manager_path)

	# Start fully black.
	if overlay:
		overlay.modulate.a = 1.0
	if subtitle_label:
		subtitle_label.text = ""

	# Lock controls until intro is done.
	_set_character_controls(false)

	player.overlay_path = player.get_path_to(overlay)
	player.subtitle_label_path = player.get_path_to(subtitle_label)
	player.sequence = sequence
	player.finished.connect(_on_finished)
	player.play()

func _unhandled_input(event: InputEvent) -> void:
	# Non-skippable intro: swallow input so gameplay doesn’t respond.
	if _block_input and sequence != null and sequence.block_input:
		get_viewport().set_input_as_handled()

func _on_finished() -> void:
	# Cutscene (sounds/fade) finished. Hand off to DialogueManager for the original intro flow.
	_block_input = false
	if subtitle_label:
		subtitle_label.text = ""

	if _dialogue != null and _dialogue.has_method("play_intro_dialogue"):
		# Wait for the intro dialogue to finish, then release controls.
		if _dialogue.has_signal("dialogue_finished"):
			_dialogue.dialogue_finished.connect(_on_dialogue_finished, CONNECT_ONE_SHOT)
		_dialogue.callv("play_intro_dialogue", [true])
		return

	# Fallback: if dialogue is missing, just end.
	_end_intro()

func _on_dialogue_finished(dialogue_id: String) -> void:
	if dialogue_id != "intro":
		return
	_end_intro()

func _end_intro() -> void:
	_set_character_controls(true)
	visible = false
	queue_free()

func _set_character_controls(enabled: bool) -> void:
	if _character == null:
		return
	if _character.has_method("set_controls_enabled"):
		_character.callv("set_controls_enabled", [enabled])
