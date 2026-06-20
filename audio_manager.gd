extends Node

const SR := 22050
const BUTTON_FREQS: Array[float] = [415.30, 493.88, 329.63, 261.63, 440.00, 587.33]

const BEAT := 0.625
const BG_MELODY: Array = [
	[523.25,1],[659.25,0.5],[783.99,0.5],[659.25,1],[0.0,0.5],
	[698.46,1],[880.00,0.5],[698.46,0.5],[659.25,1],[0.0,0.5],
	[587.33,1],[659.25,0.5],[783.99,0.5],[698.46,1],[0.0,0.5],
	[523.25,2],[0.0,1.0],
	[659.25,1],[783.99,0.5],[880.00,0.5],[783.99,1],[0.0,0.5],
	[698.46,1],[783.99,0.5],[880.00,0.5],[987.77,1],[0.0,0.5],
	[880.00,1],[783.99,0.5],[698.46,0.5],[659.25,1],[0.0,0.5],
	[523.25,2],[0.0,2.0],
]

var _music_player: AudioStreamPlayer
var _music_pb: AudioStreamGeneratorPlayback
var _music_phase := 0.0
var _music_note := 0
var _music_elapsed := 0.0
var _music_on := false

var _btn_players: Array[AudioStreamPlayer] = []
var _sfx_player: AudioStreamPlayer

func _ready() -> void:
	# Background music — generator (long-running loop)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SR
	gen.buffer_length = 0.2
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = gen
	_music_player.volume_db = -8.0
	add_child(_music_player)

	# Button tones — pre-generated WAV, one player per button
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.stream = _make_tone(BUTTON_FREQS[i], 0.75)
		p.volume_db = -3.0
		add_child(p)
		_btn_players.append(p)

	# SFX player — plays pre-generated WAV sequences
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.volume_db = -3.0
	add_child(_sfx_player)

# ── WAV generation ────────────────────────────────────────────────────────────

func _make_tone(freq: float, duration: float) -> AudioStreamWAV:
	var n := int(SR * duration)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / SR
		var env := _env(t, duration)
		var s := int(sin(TAU * freq * t) * env * 0.5 * 32767.0)
		bytes.encode_s16(i * 2, clampi(s, -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.mix_rate = SR
	wav.data = bytes
	return wav

func _make_sequence_wav(freqs: Array, note_dur: float) -> AudioStreamWAV:
	var note_n := int(SR * note_dur)
	var bytes := PackedByteArray()
	bytes.resize(note_n * freqs.size() * 2)
	for fi in freqs.size():
		var freq: float = freqs[fi]
		for i in note_n:
			var t := float(i) / SR
			var env := _env(t, note_dur)
			var s := int(sin(TAU * freq * t) * env * 0.5 * 32767.0)
			bytes.encode_s16((fi * note_n + i) * 2, clampi(s, -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.mix_rate = SR
	wav.data = bytes
	return wav

func _env(t: float, total: float) -> float:
	var attack := minf(0.02, total * 0.1)
	var rel_start := total * 0.6
	if t < attack:
		return t / attack
	if t < rel_start:
		return 1.0
	return maxf(0.0, 1.0 - (t - rel_start) / (total - rel_start))

# ── Public API ────────────────────────────────────────────────────────────────

func play_button_tone(idx: int, _duration := 0.65) -> void:
	idx = clampi(idx, 0, _btn_players.size() - 1)
	_btn_players[idx].play()

func play_lose_sound() -> void:
	_sfx_player.stream = _make_sequence_wav([392.0, 349.23, 311.13, 261.63], 0.28)
	_sfx_player.play()

func play_win_sound() -> void:
	_sfx_player.stream = _make_sequence_wav([523.25, 659.25, 783.99, 1046.5], 0.14)
	_sfx_player.play()

func play_replay_sound() -> void:
	_sfx_player.stream = _make_sequence_wav([659.25, 783.99], 0.12)
	_sfx_player.play()

func is_music_on() -> bool:
	return _music_on

func play_bg_music() -> void:
	if _music_on:
		return
	_music_on = true
	_music_note = 0
	_music_elapsed = 0.0
	_music_phase = 0.0

func stop_bg_music() -> void:
	_music_on = false
	_music_player.stop()
	_music_pb = null

# ── Background music generator ────────────────────────────────────────────────

func _process(_d: float) -> void:
	_tick_music()

func _tick_music() -> void:
	if not _music_on:
		return
	if not _music_player.playing:
		_music_player.play()
	_music_pb = _music_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if not _music_pb:
		return
	for _i in _music_pb.get_frames_available():
		var note: Array = BG_MELODY[_music_note]
		var freq: float = note[0]
		var s := 0.0
		if freq > 0.0:
			var dur: float = float(note[1]) * BEAT
			var env := _env(_music_elapsed, dur)
			s = sin(TAU * freq * _music_phase / SR) * env * 0.28
			s += sin(TAU * freq * 2.0 * _music_phase / SR) * env * 0.08
		_music_pb.push_frame(Vector2(s, s))
		_music_phase += 1.0
		_music_elapsed += 1.0 / SR
		if _music_elapsed >= float(note[1]) * BEAT:
			_music_elapsed = 0.0
			_music_phase = 0.0
			_music_note = (_music_note + 1) % BG_MELODY.size()
