extends Node
# Throwaway acceptance check for memory_game_ui.gd (V3 board). Verifies the claims
# a screenshot cannot: spacing, colour separation, that the five buttons really do
# lie on one plane, per-button input and animation isolation, a stationary frame,
# and a level readout that is nowhere near the middle and touches nothing.

const W := 1920
const H := 1080
const ORDER := ["Crimson", "Jade", "Cyan", "Amber", "Violet"]
# Radius the GLB authors the pentagon at, before MemoryGameUI spaces it out.
const AUTHORED_RADIUS := 1.83
const FRAME_RADIUS := 1.0

var _dev: MemoryGameUI
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
	_dev = MemoryGameUI.new()
	_dev.size = Vector2(W, H)
	_vp.add_child(_dev)
	await get_tree().process_frame
	_dev.configure(5, [])
	_dev.set_round_number(12)
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

	_check_hierarchy()
	_check_spacing()
	_check_plane()
	_check_colours()
	await _check_input()
	await _check_animation()
	_check_indicator()
	_check_composition()

	print("\n==== ", "ALL CHECKS PASSED" if _fails == 0 else "%d CHECK(S) FAILED" % _fails, " ====")
	get_tree().quit()

func _ok(pass_: bool, what: String, detail: String = "") -> void:
	if not pass_:
		_fails += 1
	print("  [%s] %s%s" % ["PASS" if pass_ else "FAIL", what, ("  -- " + detail) if detail != "" else ""])

func _holder(key: String) -> Node3D:
	return _board.find_child("Button_%s" % key, true, false) as Node3D

# The GLB hierarchy survives the import, and nothing was merged or rebuilt.
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
	_ok(meshes == 10, "no meshes merged", "%d MeshInstance3D (expected 10)" % meshes)
	var ap := _dev.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_ok(ap != null and ap.get_animation_list().size() == 5, "five imported Press_* clips")

# 1. The buttons are further apart than the asset authors them, by moving the
#    PARENTS only — every button keeps its authored size and orientation.
func _check_spacing() -> void:
	print("\n-- spacing --")
	var radii: Array[float] = []
	for key: String in ORDER:
		var p := _holder(key).position
		radii.append(Vector2(p.x, p.z).length())
	var r: float = radii[0]
	var even := true
	for v: float in radii:
		if absf(v - r) > 0.001:
			even = false
	_ok(even, "all five still on one circle (equal angular spacing kept)", "radii %s" % str(radii))
	var grew := r / AUTHORED_RADIUS
	_ok(grew >= 1.10 and grew <= 1.15, "radius grew 10-15%%", "%.1f%% (%.3f -> %.3f)" % [
		(grew - 1.0) * 100.0, AUTHORED_RADIUS, r])
	# Nearest neighbours, and the gap that opens between their frames.
	var min_gap := INF
	for i in ORDER.size():
		for j in range(i + 1, ORDER.size()):
			var a := _holder(ORDER[i]).position
			var b := _holder(ORDER[j]).position
			min_gap = minf(min_gap, a.distance_to(b) - FRAME_RADIUS * 2.0)
	var authored_gap := 2.0 * AUTHORED_RADIUS * sin(deg_to_rad(36.0)) - FRAME_RADIUS * 2.0
	_ok(min_gap > authored_gap * 2.0, "neighbouring frames have real breathing room",
		"gap %.3f, was %.3f" % [min_gap, authored_gap])
	# Sizes untouched.
	for key: String in ORDER:
		var mi := _dev.surface_mesh(key)
		var aabb := mi.get_aabb()
		_ok(absf(aabb.size.x - 1.49) < 0.001 and absf(aabb.size.y - 0.28) < 0.001,
			"Button_%s surface is still its authored size" % key, str(aabb.size))

