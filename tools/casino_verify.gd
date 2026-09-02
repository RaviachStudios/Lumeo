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
# ...and neither does game.gd, which owns the ceiling the finale has to fit inside.
const GAME := preload("res://game.gd")

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
		_ok(scene.get_node_or_null("Croupier") != null, "...and a croupier")
		scene.free()

	# THE FIVE-SECOND CEILING ON THE ROYAL FLUSH, asserted across the two files that
	# have to agree about it. The round is frozen for every second of the finale —
	# the ace's flight, the slam, the burst and the whole dance — and game.gd will
	# not hold it past CELEBRATION_MAX whatever the table asks for, so a celebration
	# longer than the cap is not a longer celebration: it is one that gets cut off.
	var freeze := CasinoEvents.T_FLUSH + CasinoEvents.HOLD
	_ok(freeze <= GAME.CELEBRATION_MAX,
			"the Royal Flush fits inside the game's own ceiling",
			"%.2f s of a %.2f s cap" % [freeze, GAME.CELEBRATION_MAX])
	_ok(freeze > 3.0, "...and is long enough to be a celebration", "%.2f s" % freeze)
	# The completion hook the freeze is actually released on. Every other background
	# answers false — see BackgroundScenes.celebration_busy.
	_ok(not BackgroundScenes.celebration_busy(null, THEME),
			"an absent table is not busy")


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

	# ------------------------------------------------------- the croupier
	# He is the one thing on this table that is neither temporary nor dressing: a
	# pair of arms coming down into the top of the frame, close enough to the camera
	# to be the size real hands would be. The rules they are held to are the table's
	# own — clear of the chips at rest, entering from off the top edge, and BIG —
	# and they refuse to be drawn at all on a pose that cannot give them those
	# (CasinoDealer.place), which is why these are conditional on that refusal
	# rather than on the hands always being there.
	var dealer := world.get_node_or_null("Croupier")
	_ok(dealer != null, "%s: the croupier exists" % board_name)
	if dealer != null and bool(dealer.call("placed")):
		var hl := float(dealer.call("hand_len"))
		var box: Rect2 = dealer.call("screen_rect", cam, vps, 0.0)
		var hands: Rect2 = dealer.call("hands_screen_rect", cam, vps, 0.0)
		print("   (hands %.2f long -> arms span screen rows %.0f..%.0f, hand %.0f px)"
				% [hl, box.position.y, box.end.y, hands.size.y])
		# THE HANDS ARE THE RIGHT SIZE NEXT TO THE CARDS THEY DEAL. A real hand is
		# a little over twice a playing card, and the card is the one object on this
		# table whose real size the player already knows — get this wrong and the
		# hand reads as a toy or as a giant whatever else is done to it.
		var card := float(ev.get("_hand_len"))
		# 2.1 is the real ratio; the floor is lower than that because the band caps
		# the hand on the board whose cards are biggest (see HAND_MAX_CHIPS).
		_ok(hl > card * 1.30 and hl < card * 3.4,
				"%s: the hands are a hand's size against the cards" % board_name,
				"%.2f against a %.2f card (%.1fx)" % [hl, card, hl / maxf(card, 0.01)])
		# ...and BIG ON SCREEN, which is the whole reason this is a pair of hands
		# and not the standing figure it replaced.
		# The HAND's box and not the arms', which run off the top of the frame.
		_ok(hands.size.y >= vps.y * CasinoDealer.MIN_HAND_SCREEN * 0.999,
				"%s: ...and big enough to be a close-up" % board_name,
				"%.0f px of %d" % [hands.size.y, int(vps.y)])
		# THEY COME IN FROM THE TOP EDGE. The arms are cut by it, which is what says
		# the dealer is sitting outside the frame rather than standing in it.
		_ok(box.position.y < 1.0,
				"%s: the arms enter from off the top of the frame" % board_name,
				"highest row %.1f" % box.position.y)
		# ...and at REST nothing of them reaches the chips. The deal is the one
		# exemption and it is covered by the freeze; see _run's fourth clause.
		_ok(box.end.y < top_px,
				"%s: nothing of them reaches the chips at rest" % board_name,
				"lowest %.1f vs chips %.1f" % [box.end.y, top_px])
		# The cards have to come OUT of a hand: the release point is inside the box
		# the hands cover, not a spot on the felt that happens to be nearby.
		var slot: Vector3 = ev.call("_hand_pos", ev.get("_hand_at"), card, 0)
		var rp: Vector3 = dealer.call("release_point", slot)
		var rs := cam.unproject_position(rp)
		_ok(rp.y > CasinoWorld.CHIP_TOP,
				"%s: a card leaves the fingers above the table" % board_name,
				"y %.2f" % rp.y)
		_ok(rp.distance_to(slot) > card,
				"%s: ...and far enough out for the card to travel" % board_name,
				"%.2f from the slot" % rp.distance_to(slot))
		_ok(rs.y < top_px + vps.y * 0.30,
				"%s: ...from inside the frame" % board_name, "row %.0f" % rs.y)
		# THE IDLE BREATH is the one animation that runs while the player is
		# actually playing — the deal and the celebration both freeze the round —
		# so it is the one that may never put a finger over a button. Four seconds
		# of it at the rate the table redraws at, measured on every frame.
		var idle_worst := -1e9
		for _k in 60:
			dealer.call("idle", 1.0 / 15.0)
			for p: Vector3 in (dealer.call("silhouette") as PackedVector3Array):
				if not cam.is_position_behind(p):
					idle_worst = maxf(idle_worst, cam.unproject_position(p).y)
		dealer.call("rest")
		_ok(idle_worst < top_px,
				"%s: ...and the idle breath never reaches the chips" % board_name,
				"lowest %.1f vs chips %.1f" % [idle_worst, top_px])
		# ...AND NEITHER DOES THE DEAL. The freeze excuses the CARD's flight across
		# the ring; it does not excuse the hands, and a player watching a deal is
		# looking at the buttons he is about to have to press. Every phase of the
		# deal, aimed at every slot this board deals into, held to the same chip row
		# the resting pose is. This is the check that decides how far forward the
		# clip may reach — get it wrong in Blender and it fails here, not in a
		# screenshot somebody happens to look at.
		var deal_worst := -1e9
		for si in 5:
			var s3: Vector3 = ev.call("_hand_pos", ev.get("_hand_at"), card, si)
			for k in 41:
				dealer.call("deal", -1.0 + 2.0 * float(k) / 40.0, s3)
				for p: Vector3 in (dealer.call("silhouette") as PackedVector3Array):
					if not cam.is_position_behind(p):
						deal_worst = maxf(deal_worst, cam.unproject_position(p).y)
		dealer.call("rest")
		_ok(deal_worst < top_px,
				"%s: ...and the deal itself never reaches the chips" % board_name,
				"lowest %.1f vs chips %.1f" % [deal_worst, top_px])
		# THE PINCH MEETS THE DECK. The whole hand-off rests on this one number: the
		# frame the card changes owner is the frame the fingers are ON the deck's top
		# card, so there is nothing to interpolate across and nothing to hide. It is
		# authored in Blender and asserted here, because a re-export that moved the
		# arm a centimetre would otherwise show up only as a card twitching.
		# The card is taken WHILE IT IS STILL ON THE DECK — the top card pushed out
		# under the deck thumb, which is how a card leaves a deck. Held to under a
		# card's length (a hand is 2.1 cards), so the fingers close on something
		# that is still touching the deck rather than on a gap beside it.
		var pg := float(dealer.call("pickup_gap"))
		_ok(pg < 0.48,
				"%s: the fingers close on the card while it is still on the deck"
				% board_name,
				"%.3f hand lengths from the deck, a card is 0.48" % pg)

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
	# THE HAND, built across the cycle before the flush completes it. Dealt here in
	# the order the player would earn it, so what the finale lands on is what a real
	# game would have put there.
	var low: float = ev.call("start_hand", 3)
	_ok(low > 0.0, "%s: level 3 deals the 10, J and Q" % board_name, "%.2f s" % low)
	# IT IS A THROW, not a card appearing near where it will end up. The distance is
	# measured against the play area's own radius, so "across the table" means the
	# same thing on a three-chip triangle as on a six-chip ring.
	#
	# This is also the regression guard for the bug that made the whole deal
	# invisible: the cards used to be appended by `start_hand` itself and then wiped
	# by `_begin`'s `_clear_all`, so `_cards` was EMPTY here and every frame of the
	# flight was thrown away. An empty list fails the first of these outright.
	var deal_cards: Array = ev.get("_cards")
	_ok(deal_cards.size() == 3,
			"%s: ...and all three are on the table before it starts" % board_name,
			"%d" % deal_cards.size())
	if deal_cards.size() == 3:
		var d0: Dictionary = deal_cards[0]
		var start: Vector3 = d0["from"]
		var trip := start.distance_to(d0["to"] as Vector3)
		var reach := float(ev.get("_reach"))
		# OUT OF HIS FINGERTIPS, exactly — the same point the arm is animated
		# through, not a spot on the felt that happens to be near it. Identity and
		# not proximity: `release_point` is evaluated twice, once here and once by
		# the pose, or the check is worthless.
		if dealer != null and bool(dealer.call("placed")):
			_ok(start.is_equal_approx(dealer.call("release_point", d0["to"])),
					"%s: ...out of the croupier's hand" % board_name, str(start))
		# ...and from CLEAR of the play area, which for a card means one of the two
		# things the flight rule means: outside the ring of buttons, or above the
		# height a card has to be to pass over one. It cannot be the first alone —
		# the hand reaches IN to deal, and on Easy and Medium the row it deals into
		# is well inside the ring, so the fingers let go over the felt every time.
		# What makes that legal is the height, and it is the same constant the
		# flight itself is held to.
		var out := Vector2(start.x, start.z).length()
		_ok(out > reach or start.y > CasinoEvents.FLY_CLEAR,
				"%s: ...from clear of the play area" % board_name,
				"%.2f out of a %.2f reach, at y %.2f" % [out, reach, start.y])
		_ok(trip > float(ev.get("_hand_len")),
				"%s: ...and thrown, not placed" % board_name,
				"%.2f units, card %.2f" % [trip, float(ev.get("_hand_len"))])
		# One after another, and far enough apart to read as three throws.
		# ONE CARD AT A TIME, and strictly: the gap between two cards has to be
		# longer than the whole deal animation, or one arm is dealing two cards at
		# once and the second appears from nowhere while the first is still in the
		# air.
		var gap := float(deal_cards[1]["in_at"]) - float(deal_cards[0]["in_at"])
		_ok(gap >= CasinoEvents.DEAL_WINDUP + CasinoEvents.DEAL_FOLLOW,
				"%s: ...one card at a time, the arm back before the next" % board_name,
				"%.2f s apart, the deal is %.2f long"
				% [gap, CasinoEvents.DEAL_WINDUP + CasinoEvents.DEAL_FOLLOW])
	# ...and the deal counts toward THE ONE THAT MATTERS below, exactly as every
	# other event does. Written without capturing this, the two deals were the only
	# things on this table nothing checked — and the first version of the run-in
	# flew both of them straight over a chip.
	var lo_run := await _run(ev, cam, low, dev._centres)
	if lo_run["worst"] > worst:
		worst = lo_run["worst"]
		worst_which = "hand deal (%s)" % lo_run["worst_mesh"]
	_ok(_hand_ranks(ev) == [0, 1, 2],
			"%s: ...and they stay on the table" % board_name, str(_hand_ranks(ev)))
	_ok(float(lo_run["dealer_moved"]) > 0.01 or not bool(dealer.call("placed")),
			"%s: the croupier's hand dealt them" % board_name,
			"it moved %.3f" % float(lo_run["dealer_moved"]))
	print("   (deal: %d card-frames crossed the ring, lowest at y %.2f of a %.2f floor)"
			% [int(lo_run["flew"]), float(lo_run["low_fly"]),
			CasinoEvents.FLY_CLEAR])
	var king: float = ev.call("start_hand", 6)
	_ok(king > 0.0, "%s: level 6 deals the King" % board_name, "%.2f s" % king)
	var k_run := await _run(ev, cam, king, dev._centres)
	if k_run["worst"] > worst:
		worst = k_run["worst"]
		worst_which = "king deal (%s)" % k_run["worst_mesh"]
	_ok(_hand_ranks(ev) == [0, 1, 2, 3],
			"%s: ...and the row is 10 J Q K" % board_name, str(_hand_ranks(ev)))
	# Nothing happens on the levels between: the hand is a cycle, not a per-round
	# flourish, and dealing twice for one milestone would put six cards in a row.
	_ok(ev.call("start_hand", 4) == 0.0, "%s: level 4 deals nothing" % board_name)
	_ok(ev.call("start_hand", 6) == 0.0, "%s: and level 6 does not deal twice" % board_name)

	var fsecs: float = ev.call("start_flush", 8)
	_ok(fsecs > 4.0, "%s: level 8 deals the Royal Flush" % board_name, "%.2f s" % fsecs)
	# The ACE is the only card the finale itself plays — the other four are already
	# lying on the felt — so the row it completes is the hand plus that one card.
	var ranks := _hand_ranks(ev) + _ranks(ev)
	_ok(ranks == [0, 1, 2, 3, 4],
			"%s: the hand is 10 J Q K A, in order" % board_name, str(ranks))
	_ok(int(ev.get("_cards")[0]["flip_at"] * 100) == int(CasinoEvents.RF_SLAM * 100),
			"%s: the ace is held back to the slam" % board_name)
	var rf := await _run(ev, cam, fsecs, dev._centres, CasinoEvents.RF_DANCE)
	if rf["worst"] > worst:
		worst = rf["worst"]
		worst_which = "royal flush (%s)" % rf["worst_mesh"]
	_ok(rf["faces"] >= 5, "%s: all five cards were turned face up" % board_name,
			"%d" % rf["faces"])
	_ok(rf["confetti"] > 30, "%s: the royal flush threw confetti" % board_name,
			"%d" % rf["confetti"])
	# ...and it is all down before the player is given the board back. This is what
	# makes confetti-over-a-chip acceptable at all; see the third clause in _run.
	_ok(float(rf["conf_last"]) < fsecs,
			"%s: the confetti is gone before the freeze ends" % board_name,
			"last at %.2f s vs freeze %.2f s" % [float(rf["conf_last"]), fsecs])
	_ok(_hand_ranks(ev).is_empty(),
			"%s: and the table was cleared for the next hand" % board_name,
			str(_hand_ranks(ev)))
	_ok(rf["sparks"] > 20, "%s: the burst threw gold" % board_name, "%d" % rf["sparks"])
	# THE DANCE. Two claims, and neither is "it is funny": that it HAPPENS — a
	# celebration whose dancer stands still is the `_emit` bug again — and that it
	# never puts any part of him over the play area, measured on his real poses.
	if bool(dealer.call("placed")):
		_ok(float(rf["dealer_moved"]) > 0.15,
				"%s: the croupier's hands celebrated" % board_name,
				"%.2f units of travel" % float(rf["dealer_moved"]))
		# THE DANCE ONLY EVER GOES UP, and this is where that is proved rather than
		# read off the code: through every frame of the celebration nothing on the
		# dealer is drawn as low as the chips — so it can cover neither the six
		# buttons nor the royal flush lying in the middle of the table.
		_ok(float(rf["dealer_worst"]) < top_px,
				"%s: ...without a hand reaching the chips" % board_name,
				"lowest %.1f vs chips %.1f" % [float(rf["dealer_worst"]), top_px])
		_ok(CasinoEvents.RF_DANCE + CasinoEvents.RF_DANCE_LEN
				<= CasinoEvents.T_FLUSH + 0.0001,
				"%s: ...and stopped before the freeze did" % board_name,
				"dance ends %.2f, event ends %.2f" % [CasinoEvents.RF_DANCE
				+ CasinoEvents.RF_DANCE_LEN, CasinoEvents.T_FLUSH])
	_ok(not bool(ev.call("active")), "%s: the Royal Flush cleaned itself up" % board_name)

	# THE CARD IS IN HIS HAND BEFORE IT IS THROWN, on a deal of its own — the flush
	# has just cleared the table, so this starts a fresh cycle and nothing after it
	# reads the hand. Stepped to just before the first release and read back out of
	# the live MultiMesh: there has to be a card, and it has to be AT THE PINCH. A
	# card that appears at the release, however good the throw is afterwards, is a
	# card that came out of the air, and that is the thing the croupier exists to
	# stop happening.
	if dealer != null and bool(dealer.call("placed")):
		ev.call("start_hand", 3)
		var cards: Array = ev.get("_cards")
		if not cards.is_empty():
			# THE WHOLE LIFE OF ONE CARD, frame by frame out of the live MultiMesh:
			# lying on the deck, drawn off it, carried in the fingers, thrown. The
			# window stops before the second card's turn comes round, so exactly one
			# card is on the table and instance 0 is unambiguously it.
			var in0 := float(cards[0]["in_at"])
			var mark := in0 + CasinoEvents.HAND_FLIGHT + 0.02
			var cmm := ev.get_node_or_null("Cards") as MultiMeshInstance3D
			var deck: Vector3 = dealer.call("deck_point")
			var pin_t := in0 - CasinoEvents.DEAL_WINDUP 				+ CasinoEvents.DEAL_WINDUP * float(dealer.call("pickup_frac"))
			# FOLLOW THE ONE CARD, nearest-neighbour, starting from the deck. The
			# Cards mesh also carries whatever is already lying on the table, so
			# instance 0 is not the dealt card and reading it was measuring a card
			# that never moves.
			var deck_xf: Transform3D = dealer.call("deck_card")
			var first := Vector3.INF
			var prev := Vector3.INF
			var jump := 0.0
			var at_pinch := -1.0
			var frames := 0
			var stepped := 0.0
			while stepped < mark:
				var step := minf(1.0 / 60.0, mark - stepped)
				ev.call("tick", step)
				stepped += step
				if cmm == null or cmm.multimesh.instance_count < 1:
					continue
				var anchor := deck_xf.origin if prev == Vector3.INF else prev
				var cp := Vector3.INF
				var near := 1e9
				for ii in cmm.multimesh.instance_count:
					var q := cmm.multimesh.get_instance_transform(ii).origin
					if q.distance_to(anchor) < near:
						near = q.distance_to(anchor)
						cp = q
				if cp == Vector3.INF:
					continue
				frames += 1
				if first == Vector3.INF:
					first = cp
				if prev != Vector3.INF:
					jump = maxf(jump, prev.distance_to(cp))
				prev = cp
				if at_pinch < 0.0 and stepped >= pin_t:
					at_pinch = cp.distance_to(
						(dealer.call("grip") as Transform3D).origin)
			var cl := float(ev.get("_hand_len"))
			_ok(frames > 0, "%s: the card is drawn before it is thrown" % board_name)
			if frames > 0:
				# IT COMES OFF THE DECK. The first frame it exists it is on the deck
				# in the other hand — not in the dealing hand, and not in the air.
				_ok(first.distance_to(deck) < cl * 1.2,
						"%s: ...starting on the deck in his other hand" % board_name,
						"%.2f from the deck, card is %.2f" % [first.distance_to(deck), cl])
				# ...AND IT NEVER JUMPS. One frame to the next, across the pickup and
				# across the release: this is the check that "no teleportation" is,
				# and it cannot be satisfied by a card that is re-parented anywhere.
				_ok(jump < cl * 0.75,
						"%s: ...and never teleports, deck to hand to table" % board_name,
						"worst frame-to-frame %.3f of a %.2f card" % [jump, cl])
				# ...and on the pickup frame it is IN THE PINCH, to the millimetre.
				_ok(at_pinch >= 0.0 and at_pinch < cl * 0.35,
						"%s: ...taken by the fingers, not met by them" % board_name,
						"%.3f from the pinch at the pickup" % at_pinch)
				# ...AND IT LANDED ON GAMEPLAY'S OWN MARK. This is what stops every
				# check above being satisfied by a card that never left the deck,
				# and it is the one that says the dealer is a visual layer: the slot
				# is chosen by the game, and the hand delivers the card to it.
				var mark_to: Vector3 = cards[0]["to"]
				_ok(prev.distance_to(mark_to) < cl * 0.5,
						"%s: ...and landed on the slot gameplay chose" % board_name,
						"%.2f from the slot, card is %.2f"
						% [prev.distance_to(mark_to), cl])
		ev.call("stop")

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


