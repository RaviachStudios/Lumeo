extends Node

const SR := 22050
const BUTTON_FREQS: Array[float] = [415.30, 493.88, 329.63, 261.63, 440.00, 587.33]

# Background music is the bundled Lumeo WAV. We restart it on `finished`
# rather than relying on the WAV's import-side loop_mode, because the import is
# QOA-compressed and loop points aren't reliable across re-imports.
const BG_MUSIC_PATH := "res://Lumeo WAV.wav"

var _music_player: AudioStreamPlayer
var _music_on := false

var _btn_players: Array[AudioStreamPlayer] = []
var _sfx_player: AudioStreamPlayer
var _amb_player: AudioStreamPlayer

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

	# AMBIENCE — a SEPARATE channel, and separate on purpose.
	#
	# `_sfx_player` is one player: assigning a stream to it and calling play()
	# CUTS OFF whatever it was playing. Every gameplay sound in the game shares it
	# (the win chime, the lose run, the replay blip, the zap), which is fine because
	# they are all the game speaking and none of them overlap.
	#
	# The lake's frog is not the game speaking. It fires on the environment's own
	# clock, it runs on over the start of the next round, and it must never be able
	# to truncate a gameplay sound or be truncated by one. So it gets its own player
	# and its own headroom: these are meant to be noticed and not listened to.
	_amb_player = AudioStreamPlayer.new()
	_amb_player.volume_db = -13.0
	add_child(_amb_player)

# ── WAV generation ────────────────────────────────────────────────────────────

# ── Low-note compensation ─────────────────────────────────────────────────────
#
# The tones were pure sines at one amplitude, and the amber button — 261.63 Hz,
# the lowest in the set — was almost inaudible on a phone while the 587 Hz one
# was fine. That is not a mixing mistake: a phone speaker is a centimetre across
# and rolls off hard below about 500 Hz, so it simply cannot move air at 261, and
# the ear is less sensitive down there as well.
#
# Turning it up alone does not fix it — a speaker that cannot reproduce 261 Hz
# reproduces a louder 261 Hz no better. It needs both halves:
#
#   * more amplitude as the note falls, so the low ones ask for more to begin with;
#   * HARMONICS, weighted the same way. A speaker that cannot produce 261 Hz can
#     produce 523 and 785, and the ear reconstructs the missing fundamental from
#     them — which is why the note still reads as the same PITCH rather than as
#     having jumped an octave. This is the half that actually makes it audible.
#
# Both are keyed off `_tone_lift`, so the top of the set stays the clean sine it
# always was and only the notes that need help are changed.
#
# Measured with tools/tone_check.tscn, as RMS through a 500 Hz high-pass — a crude
# stand-in for the speaker, and the only measure that showed the problem at all
# (every tone had the SAME raw RMS, which is why it looked fine):
#
#     tone     before   after
#     Amber 262  -4.1 dB  -1.5 dB     <- the complaint
#     Blue  330  -2.6 dB  -0.4 dB
#     Red   415  -1.4 dB  -0.1 dB
#     Violet 440 -1.2 dB  -0.1 dB
#     Green 494  -0.7 dB  -0.2 dB
#     Pink  587   0.0 dB   0.0 dB     <- untouched, by construction
#
# (dB relative to the loudest of the six.) Re-run that harness after any change
# here; a change that only raises amplitude will move the first column and not the
# second, which is the mistake this block exists to prevent.
const TONE_REF_HZ := 560.0      # at or above this a phone speaker needs no help
const TONE_LOW_HZ := 250.0      # full compensation at or below this

func _tone_lift(freq: float) -> float:
	return clampf((TONE_REF_HZ - freq) / (TONE_REF_HZ - TONE_LOW_HZ), 0.0, 1.0)

