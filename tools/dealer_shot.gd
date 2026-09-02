extends Node
# A big picture of the croupier on his own, at the angle the player sees him from,
# so the ASSET can be read — the gameplay filmstrips draw him ninety pixels tall.
#
#   Godot_v4.7-stable_win64_console.exe --path . tools/dealer_shot.tscn -- <clip>
#
#     clip  rest | deal | quick | dance   (default deal)
#
# Writes res://shot_dealer_<clip>.png: a 3x2 grid of beats through that clip.

const W := 1600
const H := 900
const CELL_W := 533
const CELL_H := 450

func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var clip := String(args[0]) if args.size() > 0 else "deal"
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL_W, CELL_H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.09, 0.06)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.45, 0.40)
	e.ambient_light_energy = 0.6
	env.environment = e
	vp.add_child(env)

	# a stand-in felt, so the contact shadows and the green bounce have something
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	vp.add_child(sun)

	var felt := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	felt.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.10, 0.38, 0.24)
	felt.material_override = fm
	felt.layers = CasinoDealer.BG_LAYER
	vp.add_child(felt)

	var cam := Camera3D.new()
	cam.fov = 46.0
	cam.cull_mask = CasinoDealer.BG_LAYER
	vp.add_child(cam)
	cam.current = true

	var d := CasinoDealer.new()
	vp.add_child(d)
	d.construct()
	# seat him the way `place` would on a mid-size board, without needing one
	d._felt = CasinoWorld.CARD_Y
	d._card = 1.1
	d._s = 1.6
	d._seat(-4.6)
	# ...including the measuring `place` would have done. Without it every clip's
	# release time is zero, the phase maps onto nothing, and the whole wind-up
	# renders as the rest pose — which looks exactly like a dealer who never
	# reaches for the deck.
	d._derive()
	d._placed = true
	d._mi.visible = true

	# the player's eye: above and in front, looking down at the table's middle
	cam.global_position = Vector3(0.0, 6.4, 8.2)
	cam.look_at(Vector3(0.0, 0.4, -1.6), Vector3.UP)

	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	var beats := _beats(clip)
	for i in beats.size():
		var b: Array = beats[i]
		_apply(d, clip, b[0])
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var tex := vp.get_texture().get_image()
		var x := (i % 3) * CELL_W
		var y := int(i / 3) * CELL_H
		img.blit_rect(tex, Rect2i(Vector2i.ZERO, tex.get_size()), Vector2i(x, y))
	var out := "res://shot_dealer_%s.png" % clip
	img.save_png(ProjectSettings.globalize_path(out))
	print("wrote ", out)
	get_tree().quit()

func _beats(clip: String) -> Array:
	match clip:
		"rest": return [[0.0], [0.7], [1.4], [2.1], [2.8], [3.5]]
		"dance": return [[0.30], [0.55], [0.90], [1.35], [1.75], [2.20]]
		_: return [[-1.0], [-0.55], [-0.15], [0.0], [0.25], [0.75]]

func _apply(d: CasinoDealer, clip: String, t: float) -> void:
	var at := Vector3(0.0, CasinoWorld.CARD_Y, 1.1)
	match clip:
		"rest":
			d.rest()
			d.idle(t)
		"dance":
			d.dance(t, 2.5)
		"quick":
			d.deal(t, at)
		_:
			d.deal(t, at)
