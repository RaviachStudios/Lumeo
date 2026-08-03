extends Node

# Screenshot harness for the top-left HUD (coin pill + Daily Hub). Saves two
# frames: the bar at rest, then the Daily Hub dropdown expanded.
# Builds the real home screen against the editor sim and saves a frame. Run
# WITHOUT --headless (the dummy renderer has no framebuffer to read back):
#
#   godot --path . tools/home_hud_test.tscn --resolution 1280x720
#
# Not shipped with the game; it's a developer harness.

const HomeScreen := preload("res://home_screen.gd")

# During a build the home screen only touches `welcome_prompt_shown` and the
# shop-prewarm's GL gate, so a two-member stub is enough to stand it up alone.
class StubManager extends Control:
	var welcome_prompt_shown := true
	func await_gl_stable() -> void:
		pass

func _ready() -> void:
	# Suppress the first-run tour so it doesn't cover the HUD we came to look at.
	var cfg := ConfigFile.new()
	cfg.load("user://prefs.cfg")
	cfg.set_value("tutorial", "seen", true)
	cfg.save("user://prefs.cfg")

	FirebaseManager.sign_in()
	FirebaseManager.set_display_name("Tester")
	await get_tree().process_frame
	CoinsManager.credit_task_reward(1240)          # something to show in the pill
	# A part-finished board: two tasks done, one of them still waiting to be claimed.
	DailyTasks.note_game_played("hard")
	DailyTasks.note_score("hard", 9)
	DailyTasks.claim("hard_7")

	var stub := StubManager.new()
	add_child(stub)
	var home := HomeScreen.new()
	home.game_manager = stub
	stub.add_child(home)

	# Long enough for the badge-earn toast (fired by the coins above) to slide away.
	await get_tree().create_timer(8.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://home_hud.png")
	print("shot  %s" % ProjectSettings.globalize_path("user://home_hud.png"))

	# ...and again with the Daily Hub dropdown open and settled.
	home._toggle_hub()
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var img2 := get_viewport().get_texture().get_image()
	img2.save_png("user://home_hud_open.png")
	print("shot  %s" % ProjectSettings.globalize_path("user://home_hud_open.png"))

	# ...and once more after collecting, to check the claimed state + countdown.
	home._on_hub_claim()
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var img3 := get_viewport().get_texture().get_image()
	img3.save_png("user://home_hud_claimed.png")
	print("shot  %s" % ProjectSettings.globalize_path("user://home_hud_claimed.png"))

	# Let the post-claim auto-close run, then reopen: exercises the close path and
	# proves the panel repaints its collected state on a second visit.
	await get_tree().create_timer(2.0).timeout
	home._toggle_hub()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var img4 := get_viewport().get_texture().get_image()
	img4.save_png("user://home_hud_reopen.png")
	print("shot  %s" % ProjectSettings.globalize_path("user://home_hud_reopen.png"))
	get_tree().quit()
