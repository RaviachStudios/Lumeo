extends Node

# Screenshot harness for the main menu's two pieces of hardware: the START button
# and the logo's gold "O". Saves the whole screen plus tight crops of each, and a
# filmstrip of the START accent through its colour wheel.
#
#   godot --path . tools/menu_shot.tscn --resolution 1280x720
#
# Not shipped with the game; developer harness.

const HomeScreen := preload("res://home_screen.gd")

class StubManager extends Control:
	var welcome_prompt_shown := true
	func await_gl_stable() -> void:
		pass

var _home

func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://prefs.cfg")
	cfg.set_value("tutorial", "seen", true)
	cfg.save("user://prefs.cfg")

	FirebaseManager.sign_in()
	FirebaseManager.set_display_name("Tester")
	await get_tree().process_frame

	var stub := StubManager.new()
	add_child(stub)
	_home = HomeScreen.new()
	_home.game_manager = stub
	stub.add_child(_home)

	await get_tree().create_timer(3.0).timeout
	await _shot("menu_full")
	await _crop("menu_start", _home._start_lm["wrap"], 40.0)
	await _crop("menu_o", _home._logo_box, 0.0)
	await _crop("menu_o_zoom", _home._o_frame.get_parent(), 8.0, 4)
	await _crop("menu_start_zoom", _home._start_lm["wrap"], -40.0, 2)

	# The accent through the wheel: one shot per leg boundary. The colour cycle is a
	# looping tween that re-applies its own value every frame, so it has to be killed
	# before a hand-set colour will survive to the next draw.
	for t in get_tree().get_processed_tweens():
		t.kill()
	for i in 6:
		_home._play_accent_tick(float(i))
		await get_tree().process_frame
		await _crop("menu_hue_%d" % i, _home._start_lm["wrap"], 40.0)

	# Pressed state.
	_home._on_lm_press(null)
	_home._on_o_press()
	await get_tree().create_timer(0.20).timeout
	await _crop("menu_start_down", _home._start_lm["wrap"], 40.0)
	await _crop("menu_o_down", _home._logo_box, 0.0)
	get_tree().quit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % name)
	print("shot  %s" % ProjectSettings.globalize_path("user://%s.png" % name))

func _crop(name: String, node: Control, pad: float, zoom: int = 1) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var r := node.get_global_rect().grow(pad)
	var ri := Rect2i(Vector2i(r.position), Vector2i(r.size))
	ri = ri.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if ri.size.x < 2 or ri.size.y < 2:
		print("crop %s: empty rect %s" % [name, str(r)])
		return
	var sub := img.get_region(ri)
	if zoom > 1:
		sub.resize(ri.size.x * zoom, ri.size.y * zoom, Image.INTERPOLATE_NEAREST)
	sub.save_png("user://%s.png" % name)
	print("shot  %s  %s" % [ProjectSettings.globalize_path("user://%s.png" % name), str(ri)])
