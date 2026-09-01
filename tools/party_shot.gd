extends Node
# The Magical Lake's LEVEL-8 party, rendered as a filmstrip through the real
# gameplay board.
#
# It fires the event exactly the way game.gd does — `board.background_celebration(8)`
# — so what is rendered is the shipping path and not a rehearsal of it.
#
# The questions it exists to answer are the ones a single still cannot:
#   * are there FIVE pads, in five places, and is a frog already sitting on each
#     one the moment it breaks the surface (never arriving, never landing);
#   * do the frogs face the player;
#   * do the pairs go back down TOGETHER and leave nothing behind;
#   * and does the whole thing fit in five seconds.
#
#   Godot_..._console.exe --path . tools/party_shot.tscn [-- easy|medium|hard]
#
# Run WITHOUT --headless: it reads a rendered image back, and it reads instance
# transforms back off a MultiMesh — the dummy driver gives identity for both.
#
# Writes user://party_*.png (the frame) and user://partyz_*.png (a 3x NEAREST crop
# on the busiest pair, because a frog forty pixels tall is right or wrong as PIXELS).

const LILY := preload("res://lily_buttons.gd")
const SHOT_W := 1280
const SHOT_H := 720

# Absolute times, unlike the frog's — this event does not re-roll its timeline, so
# a fixed list cannot drift off the beats it was written for.
const BEATS := [
	["a_still",   0.02, "the lake a frame after the trigger: nothing yet"],
	["b_break",   0.30, "five pads breaking the surface, frogs already aboard"],
	["c_up",      0.78, "all five up, the settle bounce dying"],
	["d_cheer",   1.35, "the cheer, with YOU ROCK! popping over the board"],
	["e_mid",     2.20, "mid celebration"],
	["f_last",    3.30, "the last of it"],
	["g_sinking", 3.95, "the pairs going back down TOGETHER"],
	["h_nearly",  4.55, "almost gone, rims at the waterline"],
	["i_over",    4.95, "the lake, exactly as it was"],
]

var _dev: MemoryGameUI
var _vp: SubViewport
var _dev_vp: SubViewport
var _cam: Camera3D
var _lake: Node3D

func _ready() -> void:
	var mode := "hard"
	for a in OS.get_cmdline_user_args():
		if ["easy", "medium", "hard"].has(String(a)):
			mode = String(a)

	for _i in 8:
		await get_tree().process_frame
	CoinsManager.selected_theme = LILY.THEME_ID

	_vp = SubViewport.new()
	_vp.size = Vector2i(SHOT_W, SHOT_H)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_vp)
	var plate := ColorRect.new()
	plate.color = Color(LakeWorld.backdrop_color("world_lake").linear_to_srgb())
	plate.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(plate)

	var count := 6
	match mode:
		"easy":
			_dev = EasyGameUI.new()
			count = 3
		"medium":
			_dev = MemoryGameUI.new()
			count = 5
		_:
			_dev = HardGameUI.new()
	_dev.input_enabled = false
	_dev.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(_dev)
	await get_tree().process_frame
	_dev.configure(count, [])
	_dev.set_level(8)

	for c in _dev.get_children():
		if c is SubViewportContainer:
			_dev_vp = (c as SubViewportContainer).get_child(0) as SubViewport
	for c in _dev_vp.get_children():
		if c is Camera3D:
			_cam = c
	_lake = _dev_vp.get_node_or_null("MagicalLake")
	print("%s board — pads worn: %s   lake: %s"
		% [mode, _dev.button_skin_id() == LILY.THEME_ID, _lake != null])
	if _lake == null:
		get_tree().quit()
		return
	for _i in 30:
		await get_tree().process_frame

	var freeze: float = _dev.background_celebration(8)
	print("party active: %s   the round is frozen for %.2f s"
		% [_lake.call("party_event_active"), freeze])
	_report_berths()

	Engine.max_fps = 0
	for i in BEATS.size():
		var when: float = float(BEATS[i][1])
		_lake.set_process(true)
		var guard := 0
		while float(_lake.get("_pt_t")) < when - 0.03 and guard < 900:
			await get_tree().process_frame
			guard += 1
		_lake.set_process(false)
		_lake.set("_pt_t", when)
		# A zero-length tick re-places everything at exactly this time and cannot
		# fire a one-shot: _pt_cross needs the interval to close over a mark, and a
		# zero step closes nothing.
		_lake.call("_pose_party", when)
		await _save("%s_%s" % [mode, String(BEATS[i][0])], String(BEATS[i][2]), when)
	_lake.set_process(true)
	var tail := 0
	while bool(_lake.call("party_event_active")) and tail < 900:
		await get_tree().process_frame
		tail += 1
	print("party active after the end: %s (want false)" % _lake.call("party_event_active"))
	print("re-firing level 8 asks for:  %.2f s (want 0.00)" % _dev.background_celebration(8))
	get_tree().quit()


