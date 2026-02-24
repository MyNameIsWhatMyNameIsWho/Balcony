extends Resource
class_name CutsceneSequence

@export var cues: Array[CutsceneCue] = []

# In release, you said “not skippable”. This simply blocks input while active.
@export var block_input: bool = true

# Debug-only skip (helps iteration).
@export var allow_debug_skip: bool = true
@export var debug_skip_action: StringName = &"ui_accept"

