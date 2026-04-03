extends Node

## Assign a rain audio file (.ogg/.mp3) here in the Inspector once you have one.
@export var rain_audio_stream: AudioStream

const FULL_VOLUME_DB   := -10.0
const FADE_IN_DURATION :=  2.5

var _canvas: CanvasLayer
var _rect:   ColorRect
var _audio:  AudioStreamPlayer
var _triggered    := false
var _fade_tween:  Tween
var _audio_tween: Tween

func _ready() -> void:
	# Build the CanvasLayer so rain draws on top of everything.
	_canvas       = CanvasLayer.new()
	_canvas.layer = 10
	add_child(_canvas)

	# Full-screen transparent rect driven by the rain shader.
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a   = 0.0
	var mat  := ShaderMaterial.new()
	mat.shader = load("res://assets/rain.gdshader") as Shader
	_rect.material = mat
	_canvas.add_child(_rect)

	# Rain sound (Foley bus — same as other ambient audio in the project).
	_audio            = AudioStreamPlayer.new()
	_audio.bus        = "Foley"
	_audio.volume_db  = -80.0
	if rain_audio_stream:
		_audio.stream = rain_audio_stream
	add_child(_audio)


## Call this once to start the rain (idempotent — safe to call multiple times).
func trigger_rain() -> void:
	if _triggered:
		return
	_triggered = true

	# Fade in the visual.
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_rect, "modulate:a", 1.0, FADE_IN_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# Start audio and fade it in.
	if _audio.stream:
		_audio.play()
	if _audio_tween:
		_audio_tween.kill()
	_audio_tween = create_tween()
	_audio_tween.tween_property(_audio, "volume_db", FULL_VOLUME_DB, FADE_IN_DURATION)\
		.set_trans(Tween.TRANS_SINE)


## Smoothly move rain audio to target_db over duration seconds.
## Use to dim the rain when the ending / darken screen appears.
func fade_audio(target_db: float, duration: float) -> void:
	if _audio_tween:
		_audio_tween.kill()
	_audio_tween = create_tween()
	_audio_tween.tween_property(_audio, "volume_db", target_db, duration)\
		.set_trans(Tween.TRANS_SINE)


func is_triggered() -> bool:
	return _triggered
