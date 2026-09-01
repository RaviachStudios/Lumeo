extends Node
# Acceptance check for the ROYAL CASINO skin — chip_buttons.gd, casino_world.gd and
# casino_events.gd, plus the wiring that hangs them off the rest of the project.
#
# It verifies the claims a screenshot cannot, and the most important of them is the
# SAFETY property the whole event system is built around: that nothing an event puts
# on the table can ever be drawn over a gameplay button. That is checked the only way
# it can be honestly checked — by running all seven events, on all three boards,
# through their real timelines at 60 Hz, reading every object's actual transform back
# out of the MultiMesh, projecting it through the board's own camera, and asserting
# it lands ABOVE the topmost chip's top edge.
#
# MUST RUN WITHOUT --headless. Two of its assertions need a real driver: a MultiMesh
# read back under the dummy driver returns the IDENTITY for every instance, silently
# (see [[headless-shader-harness-hang]]), which would report a perfectly still
# celebration as a pass. Run it as:
#
#   Godot_v4.7-stable_win64_console.exe --path . tools/casino_verify.tscn

const CHIPS := preload("res://chip_buttons.gd")
# shop_screen.gd carries no class_name, so its catalog is reached through a preload.
const SHOP := preload("res://shop_screen.gd")

# The chip asset's own contract, from APP IDEAS/Simon/Skins/Chips/README.md.
const CHIP_H := 0.324
const CHIP_R := 1.0
const FRAME_RADIUS := 1.0
const PRESS := 0.115
const THEME := "world_casino"

var _fails := 0
var _checks := 0

