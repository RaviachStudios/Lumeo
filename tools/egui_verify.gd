extends Node
# Acceptance check for easy_game_ui.gd (the three-button EASY board), modelled on
# tools/hgui_verify.gd. Verifies the claims a screenshot cannot: exactly three
# independent buttons in a triangle, the authored spacing left alone, colour
# separation, one flat plane seen in perspective, per-button input and animation
# isolation, stationary frames, an indicator nowhere near the buttons, the frame
# cosmetic reaching all three bezels, and nothing cropped.
#   Godot_..._console.exe --path . tools/egui_verify.tscn        (needs a real GPU)

const W := 1920
const H := 1080
# The board's three colour keys, in the index order game.gd's sequence draws from.
const ORDER := ["Cyan", "Yellow", "Magenta"]
# The GLB authors the triangle at this circumradius, and the device is expected to
# leave it exactly there (unlike Medium/Hard, which get pushed out 15%).
const AUTHORED_RADIUS := 1.414508
const FRAME_RADIUS := 1.0
# The two buttons at the BACK of the board, and the one at the front.
const BACK := ["Cyan", "Yellow"]
const FRONT := "Magenta"

var _dev: EasyGameUI
var _vp: SubViewport
var _dev_vp: SubViewport
var _cam: Camera3D
var _board: Node3D
var _fails := 0
var _signal_log: Array[String] = []

func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(W, H)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var bg := ColorRect.new()
	bg.color = Color8(4, 5, 7)
	bg.size = Vector2(W, H)
	_vp.add_child(bg)
	_dev = EasyGameUI.new()
	_dev.size = Vector2(W, H)
	_vp.add_child(_dev)
	await get_tree().process_frame
	_dev.configure(3, [])
	_dev.set_level(12)
	_dev.color_pressed.connect(func(n: String) -> void: _signal_log.append(n))
	for c in _dev.get_children():
		if c is SubViewportContainer:
			_dev_vp = (c as SubViewportContainer).get_child(0) as SubViewport
	for c in _dev_vp.get_children():
		if c is Camera3D:
			_cam = c
	_board = _dev.find_child("MemoryGame_UI", true, false) as Node3D
	for _i in 10:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	_check_no_wheel()
	_check_hierarchy()
	_check_spacing()
	_check_plane()
	_check_colours()
	await _check_input()
	await _check_animation()
	_check_indicator()
	_check_frames()
	_check_composition()

	print("\n==== ", "ALL CHECKS PASSED" if _fails == 0 else "%d CHECK(S) FAILED" % _fails, " ====")
	get_tree().quit(_fails)

func _ok(pass_: bool, what: String, detail: String = "") -> void:
	if not pass_:
		_fails += 1
	print("  [%s] %s%s" % ["PASS" if pass_ else "FAIL", what, ("  -- " + detail) if detail != "" else ""])

func _holder(key: String) -> Node3D:
	return _board.find_child("Button_%s" % key, true, false) as Node3D

# 0. The old device is gone from easy. Nothing anywhere in the tree is a
# SimonWheel, and easy's difficulty setup now describes a three-button game.
func _check_no_wheel() -> void:
	print("\n-- the old four-colour wheel is gone --")
	var wheels := 0
	for n in _find_all(_dev):
		if n is SimonWheel:
			wheels += 1
	_ok(wheels == 0, "no SimonWheel anywhere in the easy device", "%d found" % wheels)
	_ok(_dev is MemoryGameUI, "easy plays on the same modelled-board class as moderate/hard")
	GameState.set_difficulty("easy")
	_ok(GameState.num_colors == 3, "easy is a three-colour game", str(GameState.num_colors))
	# Everything else about easy's difficulty is untouched.
	_ok(is_equal_approx(GameState.flash_time, 0.7), "easy flash time unchanged", str(GameState.flash_time))
	_ok(is_equal_approx(GameState.flash_gap, 0.25), "easy flash gap unchanged", str(GameState.flash_gap))
	_ok(is_equal_approx(GameState.speed_increase, 0.008), "easy ramp unchanged",
		str(GameState.speed_increase))

func _find_all(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_find_all(c))
	return out