# `dance_from` is when the CELEBRATION starts, or -1 for a run that has none. The
# croupier's clearance is only measured after it: during a deal his hand comes down
# over the play area on purpose (that is the deal), and the claim being checked is
# about the celebration, which may not.
func _run(ev: Node, cam: Camera3D, secs: float, centres: PackedVector2Array,
		dance_from: float = -1.0) -> Dictionary:
	var worst := -1e9
	var moved := false
	var faces: Dictionary = {}
	var sparks := 0
	var confetti := 0
	var conf_last := -1.0
	# How many card-frames crossed the ring in the air, and the lowest any of them
	# got while it was over a chip. See the fourth clause below.
	var flew := 0
	var low_fly := 1e9
	# THE CROUPIER, watched exactly the way everything else here is: his transforms
	# are read back out of his MultiMesh every frame, not recomputed. Two questions,
	# and the first is the one that catches a whole class of bug this file has
	# caught before (`_emit` was dead code for a build): DID HE ACTUALLY MOVE. The
	# second is the table's own rule — nothing of him is ever drawn as low as the
	# chips, through the DANCE's real poses and not through a bounding box.
	var dnode := ev.get("_dealer") as Node3D
	var d_home: PackedVector3Array = PackedVector3Array()
	var d_moved := 0.0
	var d_worst := -1e9
	var worst_mesh := ""
	var elapsed := 0.0
	var first: Array[Vector3] = []
	var steps := int(ceilf((secs + 1.2) * 60.0))
	for _i in steps:
		if not bool(ev.call("tick", 1.0 / 60.0)):
			break
		elapsed += 1.0 / 60.0
		for nm: String in ["Cards", "Chips", "Sparks", "Shadows", "Confetti"]:
			var mmi := ev.get_node_or_null(nm) as MultiMeshInstance3D
			if mmi == null:
				continue
			var mm := mmi.multimesh
			if nm == "Sparks":
				sparks = maxi(sparks, mm.instance_count)
			if nm == "Confetti":
				confetti = maxi(confetti, mm.instance_count)
				if mm.instance_count > 0:
					moved = true
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
				# CONFETTI IS THE THIRD CLAUSE, and it is allowed over a chip for a
				# reason the other two do not have: the Royal Flush FREEZES the
				# round for its whole length, so while confetti is in the air there
				# is no input for it to obstruct. That exemption is only worth
				# anything if the confetti is actually gone by the time the player
				# gets the board back, which is asserted separately below — not
				# assumed from the two constants that happen to make it true.
				# ...AND A FOURTH CLAUSE: a card IN FLIGHT during an event that
				# FREEZES the round. The croupier throws from behind the table and
				# the hand is in the middle of it, so a dealt card crosses the ring
				# — and it is allowed to on exactly the terms the confetti is: for
				# every frame of the flight `freezes()` is true, so there is no
				# sequence playing and no press to obstruct.
				#
				# It is bounded where the confetti's exemption is not. The card must
				# be FLY_CLEAR above the felt — most of a chip's own height above
				# the chip it is over — so it reads as a card passing OVER a button
				# rather than through one, and its contact shadow gets no exemption
				# at all: SHADOW_GONE is FLY_CLEAR, so a card high enough to be
				# excused here is a card whose shadow is not drawn.
				if nm != "Confetti" and not _clear_of_chips(p, centres):
					var flying: bool = nm == "Cards" \
						and p.y > CasinoEvents.FLY_CLEAR and bool(ev.call("freezes"))
					if flying:
						flew += 1
						low_fly = minf(low_fly, p.y)
					elif not cam.is_position_behind(p):
						var py := cam.unproject_position(p).y
						if py > worst:
							worst = py
							worst_mesh = "%s at %s" % [nm, p]
				if nm == "Confetti" and mm.instance_count > 0:
					conf_last = maxf(conf_last, elapsed)
				if nm == "Chips" and mm.instance_count > 0:
					moved = true
				if nm == "Cards":
					if mm.get_instance_custom_data(k).g > 0.5:
						faces[k] = true
					if first.size() <= k:
						first.append(p)
					elif p.distance_to(first[k]) > 0.02:
						moved = true
		# THE CROUPIER, read back out of his own posed rig — every joint, knuckle
		# and fingertip of both hands, in world space, on every frame.
		if dnode != null and bool(dnode.call("placed")):
			var pts: PackedVector3Array = dnode.call("silhouette")
			for k in pts.size():
				var q := pts[k]
				if d_home.size() <= k:
					d_home.append(q)
				else:
					d_moved = maxf(d_moved, q.distance_to(d_home[k]))
				if dance_from < 0.0 or elapsed < dance_from:
					continue
				if not cam.is_position_behind(q):
					d_worst = maxf(d_worst, cam.unproject_position(q).y)
		var ball := ev.get_node_or_null("Ball") as MeshInstance3D
		if ball != null and ball.visible:
			moved = true
			var bp := ball.global_position
			if not cam.is_position_behind(bp):
				worst = maxf(worst, cam.unproject_position(bp).y)
		await get_tree().process_frame
	return {"worst": worst, "moved": moved, "faces": faces.size(), "sparks": sparks,
		"confetti": confetti, "conf_last": conf_last, "worst_mesh": worst_mesh,
		"flew": flew, "low_fly": low_fly, "dealer_moved": d_moved,
		"dealer_worst": d_worst}


# The SETTLED hand — the cards lying in the middle of the table between milestones.
func _hand_ranks(ev: Node) -> Array:
	var out: Array = []
	for c in ev.get("_hand"):
		out.append(int(c["rank"]))
	return out


func _ranks(ev: Node) -> Array:
	var out: Array = []
	for c in ev.get("_cards"):
		out.append(int(c["rank"]))
	return out
