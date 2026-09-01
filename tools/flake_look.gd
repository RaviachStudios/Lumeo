extends Node
# ONE Ice Kingdom snowflake, at ACTUAL gameplay size, through the real board.
#
# ice_buttons_shot.tscn renders the Hard board at the Blender reference's 1920x1080
# so it can be put beside that render. This does the opposite job: it renders the
# board at the game's own 1280x720 design resolution — the size a flake is actually
# looked at on a phone — crops one button out of it at 1:1, and magnifies that crop
# with NEAREST so the silhouette, the bevels and the arm edges can be inspected as
# PIXELS rather than as a picture that has been resampled into looking fine.
#
# It also puts a NUMBER on the two things the quality pass is about, per flake:
#
#   sat    the mean saturation of the button's pixels. A colour-identification
#          game cannot have grey buttons, and both the ways this asset can go grey
#          (a white specular lobe on a saturated albedo, and the board's bright
#          ProceduralSky reflecting off roughness 0.13) do it silently.
#   grad   the standard deviation of luminance across the button's own pixels.
#          This is "does it have any shape at all" as a number: a self-lit flake is
#          one flat value and scores near zero however bright it is, and a lit one
#          has the arms, the bevel roll, the hub dome and the side wall all sitting
#          at different values, which is the entire point of the exercise.
#
#   Godot_..._console.exe --path . tools/flake_look.tscn [-- <Key>]
#
# Run WITHOUT --headless: it reads back a rendered image, and the dummy driver
# never draws (see the harness-hang note).

const ICE := preload("res://ice_buttons.gd")
const SHOT_W := 1280           # the game's own design resolution, not the render's
const SHOT_H := 720
const ORDER := ["Crimson", "Jade", "Cyan", "Amber", "Violet", "Magenta"]
const ZOOM := 4                # magnification of the single-flake crop
const HALF := 88               # half-width of that crop, in gameplay pixels

var _dev: HardGameUI
var _vp: SubViewport
var _dev_vp: SubViewport
var _cam: Camera3D
var _board: Node3D

func _ready() -> void:
	var pick := "Violet"
	for a in OS.get_cmdline_user_args():
		if ORDER.has(String(a)):
			pick = String(a)

	for _i in 8:
		await get_tree().process_frame     # let CoinsManager load the wallet
	CoinsManager.selected_theme = ICE.THEME_ID

	_vp = SubViewport.new()
	_vp.size = Vector2i(SHOT_W, SHOT_H)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_vp)
	var plate := ColorRect.new()
	plate.color = Color8(4, 5, 7)
	plate.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(plate)

	_dev = HardGameUI.new()
	_dev.input_enabled = false
	_dev.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(_dev)
	await get_tree().process_frame
	_dev.configure(6, [])
	_dev.set_level(12)

	for c in _dev.get_children():
		if c is SubViewportContainer:
			_dev_vp = (c as SubViewportContainer).get_child(0) as SubViewport
	for c in _dev_vp.get_children():
		if c is Camera3D:
			_cam = c
	_board = _dev.find_child("MemoryGame_UI", true, false) as Node3D
	print("ice skin worn: %s   msaa %d   skin lights %d"
		% [_dev.button_skin_id() == ICE.THEME_ID, _dev_vp.msaa_3d,
			(_dev_vp.get_node_or_null("SkinLights").get_child_count()
				if _dev_vp.get_node_or_null("SkinLights") != null else 0)])

	# What the board is ACTUALLY holding after the skin has been applied. Every
	# quality problem this asset has had so far was a material flag rather than a
	# mesh, and reading them back off the live board is the only way to be sure the
	# swap, the state machine and the per-button override chain all left them alone.
	var probe := _board.find_child("Button_Violet_Surface", true, false) as MeshInstance3D
	for i in probe.mesh.get_surface_count():
		var mm := probe.get_surface_override_material(i) as StandardMaterial3D
		if mm == null:
			mm = probe.mesh.surface_get_material(i) as StandardMaterial3D
		print("  Violet surf %d  shading %d  albedo %s  vcol %s  ambient_off %s  emis %s x%.2f  rough %.2f  metal %.2f"
			% [i, mm.shading_mode, str(mm.albedo_color), mm.vertex_color_use_as_albedo,
				mm.disable_ambient_light, str(mm.emission), mm.emission_energy_multiplier,
				mm.roughness, mm.metallic])
	var lit := _dev_vp.get_node_or_null("SkinLights")
	if lit != null:
		for l: Light3D in lit.get_children():
			print("  light  %-16s at %s  energy %.2f  spec %.2f  mask %d  visible %s"
				% [l.get_class(), str(l.position), l.light_energy, l.light_specular,
					l.light_cull_mask, l.visible])
	print("  buttons render layer %d" % probe.layers)

	await _settle(40)
	var img := await _grab()
	img.save_png("user://flake_board.png")
	print("shot  %s" % ProjectSettings.globalize_path("user://flake_board.png"))
	_report(img)
	_crop(img, pick)
	get_tree().quit()