# 1. Exactly three buttons, the GLB hierarchy intact, nothing merged or rebuilt.
func _check_hierarchy() -> void:
	print("\n-- hierarchy (the GLB is untouched) --")
	_ok(_board != null, "GLB scene instantiated")
	for key: String in ORDER:
		var h := _holder(key)
		var s := _board.find_child("Button_%s_Surface" % key, true, false)
		var f := _board.find_child("Button_%s_Frame" % key, true, false)
		_ok(h != null and s != null and f != null and s.get_parent() == h and f.get_parent() == h,
			"Button_%s / _Surface + _Frame under it" % key)
	var meshes := _board.find_children("*", "MeshInstance3D", true, false).size()
	_ok(meshes == 6, "exactly three buttons, no meshes merged", "%d MeshInstance3D (expected 6)" % meshes)
	var ap := _dev.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clips: PackedStringArray = ap.get_animation_list() if ap != null else PackedStringArray()
	_ok(clips.size() == 3, "three imported Press_* clips", str(clips))
	var all_there := true
	for key: String in ORDER:
		if not ap.has_animation("Press_%s" % key):
			all_there = false
	_ok(all_there, "one clip per colour key, named as the asset names them")
	# No fourth button, no centre module, no wheel remnant.
	_ok(_board.get_child_count() == 3, "the board holds the three buttons and nothing else",
		"%d children" % _board.get_child_count())
	_ok(_dev._count == 3 and _dev._keys.size() == 3, "the device drives three buttons",
		"%d / %s" % [_dev._count, str(_dev._keys)])

# The asset already spaces this board correctly, so the device must NOT push it
# out the way it does the other two.
func _check_spacing() -> void:
	print("\n-- spacing (authored, not pushed) --")
	var radii: Array[float] = []
	for key: String in ORDER:
		var p := _holder(key).position
		radii.append(Vector2(p.x, p.z).length())
	var even := true
	for v: float in radii:
		if absf(v - AUTHORED_RADIUS) > 0.001:
			even = false
	_ok(even, "all three still at the authored circumradius (equal angles kept)",
		"radii %s vs %.4f" % [str(radii), AUTHORED_RADIUS])
	var gaps: Array[float] = []
	var min_gap := INF
	for i in ORDER.size():
		for j in range(i + 1, ORDER.size()):
			var d := _holder(ORDER[i]).position.distance_to(_holder(ORDER[j]).position)
			gaps.append(d)
			min_gap = minf(min_gap, d - FRAME_RADIUS * 2.0)
	var equilateral := true
	for d: float in gaps:
		if absf(d - gaps[0]) > 0.001:
			equilateral = false
	_ok(equilateral, "the three sit on an equilateral triangle", str(gaps))
	# Medium and Hard reach a 0.47 gap only after their 15% push. This board is
	# there as authored, which is why _spacing is 1.0.
	_ok(min_gap > 0.40 and min_gap < 0.55, "frames have the same breathing room as the other boards",
		"gap %.3f" % min_gap)
	for key: String in ORDER:
		var aabb := _dev.surface_mesh(key).get_aabb()
		_ok(absf(aabb.size.x - 1.49) < 0.001 and absf(aabb.size.y - 0.28) < 0.001,
			"Button_%s surface is still its authored size" % key, str(aabb.size))

