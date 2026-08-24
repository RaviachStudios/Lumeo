extends Node
# Throwaway harness: the REAL moderate game screen at the mobile design
# resolution, so the panel's framing can be checked against the HUD it shares the
# viewport with. Run WITHOUT --headless.

const Game := preload("res://game.gd")

class StubManager extends Control:
	func show_game_over(_rounds: int) -> void: pass
	func show_contest_detail(_cid: String) -> void: pass
	func show_home() -> void: pass

func _ready() -> void:
	GameState.difficulty = "moderate"
	GameState.num_colors = 5
	var stub := StubManager.new()
	stub.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(stub)
	var game := Game.new()
	game.game_manager = stub
	stub.add_child(game)
	await get_tree().create_timer(1.0).timeout
	game._wheel.set_level(12)
	game._wheel.set_lit(4, true)      # violet lit, as the sequence plays it
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://mgui_ingame.png")
	print("shot  %s" % ProjectSettings.globalize_path("user://mgui_ingame.png"))
	get_tree().quit()
