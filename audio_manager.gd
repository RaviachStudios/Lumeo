extends Node

const SR := 22050
const BUTTON_FREQS: Array[float] = [415.30, 493.88, 329.63, 261.63, 440.00, 587.33]

# Background music is the bundled Simon WAV. We restart it on `finished`
# rather than relying on the WAV's import-side loop_mode, because the import is
# QOA-compressed and loop points aren't reliable across re-imports.
const BG_MUSIC_PATH := "res://Simon WAV.wav"

var _music_player: AudioStreamPlayer
var _music_on := false

var _btn_players: Array[AudioStreamPlayer] = []
var _sfx_player: AudioStreamPlayer

func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = load(BG_MUSIC_PATH)
	# Source WAV ships with low headroom — at the old -8 dB attenuation the
	# track was barely audible on phones even at master max, so we push it up.
	_music_player.volume_db = 6.0
	_music_player.finished.connect(_on_music_finished)
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
	_music_player.play()

func stop_bg_music() -> void:
	_music_on = false
	_music_player.stop()

func _on_music_finished() -> void:
	if _music_on:
		_music_player.play()