# 3. One coherent physical plane: every button sits at the same height with no
#    rotation of its own. The tilt is the camera's, not the buttons'.
func _check_plane() -> void:
	print("\n-- one tilted plane --")
	for key: String in ORDER:
		var h := _holder(key)
		_ok(absf(h.position.y) < 0.0001, "Button_%s sits on the board plane" % key,
			"y=%.4f" % h.position.y)
		_ok(h.quaternion.is_equal_approx(Quaternion.IDENTITY),
			"Button_%s is not individually rotated" % key, str(h.rotation_degrees))
	_ok(_cam.projection == Camera3D.PROJECTION_PERSPECTIVE, "camera is perspective")
	var elev := rad_to_deg(asin(_cam.global_transform.basis.z.normalized().y))
	_ok(elev > 20.0 and elev < 50.0, "tilt is present but not extreme",
		"%.1f deg above the board" % elev)
	# 4 + 5. The far button really is higher in frame than the front two.
	var far_y := _cam.unproject_position(_holder("Cyan").position).y
	var near_y := minf(_cam.unproject_position(_holder("Crimson").position).y,
		_cam.unproject_position(_holder("Jade").position).y)
	_ok(far_y < near_y - 200.0, "back button sits well above the front two",
		"y %.0f vs %.0f" % [far_y, near_y])
	# 6. Depth reads: the raised surface and the frame it sits in project apart.
	var c := _holder("Crimson").position
	var lip := _cam.unproject_position(c + Vector3(0.0, 0.525, 0.745)).y
	var rim := _cam.unproject_position(c + Vector3(0.0, 0.0, 1.0)).y
	_ok(rim - lip > 25.0, "frame thickness and the raised surface are both visible",
		"%.0f px between the surface lip and the frame rim" % (rim - lip))

# 2. Jade must be clearly darker and deeper than Cyan, and still obviously green.
func _check_colours() -> void:
	print("\n-- palette separation --")
	var img := _vp.get_texture().get_image()
	var got := {}
	for key: String in ORDER:
		var s := _cam.unproject_position(_holder(key).position + Vector3(0.0, 0.525, 0.0))
		var c := img.get_pixel(int(s.x), int(s.y))
		got[key] = Vector3(round(c.r * 255.0), round(c.g * 255.0), round(c.b * 255.0))
		print("      %-8s renders (%d,%d,%d)" % [key, got[key].x, got[key].y, got[key].z])
	var jade: Vector3 = got["Jade"]
	var cyan: Vector3 = got["Cyan"]
	var target := Color("087a58")
	var want := Vector3(round(target.r * 255.0), round(target.g * 255.0), round(target.b * 255.0))
	_ok((jade - want).length() < 25.0, "Jade lands on the #087A58 target",
		"(%d,%d,%d) vs (%d,%d,%d)" % [jade.x, jade.y, jade.z, want.x, want.y, want.z])
	_ok(jade.length() < cyan.length() * 0.75, "Jade is clearly darker than Cyan",
		"luma %.0f vs %.0f" % [jade.length(), cyan.length()])
	_ok(jade.y > 60.0 and jade.y > jade.x + 40.0 and jade.y > jade.z + 15.0,
		"Jade is still visibly green, not black or teal", str(jade))
	_ok(cyan.y > 140.0 and cyan.z > 140.0, "Cyan stays bright", str(cyan))
	# Every pair must be far apart in colour.
	var worst := INF
	var worst_pair := ""
	for i in ORDER.size():
		for j in range(i + 1, ORDER.size()):
			var d: float = ((got[ORDER[i]] as Vector3) - (got[ORDER[j]] as Vector3)).length()
			if d < worst:
				worst = d
				worst_pair = "%s/%s" % [ORDER[i], ORDER[j]]
	_ok(worst > 80.0, "closest pair of colours is still well separated",
		"%s at %.0f" % [worst_pair, worst])

# All five buttons are independently hit-testable, and the gaps are dead.
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
	_ok(_dev.segment_at_point(_cam.unproject_position(Vector3(0.0, 0.02, 0.0))) == -1,
		"the empty middle is not a button")
	_ok(_dev.segment_at_point(_cam.unproject_position(
		Vector3(0.0, 0.02, -5.10))) == -1, "the dead board behind the back button is not one either")

	_dev.input_enabled = true
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = _cam.unproject_position(_holder("Amber").position + Vector3(0.0, 0.5, 0.0))
	_dev._input(ev)
	await get_tree().process_frame
	_ok(_signal_log == ["amber"], "color_pressed emits \"amber\"", str(_signal_log))
	_dev.input_enabled = false

