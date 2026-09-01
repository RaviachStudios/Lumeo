extends Node
# What does the lake cost, against the backgrounds already shipping?
#
# The water is the only full-screen fragment shader any 3D background has: a
# three-wave field with an analytic gradient, plus a per-pad loop. That is exactly
# the shape of thing that measures fine on a desktop GPU and drops a phone to 20
# fps, and the eight Themes1 floors are geometry with almost no per-pixel work, so
# they are the honest baseline.
#
# Each background is built into the real Hard board at a phone-sized viewport, its
# SubViewport is pinned to UPDATE_ALWAYS, and the wall clock over FRAMES redraws is
# divided out. Same board, same camera, same buttons every time, so the difference
# between the rows IS the background.
#
# Run WITHOUT --headless (nothing is drawn under the dummy driver, so every row
# would measure the same nothing):
#
#   Godot_..._console.exe --path . tools/lake_cost.tscn
#
# Developer harness; not shipped.

const W := 1080
const H := 2160          # a portrait phone, which is the worst case for fill
const WARM := 40
const FRAMES := 150
const IDS := ["", "bg_neongrid", "bg_arcade", "world_forest", "world_ice", "world_lake"]
# ...and the lake again with the every-five-rounds frog event running through the
# whole measurement, which is what the player actually pays for it: four extra draw
# calls, ten small spheres and five rings, for about six seconds in every five
# rounds. Measured rather than reasoned about — this is a mobile game, and "it is
# only a frog" is how a background ends up costing 3 ms.
const FROG_ID := "world_lake"
# ...and Ice Kingdom's every-eighth-level celebration, for exactly the same reason:
# it adds the reindeer, its wake and a snowfall at nearly twice the density, and
# "it is only a sleigh" is the other way a background ends up costing 3 ms.
const ICE_ID := "world_ice"

func _ready() -> void:
	# Without this every row measures 16.67 ms, which is the vsync interval and not
	# the scene: the whole comparison is of work that fits inside one frame, so the
	# frame has to be allowed to be as short as it can.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for _i in 10:
		await get_tree().process_frame
	print("\n=== background cost, %dx%d, Hard board, %d frames each ===\n" % [W, H, FRAMES])
	print("  %-14s %8s  %8s" % ["background", "ms/frame", "vs none"])
	var base := 0.0
	for id: String in IDS:
		var ms := await _time(id)
		if id == "":
			base = ms
		print("  %-14s %8.2f  %8s" % [id if id != "" else "(none)", ms,
			"—" if id == "" else "%+.2f" % (ms - base)])
	var lake := await _time(FROG_ID)
	var frog := await _time(FROG_ID, true)
	print("  %-14s %8.2f  %8s" % ["+ frog event", frog, "%+.2f" % (frog - lake)])
	var ice := await _time(ICE_ID)
	var party := await _time(ICE_ID, false, true)
	print("  %-14s %8.2f  %8s" % ["+ ice aurora", party, "%+.2f" % (party - ice)])
	print("")
	get_tree().quit()

func _time(id: String, frog := false, ice := false) -> float:
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var dev := HardGameUI.new()
	dev.input_enabled = false
	dev.preview_bare = id == ""
	dev.preview_background = id
	dev.size = Vector2(W, H)
	vp.add_child(dev)
	await get_tree().process_frame
	dev.configure(6, [])

	var inner: SubViewport = null
	for c in dev.get_children():
		if c is SubViewportContainer:
			inner = (c as SubViewportContainer).get_child(0) as SubViewport
	if inner != null:
		inner.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	for _i in WARM:
		await get_tree().process_frame
	# Lit, so the emission machine and the ground pools are doing their real work.
	dev.set_lit(2, true)
	# The frog runs ~6 s and FRAMES is far shorter than that at these rates, so one
	# trigger covers the whole measurement — but re-fire on a fresh round each time
	# it does finish, so a slow machine measures the event rather than the tail of it.
	var round_no := 5
	if frog:
		dev.background_milestone(round_no)
	var level_no := 8
	if ice:
		dev.background_celebration(level_no)
	var t0 := Time.get_ticks_usec()
	for _i in FRAMES:
		await get_tree().process_frame
		if frog and dev._bg_scene != null and not dev._bg_scene.call("frog_event_active"):
			round_no += 5
			dev.background_milestone(round_no)
		# The ice celebration is 4.85 s and builds and frees its sleigh each time, so
		# re-firing it inside the window measures the BUILD as well as the drawing.
		if ice and dev._bg_scene != null and not dev._bg_scene.call("event_active"):
			level_no += 8
			dev.background_celebration(level_no)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(FRAMES)
	vp.queue_free()
	await get_tree().process_frame
	return ms