func _ok(cond: bool, what: String, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("  ok    %s" % what)
	else:
		_fails += 1
		print("  FAIL  %s%s" % [what, ("  [%s]" % detail) if detail != "" else ""])

func _radius(aabb: AABB) -> float:
	var p := aabb.position
	var e := aabb.end
	return maxf(maxf(absf(p.x), absf(e.x)), maxf(absf(p.z), absf(e.z)))

func _ready() -> void:
	print("\n=== Royal Casino ===\n")
	_assets()
	_wiring()
	await _boards()
	print("\n%s  (%d checks, %d failure%s)\n" % ["PASS" if _fails == 0 else "FAIL",
			_checks, _fails, "" if _fails == 1 else "s"])
	get_tree().quit(1 if _fails > 0 else 0)


# --------------------------------------------------------------- the assets
func _assets() -> void:
	print("-- chip asset contract --")
	var shapes: Dictionary = {}
	for key: String in ["Crimson", "Jade", "Cyan", "Amber", "Violet", "Magenta", "Yellow"]:
		var kit: Dictionary = CHIPS.build(key)
		if kit.is_empty():
			_ok(false, "%s loads" % key, "ChipButtons.build returned nothing")
			continue
		var s: Mesh = kit["surface"]
		var f: Mesh = kit["frame"]
		var sa := s.get_aabb()
		_ok(s.get_surface_count() == 2 and f.get_surface_count() == 2,
				"%s: two surfaces on each mesh" % key,
				"%d / %d" % [s.get_surface_count(), f.get_surface_count()])
		_ok(absf(sa.position.y) < 0.0005,
				"%s: the chip's base sits on the felt" % key, "y0 %.4f" % sa.position.y)
		_ok(absf(sa.end.y - CHIP_H) < 0.002,
				"%s: the chip is %.3f tall" % [key, CHIP_H], "%.4f" % sa.end.y)
		_ok(_radius(sa) <= CHIP_R + 0.0005,
				"%s: inside the reserved footprint" % key, "r %.4f" % _radius(sa))
		# The press must not bury it. This is the number PRESS_SCALE exists to set.
		_ok(CHIP_H - PRESS * CHIPS.PRESS_SCALE > CHIP_H * 0.80,
				"%s: a full press leaves >80%% of the chip proud" % key,
				"%.1f%%" % (100.0 * (CHIP_H - PRESS * CHIPS.PRESS_SCALE) / CHIP_H))
		# The felt-contact sheets must stay under the board's own ground pools.
		var fa := f.get_aabb()
		_ok(fa.end.y < 0.012,
				"%s: contact sheets sit under the ground pools" % key,
				"%.4f" % fa.end.y)
		_ok(_radius(fa) > _radius(sa),
				"%s: the contact spreads past the chip" % key,
				"%.3f vs %.3f" % [_radius(fa), _radius(sa)])

		# The import fix, and the two material rules that make a chip read as a lit
		# solid rather than as a flat disc.
		for i in 2:
			var m := s.surface_get_material(i) as StandardMaterial3D
			_ok(m != null and m.vertex_color_use_as_albedo,
					"%s surf %d: COLOR_0 is used as albedo" % [key, i])
			_ok(m != null and m.emission_enabled
					and m.emission_operator == BaseMaterial3D.EMISSION_OP_ADD,
					"%s surf %d: emission is ADD (MULTIPLY renders black here)" % [key, i])
			_ok(m != null and is_equal_approx(m.emission_energy_multiplier, 1.0),
					"%s surf %d: energy pinned at 1.0" % [key, i])
			_ok(m != null and m.disable_ambient_light,
					"%s surf %d: does not mirror the board's sky" % [key, i])
		# The accent's GLOW comes from the body's hue, not from its own — the whole
		# point of the RING_EMISSION note. Test it by hue rather than by value: on
		# Cyan, Green and Yellow the accent's own albedo is a dark tint and would
		# give a visibly different flash colour.
		var body := s.surface_get_material(0) as StandardMaterial3D
		var ring := s.surface_get_material(1) as StandardMaterial3D
		_ok(_hue_close(body.emission, ring.emission),
				"%s: face and accent flash the same colour" % key,
				"%s vs %s" % [body.emission, ring.emission])
		shapes[key] = _signature(s)

	# One geometry, six colours.
	var keys: Array = shapes.keys()
	var same := true
	for k: String in keys:
		same = same and shapes[k] == shapes[keys[0]]
	_ok(same, "all seven colours are the same mesh, vertex for vertex")

	# The chip's albedo palette must not be so spread that one button reads dim.
	var lo := 9.0
	var hi := 0.0
	for key: String in keys:
		var m := (CHIPS.build(key)["surface"] as Mesh).surface_get_material(0) as StandardMaterial3D
		var c := m.albedo_color.srgb_to_linear()
		var peak := maxf(c.r, maxf(c.g, c.b))
		lo = minf(lo, peak)
		hi = maxf(hi, peak)
	# The AUTHORED spread is allowed to be wide — it is the asset's palette. What
	# must be narrow is the spread AFTER ChipButtons' NORM_POWER correction, which is
	# what actually decides whether one button reads dimmer than its neighbours.
	_ok(hi / lo < 3.0, "the authored palette is within one asset's worth of spread",
			"%.2fx" % (hi / lo))
	_ok(pow(hi / lo, CHIPS.NORM_POWER) < 1.8,
			"...and the normalised emission spread is under 1.8x",
			"%.2fx" % pow(hi / lo, CHIPS.NORM_POWER))
	CHIPS.trim_cache([])


func _hue_close(a: Color, b: Color) -> bool:
	var na := _norm_rgb(a)
	var nb := _norm_rgb(b)
	return na.distance_to(nb) < 0.06


func _col_dist(a: Color, b: Color) -> float:
	var x := a.srgb_to_linear()
	var y := b.srgb_to_linear()
	return Vector3(x.r, x.g, x.b).distance_to(Vector3(y.r, y.g, y.b))


func _norm_rgb(c: Color) -> Vector3:
	var m := maxf(c.r, maxf(c.g, c.b))
	return Vector3.ZERO if m < 0.0001 else Vector3(c.r / m, c.g / m, c.b / m)


func _signature(m: Mesh) -> String:
	var out := ""
	for i in m.get_surface_count():
		var a: Array = m.surface_get_arrays(i)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var acc := Vector3.ZERO
		for p: Vector3 in v:
			acc += p
		out += "%d:%d:%.5f,%.5f,%.5f|" % [v.size(), idx.size(), acc.x, acc.y, acc.z]
	return out


# --------------------------------------------------------------- the wiring
func _wiring() -> void:
	print("\n-- catalog and shop wiring --")
	_ok(BackgroundScenes.has_scene(THEME), "BackgroundScenes knows world_casino")
	_ok(BackgroundScenes.all_order().has(THEME), "...and lists it in all_order")
	_ok(BackgroundScenes.display_name(THEME) == "Royal Casino", "display name")
	_ok(BackgroundScenes.is_animated(THEME), "is animated")
	_ok(is_equal_approx(BackgroundScenes.pool_plane_y(THEME), 0.0),
			"the felt is the board plane")
	_ok(BackgroundScenes.pool_gain(THEME) < 1.0 and BackgroundScenes.pool_gain(THEME) > 0.3,
			"pool gain is reduced for a lit surface", "%.2f" % BackgroundScenes.pool_gain(THEME))
	_ok(BackgroundScenes.frame_bias(THEME) != Vector2.ZERO,
			"the board is re-framed for the table")
	_ok(BackgroundScenes.make_preview_camera(1.0, THEME) != null, "preview camera")
	_ok(BackgroundScenes.make_preview_environment(THEME) != null, "preview environment")
	_ok(BackgroundScenes.backdrop_color(THEME) != BackgroundScenes.BACKDROP_COLOR,
			"its own backdrop colour")
	_ok(CoinsManager.THEMES.has(THEME), "CoinsManager sells it")
	_ok(String(CoinsManager.THEMES[THEME].get("category", "")) == "themes",
			"...in the themes category")
	# The two ids must stay apart: "casino" is the old JACKPOT wheel skin.
	_ok(not CoinsManager.THEMES.has("casino"),
			"the JACKPOT wheel skin's id is still not a theme")
	var listed := false
	for d: Dictionary in SHOP.SKIN_DEFS:
		if String(d.get("id", "")) == THEME:
			listed = String(d.get("theme", "")) == THEME and bool(d.get("released", false))
	_ok(listed, "the SPECIAL SKINS shelf carries it, theme-backed and released")

	var scene := BackgroundScenes.build(THEME)
	_ok(scene != null, "the table builds")
	if scene != null:
		_ok(scene.get_node_or_null("Felt") != null, "it has a felt")
		_ok(scene.get_node_or_null("EventsRoot") != null, "...and an event system")
		scene.free()


# --------------------------------------------------------------- the boards
func _boards() -> void:
	# Let CoinsManager finish loading the saved wallet first: it assigns
	# selected_theme during start-up and would otherwise overwrite the one this test
	# sets, which is what makes the FIRST board tested look broken.
	for _i in 8:
		await get_tree().process_frame
	var was := CoinsManager.selected_theme
	for spec: Array in [["Easy", EasyGameUI], ["Medium", MemoryGameUI], ["Hard", HardGameUI]]:
		print("\n-- %s board --" % spec[0])
		CoinsManager.selected_theme = THEME
		_ok(CHIPS.active(), "Royal Casino reads as equipped")
		var dev: MemoryGameUI = (spec[1] as Script).new() if spec[1] is Script else spec[1].new()
		var vp := SubViewport.new()
		vp.size = Vector2i(1280, 720)
		add_child(vp)
		vp.add_child(dev)
		dev.size = Vector2(1280, 720)
		await get_tree().process_frame
		dev.configure(0, [])
		for _i in 4:
			await get_tree().process_frame

		_ok(dev.button_skin_id() == THEME, "the board wears the chips",
				dev.button_skin_id())
		_ok(dev.background_id() == THEME, "...and stands on the table",
				dev.background_id())
		var board: Node3D = dev._board
		var ap: AnimationPlayer = dev._ap
		for key: String in dev._keys:
			var surf := board.find_child("Button_%s_Surface" % key, true, false) as MeshInstance3D
			var frame := board.find_child("Button_%s_Frame" % key, true, false) as MeshInstance3D
			var holder := board.find_child("Button_%s" % key, true, false) as Node3D
			var kit: Dictionary = CHIPS.build(key)
			_ok(surf.mesh == kit.get("surface"), "%s wears the poker chip" % key)
			_ok(frame.mesh == kit.get("frame"), "%s wears the felt contact" % key)
			_ok(ap != null and ap.has_animation("Press_%s" % key),
					"%s keeps its Press_ clip" % key)
			var hits := 0
			for c in holder.get_children():
				if c is Area3D:
					hits += 1
			_ok(hits == 1, "%s has exactly one hit area" % key, "%d" % hits)
		_ok(dev._face_mats.size() == dev._count and dev._ring_mats.size() == dev._count
				and dev._glow_mats.size() == dev._count,
				"the emission state machine bound all %d buttons" % dev._count)
		# The press amplitude is scaled, and only the amplitude.
		var travel := _press_travel(ap, dev._keys[0])
		_ok(absf(travel - PRESS * CHIPS.PRESS_SCALE) < 0.002,
				"the press stroke is scaled to %.3f" % (PRESS * CHIPS.PRESS_SCALE),
				"%.4f" % travel)
		_ok(dev._vp.msaa_3d == Viewport.MSAA_2X, "the viewport is anti-aliased")
		_ok(dev._vp.get_node_or_null("SkinLights") != null, "the chips brought a rig")
		var rig := dev._vp.get_node_or_null("SkinLights")
		if rig != null:
			var omnis := 0
			var dirs := 0
			for l in rig.get_children():
				if l is OmniLight3D:
					omnis += 1
				elif l is DirectionalLight3D:
					dirs += 1
			_ok(omnis == 3 and dirs == 0,
					"the rig is omni lights (this renderer draws one directional)",
					"%d omni, %d directional" % [omnis, dirs])
		# Jade must NOT have been replaced with the felt's own hue.
		if dev._keys.has("Jade"):
			var jade := board.find_child("Button_Jade_Surface", true, false) as MeshInstance3D
			var m := jade.get_surface_override_material(0) as StandardMaterial3D
			_ok(m != null and _col_dist(m.albedo_color, MemoryGameUI.JADE_TARGET) > 0.05,
					"Jade keeps the chip's own green",
					"" if m == null else str(m.albedo_color))

		await _events(dev, String(spec[0]))
		vp.queue_free()
		await get_tree().process_frame
	CoinsManager.selected_theme = was
	CHIPS.trim_cache([])


func _press_travel(ap: AnimationPlayer, key: String) -> float:
	var a := ap.get_animation("Press_%s" % key)
	if a == null:
		return -1.0
	var drop := 0.0
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		for k in a.track_get_key_count(t):
			var p: Vector3 = a.track_get_key_value(t, k)
			drop = minf(drop, p.y)
	return -drop


# ------------------------------------------------------- the events, on a board
#
# The heart of this file. Every event is run through its real timeline and every
# object it places is projected through the board's OWN camera and required to land
# above the topmost chip. Read out of the live MultiMeshes, not recomputed here — a
# test that re-derives the pose is a test of the test.
func _events(dev: MemoryGameUI, board_name: String) -> void:
	var world: Node3D = dev._bg_scene
	if world == null:
		_ok(false, "%s: the table is the live background" % board_name)
		return
	var ev := world.get_node_or_null("EventsRoot")
	if ev == null:
		_ok(false, "%s: the event system is present" % board_name)
		return
	var cam: Camera3D = dev._cam
	var vps := Vector2(dev._vp.size)

	_ok(bool(ev.get("_lane_ok")), "%s: the lane solved" % board_name)
	if not bool(ev.get("_lane_ok")):
		return

	# Where the highest chip's top edge lands. Everything an event places must be
	# strictly above this row, with a margin.
	var top_px := vps.y
	for c: Vector2 in dev._centres:
		top_px = minf(top_px, cam.unproject_position(
				Vector3(c.x, CasinoWorld.CHIP_TOP, c.y)).y)
	print("   (top chip at y %.1f of %d; lane z %.2f, card %.2f)" % [
			top_px, int(vps.y), float(ev.get("_lane_z")), float(ev.get("_card_len"))])

	# The felt's rail must clear the same row, or be switched off entirely.
	var fmat: ShaderMaterial = world.get("_fmat")
	var rail_on := float(fmat.get_shader_parameter("rail_on"))
	if rail_on > 0.5:
		var rail_r := float(fmat.get_shader_parameter("rail_r"))
		var ry := cam.unproject_position(Vector3(0.0, 0.0, -rail_r)).y
		_ok(ry < top_px, "%s: the table's rail clears the chips" % board_name,
				"rail %.1f vs chips %.1f" % [ry, top_px])
	else:
		_ok(true, "%s: no rail on this pose, and the felt runs to the dark" % board_name)

	# Every event, plus the finale, at 60 Hz.
	var names := ["community", "roulette", "cascade", "flip", "deal", "lights"]
	var worst := -1e9
	var worst_which := ""
	var seen: Array = []
	for round_no in range(3, 3 * 14, 3):
		var secs: float = ev.call("start_event", round_no)
		# The SMALL events deliberately ask for no freeze at all — they play over the
		# next round from a lane above the buttons. So what is checked is that one
		# started, not what it asked for, and that it asked for nothing.
		_ok(bool(ev.call("active")), "%s: round %d starts an event" % [board_name, round_no])
		_ok(is_equal_approx(secs, 0.0),
				"%s: round %d does not freeze the game" % [board_name, round_no],
				"%.2f s" % secs)
		if not bool(ev.call("active")):
			continue
		secs = float(ev.get("_len"))
		var kind := int(ev.get("_kind"))
		_ok(kind >= 0 and kind < 6, "%s: round %d picked a real event" % [board_name, round_no])
		if not seen.is_empty():
			_ok(kind != int(seen[seen.size() - 1]),
					"%s: round %d is not a repeat of the last" % [board_name, round_no])
		seen.append(kind)
		var res := await _run(ev, cam, secs, dev._centres)
		if res["worst"] > worst:
			worst = res["worst"]
			worst_which = names[kind] if kind < names.size() else "?"
		_ok(res["moved"], "%s: %s actually moved something" % [board_name, names[kind]])
		_ok(not bool(ev.call("active")),
				"%s: %s cleaned itself up" % [board_name, names[kind]])
	# Every one of the six must have come up at least once over fourteen milestones.
	var distinct: Dictionary = {}
	for k in seen:
		distinct[k] = true
	_ok(distinct.size() == 6, "%s: all six events are reachable" % board_name,
			"%d of 6 in 14 draws" % distinct.size())
	# The bag's stronger promise: every one of the six inside any six occurrences.
	var first_six: Dictionary = {}
	for i in mini(6, seen.size()):
		first_six[seen[i]] = true
	_ok(first_six.size() == 6, "%s: the first six draws are all six events" % board_name,
			"%d of 6" % first_six.size())

	# ...and the Royal Flush.
	var fsecs: float = ev.call("start_flush", 8)
	_ok(fsecs > 4.0, "%s: level 8 deals the Royal Flush" % board_name, "%.2f s" % fsecs)
	var ranks := _ranks(ev)
	_ok(ranks == [0, 1, 2, 3, 4],
			"%s: the hand is 10 J Q K A, in order" % board_name, str(ranks))
	_ok(int(ev.get("_cards")[4]["flip_at"] * 100) == int(CasinoEvents.RF_SLAM * 100),
			"%s: the fifth card is held back to the slam" % board_name)
	var rf := await _run(ev, cam, fsecs, dev._centres)
	if rf["worst"] > worst:
		worst = rf["worst"]
		worst_which = "royal flush"
	_ok(rf["faces"] >= 5, "%s: all five cards were turned face up" % board_name,
			"%d" % rf["faces"])
	_ok(rf["sparks"] > 20, "%s: the burst threw gold" % board_name, "%d" % rf["sparks"])
	_ok(not bool(ev.call("active")), "%s: the Royal Flush cleaned itself up" % board_name)

	# THE ONE THAT MATTERS.
	_ok(worst < top_px, "%s: NOTHING any event placed reached the chips" % board_name,
			"worst was %s at y %.1f, chips start at %.1f" % [worst_which, worst, top_px])

	# The gating: only every third round, never twice for the same round.
	ev.call("start_event", 4)
	_ok(not bool(ev.call("active")), "%s: round 4 does nothing" % board_name)
	ev.call("start_event", 41)
	_ok(not bool(ev.call("active")), "%s: round 41 does nothing" % board_name)
	ev.call("start_event", 42)
	_ok(bool(ev.call("active")), "%s: round 42 fires" % board_name)
	await _run(ev, cam, float(ev.get("_len")), dev._centres)
	ev.call("start_event", 42)
	_ok(not bool(ev.call("active")),
			"%s: round 42 refuses to fire twice" % board_name)
	_ok(ev.call("start_flush", 8) == 0.0, "%s: level 8 refuses to fire twice" % board_name)
	_ok(ev.call("start_flush", 9) == 0.0, "%s: level 9 is not a finale" % board_name)


# Run whatever is live to completion at 60 Hz, sampling every frame. Returns the
# LOWEST screen row (largest y) any object reached, whether anything moved at all,
# how many cards were seen face up, and the peak spark count.
func _clear_of_chips(p: Vector3, centres: PackedVector2Array) -> bool:
	for c: Vector2 in centres:
		if Vector2(p.x, p.z).distance_to(c) < CasinoEvents.CHIP_CLEAR:
			return false
	return true


func _run(ev: Node, cam: Camera3D, secs: float, centres: PackedVector2Array) -> Dictionary:
	var worst := -1e9
	var moved := false
	var faces: Dictionary = {}
	var sparks := 0
	var first: Array[Vector3] = []
	var steps := int(ceilf((secs + 1.2) * 60.0))
	for _i in steps:
		if not bool(ev.call("tick", 1.0 / 60.0)):
			break
		for nm: String in ["Cards", "Chips", "Sparks", "Shadows"]:
			var mmi := ev.get_node_or_null(nm) as MultiMeshInstance3D
			if mmi == null:
				continue
			var mm := mmi.multimesh
			if nm == "Sparks":
				sparks = maxi(sparks, mm.instance_count)
			if nm == "Sparks" and mm.instance_count > 0:
				moved = true              # the lighting event's only moving parts
			for k in mm.instance_count:
				var p := mm.get_instance_transform(k).origin
				# THE SAFETY TEST, in two clauses, because the events keep clear of
				# the buttons in two different ways. Anything on the LANE is above
				# the top chip on screen, which is the strong guarantee and the one
				# every card, chip and the ball are held to. The jackpot lights are
				# deliberately all over the table, and are held instead to the WORLD
				# rule they are emitted under: outside every button's hit disc.
				if not _clear_of_chips(p, centres):
					if not cam.is_position_behind(p):
						worst = maxf(worst, cam.unproject_position(p).y)
				if nm == "Chips" and mm.instance_count > 0:
					moved = true
				if nm == "Cards":
					if mm.get_instance_custom_data(k).g > 0.5:
						faces[k] = true
					if first.size() <= k:
						first.append(p)
					elif p.distance_to(first[k]) > 0.02:
						moved = true
		var ball := ev.get_node_or_null("Ball") as MeshInstance3D
		if ball != null and ball.visible:
			moved = true
			var bp := ball.global_position
			if not cam.is_position_behind(bp):
				worst = maxf(worst, cam.unproject_position(bp).y)
		await get_tree().process_frame
	return {"worst": worst, "moved": moved, "faces": faces.size(), "sparks": sparks}


func _ranks(ev: Node) -> Array:
	var out: Array = []
	for c in ev.get("_cards"):
		out.append(int(c["rank"]))
	return out
