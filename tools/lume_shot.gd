extends Node
# Throwaway-but-kept harness: the REAL gameplay screen wearing a chosen theme, at
# the design resolution, so a LumeWorlds background can be checked against the
# board and the HUD it shares the frame with.
#
#   Godot --path . res://tools/lume_shot.tscn -- <theme_id> [difficulty] [out.png]
#
# difficulty: easy | moderate | hard   (default moderate)

const Game := preload("res://game.gd")

class StubManager extends Control:
	func show_game_over(_rounds: int) -> void: pass
	func show_contest_detail(_cid: String) -> void: pass
	func show_home() -> void: pass

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var theme: String = args[0] if args.size() > 0 else "clouds"
	var diff: String = args[1] if args.size() > 1 else "moderate"
	var out: String = args[2] if args.size() > 2 else ("lume_%s_%s.png" % [theme, diff])
	GameState.difficulty = diff
	GameState.num_colors = {"easy": 3, "moderate": 5, "hard": 6}.get(diff, 5)
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
	# Long enough for the plate bake + the props to settle.
	await get_tree().create_timer(2.5).timeout
	game._wheel.set_level(12)
	game._wheel.set_lit(4, true)
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://" + out)
	print("shot  %s   mode=%s" % [ProjectSettings.globalize_path("user://" + out),
		BackgroundManager._render_mode])
	get_tree().quit()
