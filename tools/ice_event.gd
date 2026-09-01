extends Node
# Screenshot + assertion harness for ICE KINGDOM's TWO MILESTONE EVENTS, through the
# real gameplay path: the real device class, the real camera fit, the real skin
# resolution, on whichever board is asked for.
#
# Run WITHOUT --headless (both events are read back as rendered images, and the
# dummy driver never draws — see the note in ice_shot.gd):
#
#   Godot_..._console.exe --path . tools/ice_event.tscn -- [easy|medium|hard]
#
# It fires both events in turn and saves a strip of frames through each, then
# asserts the things about them that a picture cannot show: that the crossing
# starts and finishes OUTSIDE the frame, that it stays above the horizon, that the
# cadence is every third and every eighth level, that a repeat is refused, and that
# nothing at all is left standing afterwards.
#
# Writes res://shot_icev_*.png. Delete them when done.

const ICE := preload("res://ice_buttons.gd")
const SHOT_W := 1280
const SHOT_H := 720

var _dev: MemoryGameUI
var _vp: SubViewport
var _dev_vp: SubViewport
var _cam: Camera3D
var _ice: Node3D
var _tag := "hard"
var _fails := 0


func _ok(cond: bool, what: String, detail: String = "") -> void:
	if not cond:
		_fails += 1
	print("  %s %s%s" % ["ok  " if cond else "FAIL", what,
		("   [%s]" % detail) if detail != "" else ""])


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_tag = String(args[0]) if args.size() > 0 else "hard"

	for _i in 10:
		await get_tree().process_frame
	CoinsManager.selected_theme = ICE.THEME_ID

	_vp = SubViewport.new()
	_vp.size = Vector2i(SHOT_W, SHOT_H)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_vp)
	var plate := ColorRect.new()
	plate.color = BackgroundScenes.backdrop_color(ICE.THEME_ID).linear_to_srgb()
	plate.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(plate)

	match _tag:
		"easy": _dev = EasyGameUI.new()
		"medium": _dev = MemoryGameUI.new()
		_: _dev = HardGameUI.new()
	_dev.input_enabled = false
	_dev.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(_dev)
	await get_tree().process_frame
	_dev.configure(_dev._count, [])
	_dev.set_level(12)

	for c in _dev.get_children():
		if c is SubViewportContainer:
			_dev_vp = (c as SubViewportContainer).get_child(0) as SubViewport
	for c in _dev_vp.get_children():
		if c is Camera3D:
			_cam = c
	_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_ice = _dev._bg_scene
	print("board %s   background: %s" % [_tag, _dev._bg_id])
	_ok(_ice != null and _ice.has_method("start_streak_event"),
		"standing on Ice Kingdom")
	if _ice == null:
		get_tree().quit(1)
		return
	for _i in 30:
		await get_tree().process_frame

	await _cadence()
	await _streak()
	await _party()

	print("\n==== %s ====" % ("ALL CHECKS PASSED" if _fails == 0
		else "%d CHECK(S) FAILED" % _fails))
	get_tree().quit(_fails)


# Which level numbers each event answers to, asked of the BACKGROUND and not of
# game.gd — this is where that decision lives now, so this is where it is pinned.
func _cadence() -> void:
	print("\n--- cadence ---")
	_ok(_dev.background_milestone(1) == 0.0, "level 1: no burst")
	_ok(_dev.background_milestone(2) == 0.0, "level 2: no burst")
	var f3 := _dev.background_milestone(3)
	_ok(f3 > 0.0, "level 3: the burst, and a freeze", "%.2f s" % f3)
	_ok(absf(f3 - IceWorld.EV_TOTAL) < 0.001, "the freeze is the event's own length")
	_ok(_dev.background_milestone(3) == 0.0, "a repeat of level 3 asks for nothing")
	_ok(_dev.background_milestone(4) == 0.0, "and neither does level 4")
	_ice.call("stop_streak_event")
	_ok(_dev.background_milestone(24) == 0.0,
		"level 24 is an eighth, so the burst stands down for the celebration")
	_ok(_dev.background_celebration(7) == 0.0, "level 7: no celebration")
	var f8 := _dev.background_celebration(8)
	_ok(f8 > 0.0, "level 8: the celebration, and a freeze", "%.2f s" % f8)
	_ok(f8 >= 4.0 and f8 <= 5.0, "and it is the brief's four to five seconds",
		"%.2f s" % f8)
	_ok(_dev.background_celebration(8) == 0.0, "a repeat of level 8 asks for nothing")
	_ice.call("stop_party_event")
	for _i in 4:
		await get_tree().process_frame
	_ok(not bool(_ice.call("event_active")), "and both are stopped again")