# One coherent physical plane, seen in perspective from above. The tilt is the
# camera's; no button and no board node is rotated.
func _check_plane() -> void:
	print("\n-- one tilted tabletop --")
	for key: String in ORDER:
		var h := _holder(key)
		_ok(absf(h.position.y) < 0.0001, "Button_%s sits on the board plane" % key,
			"y=%.4f" % h.position.y)
		_ok(h.quaternion.is_equal_approx(Quaternion.IDENTITY),
			"Button_%s is not individually rotated" % key, str(h.rotation_degrees))
	_ok(_cam.projection == Camera3D.PROJECTION_PERSPECTIVE, "camera is perspective, not ortho")
	var elev := rad_to_deg(asin(_cam.global_transform.basis.z.normalized().y))
	_ok(elev > 20.0 and elev < 50.0, "tilt is present but nowhere near top-down",
		"%.1f deg above the board" % elev)
	# The two back buttons sit higher in frame than the front one...
	var front_y := _cam.unproject_position(_holder(FRONT).position).y
	for key: String in BACK:
		var back_y := _cam.unproject_position(_holder(key).position).y
		_ok(back_y < front_y - 200.0, "%s sits well above %s in frame" % [key, FRONT],
			"y %.0f vs %.0f" % [back_y, front_y])
		# ...and are further away, which is what makes it a tabletop, not a card.
		var back_d := _cam.global_position.distance_to(_holder(key).position)
		var front_d := _cam.global_position.distance_to(_holder(FRONT).position)
		_ok(back_d > front_d * 1.15, "%s really is further from the camera" % key,
			"%.2f vs %.2f" % [back_d, front_d])
		var back_w := _cam.unproject_position(_holder(key).position + Vector3(1, 0, 0)).x \
			- _cam.unproject_position(_holder(key).position + Vector3(-1, 0, 0)).x
		var front_w := _cam.unproject_position(_holder(FRONT).position + Vector3(1, 0, 0)).x \
			- _cam.unproject_position(_holder(FRONT).position + Vector3(-1, 0, 0)).x
		_ok(front_w > back_w * 1.15, "  ...and is drawn smaller, so the perspective is real",
			"back %.0f px wide vs front %.0f px" % [back_w, front_w])
	# The two back buttons are level with each other — the camera has no roll.
	var l := _cam.unproject_position(_holder("Cyan").position)
	var r := _cam.unproject_position(_holder("Yellow").position)
	_ok(absf(l.y - r.y) < 1.0, "the two back buttons are level", "%.1f vs %.1f" % [l.y, r.y])
	# Depth reads: the raised surface and the frame it sits in project apart.
	var c := _holder(FRONT).position
	var lip := _cam.unproject_position(c + Vector3(0.0, 0.525, 0.745)).y
	var rim := _cam.unproject_position(c + Vector3(0.0, 0.0, 1.0)).y
	_ok(rim - lip > 25.0, "frame thickness and the raised surface are both visible",
		"%.0f px between the surface lip and the frame rim" % (rim - lip))

# The three colours the asset authors, and how far apart they read.
func _check_colours() -> void:
	print("\n-- palette separation --")
	var img := _vp.get_texture().get_image()
	var got := {}
	for key: String in ORDER:
		var s := _cam.unproject_position(_holder(key).position + Vector3(0.0, 0.525, 0.0))
		var c := img.get_pixel(int(s.x), int(s.y))
		got[key] = Vector3(round(c.r * 255.0), round(c.g * 255.0), round(c.b * 255.0))
		print("      %-8s renders (%d,%d,%d)" % [key, got[key].x, got[key].y, got[key].z])
	# Each one is the hue its name claims: cyan is green+blue with least red,
	# yellow is red+green with least blue, magenta is red+blue with least green.
	var cy: Vector3 = got["Cyan"]
	var ye: Vector3 = got["Yellow"]
	var ma: Vector3 = got["Magenta"]
	_ok(cy.x < cy.y and cy.x < cy.z, "Cyan is least red", str(cy))
	_ok(ye.z < ye.x and ye.z < ye.y, "Yellow is least blue", str(ye))
	_ok(ma.y < ma.x and ma.y < ma.z, "Magenta is least green", str(ma))
	var worst := INF
	var worst_pair := ""
	for i in ORDER.size():
		for j in range(i + 1, ORDER.size()):
			var d: float = ((got[ORDER[i]] as Vector3) - (got[ORDER[j]] as Vector3)).length()
			if d < worst:
				worst = d
				worst_pair = "%s/%s" % [ORDER[i], ORDER[j]]
	_ok(worst > 80.0, "closest pair of the three is well separated",
		"%s at %.0f" % [worst_pair, worst])