# The button's centre on screen, at the height of the flake's own cap.
func _centre(key: String) -> Vector2:
	var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
	return _cam.unproject_position(holder.position + Vector3(0.0, 0.39, 0.0))


func _report(img: Image) -> void:
	print("--- per flake, at %dx%d ---" % [SHOT_W, SHOT_H])
	print("  key        mean rgb        sat    grad   lum min..max   px")
	for key: String in ORDER:
		_stats(img, key, "Surface")
	# The socket is measured separately and it matters: it is the piece the rig can
	# most easily overcook. It is a pale frosted disc at roughness 0.52, so it takes
	# far more diffuse than the polished cap does, and a rig tuned on the flake alone
	# renders it as a white plastic puck that outshines the button standing on it.
	print("  --- sockets ---")
	for key: String in ORDER:
		_stats(img, key, "Frame")


# The flake's OWN pixels, and nothing else.
#
# A box around the button is not a mask: the Ice Kingdom cave behind it is a bright
# blue, so a box average is mostly background and both statistics come out of the
# wall rather than out of the button. So the mask is built from the MESH — every
# vertex of the cap, put through the board's own camera — which is exact, costs one
# projection per vertex, and cannot drift if the camera fit or the spacing changes.
func _stats(img: Image, key: String, part: String = "Surface") -> void:
	var mi := _board.find_child("Button_%s_%s" % [key, part], true, false) as MeshInstance3D
	if mi == null or mi.mesh == null:
		print("  %-9s (no mesh)" % key)
		return
	var xf := mi.global_transform
	var seen: Dictionary = {}
	for s in mi.mesh.get_surface_count():
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in verts:
			var p := _cam.unproject_position(xf * v)
			var x := int(p.x)
			var y := int(p.y)
			if x < 1 or y < 1 or x >= SHOT_W - 1 or y >= SHOT_H - 1:
				continue
			seen[y * SHOT_W + x] = true
	if seen.is_empty():
		print("  %-9s (off screen)" % key)
		return
	var sum := Vector3.ZERO
	var lums := PackedFloat32Array()
	var lo := 1.0
	var hi := 0.0
	for k: int in seen:
		var p := img.get_pixel(k % SHOT_W, k / SHOT_W)
		var l := 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
		sum += Vector3(p.r, p.g, p.b)
		lums.append(l)
		lo = minf(lo, l)
		hi = maxf(hi, l)
	var n := float(lums.size())
	var mean := sum / n
	var mu := 0.0
	for l: float in lums:
		mu += l
	mu /= n
	var var_sum := 0.0
	for l: float in lums:
		var_sum += (l - mu) * (l - mu)
	var peak: float = maxf(mean.x, maxf(mean.y, mean.z))
	var trough: float = minf(mean.x, minf(mean.y, mean.z))
	var sat: float = 0.0 if peak <= 0.0 else (peak - trough) / peak
	print("  %-9s (%3d,%3d,%3d)   %.3f  %.4f  %.3f..%.3f  %d"
		% [key, int(mean.x * 255.0), int(mean.y * 255.0), int(mean.z * 255.0),
			sat, sqrt(var_sum / n), lo, hi, lums.size()])


# One flake, cut out at 1:1 and magnified with NEAREST so no resampling can smooth
# over an edge that is actually stair-stepped.
func _crop(img: Image, key: String) -> void:
	var c := _centre(key)
	var rect := Rect2i(int(c.x) - HALF, int(c.y) - HALF, HALF * 2, HALF * 2)
	var cut := img.get_region(rect)
	cut.save_png("user://flake_%s_1x.png" % key.to_lower())
	var big := cut.duplicate() as Image
	big.resize(HALF * 2 * ZOOM, HALF * 2 * ZOOM, Image.INTERPOLATE_NEAREST)
	big.save_png("user://flake_%s_%dx.png" % [key.to_lower(), ZOOM])
	print("crop  %s at %s, and %dx" % [key, str(rect), ZOOM])


func _settle(n: int) -> void:
	_dev.set_process(true)
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in n:
		await get_tree().process_frame


func _grab() -> Image:
	_dev.set_process(false)
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return _vp.get_texture().get_image()