# EVENT 1. Six frames through the 1.35 s, and the two things a picture cannot show:
# that no crystal grows inside the play area, and that nothing is left afterwards.
func _streak() -> void:
	print("\n--- the crystal burst ---")
	var freeze: float = _dev.background_milestone(9)
	_ok(freeze > 0.0, "level 9 starts it")
	var mm: MultiMesh = (_ice.get_node("Milestone/StreakCrystals")
		as MultiMeshInstance3D).multimesh
	_ok(mm.visible_instance_count > 0, "crystals are drawn",
		"%d of %d" % [mm.visible_instance_count, mm.instance_count])

	# The promise the whole placement exists to keep, checked the way the code makes
	# it: every crystal is outside the outermost button's reach.
	var reach := float(_ice.get("_reach"))
	var worst := 1e9
	for i in mm.instance_count:
		var o := mm.get_instance_transform(i).origin
		worst = minf(worst, Vector2(o.x, o.z).length())
	_ok(worst >= reach * IceWorld.DRESS_CLEAR - 0.01,
		"every crystal is outside the play area",
		"nearest %.2f m vs reach %.2f" % [worst, reach])

	for k in 6:
		var want := IceWorld.EV_TOTAL * float(k) / 5.0 * 0.95
		await _run_to("_ev_t", want)
		await _save("streak_%d" % k)
	await _run_to("_ev_t", 99.0)
	for _i in 4:
		await get_tree().process_frame
	_ok(not bool(_ice.call("event_active")), "it ends on its own clock")
	_ok(mm.visible_instance_count == 0, "and draws nothing afterwards")
	_ok(absf(float(_ice._imat.get_shader_parameter("dim")) - 1.0) < 0.001,
		"the scene is back to full brightness")