# One sample of a compensated tone at phase `w` = TAU * freq * t.
# `norm` keeps the peak at `amp` however much harmonic content was added, so a low
# note gains real energy in the band the speaker can reach without ever clipping.
func _tone_sample(w: float, lift: float) -> float:
	var h2 := 0.62 * lift
	var h3 := 0.32 * lift
	var amp: float = minf(0.88, 0.5 * (1.0 + 1.15 * lift))
	return (sin(w) + h2 * sin(2.0 * w) + h3 * sin(3.0 * w)) * (amp / (1.0 + h2 + h3))

func _make_tone(freq: float, duration: float) -> AudioStreamWAV:
	var n := int(SR * duration)
	var lift := _tone_lift(freq)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / SR
		var s := int(_tone_sample(TAU * freq * t, lift) * _env(t, duration) * 32767.0)
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
		var lift := _tone_lift(freq)
		for i in note_n:
			var t := float(i) / SR
			var s := int(_tone_sample(TAU * freq * t, lift) * _env(t, note_dur) * 32767.0)
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


# ── Lake ambience ─────────────────────────────────────────────────────────────
#
# The four sounds the Magical Lake's frog event makes, all procedural like the rest
# of this file and all on `_amb_player` so none of them can interrupt, or be
# interrupted by, a gameplay sound (see the note where that player is built).
#
# They are one player, so they are also mutually exclusive: two of them asked for at
# the same instant is one of them truncated. That is a constraint on the EVENT, and
# lake_world.gd's _frog_beats keeps it — one sound per beat, and the ribbit has its
# beat to itself.
#
# They are deliberately quiet and deliberately short. The brief is a small creature
# noticed out of the corner of the ear — the moment any of these is loud enough to
# be listened to properly it stops being ambience and starts competing with the
# tones the player is trying to memorise.

# The lily pad breaking the surface: a soft water swell. Filtered noise with a slow
# attack, which is the shape of water moving rather than water being hit.
func play_lake_emerge() -> void:
	_amb_player.stream = _make_swell()
	_amb_player.play()

# RI-BBIT. The frog's own sound, played once per event, on the last jump as it
# leaves the pad (LakeWorld._frog_beats).
#
# It replaced a single buzzy croak, and the reason is not timbre: what makes a noise
# read as "a frog said something" is that it has TWO SYLLABLES — a short high chirp
# and a longer, lower one after it, with a gap between them. One note of the same
# material is a creak, however well it is voiced.
func play_frog_ribbit() -> void:
	_amb_player.stream = _make_ribbit()
	_amb_player.play()

# The push-off: a short breathy whoosh, almost under the threshold.
func play_frog_hop() -> void:
	_amb_player.stream = _make_whoosh()
	_amb_player.play()

# WOO-HOO. The level-8 party's one sound — five frogs cheering at once — played
# exactly once, as the pads finish surfacing (LakeWorld._party_beats).
#
# It is on the SAME ambience player as the other four, which is what stops a
# celebration from truncating a button tone, and it is the one lake sound allowed
# to be a little louder and a little longer than the rest: nothing is being
# memorised while it plays, because the round is frozen for the whole event.
func play_frog_woohoo() -> void:
	_amb_player.stream = _make_woohoo()
	_amb_player.play()

# Something small hitting water. `strength` scales the length and the brightness,
# so a landing on a leaf and a landing in the lake are the same sound at two sizes
# rather than two sounds.
func play_water_tap(strength := 1.0) -> void:
	_amb_player.stream = _make_tap(clampf(strength, 0.15, 1.0))
	_amb_player.play()


# ---------------------------------------------------------------------------
# Ice Kingdom
# ---------------------------------------------------------------------------
# Two, and on the SAME ambience player as the lake's five, for the same reason: a
# skin's atmosphere may never truncate a button tone. They are also mutually
# exclusive with each other, which the events already are.

# The every-third-level crystal burst: ice giving way. A dry crack with a ring of
# glassy partials on top of it, and the partials are the whole sound — a crack with
# no ring is a stick breaking.
func play_ice_crack() -> void:
	_amb_player.stream = _make_ice_crack()
	_amb_player.play()

