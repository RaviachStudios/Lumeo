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

# Short arcade-style electric discharge (the every-3-rounds "charging" zap): a harsh
# square-ish tone whose pitch sweeps down fast, layered with a crackle of white noise
# and an instant-attack exponential decay. Fully procedural — no asset needed.
func play_electric_discharge() -> void:
	_sfx_player.stream = _make_zap()
	_sfx_player.play()

func _make_zap() -> AudioStreamWAV:
	var dur := 0.42
	var n := int(SR * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var phase := 0.0
	for i in n:
		var u := float(i) / float(n)
		var freq: float = lerp(1600.0, 220.0, sqrt(u))   # fast downward zap sweep
		phase += TAU * freq / SR
		var tone := float(sign(sin(phase))) * 0.5 + 0.5 * sin(phase * 2.01)   # buzzy square + detuned partial
		var noise := (randf() * 2.0 - 1.0) * exp(-u * 7.0)             # crackle, loudest at the front
		var env := exp(-u * 5.5)                                       # instant attack, exp decay
		var s := int(clampf((tone * 0.6 + noise * 0.7) * env, -1.0, 1.0) * 0.5 * 32767.0)
		bytes.encode_s16(i * 2, clampi(s, -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.mix_rate = SR
	wav.data = bytes
	return wav

# Soft casino roulette-ball roll (the Jackpot skin's every-3-rounds lap): a gentle
# rolling hiss with a faint low rumble, overlaid with "fret" ticks whose rate tracks
# the ball's speed (sparse at the ends, dense mid-lap — matching the eased motion),
# ending in a subtle click as the ball drops home. `dur` matches the lap length so the
# closing click lands exactly as the ball returns. Fully procedural — no asset needed.
func play_roulette_roll(dur := 1.0) -> void:
	_sfx_player.stream = _make_roulette_roll(dur)
	_sfx_player.play()

func _make_roulette_roll(dur: float) -> AudioStreamWAV:
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = 0.0
	# Rolling hiss (soft-lowpassed noise), louder mid-lap where the ball is fastest,
	# plus a faint low body so it reads as a ball on a track rather than pure hiss.
	var lp := 0.0
	for i in n:
		var u := float(i) / float(n)
		var speed := sin(PI * u)                       # 0 at the ends, 1 mid-lap
		var white := randf() * 2.0 - 1.0
		lp += (white - lp) * 0.12                       # one-pole lowpass → soft hiss
		var body := sin(TAU * 90.0 * float(i) / SR) * 0.05 * speed
		buf[i] = lp * (0.05 + 0.16 * speed) + body
	# Fret ticks: emit one each time the speed-weighted accumulator crosses an integer,
	# so ticks thicken mid-lap and thin toward the ends (∫ sin(πu) du over [0,1] = 2/π).
	var total_ticks := 20.0
	var rate := total_ticks / ((2.0 / PI) * dur)
	var acc := 0.0
	var next_tick := 0.6
	for i in n:
		var u := float(i) / float(n)
		acc += sin(PI * u) * rate / float(SR)
		if acc >= next_tick:
			next_tick += 1.0
			_add_click(buf, i, n, 1900.0 + randf() * 700.0, 0.22, 150.0)
	# Subtle closing click as the ball drops into its pocket.
	_add_click(buf, n - 1 - int(SR * 0.035), n, 1250.0, 0.5, 90.0)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var s := int(clampf(buf[i], -1.0, 1.0) * 0.5 * 32767.0)
		bytes.encode_s16(i * 2, clampi(s, -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.mix_rate = SR
	wav.data = bytes
	return wav

# Add a short decaying sine "click" into `buf` starting at sample `start`.
func _add_click(buf: PackedFloat32Array, start: int, n: int, freq: float, amp: float, decay: float) -> void:
	var length := int(SR * 0.04)
	for j in length:
		var idx := start + j
		if idx >= n:
			break
		var t := float(j) / float(SR)
		buf[idx] += sin(TAU * freq * t) * exp(-t * decay) * amp

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