# All three are independently hit-testable, and everything between them is dead.
func _check_input() -> void:
	print("\n-- input --")
	for i in ORDER.size():
		var key: String = ORDER[i]
		var c := _holder(key).position
		var hit := _dev.segment_at_point(_cam.unproject_position(c + Vector3(0.0, 0.5, 0.0)))
		_ok(hit == i, "tap centre of %s -> index %d" % [key, i], "got %d" % hit)
		var edge := _dev.segment_at_point(
			_cam.unproject_position(c + Vector3(0.62, 0.5, 0.0)))
		_ok(edge == i, "tap off-centre on %s" % key, "got %d" % edge)
	# The tap TARGET — the raised coloured top, which is what a player aims at — must
	# answer correctly on every one of its pixels, with no soft edge and no pixel
	# stolen by a neighbour. Swept per button rather than sampled at a few points.
	#
	# The whole button (frame rim included) is deliberately NOT held to that: the
	# Area3D is a cylinder of radius 1.12 around a frame of radius 1.0, so each
	# collider reaches ~12% past what it draws, and a nearer button's margin can
	# cover the far rim of one behind it. That forgiveness is the parent's, it is
	# what Medium and Hard have always shipped, and it is measurable: the far
	# buttons' rims read 79.4% correct on Medium and 76.8% on Hard against 80.5%
	# here. Easy is not a special case in either direction.
	for i in ORDER.size():
		var key: String = ORDER[i]
		var top := _screen_hull(key, 0.745, 0.525)
		var inside := 0
		var right := 0
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for pt: Vector2 in top:
			mn = mn.min(pt)
			mx = mx.max(pt)
		var y := int(mn.y)
		while y <= int(mx.y):
			var x := int(mn.x)
			while x <= int(mx.x):
				var p := Vector2(x, y)
				if Geometry2D.is_point_in_polygon(p, top):
					inside += 1
					if _dev.segment_at_point(p) == i:
						right += 1
				x += 2
			y += 2
		_ok(inside > 1000 and right == inside,
			"every pixel of %s's coloured top answers as index %d" % [key, i],
			"%d/%d over %d px of top" % [right, inside, inside])
	# Index order is what pairs each button with its existing per-index tone.
	for i in ORDER.size():
		_ok(_dev.index_of(ORDER[i].to_lower()) == i, "index_of(%s) == %d" % [ORDER[i].to_lower(), i])
	# Well clear of the board on either side, nothing answers at all.
	for side: float in [-1.0, 1.0]:
		var far := Vector3(side * 3.6, 0.0, -0.707254)
		_ok(_dev.segment_at_point(_cam.unproject_position(far)) == -1,
			"the board plane beyond the outer frames is dead", "x=%.1f" % far.x)
	_ok(_dev.segment_at_point(Vector2(-50.0, -50.0)) == -1, "a tap off the board is dead")
	# Nothing can answer with an index the three-value sequence cannot produce.
	var seen := {}
	for y2 in range(0, H, 7):
		for x2 in range(0, W, 7):
			var idx2 := _dev.segment_at_point(Vector2(x2, y2))
			if idx2 >= 0:
				seen[idx2] = true
	var keys := seen.keys()
	keys.sort()
	_ok(keys == [0, 1, 2], "the board only ever answers 0, 1 or 2", str(keys))

	_dev.input_enabled = true
	for i in ORDER.size():
		_signal_log.clear()
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = _cam.unproject_position(_holder(ORDER[i]).position + Vector3(0.0, 0.5, 0.0))
		_dev._input(ev)
		await get_tree().process_frame
		_ok(_signal_log == [ORDER[i].to_lower()],
			"pressing %s emits color_pressed(\"%s\")" % [ORDER[i], ORDER[i].to_lower()],
			str(_signal_log))
	_dev.input_enabled = false

