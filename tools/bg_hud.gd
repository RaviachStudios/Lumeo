extends Node
# The REAL gameplay screen — HUD and all — over a modelled 3D background, so the
# LEVEL badge, the "Your turn!" status pill and the Close/quit dome can be checked
# for readability against the brightest scenes.
#
#   ... res://tools/bg_hud.tscn -- <difficulty> <bg id>
const Game := preload("res://game.gd")

class StubManager extends Control:
	func show_game_over(_rounds: int) -> void: pass
	func show_contest_detail(_cid: String) -> void: pass
	func show_home() -> void: pass

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var diff := args[0] if args.size() > 0 else "hard"
	var id := args[1] if args.size() > 1 else "bg_arcade"
	for i in 40:
		await get_tree().process_frame
	CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL
	CoinsManager.selected_skin = ""
	CoinsManager.selected_theme = id
	GameState.difficulty = diff
	GameState.num_colors = 3 if diff == "easy" else (6 if diff == "hard" else 5)
	BackgroundManager.set_active(true)
	var stub := StubManager.new()
	stub.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(stub)
	var game := Game.new()
	game.game_manager = stub
	stub.add_child(game)
	await get_tree().create_timer(1.4).timeout
	game._wheel.set_level(12)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://bghud_%s_%s.png" % [diff, id])
	print("shot %s %s" % [diff, id])
	get_tree().quit()
