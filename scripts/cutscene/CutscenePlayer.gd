extends Node
class_name CutscenePlayer

signal subtitle_changed(text: String)
signal finished

@export var sequence: CutsceneSequence
@export var overlay_path: NodePath
@export var subtitle_label_path: NodePath

# If set, these AudioStreamPlayers are used; otherwise they are created on demand.
@export var sfx_player_path: NodePath
@export var overlap_sfx: bool = true

var _cues_sorted: Array[CutsceneCue] = []
var _elapsed := 0.0
var _cue_index := 0
var _playing := false
var _intro_task_running := false
var _active_tweens := 0

var _overlay: CanvasItem
var _subtitle_label: Label
var _sfx_player: AudioStreamPlayer

func _ready() -> void:
	# Keep cutscenes running regardless of pause/time scale.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_process_unhandled_input(false)

func play(seq: CutsceneSequence = null) -> void:
	if seq != null:
		sequence = seq
	if sequence == null:
		push_warning("CutscenePlayer: no sequence set")
		return

	_resolve_targets()

	_cues_sorted = sequence.cues.duplicate()
	_cues_sorted.sort_custom(func(a: CutsceneCue, b: CutsceneCue) -> bool: return a.time < b.time)

	_elapsed = 0.0
	_cue_index = 0
	_playing = true
	_intro_task_running = false
	_active_tweens = 0
	set_process(true)
	set_process_unhandled_input(true)

func stop() -> void:
	_playing = false
	set_process(false)
	set_process_unhandled_input(false)

func _resolve_targets() -> void:
	# Important: the intro scene sets these NodePaths in its own _ready(),
	# but child nodes’ _ready() runs first. Resolve at play() time.
	_overlay = get_node_or_null(overlay_path) as CanvasItem
	_subtitle_label = get_node_or_null(subtitle_label_path) as Label
	_sfx_player = get_node_or_null(sfx_player_path) as AudioStreamPlayer

func _unhandled_input(event: InputEvent) -> void:
	if sequence == null or not _playing:
		return
	# Not skippable in release, but allow a debug-only skip for iteration.
	if sequence.allow_debug_skip and OS.is_debug_build():
		if event.is_action_pressed(sequence.debug_skip_action):
			_finish_now()
			get_viewport().set_input_as_handled()

func _finish_now() -> void:
	# Don’t try to kill all tweens (they might be shared); just stop and emit.
	_playing = false
	_intro_task_running = false
	_active_tweens = 0
	set_process(false)
	set_process_unhandled_input(false)
	finished.emit()

func _process(delta: float) -> void:
	if not _playing or sequence == null:
		return

	_elapsed += delta

	while _cue_index < _cues_sorted.size() and _cues_sorted[_cue_index].time <= _elapsed:
		var cue := _cues_sorted[_cue_index]
		_cue_index += 1
		_execute_cue(cue)

	_maybe_finish()

func _execute_cue(cue: CutsceneCue) -> void:
	match cue.type:
		CutsceneCue.CueType.PLAY_SFX:
			_play_sfx(cue)
		CutsceneCue.CueType.FADE_OVERLAY:
			_fade_overlay(cue.fade_to_alpha, cue.fade_duration)
		CutsceneCue.CueType.SET_SUBTITLE:
			_set_subtitle(cue.subtitle_text)
		CutsceneCue.CueType.PLAY_INTRO_FROM_CONTENTDB:
			if not _intro_task_running:
				_intro_task_running = true
				_run_intro_blocks_async(cue)
		CutsceneCue.CueType.CALL_METHOD:
			_call_method(cue)
		_:
			pass

func _play_sfx(cue: CutsceneCue) -> void:
	if cue.audio == null:
		return
	if overlap_sfx:
		var one_shot := AudioStreamPlayer.new()
		one_shot.name = "SFXOneShot"
		one_shot.bus = cue.bus
		one_shot.volume_db = cue.volume_db
		one_shot.pitch_scale = cue.pitch_scale
		one_shot.stream = cue.audio
		add_child(one_shot)
		one_shot.finished.connect(func() -> void:
			if is_instance_valid(one_shot):
				one_shot.queue_free()
		)
		one_shot.play()
		return
	var p := _get_sfx_player()
	p.bus = cue.bus
	p.volume_db = cue.volume_db
	p.pitch_scale = cue.pitch_scale
	p.stream = cue.audio
	p.play()

func _get_sfx_player() -> AudioStreamPlayer:
	if _sfx_player != null:
		return _sfx_player
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "SFXPlayer"
	add_child(_sfx_player)
	return _sfx_player

func _fade_overlay(target_alpha: float, duration: float) -> void:
	if _overlay == null:
		return
	var t := get_tree().create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_active_tweens += 1
	t.finished.connect(func() -> void:
		_active_tweens = maxi(0, _active_tweens - 1)
		_maybe_finish()
	)
	t.tween_property(_overlay, "modulate:a", clampf(target_alpha, 0.0, 1.0), maxf(0.0, duration))\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _set_subtitle(text: String) -> void:
	if _subtitle_label != null:
		_subtitle_label.text = text
	subtitle_changed.emit(text)

func _call_method(cue: CutsceneCue) -> void:
	if cue.call_method == &"":
		return
	var target: Node = get_node_or_null(cue.call_target_path)
	if target == null:
		push_warning("CutscenePlayer: call target missing: %s" % str(cue.call_target_path))
		return
	if not target.has_method(String(cue.call_method)):
		push_warning("CutscenePlayer: target has no method: %s" % String(cue.call_method))
		return
	if cue.call_arg == "":
		target.callv(String(cue.call_method), [])
	else:
		target.callv(String(cue.call_method), [cue.call_arg])

func _run_intro_blocks_async(cue: CutsceneCue) -> void:
	# Fire-and-forget async coroutine.
	_run_intro_blocks(cue)

func _split_into_blocks(lines: Array[String]) -> Array[String]:
	return ContentDB.split_into_blocks(lines)

func _estimate_block_duration(text: String, chars_per_sec: float, min_s: float, max_s: float) -> float:
	var cps := maxf(1.0, chars_per_sec)
	var d := float(text.length()) / cps
	return clampf(d, min_s, max_s)

func _run_intro_blocks(cue: CutsceneCue) -> void:
	# Note: no VO yet. This uses a readable auto-timing based on text length.
	var lines := ContentDB.get_intro_lines()
	var blocks := _split_into_blocks(lines)
	for block in blocks:
		_set_subtitle(block)
		var dur := _estimate_block_duration(block, cue.intro_chars_per_sec, cue.intro_min_seconds, cue.intro_max_seconds)
		await get_tree().create_timer(dur, true, false, true).timeout

	_set_subtitle("")
	_intro_task_running = false
	_maybe_finish()

func _maybe_finish() -> void:
	if not _playing:
		return
	if _cue_index < _cues_sorted.size():
		return
	if _intro_task_running:
		return
	if _active_tweens > 0:
		return
	_playing = false
	set_process(false)
	finished.emit()
