extends Node
# Throwaway harness: the REAL easy game screen at the mobile design resolution, so
# the three-button board's framing can be checked against the HUD it shares the
# viewport with. Run WITHOUT --headless.
#   Godot_..._console.exe --path . tools/egui_ingame.tscn

const Game := preload("res://game.gd")

class StubManager extends Control:
	func show_game_over(_rounds: int) -> void: pass
	func show_contest_detail(_cid: String) -> void: pass
	func show_home() -> void: pass

func _ready() -> void:
	GameState.set_difficulty("easy")
	var stub := StubManager.new()
	stub.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(stub)
	var game := Game.new()
	game.game_manager = stub
	stub.add_child(game)
	await get_tree().create_timer(1.0).timeout
	game._wheel.set_level(7)
	# The worst case for HUD overlap: every control the screen can show, up at once.
	game._watch_ad_btn.visible = true
	game._wheel.set_lit(0, true)       # cyan lit, as the sequence plays it
	game._wheel.set_press(2, 1.0)      # magenta held down
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://egui_ingame.png")
	print("shot  %s" % ProjectSettings.globalize_path("user://egui_ingame.png"))
	get_tree().quit()