# The every-eighth-level celebration: a soft rising shimmer, played once as the
# aurora comes up. Longer and quieter than the crack; nothing is being memorised
# while it plays, because the round is frozen for the whole event.
func play_ice_shimmer() -> void:
	_amb_player.stream = _make_ice_shimmer()
	_amb_player.play()


# A short crack with four inharmonic partials ringing after it. Inharmonic on
# purpose: a harmonic stack at these frequencies is a BELL, and a bell is a warm
# sound. Ice is the same material struck badly.
func _make_ice_crack() -> AudioStreamWAV:
	var dur := 0.34
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var parts := [1780.0, 2410.0, 3170.0, 4630.0]
	var decay := [9.0, 13.0, 17.0, 24.0]
	var lp := 0.0
	for i in n:
		var u := float(i) / float(n)
		# The break itself: filtered noise, gone in a twentieth of a second.
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.62
		var v := lp * exp(-u * 42.0) * 0.7
		for k in parts.size():
			v += sin(TAU * float(parts[k]) * u * dur) \
				* exp(-u * float(decay[k])) * (0.30 / float(k + 1))
		buf[i] = v
	return _to_wav(buf, 0.34)


# A slow swell of high, slightly detuned partials — the aurora coming up. No attack
# anywhere in it: the moment this has a transient it reads as a chime being struck
# rather than as a sky lighting.
func _make_ice_shimmer() -> AudioStreamWAV:
	var dur := 1.25
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var parts := [1046.5, 1318.5, 1568.0, 2093.0, 2637.0]
	for i in n:
		var u := float(i) / float(n)
		# In over a third of the sound, out over the rest, and never at full: the
		# envelope IS the effect.
		var env: float = smoothstep(0.0, 0.34, u) * (1.0 - smoothstep(0.42, 1.0, u))
		var v := 0.0
		for k in parts.size():
			# A slow beat between each partial and a copy of itself a few cents
			# away, which is what makes a sustained tone shimmer rather than sit.
			var f := float(parts[k])
			v += (sin(TAU * f * u * dur) + sin(TAU * f * 1.004 * u * dur)) \
				* (0.22 / float(k + 1)) * (0.55 + 0.45 * sin(TAU * (0.7 + 0.3 * float(k)) * u))
		buf[i] = v * env
	return _to_wav(buf, 0.26)


# Rising filtered noise with a rounded top — the pad coming up through the surface.
func _make_swell() -> AudioStreamWAV:
	var dur := 0.55
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var u := float(i) / float(n)
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.045
		lp2 += (lp - lp2) * 0.055                       # two poles: water, not hiss
		# Slow in, slower out. A percussive attack here would read as a splash, and
		# the pad is RISING.
		var env := sin(clampf(u, 0.0, 1.0) * PI)
		buf[i] = lp2 * env * 2.4
	return _to_wav(buf, 0.34)


# The two-syllable one: "ri-" (short, higher, quiet) then "-bbit" (longer, lower,
# the one that carries), with 40 ms of silence between them.
#
# A gated harmonic stack, like the button tones, tuned against three constraints
# rather than against realism:
#
#   * a PHONE SPEAKER. Both syllables sit at 300-430 Hz with two partials on top,
#     for exactly the reason the button tones do (see the low-note note above): a
#     real frog's 120 Hz is silent on a handset, and the harmonics are what let the
#     ear put the missing fundamental back.
#   * CUTE, not authentic. The pitch RISES through the second syllable instead of
#     falling, which is the difference between a cartoon frog and a bullfrog, and
#     the gate is slow (18 Hz, well under a croak's rattle) so it reads as a voice
#     with a wobble rather than as a rattle.
#   * SHORT. 0.30 s all in. This plays while the player is being shown a colour
#     sequence to memorise; anything long enough to listen to properly is competing
#     with the thing the game is asking them to do.
func _make_ribbit() -> AudioStreamWAV:
	var dur := 0.30
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	# start, end, pitch at the start, pitch at the end, loudness
	var syllables := [
		[0.000, 0.075, 430.0, 405.0, 0.55],
		[0.115, 0.300, 300.0, 360.0, 1.00],
	]
	var phase := 0.0
	for i in n:
		var t := float(i) / float(SR)
		var amp := 0.0
		var freq := 300.0
		for sy: Array in syllables:
			var t0: float = sy[0]
			var t1: float = sy[1]
			if t < t0 or t >= t1:
				continue
			var u: float = (t - t0) / (t1 - t0)
			freq = lerpf(float(sy[2]), float(sy[3]), u)
			# Quick in, rounded, released — a little vocal shape rather than a gate.
			amp = float(sy[4]) * minf(u / 0.10, 1.0) * pow(1.0 - u, 0.55)
		phase += TAU * freq / SR
		if amp <= 0.0:
			continue
		var tone := sin(phase) * 0.55 + sin(phase * 2.0) * 0.30 + sin(phase * 3.0) * 0.14
		var gate := 0.55 + 0.45 * pow(maxf(sin(TAU * 18.0 * t), 0.0), 0.7)
		buf[i] = tone * gate * amp
	return _to_wav(buf, 0.34)


