extends Node
# What a PHONE SPEAKER actually gets out of each button tone.
#
#   Godot..._console.exe --path . res://tools/tone_check.tscn
#
# Two numbers per tone: the RMS of the raw wave, and the RMS after a one-pole
# high-pass at 500 Hz — a crude stand-in for a small speaker's low rolloff, and
# the only one of the two that predicted the complaint. The amber button (261.63
# Hz, the lowest of the six) measured the SAME raw RMS as every other tone and 4.1
# dB below the top one through the filter, which is exactly what "the bass sound
# is almost not heard" is. Raw RMS alone would have said nothing was wrong.
#
# The second column is what to watch: the six should land close together. See
# AudioManager._tone_sample for the compensation.
func _ready() -> void:
	var names := ["Red 415", "Green 494", "Blue 330", "Amber 262 (orange)", "Violet 440", "Pink 587"]
	print("tone                    raw RMS   thru-500Hz RMS    vs loudest")
	var vals := []
	for i in 6:
		var wav: AudioStreamWAV = AudioManager._btn_players[i].stream
		var d := wav.data
		var n := d.size() / 2
		var sr := float(wav.mix_rate)
		var rc := 1.0 / (TAU * 500.0)
		var alpha := rc / (rc + 1.0 / sr)
		var prev_in := 0.0
		var prev_out := 0.0
		var acc := 0.0
		var acc_hp := 0.0
		for k in n:
			var x := float(d.decode_s16(k * 2)) / 32768.0
			var y: float = alpha * (prev_out + x - prev_in)
			prev_in = x
			prev_out = y
			acc += x * x
			acc_hp += y * y
		vals.append([sqrt(acc / n), sqrt(acc_hp / n)])
	var best := 0.0
	for v in vals:
		best = maxf(best, v[1])
	for i in 6:
		print("%-22s %7.4f   %7.4f        %+5.1f dB"
			% [names[i], vals[i][0], vals[i][1], 20.0 * (log(vals[i][1] / best) / log(10.0))])
	get_tree().quit()
