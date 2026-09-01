extends Node
# The Magical Lake's every-five-rounds FROG event, rendered as a filmstrip through
# the real gameplay board.
#
# It fires the event exactly the way game.gd does — `board.background_milestone(5)`
# — so what is rendered is the shipping path and not a rehearsal of it: the same
# hook, the same façade, the same scene, the same camera.
#
# It then advances the frame clock by hand and grabs a still at each beat, because
# the thing that has to be checked is not "does it run" but "is the frog IN FRAME,
# behind the buttons, the right size, and does the jump read as a jump". Those are
# questions about six particular moments, and a video answers them worse than six
# stills do.
#
#   Godot_..._console.exe --path . tools/frog_shot.tscn [-- easy|medium|hard]
#
# Run WITHOUT --headless: it reads back a rendered image (see the harness-hang note).

const LILY := preload("res://lily_buttons.gd")
const SHOT_W := 1280            # the game's own design resolution
const SHOT_H := 720

# What to grab, and what each one is for. The times are NOT written here: the
# timeline is re-rolled per occurrence (the event still varies its pause and its
# arc height from round to round), so a fixed list of seconds drifts off the beats
# it was written for and starts photographing the gaps between them — which is
# exactly what the first run of this harness did, catching an empty lake at a beat.
# Each entry names two of the lake's own phase marks and a point between them, and
# the times come out of the event itself.
#
# Four of the twelve are on the exit jump on purpose: "ONE jump, no intermediate
# bounce, fully off the left edge" is the thing about this event most likely to be
# got wrong, and it is the thing a single still cannot show.
const BEATS := [
	["a_trigger",  "_k_in",   "_k_in",   0.02, "the moment it fires: still an empty lake"],
	["b_padrise",  "_k_in",   "_k_in",   0.55, "the pad coming up, first ripple spreading"],
	["c_frog_in",  "_k_in",   "_k_land", 0.50, "the frog in the air, entering from the RIGHT"],
	["d_nearly",   "_k_in",   "_k_land", 0.88, "coming down onto the CENTRE pad"],
	["e_landed",   "_k_land", "_k_go",   0.25, "landed, the landing squash"],
	["f_crouch",   "_k_land", "_k_go",   0.80, "the crouch that launches the exit"],
	["g_leaving",  "_k_go",   "_k_gone", 0.30, "one jump, heading LEFT off the pad"],
	["h_apex",     "_k_go",   "_k_gone", 0.50, "the top of that arc — the only one there is"],
	["i_edge",     "_k_go",   "_k_gone", 0.80, "at the left edge of the frame, still going"],
	["j_gone",     "_k_gone", "_k_gone", 1.01, "outside the frame completely"],
	["k_padsink",  "_k_sink", "_k_end",  0.55, "frog gone, the pad going back under"],
	["l_over",     "_k_end",  "_k_end",  1.02, "the lake, exactly as it was"],
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
	_dev.set_level(12)

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

	# Exactly what game.gd does on a completed round divisible by five, through
	# exactly the same call.
	_dev.background_milestone(5)
	print("event active after trigger: %s" % _lake.call("frog_event_active"))
	_report_path()

	# Resolve the beats against the timeline this occurrence actually rolled.
	var when := PackedFloat32Array()
	for b: Array in BEATS:
		var a: float = float(_lake.get(String(b[1])))
		var c: float = float(_lake.get(String(b[2])))
		when.append(a if is_equal_approx(a, c) else lerpf(a, c, float(b[3])))
	for i in BEATS.size():
		if is_equal_approx(float(_lake.get(String(BEATS[i][1]))),
				float(_lake.get(String(BEATS[i][2])))):
			when[i] = float(_lake.get(String(BEATS[i][1]))) * float(BEATS[i][3])

	# The event advances on the LAKE's own clock, and the still is taken with that
	# clock pinned to the beat rather than near it.
	#
	# The first version of this loop ran the tree and accumulated
	# get_process_delta_time() into a clock of its own, and the two drifted: saving
	# a frame costs three more process frames plus a frame_post_draw, so by "the top
	# of the exit arc" the event was 0.3 s further on than the harness thought and
	# the frog was already outside the frame. A filmstrip that photographs the wrong
	# moments is worse than no filmstrip, because it looks like an animation bug.
	#
	# So: let it run to just before the beat, stop the scene, set the clock to the
	# beat exactly, and re-place everything at that time with a zero-length tick
	# (which cannot fire a one-shot — _cross needs the interval to close over the
	# mark, and a zero step closes nothing).
	Engine.max_fps = 0
	for next in BEATS.size():
		_lake.set_process(true)
		var guard := 0
		while float(_lake.get("_ev_t")) < when[next] - 0.03 and guard < 900:
			await get_tree().process_frame
			guard += 1
		_lake.set_process(false)
		_lake.set("_ev_t", when[next])
		_lake.call("_tick_event", 0.0)
		await _save("%s_%s" % [mode, String(BEATS[next][0])],
			String(BEATS[next][4]), when[next])
	_lake.set_process(true)
	# ...and then let it finish on its own, which is the state the last two checks
	# below are about.
	var tail := 0
	while bool(_lake.call("frog_event_active")) and tail < 900:
		await get_tree().process_frame
		tail += 1
	print("event active after the end: %s" % _lake.call("frog_event_active"))

	# And the two things that are easy to get wrong and impossible to see in a still:
	# a second trigger for the SAME round must do nothing, and a later round must
	# start a fresh event.
	_dev.background_milestone(5)
	print("re-firing round 5 restarts it: %s (want false)" % _lake.call("frog_event_active"))
	_dev.background_milestone(10)
	print("round 10 starts a new one:     %s (want true)" % _lake.call("frog_event_active"))
	get_tree().quit()


# Where the path landed on screen. The frog is only correct if it enters OFF the
# right edge, stops in the MIDDLE of the frame and leaves OFF the left edge — and
# if all three sit ABOVE the topmost button, which is what keeps it out of the play
# area.
func _report_path() -> void:
	var names := ["in", "pad", "out"]
	var pts: Array = [_lake.get("_p_in"), _lake.get("_p_pad"), _lake.get("_p_out")]
	print("--- path, at %dx%d ---" % [SHOT_W, SHOT_H])
	for i in 3:
		var p: Vector3 = pts[i]
		var s := _cam.unproject_position(p)
		print("  %-4s world %6.2f, %6.2f   screen %7.1f, %6.1f  (%.2f of width)"
			% [names[i], p.x, p.z, s.x, s.y, s.x / float(SHOT_W)])
	print("  apex fitted to %.3f m   stop clears the nearest pad by %.0f px (want %.0f)"
		% [float(_lake.get("_ev_apex")),
			float(_lake.call("_stop_room", float(_lake.get("_p_pad").x),
				float(_lake.get("_p_pad").z), _cam)),
			SHOT_W * float(LakeWorld.STOP_ROOM)])
	# ...and the whole window it chose from, because "the stop is not where the
	# composition asked for it" is only ever answerable against the profile.
	var prof := PackedStringArray()
	var z: float = float(_lake.get("_p_pad").z)
	for i in 12:
		var f: float = lerpf(float(LakeWorld.PATH_PAD_LO), float(LakeWorld.PATH_PAD_HI),
			float(i) / 11.0)
		var wx: float = _lake.call("_x_at_screen", f, z, _cam, Vector2(SHOT_W, SHOT_H))
		prof.append("%.2f:%.0f" % [f, float(_lake.call("_stop_room", wx, z, _cam))])
	print("  room across the window: " + "  ".join(prof))
	# The resolved timeline, so a beat that photographs the wrong thing can be told
	# apart from a beat that fires at the wrong time.
	var marks := ["_k_in", "_k_land", "_k_go", "_k_gone", "_k_sink", "_k_end"]
	var line := PackedStringArray()
	for m: String in marks:
		line.append("%s %.2f" % [m.substr(3), float(_lake.get(m))])
	print("  timeline: " + "  ".join(line))
	# The lowest the frog's own path may be on screen against the HIGHEST any button
	# reaches: a positive gap is the frog clearing the play area.
	var top := 1e9
	var centres: PackedVector2Array = _lake.get("_centres")
	for c: Vector2 in centres:
		top = minf(top, _cam.unproject_position(Vector3(c.x, 0.45, c.y)).y)
	var path_y := _cam.unproject_position(_lake.get("_p_pad")).y
	print("  topmost button at y %.1f, path at y %.1f -> %s by %.1f px"
		% [top, path_y, "CLEAR" if path_y < top else "OVERLAPS", absf(top - path_y)])


func _save(tag: String, why: String, t: float) -> void:
	for _i in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.save_png("user://frog_%s.png" % tag)
	# And the lane on its own, magnified with NEAREST. A frog forty pixels tall is
	# either right or wrong as PIXELS, and a 1280-wide frame is not where that can
	# be judged — the first pass looked acceptable full-frame while the model was a
	# green speck with no eyes in it.
	# Centred on the FROG when there is one, and on the pad when there is not —
	# a crop that follows the pad shows an empty leaf for every airborne beat, which
	# is exactly the half of the animation worth looking at.
	var frog := _lake.get_node_or_null("FrogEvent/Frog") as MeshInstance3D
	var anchor: Vector3 = frog.global_position if (frog != null and frog.visible) \
		else _lake.get("_p_pad")
	var c := _cam.unproject_position(anchor)
	var r := Rect2i(clampi(int(c.x) - 150, 0, SHOT_W - 300),
		clampi(int(c.y) - 110, 0, SHOT_H - 200), 300, 200)
	var cut := _vp.get_texture().get_image().get_region(r)
	cut.resize(300 * 3, 200 * 3, Image.INTERPOLATE_NEAREST)
	cut.save_png("user://frogz_%s.png" % tag)
	print("  t=%5.2f  %-12s  rings %d  drops %d  %s"
		% [t, tag, _rings_live(), _drops_live(), why])


# How many ripple rings and droplets the event has on screen right now. Printed at
# every beat because a splash that silently never fires looks identical to one that
# fired and is small — and the first thing that gets broken by an edit to the pools
# is the count, not the look.
func _rings_live() -> int:
	var mm := _lake.get_node_or_null("FrogEvent/Ripples") as MultiMeshInstance3D
	return 0 if mm == null else mm.multimesh.visible_instance_count


func _drops_live() -> int:
	var mm := _lake.get_node_or_null("FrogEvent/Droplets") as MultiMeshInstance3D
	return 0 if mm == null else mm.multimesh.visible_instance_count