# The push-off. Band-passed noise that swells and goes, and nothing else.
func _make_whoosh() -> AudioStreamWAV:
	var dur := 0.20
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var u := float(i) / float(n)
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.30      # takes the fizz off the top
		var env := pow(sin(clampf(u, 0.0, 1.0) * PI), 1.6)
		buf[i] = lp * env * 1.6
	return _to_wav(buf, 0.26)


# WOO-HOO, sung by FIVE frogs. The level-8 party's sound.
#
# Built out of the ribbit's material — a gated harmonic stack at phone-speaker
# pitches — and changed in exactly two ways, both of which are what makes it read
# as a cheer rather than as a longer ribbit:
#
#   * THE PITCH RISES ALL THE WAY THROUGH, across both syllables and between them.
#     A falling second syllable is a call; a rising one is a whoop. This is the
#     same trick the ribbit already uses on its second syllable, pushed further.
#   * THREE DETUNED VOICES, staggered by a few milliseconds. One voice at this
#     pitch is a frog; three voices 3-4 % apart that do not start together are a
#     GROUP of them, and the beating between them is most of the joy in the sound.
#     Five voices was tried and is mush at 22 kHz mono — three is where the chorus
#     stops being countable and has not yet become a chord.
#
# 0.55 s, which is longer than anything else in this file and is affordable for the
# only reason that matters: the round is frozen for the whole party, so this sound
# is not competing with a sequence the player is trying to memorise.
func _make_woohoo() -> AudioStreamWAV:
	var dur := 0.55
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	# start, end, pitch at the start, pitch at the end, loudness
	var syllables := [
		[0.000, 0.185, 330.0, 470.0, 0.72],   # "woo-"
		[0.230, 0.550, 470.0, 640.0, 1.00],   # "-HOO"
	]
	# detune, start offset, weight — the chorus
	var voices := [[1.000, 0.000, 1.00], [0.965, 0.018, 0.80], [1.038, 0.033, 0.68]]
	var phase := PackedFloat32Array([0.0, 0.0, 0.0])
	for i in n:
		var t := float(i) / float(SR)
		var acc := 0.0
		for v in voices.size():
			var vo: Array = voices[v]
			var tv: float = t - float(vo[1])
			var amp := 0.0
			var freq := 330.0
			for sy: Array in syllables:
				var t0: float = sy[0]
				var t1: float = sy[1]
				if tv < t0 or tv >= t1:
					continue
				var u: float = (tv - t0) / (t1 - t0)
				freq = lerpf(float(sy[2]), float(sy[3]), pow(u, 0.75)) * float(vo[0])
				amp = float(sy[4]) * minf(u / 0.12, 1.0) * pow(1.0 - u, 0.45)
			phase[v] += TAU * freq / SR
			if amp <= 0.0:
				continue
			var tone := sin(phase[v]) * 0.55 + sin(phase[v] * 2.0) * 0.28 \
				+ sin(phase[v] * 3.0) * 0.12
			# The same slow wobble the ribbit has, a little quicker: it is what keeps
			# a held vowel from sounding like an organ.
			var gate := 0.62 + 0.38 * pow(maxf(sin(TAU * 21.0 * tv), 0.0), 0.7)
			acc += tone * gate * amp * float(vo[2])
		buf[i] = acc
	return _to_wav(buf, 0.40)


