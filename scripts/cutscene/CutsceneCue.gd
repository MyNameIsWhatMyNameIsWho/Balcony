extends Resource
class_name CutsceneCue

enum CueType {
	PLAY_SFX,
	FADE_OVERLAY,
	SET_SUBTITLE,
	PLAY_INTRO_FROM_CONTENTDB,
	CALL_METHOD,
}

@export var time: float = 0.0
@export var type: CueType = CueType.PLAY_SFX

# --- PLAY_SFX ---
@export var audio: AudioStream
@export var bus: StringName = &"Foley"
@export var volume_db: float = 0.0
@export var pitch_scale: float = 1.0

# --- FADE_OVERLAY ---
@export_range(0.0, 1.0, 0.01) var fade_to_alpha: float = 0.0
@export var fade_duration: float = 1.0

# --- SET_SUBTITLE ---
@export_multiline var subtitle_text: String = ""

# --- PLAY_INTRO_FROM_CONTENTDB ---
# Uses `ContentDB.get_intro_lines()` (blocks separated by empty line).
@export var intro_chars_per_sec: float = 18.0
@export var intro_min_seconds: float = 2.2
@export var intro_max_seconds: float = 10.0

# --- CALL_METHOD ---
# Calls a method on a target node (relative to CutscenePlayer).
@export var call_target_path: NodePath
@export var call_method: StringName = &""
@export var call_arg: String = ""

