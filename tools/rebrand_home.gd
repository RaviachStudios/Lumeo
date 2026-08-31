extends Node

# End-to-end check of the wiring, not just the popup: seed a receipt into the
# editor's simulated wallet, then open the real home screen and see whether it
# surfaces the welcome by itself. Developer harness, not shipped.

const HomeScreen := preload("res://home_screen.gd")

class StubManager extends Control:
	var welcome_prompt_shown := true
	func await_gl_stable() -> void:
		pass

func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://prefs.cfg")
	cfg.set_value("tutorial", "seen", true)
	cfg.save("user://prefs.cfg")
	FirebaseManager.sign_in()
	FirebaseManager.set_display_name("Tester")
	await get_tree().process_frame
	while not CoinsManager.is_loaded():
		await get_tree().process_frame
	# Seeded straight into the sim store: the receipt carries an array, which only
	# the server may write — a client _save_partial of it is refused, on device and
	# now in the editor too (see CoinsManager._no_arrays).
	var doc: Dictionary = CoinsManager._sim_db.get(FirebaseManager.uid, {})
	doc[CoinsManager.REBRAND_FIELD] = {
		"at": "2026-08-30T19:15:19Z", "refund": 7870, "gift": 2000,
		"items": [
			{"key": "wheel",  "label": "Wheel cosmetics", "n": 38, "coins": 5690},
			{"key": "themes", "label": "Old backgrounds", "n": 10, "coins": 2180},
		]}
	CoinsManager._sim_db[FirebaseManager.uid] = doc
	CoinsManager._loaded_for_uid = ""
	CoinsManager._load_user()
	await get_tree().process_frame

	var stub := StubManager.new()
	add_child(stub)
	var home = HomeScreen.new()
	home.game_manager = stub
	stub.add_child(home)
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://rebrand_home.png")
	print("shot  %s" % ProjectSettings.globalize_path("user://rebrand_home.png"))
	print("popup still pending after showing? -> ", CoinsManager.has_unseen_rebrand_grant())
	get_tree().quit()