# Pressing one colour sinks that colour's SURFACE only. No frame ever moves.
func _check_animation() -> void:
	print("\n-- press animation --")
	var ap := _dev.find_child("AnimationPlayer", true, false) as AnimationPlayer
	await _rest(ap)
	var rest := _capture()
	for i in ORDER.size():
		var key: String = ORDER[i]
		_dev.set_press(i, 1.0)
		for _f in 8:
			await get_tree().process_frame
		ap.seek(0.10, true)
		await get_tree().process_frame
		var now := _capture()
		var moved: Array[String] = []
		for n: String in now:
			if (now[n] as Vector3).distance_to(rest[n]) > 0.0005:
				moved.append(n)
		_ok(moved == ["Button_%s_Surface" % key],
			"Press_%s moves only Button_%s_Surface" % [key, key], "moved: %s" % str(moved))
		var deepest := 0.0
		var t := 0.0
		while t <= 0.29:
			ap.seek(t, true)
			deepest = minf(deepest, _dev.surface_mesh(key).global_position.y
				- (rest["Button_%s_Surface" % key] as Vector3).y)
			t += 0.0167
		_ok(absf(deepest + 0.115) < 0.003, "  ...downward by the authored 0.115",
			"deepest %.4f" % deepest)
		_dev.set_press(i, 0.0)
		await _rest(ap)
	var tracks_frames := false
	for clip: String in ap.get_animation_list():
		var a := ap.get_animation(clip)
		for tr in a.get_track_count():
			if String(a.track_get_path(tr)).contains("_Frame"):
				tracks_frames = true
	_ok(not tracks_frames, "no clip animates any frame — frames are stationary by construction")

	# A highlight (sequence playback) brightens without sinking anything.
	await _rest(ap)
	var before := _capture()
	_dev.set_lit(0, true)
	for _f in 12:
		await get_tree().process_frame
	var still := true
	var after := _capture()
	for n: String in after:
		if (after[n] as Vector3).distance_to(before[n]) > 0.0005:
			still = false
	_ok(still, "set_lit lights a button without moving any geometry")
	var lit_mat := _dev.surface_mesh("Cyan").get_surface_override_material(0) as StandardMaterial3D
	var idle_mat := _dev.surface_mesh("Yellow").get_surface_override_material(0) as StandardMaterial3D
	var lit_e := lit_mat.emission.srgb_to_linear().b
	_dev.set_lit(0, false)
	for _f in 20:
		await get_tree().process_frame
	var back_e := lit_mat.emission.srgb_to_linear().b
	_ok(lit_e > back_e * 1.8, "  ...by raising its emission, and it comes back down",
		"lit %.3f -> idle %.3f" % [lit_e, back_e])
	_ok(idle_mat != null, "each button drives its own material copy")

# The convex hull, in screen space, of one button's circle of radius `r` at
# height `y` on the button's own axis.
func _screen_hull(key: String, r: float, y: float) -> PackedVector2Array:
	var c := _holder(key).position
	var pts := PackedVector2Array()
	for i in 64:
		var a := TAU * float(i) / 64.0
		pts.append(_cam.unproject_position(c + Vector3(cos(a) * r, y, sin(a) * r)))
	return Geometry2D.convex_hull(pts)

func _rest(ap: AnimationPlayer) -> void:
	ap.stop()
	ap.seek(0.0, true)
	for _f in 6:
		await get_tree().process_frame

func _capture() -> Dictionary:
	var out := {}
	for n in _board.find_children("*", "MeshInstance3D", true, false):
		out[n.name] = (n as MeshInstance3D).global_position
	return out

# The round indicator is separate Godot UI, outside all three buttons, and not in
# the middle of the triangle where the old wheel's hub used to be.
func _check_indicator() -> void:
	print("\n-- round indicator --")
	_ok(_dev._readout == null and _dev_vp.find_child("StagePlate", true, false) == null,
		"nothing was added to the board itself")
	var pill: Panel = _dev._pill
	_ok(pill != null and pill.get_parent() == _dev, "it is a 2D Control over the board")
	if pill == null:
		return
	_ok(_dev._pill_number.text == "12", "shows the round it was given",
		_dev._pill_number.text)
	_dev.set_level(148)
	_ok(_dev._pill_number.text == "148", "set_level(148)", _dev._pill_number.text)
	var wide := pill.size.x
	_dev.set_level(7)
	_ok(pill.size.x < wide, "the pill resizes to its number", "%.0f -> %.0f" % [wide, pill.size.x])
	var r := Rect2(pill.position, pill.size)
	_ok(r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= W and r.end.y <= H,
		"on screen", str(r))
	# Clear of every button's silhouette.
	var overlaps := ""
	for key: String in ORDER:
		var c := _holder(key).position
		for i in 48:
			var a := TAU * float(i) / 48.0
			for pt: Vector3 in [c + Vector3(cos(a), 0.0, sin(a)),
					c + Vector3(cos(a) * 0.745, 0.525, sin(a) * 0.525)]:
				if r.has_point(_cam.unproject_position(pt)):
					overlaps = key
	_ok(overlaps == "", "clear of all three buttons on screen", "overlaps %s" % overlaps)
	# Clear of game.gd's status pill, which is centred 84 px up from the bottom.
	_ok(r.end.y <= H - 84.0 + 0.5, "clear of the status pill's row",
		"bottom %.0f vs %.0f" % [r.end.y, H - 84.0])
	_ok(r.position.y > H * 0.5, "sits in the bottom corner, not over the play area")
	# The middle of the triangle stays empty — no hub, no centre display.
	var centre := _cam.unproject_position(Vector3(0.0, 0.0, 0.0))
	_ok(not r.has_point(centre), "and not in the middle of the triangle either", str(centre))