# EVENT 2. Eight frames through the 4.85 s, plus the crossing's own geometry.
func _party() -> void:
	print("\n--- the aurora and the sleigh ---")
	var freeze: float = _dev.background_celebration(16)
	_ok(freeze > 0.0, "level 16 starts it")

	# THE CROSSING, checked as the brief states it: in from off one side, out past
	# the other, never stopping in the middle, and never below the horizon.
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	for k in 21:
		var u := float(k) / 20.0
		var p: Vector3 = _ice.call("_bez", u)
		var sp := _cam.unproject_position(p)
		xs.append(sp.x)
		ys.append(sp.y)
	_ok(xs[0] < 0.0, "it enters from outside the left edge", "%.0f px" % xs[0])
	_ok(xs[20] > float(SHOT_W), "and leaves past the right one", "%.0f px" % xs[20])
	var mono := true
	for k in 20:
		if xs[k + 1] <= xs[k]:
			mono = false
	_ok(mono, "it never stops or turns back")
	# The SILHOUETTE and not the path: the team is 0.06 of the frame tall and the sky
	# it flies in is 0.195 of it, so a centre line that clears the horizon says
	# almost nothing about whether the hooves do.
	var unit := float(SHOT_W) * IceWorld.PT_SPAN / IceWorld.TEAM_LEN
	var lowest := 0.0
	var highest := 1e9
	for y: float in ys:
		lowest = maxf(lowest, y - IceWorld.TEAM_BOT * unit)
		highest = minf(highest, y - IceWorld.TEAM_TOP * unit)
	_ok(lowest < float(SHOT_H) * IceWorld.HORIZON_FY,
		"the whole team stays above the horizon, hooves included",
		"lowest %.0f px vs horizon %.0f" % [lowest, SHOT_H * IceWorld.HORIZON_FY])
	_ok(highest > 0.0, "and never leaves the top of the frame, antlers included",
		"highest %.0f px" % highest)
	# ...and that it is an ARC and not a straight line: the middle of the path is
	# measurably higher than the chord between its ends.
	var chord := (ys[0] + ys[20]) * 0.5
	_ok(chord - ys[10] > float(SHOT_H) * 0.015, "and it arcs rather than ruling a line",
		"%.0f px of rise" % (chord - ys[10]))

	for k in 8:
		var want := IceWorld.PT_TOTAL * float(k) / 7.0 * 0.98
		await _run_to("_pt_t", want)
		if k == 2:
			var sl := _ice.get_node_or_null("AuroraSleigh")
			_ok(sl != null and sl.visible, "the sleigh is up while it crosses")
		await _save("party_%d" % k)
		if k >= 1 and k <= 3:
			await _crop("party_%d" % k)
	await _run_to("_pt_t", 99.0)
	for _i in 4:
		await get_tree().process_frame
	_ok(not bool(_ice.call("event_active")), "it ends on its own clock")
	_ok(_ice.get_node_or_null("AuroraSleigh") == null,
		"and no reindeer or sleigh node remains")
	_ok(absf(float(_ice._imat.get_shader_parameter("dim")) - 1.0) < 0.001,
		"the scene is back to full brightness")
	_ok(absf(float(_ice._smat.get_shader_parameter("aurora_boost"))) < 0.001,
		"the aurora is back to its own cycle")
	var swp: Vector2 = _ice._imat.get_shader_parameter("sweep")
	_ok(absf(swp.y) < 0.001, "and the light sweep is off")


# Let real frames pass until the event's clock reaches `want`.
func _run_to(field: String, want: float) -> void:
	var guard := 0
	while float(_ice.get(field)) < want and bool(_ice.call("event_active")) \
			and guard < 900:
		guard += 1
		await get_tree().process_frame


# The sky strip, at 3x and NEAREST, because the team is about 190 px across in a
# 1280 px frame and a 190 px silhouette cannot be judged at 1:1.
func _crop(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var band := Image.create(SHOT_W, 190, false, img.get_format())
	band.blit_rect(img, Rect2i(0, 0, SHOT_W, 190), Vector2i.ZERO)
	band.resize(SHOT_W * 3, 570, Image.INTERPOLATE_NEAREST)
	band.save_png("res://shot_icev_%s_%s_zoom.png" % [_tag, tag])
	# ...and a tight one on the team itself, at 6x, because the reindeer is about
	# 80 px of that strip and a quadruped at 80 px is judged one pixel at a time.
	var sl := _ice.get_node_or_null("AuroraSleigh") as Node3D
	if sl == null:
		return
	var c := _cam.unproject_position(sl.global_transform.origin)
	var x := clampi(int(c.x) - 140, 0, SHOT_W - 280)
	var y := clampi(int(c.y) - 100, 0, SHOT_H - 160)
	var tight := Image.create(280, 160, false, img.get_format())
	tight.blit_rect(img, Rect2i(x, y, 280, 160), Vector2i.ZERO)
	tight.resize(1400, 800, Image.INTERPOLATE_NEAREST)
	tight.save_png("res://shot_icev_%s_%s_team.png" % [_tag, tag])


func _save(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.save_png("res://shot_icev_%s_%s.png" % [_tag, tag])
	print("shot  res://shot_icev_%s_%s.png" % [_tag, tag])