# Where the five berths landed on screen, and how much open water each one has. A
# berth is only correct if it is IN the frame, clear of every button, and not on
# top of another berth.
func _report_berths() -> void:
	var berths: Array = _lake.get("_pt_p")
	var scale: PackedFloat32Array = _lake.get("_pt_scale")
	var yaw: PackedFloat32Array = _lake.get("_pt_yaw")
	print("--- five berths, at %dx%d ---" % [SHOT_W, SHOT_H])
	for i in berths.size():
		var p: Vector3 = berths[i]
		var s := _cam.unproject_position(Vector3(p.x, LakeWorld.PAD_TOP, p.z))
		# How far off facing the camera this frog is, in degrees.
		var nose := Vector3(cos(yaw[i]), 0.0, -sin(yaw[i]))
		var to_cam := _cam.global_position - p
		to_cam.y = 0.0
		print("  %d  world %6.2f, %6.2f   screen %6.1f, %5.1f (%.2f, %.2f of frame)"
			% [i, p.x, p.z, s.x, s.y, s.x / SHOT_W, s.y / SHOT_H]
			+ "   scale %.2f   room %5.0f px   facing off by %4.1f deg"
			% [scale[i], float(_lake.call("_stop_room", p.x, p.z, _cam)),
				rad_to_deg(acos(clampf(nose.dot(to_cam.normalized()), -1.0, 1.0)))])
	# The topmost button, so "the pads are not over the play area" is a number.
	var top := 1e9
	var centres: PackedVector2Array = _lake.get("_centres")
	for c: Vector2 in centres:
		top = minf(top, _cam.unproject_position(Vector3(c.x, 0.45, c.y)).y)
	print("  topmost button at y %.1f" % top)


func _save(tag: String, why: String, t: float) -> void:
	for _i in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_vp.get_texture().get_image().save_png("user://party_%s.png" % tag)
	# A 3x NEAREST crop on the pair nearest the middle of the frame — the one whose
	# frog is biggest and therefore the one whose seat, face and squash can actually
	# be judged.
	var pads := _lake.get_node_or_null("FrogEvent/PartyPads") as MultiMeshInstance3D
	var anchor := Vector3(0.0, LakeWorld.WATER_Y, 0.0)
	if pads != null and pads.multimesh.visible_instance_count > 0:
		var best := 1e9
		for i in pads.multimesh.visible_instance_count:
			var o: Vector3 = pads.multimesh.get_instance_transform(i).origin
			var d := _cam.unproject_position(o).distance_to(Vector2(SHOT_W, SHOT_H) * 0.5)
			if d < best:
				best = d
				anchor = o
	var c := _cam.unproject_position(anchor)
	var r := Rect2i(clampi(int(c.x) - 150, 0, SHOT_W - 300),
		clampi(int(c.y) - 110, 0, SHOT_H - 200), 300, 200)
	var cut := _vp.get_texture().get_image().get_region(r)
	cut.resize(300 * 3, 200 * 3, Image.INTERPOLATE_NEAREST)
	cut.save_png("user://partyz_%s.png" % tag)
	print("  t=%5.2f  %-12s  pads %d  frogs %d  rings %d  drops %d  %s"
		% [t, tag, _live("PartyPads"), _live("PartyFrogs"), _live("Ripples"),
			_live("Droplets"), why])


func _live(nm: String) -> int:
	var mm := _lake.get_node_or_null("FrogEvent/%s" % nm) as MultiMeshInstance3D
	return 0 if mm == null else mm.multimesh.visible_instance_count