# The global button-frame cosmetic dresses all three bezels and nothing else. The
# same eighteen meshes that fit Medium's five buttons and Hard's six have to fit
# Easy's three at the identity transform, with no rescaling and no per-difficulty
# special case — that claim is what this checks on the real board.
func _check_frames() -> void:
	print("\n-- button-frame cosmetics --")
	var before := {}
	for key: String in ORDER:
		before[key] = [_dev.surface_mesh(key).get_surface_override_material(0),
			_dev.surface_mesh(key).get_surface_override_material(1),
			_dev.frame_mesh(key).get_surface_override_material(1)]
	for id: String in ButtonFrames.ORDER:
		if id == ButtonFrames.DEFAULT_ID:
			continue
		_dev.apply_button_frame(id)
		_assert_worn(id)
	# The three skin-bound frames are not in ORDER but must dress this board too.
	for skin: String in ["arcade", "casino", "lunapark"]:
		var id := ButtonFrames.effective_frame(ButtonFrames.DEFAULT_ID, skin)
		_ok(ButtonFrames.is_cosmetic(id), "skin \"%s\" resolves to a frame" % skin, id)
		_dev.apply_button_frame(id)
		_assert_worn("%s -> %s" % [skin, id])
	# The priority ladder: an active skin's frame outranks the equipped cosmetic,
	# and with no skin the equipped one is what shows.
	_ok(ButtonFrames.effective_frame("purple_neon", "arcade")
		== ButtonFrames.effective_frame(ButtonFrames.DEFAULT_ID, "arcade"),
		"an active skin's frame outranks the equipped cosmetic")
	_ok(ButtonFrames.effective_frame("purple_neon", "") == "purple_neon",
		"with no skin, the equipped cosmetic is what shows")

	_dev.apply_button_frame(ButtonFrames.DEFAULT_ID)
	var cleared := true
	var authored := true
	var gone := true
	for key: String in ORDER:
		var mi := _dev.frame_mesh(key)
		if mi.get_surface_override_material(0) != null:
			cleared = false
		if _dev.cosmetic_frame(key) != null:
			gone = false
		var m := mi.mesh.surface_get_material(0)
		if not (m is StandardMaterial3D) or not String(m.resource_name).ends_with("_Frame"):
			authored = false
	_ok(cleared, "default clears the override on all three")
	_ok(gone, "default frees the cosmetic mesh on all three")
	_ok(authored, "the GLB's own Mat_<Colour>_Frame is what comes back")
	var untouched := true
	for key: String in ORDER:
		if _dev.surface_mesh(key).get_surface_override_material(0) != before[key][0]: untouched = false
		if _dev.surface_mesh(key).get_surface_override_material(1) != before[key][1]: untouched = false
		if _dev.frame_mesh(key).get_surface_override_material(1) != before[key][2]: untouched = false
	_ok(untouched, "surfaces, rims and under-glows are never touched")