# 7. Pressing one colour sinks that colour's SURFACE only. No frame ever moves.
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
	# The frames are in no clip at all.
	var tracks_frames := false
	for clip: String in ap.get_animation_list():
		var a := ap.get_animation(clip)
		for tr in a.get_track_count():
			if String(a.track_get_path(tr)).contains("_Frame"):
				tracks_frames = true
	_ok(not tracks_frames, "no clip animates any frame — frames are stationary by construction")

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

# 8 + 9. The level readout is separate Godot UI in game.gd's left-hand HUD
#        gutter, high on the left, outside every button, and nothing is added to
#        the board itself.
func _check_indicator() -> void:
	print("\n-- level tab --")
	_ok(_dev_vp.find_child("StagePlate", true, false) == null,
		"nothing was added to the board itself")
	_ok(_dev_vp.find_child("RoundNumber", true, false) == null,
		"and no numeral lies on it either")
	var tab: Control = _dev._tab
	_ok(tab != null and tab.get_parent() == _dev, "it is a 2D Control over the board")
	if tab == null:
		return
	_ok(tab.mouse_filter == Control.MOUSE_FILTER_IGNORE, "it never eats a tap")
	_ok(tab._num.text == "12", "shows the round it was given", tab._num.text)
	_dev.set_round_number(148)
	_ok(tab._num.text == "148", "set_round_number(148)", tab._num.text)
	_ok(tab._num._size_for("148", tab._face()) < tab._num.base_size,
		"the numeral shrinks to fit once it is 3 digits",
		"%d px" % tab._num._size_for("148", tab._face()))
	_dev.set_round_number(12)
	_ok(tab._num.text == "12", "and back", tab._num.text)
	var r := Rect2(tab.position, tab.size)
	_ok(r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= W and r.end.y <= H,
		"on screen", str(r))
	_ok(r.end.x < W * 0.5, "sits in the LEFT-hand column")
	_ok(r.position.x >= tab.TAB_MARGIN - 0.5 and r.position.x <= tab.TAB_MARGIN_MAX + 0.5,
		"comfortable spacing from the screen edge", "%.0f px" % r.position.x)
	# Riding at 75% of the screen height, measured up from the bottom.
	_ok(absf(r.get_center().y - H * tab.TAB_CENTRE_Y) < 1.0,
		"centred 75% of the way up the screen",
		"badge centre %.0f vs %.0f" % [r.get_center().y, H * tab.TAB_CENTRE_Y])
	_ok(r.position.y >= 88.0 - 0.5, "never up into the watch-ad / Quit row")
	_ok(r.end.y <= H - 84.0 + 0.5, "clear of the status pill's row",
		"bottom %.0f vs %.0f" % [r.end.y, H - 84.0])
	# Clear of every button's silhouette. The plate is what must not overlap; its
	# bloom is a soft halo over a near-black bezel and is allowed to graze the
	# outermost rim, which is what keeps the reserved column narrow enough that the
	# board barely has to move for it.
	var plate := r.grow(6.0)
	var overlaps := ""
	for key: String in ORDER:
		var c := _holder(key).position
		for i in 48:
			var a := TAU * float(i) / 48.0
			for pt: Vector3 in [c + Vector3(cos(a), 0.0, sin(a)),
					c + Vector3(cos(a) * 0.745, 0.525, sin(a) * 0.745)]:
				if plate.has_point(_cam.unproject_position(pt)):
					overlaps = key
	_ok(overlaps == "", "clear of every button on screen", "overlaps %s" % overlaps)
	_ok(_dev.segment_at_point(r.get_center()) == -1, "a tap on it is not a button")

# 10. Nothing cropped, and the board fills the frame.
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
	_ok(fill_x > 0.65 and fill_y > 0.65, "the board fills the frame",
		"%.0f%% wide, %.0f%% tall" % [fill_x * 100.0, fill_y * 100.0])