# Something small hitting water: a very short noise transient with a pitch-dropping
# body under it. The drop is what makes it a "plop" rather than a click — it is the
# bubble the impact leaves, and it is the whole sound.
func _make_tap(strength: float) -> AudioStreamWAV:
	var dur: float = 0.10 + 0.16 * strength
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var u := float(i) / float(n)
		var freq: float = lerpf(880.0 * (0.7 + 0.5 * strength), 260.0, sqrt(u))
		phase += TAU * freq / SR
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.5
		var click := lp * exp(-u * 26.0) * 0.55
		var body := sin(phase) * exp(-u * 7.0)
		buf[i] = (click + body) * (0.45 + 0.55 * strength)
	return _to_wav(buf, 0.42)


# A float buffer, normalised to `peak` and written out as 16-bit mono at SR.
# Normalising rather than trusting the arithmetic keeps these four at a level
# relative to EACH OTHER, which is what makes the set sound like one lake.
func _to_wav(buf: PackedFloat32Array, peak: float) -> AudioStreamWAV:
	var hi := 0.0
	for v: float in buf:
		hi = maxf(hi, absf(v))
	var k: float = (peak / hi) if hi > 0.0001 else 0.0
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, clampi(int(clampf(buf[i] * k, -1.0, 1.0) * 32767.0),
			-32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.mix_rate = SR
	wav.data = bytes
	return wav


# ---------------------------------------------------------------------------
# Royal Casino
# ---------------------------------------------------------------------------
# The seven sounds the casino table's events make. On the SAME `_amb_player` as the
# lake's five and Ice Kingdom's two, for the same reason: a skin's atmosphere may
# never truncate a button tone, and a button tone may never truncate it.
#
# THAT ONE PLAYER IS ALSO WHY EACH EVENT GETS AT MOST TWO BEATS, AND NEVER TWO AT
# ONE INSTANT. Assigning a stream and calling play() cuts off whatever was running,
# so "three cards land, each with a tap" would be one tap and two silences. Where a
# rhythm is wanted, it is baked into ONE buffer — see `_make_deal_three`, which is
# three slaps in a single stream rather than three calls. CasinoEvents._beat keeps
# to that.
#
# They are deliberately quiet and deliberately short. A casino table heard from the
# next chair, not a casino floor.

# A card sliding across felt: a soft band-limited shhh with a slow attack. This is
# the sound every card event opens on, played ONCE for the whole deal rather than
# once per card.
func play_card_slide() -> void:
	_amb_player.stream = _make_card_slide()
	_amb_player.play()

# A card landing: a short dry tap with a papery top. Brighter and shorter than the
# lake's water tap, which is the same event on a different material.
func play_card_tap() -> void:
	_amb_player.stream = _make_card_tap(1.0)
	_amb_player.play()

# SLAP SLAP SLAP — the golden deal's three cards, as ONE stream. See the note above:
# three calls to play_card_tap 120 ms apart is one tap.
func play_card_deal_three() -> void:
	_amb_player.stream = _make_deal_three()
	_amb_player.play()

# Clay chips knocking together. Two knocks, not one: a single click is a switch, and
# what makes a noise read as chips is that they arrive in twos and threes.
func play_chip_clink() -> void:
	_amb_player.stream = _make_chip_clink()
	_amb_player.play()

# The roulette ball going round its track: a rattle whose RATE rises with the ball
# and then falls away as it slows, ending in the little run of bounces a ball makes
# as it drops. `dur` is the event's own spin length, so the sound and the picture
# finish together.
func play_roulette_spin(dur := 1.6) -> void:
	_amb_player.stream = _make_roulette_spin(clampf(dur, 0.6, 3.0))
	_amb_player.play()

# The jackpot lights coming up: a soft warm swell, the quietest thing here.
func play_casino_swell() -> void:
	_amb_player.stream = _make_casino_swell()
	_amb_player.play()

# The ROYAL FLUSH. A short rising shimmer into a bright major chord — the one casino
# sound allowed to be a little louder and a little longer than the rest, for the
# only reason that matters: the round is frozen for the whole celebration, so it is
# not competing with a sequence the player is trying to memorise.
func play_royal_fanfare() -> void:
	_amb_player.stream = _make_royal_fanfare()
	_amb_player.play()


# Filtered noise with a slow attack and a slower decay. Two poles of low-pass rather
# than one: a single pole leaves enough top on white noise that it reads as a hiss
# from a speaker instead of card stock on cloth.
func _make_card_slide() -> AudioStreamWAV:
	var dur := 0.26
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var u := float(i) / float(n)
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.42
		lp2 += (lp - lp2) * 0.42
		# Attack over the first fifth, then a long tail: a card accelerates away from
		# the hand and decelerates into the felt.
		var env := pow(sin(clampf(u, 0.0, 1.0) * PI), 1.9)
		buf[i] = lp2 * env * 2.2
	return _to_wav(buf, 0.22)


# A card hitting the table. A noise click for the edge and one short mid partial for
# the body of the card — no long decay at all, because paper on cloth does not ring.
func _make_card_tap(strength: float) -> AudioStreamWAV:
	var dur := 0.075
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var u := float(i) / float(n)
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.62
		phase += TAU * 420.0 / SR
		buf[i] = (lp * exp(-u * 20.0) * 0.9 + sin(phase) * exp(-u * 30.0) * 0.35) * strength
	return _to_wav(buf, 0.30)


# Three of those, 115 ms apart, in one buffer.
func _make_deal_three() -> AudioStreamWAV:
	var dur := 0.44
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var phase := 0.0
	# The third is the loudest: a dealer's last card is the one that is placed
	# rather than dropped, and a flat three is a machine.
	var hits := [{"at": 0.000, "amp": 0.80}, {"at": 0.115, "amp": 0.88},
		{"at": 0.230, "amp": 1.00}]
	for i in n:
		var t := float(i) / float(SR)
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.62
		phase += TAU * 420.0 / SR
		var v := 0.0
		for h: Dictionary in hits:
			var d: float = t - float(h["at"])
			if d < 0.0 or d > 0.09:
				continue
			var u := d / 0.09
			v += (lp * exp(-u * 20.0) * 0.9 + sin(phase) * exp(-u * 30.0) * 0.35) \
				* float(h["amp"])
		buf[i] = v
	return _to_wav(buf, 0.34)


# Clay chips. A click with ONE short inharmonic partial over it — clay is a dull
# material and a harmonic ring here sounds like glass, which is the wrong casino.
# Two knocks 70 ms apart, the second quieter.
func _make_chip_clink() -> AudioStreamWAV:
	var dur := 0.22
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		var t := float(i) / float(SR)
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.55
		p1 += TAU * 1180.0 / SR
		p2 += TAU * 1790.0 / SR
		var v := 0.0
		for k in 2:
			var at := 0.0 if k == 0 else 0.070
			var amp := 1.0 if k == 0 else 0.62
			var d := t - at
			if d < 0.0 or d > 0.11:
				continue
			var u := d / 0.11
			v += (lp * exp(-u * 24.0) * 0.55
				+ sin(p1) * exp(-u * 17.0) * 0.40
				+ sin(p2) * exp(-u * 25.0) * 0.22) * amp
		buf[i] = v
	return _to_wav(buf, 0.26)


# The ball on the track. A rattle whose RATE is the whole sound: the ticks speed up
# while the ball is being driven and slow down as it loses the rim, and the last
# fifth is the run of bounces as it drops into a pocket.
#
# The ticks come from an amplitude gate on filtered noise rather than from a
# sequence of one-shots, so the rate can be a continuous function of time and the
# spin can end anywhere without a click.
func _make_roulette_spin(dur: float) -> AudioStreamWAV:
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var phase := 0.0
	var drop := dur * 0.78
	for i in n:
		var t := float(i) / float(SR)
		var u := t / dur
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.50
		# Rate: accelerates to a peak at about two thirds, then falls away hard.
		var rate: float = lerpf(26.0, 62.0, smoothstep(0.0, 0.62, u)) \
			* (1.0 - 0.72 * smoothstep(0.62, 1.0, u))
		phase += TAU * rate / SR
		var tick := pow(clampf(0.5 + 0.5 * sin(phase), 0.0, 1.0), 7.0)
		var body := lp * tick
		# The drop: three heavier bounces once the ball leaves the rim.
		if t > drop:
			var d := (t - drop) / maxf(dur - drop, 0.001)
			body += lp * pow(clampf(0.5 + 0.5 * sin(d * 22.0), 0.0, 1.0), 5.0) \
				* (1.0 - d) * 1.8
		var env := smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.90, 1.0, u))
		buf[i] = body * env
	return _to_wav(buf, 0.24)


