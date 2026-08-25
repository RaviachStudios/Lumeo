extends Node

# Screenshot harness for the Arena card's button pad. Saves the card at 1x and 4x,
# plus one frame per step of the idle pulse. Developer harness, not shipped.

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

	await _shot("arena_menu_full")
	var wrap: Control = _home._arena_card["wrap"]
	await _crop("arena_card", wrap, 6.0)
	await _rect("arena_card_zoom", wrap, Rect2(0, 0, 312, 124), 4)

	# every light on at once, to check placement against the buttons
	for t in get_tree().get_processed_tweens():
		t.kill()
	for n in _home._pad_lights:
		n.modulate.a = 1.0
	await _rect("arena_all_lit", wrap, Rect2(0, 0, 312, 124), 4)
	for n in _home._pad_lights:
		n.modulate.a = 0.0
	# one lit at a time
	for i in _home._pad_lights.size():
		_home._pad_lights[i].modulate.a = 1.0
		await _rect("arena_lit_%d" % i, wrap, Rect2(0, 0, 312, 124), 4)
		_home._pad_lights[i].modulate.a = 0.0
	get_tree().quit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://%s.png" % name)
	print("shot  %s" % ProjectSettings.globalize_path("user://%s.png" % name))

func _rect(name: String, node: Control, local: Rect2, zoom: int = 1) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var g := node.get_global_rect()
	var ri := Rect2i(Vector2i(g.position + local.position), Vector2i(local.size))
	ri = ri.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var sub := img.get_region(ri)
	if zoom > 1:
		sub.resize(ri.size.x * zoom, ri.size.y * zoom, Image.INTERPOLATE_NEAREST)
	sub.save_png("user://%s.png" % name)
	print("shot  %s  %s" % [ProjectSettings.globalize_path("user://%s.png" % name), str(ri)])

func _crop(name: String, node: Control, pad: float, zoom: int = 1) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var r := node.get_global_rect().grow(pad)
	var ri := Rect2i(Vector2i(r.position), Vector2i(r.size))
	ri = ri.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if ri.size.x < 2 or ri.size.y < 2:
		print("crop %s: empty" % name)
		return
	var sub := img.get_region(ri)
	if zoom > 1:
		sub.resize(ri.size.x * zoom, ri.size.y * zoom, Image.INTERPOLATE_NEAREST)
	sub.save_png("user://%s.png" % name)
	print("shot  %s  %s" % [ProjectSettings.globalize_path("user://%s.png" % name), str(ri)])