func _assert_worn(label: String) -> void:
	var worn: Array[MeshInstance3D] = []
	var all_there := true
	for key: String in ORDER:
		var mi := _dev.cosmetic_frame(key)
		if mi == null:
			all_there = false
		else:
			worn.append(mi)
	_ok(all_there, "\"%s\" is worn by all three buttons" % label)
	if not all_there:
		return
	var one_mesh := true
	var at_identity := true
	var one_matset := true
	var hidden := true
	for i in worn.size():
		var mi := worn[i]
		if mi.mesh != worn[0].mesh:
			one_mesh = false
		if mi.transform != Transform3D.IDENTITY:
			at_identity = false
		var m0 := mi.get_surface_override_material(0)
		if not (m0 is ShaderMaterial) or m0 != worn[0].get_surface_override_material(0):
			one_matset = false
		if _dev.frame_mesh(ORDER[i]).get_surface_override_material(0) != ButtonFrames.hidden_material():
			hidden = false
	_ok(one_mesh, "  ...as ONE shared mesh (no per-button copy)")
	_ok(at_identity, "  ...at the identity transform on every button")
	_ok(one_matset, "  ...sharing one material set")
	_ok(hidden, "  ...with the stock bezel's metal hidden")

# Nothing cropped, and the board fills the frame.
func _check_composition() -> void:
	print("\n-- composition --")
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for key: String in ORDER:
		var c := _holder(key).position
		for i in 32:
			var a := TAU * float(i) / 32.0
			for pt: Vector3 in [c + Vector3(cos(a), 0.0, sin(a)),
					c + Vector3(cos(a) * 0.745, 0.525, sin(a) * 0.745)]:
				var s := _cam.unproject_position(pt)
				mn = mn.min(s)
				mx = mx.max(s)
	_ok(mn.x > 0.0 and mn.y > 0.0 and mx.x < W and mx.y < H, "no button is cropped",
		"x[%.0f..%.0f] y[%.0f..%.0f]" % [mn.x, mx.x, mn.y, mx.y])
	var fill_x := (mx.x - mn.x) / float(W)
	var fill_y := (mx.y - mn.y) / float(H)
	_ok(fill_x > 0.60 and fill_y > 0.55, "the board fills the frame",
		"%.0f%% wide, %.0f%% tall" % [fill_x * 100.0, fill_y * 100.0])
	# Three buttons on this much screen should be BIG — that is the whole point of
	# giving easy its own fit rather than borrowing Hard's.
	var widest := 0.0
	for key: String in ORDER:
		var c := _holder(key).position
		var w := _cam.unproject_position(c + Vector3(1, 0, 0)).x \
			- _cam.unproject_position(c + Vector3(-1, 0, 0)).x
		widest = maxf(widest, w)
		print("      %-8s is %.0f px across" % [key, w])
	_ok(widest > 380.0, "the buttons are large enough to feel tactile",
		"widest %.0f px of %d" % [widest, W])
	# The HUD game.gd draws over the board must not land on any button. The rects
	# below are game.gd's own, in fractions of its 1280x720 design viewport so they
	# scale with whatever this harness renders at: the watch-ad pill (top-left, sized
	# generously at 360 px), Quit (top-right), the coins pill under it, and the
	# status pill along the bottom centre.
	var hud := {
		"watch-ad button": Rect2(0.0156, 0.0278, 0.2813, 0.0666),
		"quit button": Rect2(0.9438, 0.0278, 0.0406, 0.0722),
		"coins pill": Rect2(0.8953, 0.1083, 0.0891, 0.0611),
		"status pill": Rect2(0.3438, 0.8833, 0.3125, 0.0723),
		"round pill": Rect2(_dev._pill.position.x / W, _dev._pill.position.y / H,
			_dev._pill.size.x / W, _dev._pill.size.y / H),
	}
	for name: String in hud:
		var r: Rect2 = hud[name]
		var px := Rect2(r.position * Vector2(W, H), r.size * Vector2(W, H))
		var hits := ""
		for key: String in ORDER:
			var c := _holder(key).position
			for i in 48:
				var a := TAU * float(i) / 48.0
				for pt: Vector3 in [c + Vector3(cos(a), 0.0, sin(a)),
						c + Vector3(cos(a) * 0.745, 0.525, sin(a) * 0.745)]:
					if px.has_point(_cam.unproject_position(pt)):
						hits = key
		_ok(hits == "", "the %s does not sit on a button" % name, "hits %s" % hits)