# The lights coming up. A warm low swell with a fifth over it and no attack at all —
# this is a room getting brighter, not something being struck.
func _make_casino_swell() -> AudioStreamWAV:
	var dur := 0.70
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var p1 := 0.0
	var p2 := 0.0
	var lp := 0.0
	for i in n:
		var u := float(i) / float(n)
		p1 += TAU * lerpf(146.8, 174.6, u) / SR      # D3 -> F3
		p2 += TAU * lerpf(220.0, 261.6, u) / SR      # A3 -> C4
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.12
		var env := pow(sin(clampf(u, 0.0, 1.0) * PI), 1.4)
		buf[i] = (sin(p1) * 0.55 + sin(p2) * 0.35 + lp * 0.25) * env
	return _to_wav(buf, 0.20)


# ROYAL FLUSH. Two halves in one buffer, which is the only way to get a buildup and
# its payoff out of a single player:
#
#   0.00 - 0.62   the buildup: a rising filtered-noise shimmer with a tone climbing
#                 an octave under it. This is the anticipation while the fifth card
#                 shakes and the gold gathers.
#   0.62 - 1.55   the chord: a major triad plus its octave, struck together, with a
#                 bright bell partial on top and a long decay.
#
# The chord is a MAJOR triad and not a fanfare run, deliberately. A run has a tempo,
# and a tempo that does not match the animation is worse than no tune at all; a
# struck chord lands on one frame and decays under whatever happens next.
func _make_royal_fanfare() -> AudioStreamWAV:
	var dur := 1.55
	var hit := 0.62
	var n := int(SR * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var climb := 0.0
	# C5, E5, G5, C6, and a bright partial well above them for the shine.
	var chord := [523.25, 659.25, 783.99, 1046.50, 2093.00]
	var amps := [0.70, 0.58, 0.52, 0.40, 0.14]
	var ph := PackedFloat32Array()
	ph.resize(chord.size())
	for i in n:
		var t := float(i) / float(SR)
		var v := 0.0
		if t < hit:
			var u := t / hit
			lp += ((randf() * 2.0 - 1.0) - lp) * lerpf(0.10, 0.55, u)
			climb += TAU * lerpf(196.0, 392.0, u * u) / SR
			v += (lp * 0.85 + sin(climb) * 0.30) * pow(u, 2.1)
		else:
			var u := (t - hit) / (dur - hit)
			for k in chord.size():
				ph[k] += TAU * float(chord[k]) / SR
				v += sin(ph[k]) * float(amps[k]) * exp(-u * (2.6 + 1.4 * float(k)))
			# A touch of noise on the attack so the chord has a strike in it.
			lp += ((randf() * 2.0 - 1.0) - lp) * 0.6
			v += lp * exp(-u * 40.0) * 0.35
		buf[i] = v
	return _to_wav(buf, 0.40)
