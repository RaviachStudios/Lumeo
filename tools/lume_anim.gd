extends Node
# Does a LUMEO world's animation actually RUN on the real gameplay path, and is it
# the PROPS that are moving rather than a haze breathing somewhere?
#
#   Godot..._console.exe --path . res://tools/lume_anim.tscn -- <id> [gap] [diff.png]
#
# Renders the real gameplay screen wearing the theme, twice, `gap` seconds apart,
# and reports how much moved between them: the mean absolute difference over the
# frame, the largest single-pixel change, and how many pixels moved by more than a
# just-visible amount. It writes an AMPLIFIED difference image too, because the
# numbers cannot tell you WHAT moved — a bird walking and a wash breathing look
# the same in a mean, and only the picture shows you the bird-shaped trail.
#
# tools/bg_anim.tscn cannot answer any of this for a canvas theme: it screenshots
# the board's own viewport without ever activating BackgroundManager's layer, so
# every LUMEO world reports 0.00 there no matter what it is doing.

const Game := preload("res://game.gd")
const VISIBLE := 8          # sRGB counts; below this a change is not read as motion

class StubManager extends Control:
	func show_game_over(_rounds: int) -> void: pass
	func show_contest_detail(_cid: String) -> void: pass
	func show_home() -> void: pass

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var theme: String = args[0] if args.size() > 0 else "lume_ocean"
	var gap: float = float(args[1]) if args.size() > 1 else 3.0
	var out: String = args[2] if args.size() > 2 else ("anim_%s.png" % theme)
	GameState.difficulty = "moderate"
	GameState.num_colors = 5
	for i in 10: await get_tree().process_frame
	CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL
	CoinsManager.selected_theme = theme
	BackgroundManager.set_active(true)
	BackgroundManager._on_themes_changed()
	var stub := StubManager.new()
	stub.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(stub)
	var game := Game.new()
	game.game_manager = stub
	stub.add_child(game)
	await get_tree().create_timer(2.5).timeout
	game._wheel.set_level(12)
	var a := await _grab()
	await get_tree().create_timer(gap).timeout
	var b := await _grab()

	var w := a.get_width()
	var h := a.get_height()
	var diff := Image.create(w, h, false, Image.FORMAT_RGB8)
	var total := 0.0
	var peak := 0.0
	var moved := 0
	for y in h:
		for x in w:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0 * 255.0
			total += d
			peak = maxf(peak, d)
			if d > float(VISIBLE):
				moved += 1
			# amplified, so a 3-count change is visible on screen
			var v := clampf(d / 24.0, 0.0, 1.0)
			diff.set_pixel(x, y, Color(v, v, v))
	var px := float(w * h)
	print("%-14s gap=%.1fs  mean|d|=%.3f  max|d|=%.1f  moved>%d: %d px (%.2f%%)  %s"
		% [theme, gap, total / px, peak, VISIBLE, moved, 100.0 * float(moved) / px,
			"ANIMATED" if moved > 400 else "STILL"])
	diff.save_png("user://" + out)
	print("diff  %s" % ProjectSettings.globalize_path("user://" + out))
	get_tree().quit()

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()
