extends Node
# Acceptance check for MAGICAL LAKE: the lily-pad buttons (lily_buttons.gd), the
# lake environment (lake_world.gd), the façade they are reached through
# (background_scenes.gd) and the shelf they are sold from.
#
# Since the frog was added it also verifies the every-five-rounds event: that it
# fires through the shipping hook and nothing else, that it refuses a repeat, that
# it never puts anything over a button, and that it takes nothing with it when the
# player leaves the skin.
#
# Verifies the claims a screenshot cannot: that the six pads are one design in six
# colours and land on the stock button's contract even though the asset was not
# built to it; that the swap reaches every button on all THREE boards and that
# unequipping puts the stock board back mesh for mesh; that the lake answers every
# façade question and that no other background's answers moved; that the shelf,
# the wallet and the save round-trip; and that the dressing is actually laid, in
# frame, on each board.
#
# RUN IT WITHOUT --headless:
#   Godot_..._console.exe --path . tools/lake_verify.tscn
#
# Most of it is meshes, nodes and dictionaries and would be happy headless, but the
# party section READS INSTANCE TRANSFORMS BACK OFF A MULTIMESH, and a MultiMesh's
# buffer lives in the RenderingServer — under the dummy driver every one of them
# comes back as the IDENTITY. That does not fail loudly: it fails as five pads that
# appear never to have moved, which is a much more convincing bug than it is a
# harness artefact. (It is the same shape of trap as the one in tools/lume_verify.gd,
# where a headless run hangs on a frame that never draws.)

const LILY := preload("res://lily_buttons.gd")
const ICE := preload("res://ice_buttons.gd")
const ShopScreen := preload("res://shop_screen.gd")

const ID := "world_lake"

# The stock button contract, measured off the shipping boards — the same one
# tools/ice_buttons_verify.gd holds.
const FRAME_RADIUS := 1.0          # what the board reserves per button
const AREA_RADIUS := 1.12          # _add_button_area's cylinder
const PRESS := 0.115               # how far a Press_<Key> clip sinks the surface

# The ten 3D backgrounds that existed before the lake. None of their answers may
# move, and the lake must not have leaked into either of their catalogs.
const BEFORE := ["bg_darkmetal", "bg_hexfloor", "bg_neongrid", "bg_circuit",
	"bg_deepspace", "bg_volcanic", "bg_crystal", "bg_arcade",
	"world_forest", "world_ice"]

var _fails := 0

func _ok(cond: bool, what: String, detail: String = "") -> void:
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
	print("\n=== Magical Lake ===\n")
	for _i in 8:
		await get_tree().process_frame        # let CoinsManager load the wallet
	_tone()
	_assets()
	_facade()
	_shelf()
	await _wallet()
	await _boards()
	await _frog()
	await _party()
	_wiring()
	print("\n%s  (%d failure%s)\n" % ["PASS" if _fails == 0 else "FAIL",
			_fails, "" if _fails == 1 else "s"])
	get_tree().quit(1 if _fails > 0 else 0)


# ------------------------------------------------------------------ the tone
# The palette is authored on SCREEN and solved to radiance through a MEASURED
# ramp, so the ramp itself is worth pinning: it is the one number in the lake that
# came out of a render rather than out of a judgement, and a silent edit to it
# would move every colour at once.
func _tone() -> void:
	print("-- tone --")
	_ok(LakeWorld.TONE_RAMP.size() == 65, "the ramp covers screen 0..256 in steps of 4",
		"%d entries" % LakeWorld.TONE_RAMP.size())
	_ok(float(LakeWorld.TONE_RAMP[0]) == 0.0, "black needs no light")
	var mono := true
	for i in range(1, LakeWorld.TONE_RAMP.size()):
		if float(LakeWorld.TONE_RAMP[i]) <= float(LakeWorld.TONE_RAMP[i - 1]):
			mono = false
	_ok(mono, "and the ramp is strictly increasing, so it can be inverted")
	# The transform's toe is the whole reason the palette cannot be authored in
	# linear light: a mid grey needs more than half a unit of radiance, and the
	# darkest colour it can resolve at all still needs a tenth of one.
	var mid := LakeWorld.tone(Color8(128, 128, 128))
	_ok(mid.x > 0.60 and mid.x < 0.95, "screen 128 needs 0.6-0.95 of radiance",
		"%.3f" % mid.x)
	var dark := LakeWorld.tone(Color8(8, 8, 8))
	_ok(dark.x > 0.05, "and screen 8 still needs 0.05+, which is the toe", "%.3f" % dark.x)
	var a := LakeWorld.tone(Color8(40, 90, 200))
	_ok(a.x < a.y and a.y < a.z, "channels stay in the order they were authored in")


# ---------------------------------------------------------------- the assets
func _assets() -> void:
	print("\n-- asset contract --")
	# Six files, seven keys: Easy names its third button Yellow where Medium and
	# Hard name theirs Amber, and a leaf has no reason to draw that distinction.
	_ok(LILY.PAD_FOR.size() == 7, "seven board keys are mapped",
		"%d" % LILY.PAD_FOR.size())
	var pads: Dictionary = {}
	for v in LILY.PAD_FOR.values():
		pads[v] = true
	_ok(pads.size() == 6, "onto six pad colours", str(pads.keys()))
	_ok(String(LILY.PAD_FOR["Amber"]) == String(LILY.PAD_FOR["Yellow"]),
		"Amber and Yellow share one pad")

	var geo := ""
	for key: String in LILY.PAD_FOR.keys():
		var kit: Dictionary = LILY.build(key)
		if kit.is_empty():
			_ok(false, "%s builds" % key, "LilyButtons.build returned nothing")
			continue
		var s: Mesh = kit["surface"]
		var f: Mesh = kit["frame"]

		# Two surfaces on each, because MemoryGameUI reads slot 0 and slot 1 BY
		# NUMBER: the pad's dish and rim, and the waterline's meniscus and halo.
		_ok(s.get_surface_count() == 2, "%s pad has 2 surfaces (dish, rim)" % key,
			"%d" % s.get_surface_count())
		_ok(f.get_surface_count() == 2, "%s waterline has 2 surfaces (lip, halo)" % key,
			"%d" % f.get_surface_count())
		# Neither half may be empty: the split is by triangle centroid radius, and a
		# threshold past the pad's outline would put every face in one of them and
		# silently cost the board its whole flash channel.
		for i in mini(2, s.get_surface_count()):
			_ok(s.surface_get_array_index_len(i) >= 300,
				"%s pad surface %d carries real geometry" % [key, i],
				"%d indices" % s.surface_get_array_index_len(i))

		var sa := s.get_aabb()
		_ok(_radius(sa) <= AREA_RADIUS,
			"%s pad fits inside the hit cylinder" % key, "r %.3f" % _radius(sa))
		# The pad's underside must be AT the board plane: the waterline is derived
		# from it (LakeWorld.WATER_Y crosses the dish at about r 0.55), and a pad
		# floated even a centimetre would sit ON the lake instead of IN it.
		_ok(absf(sa.position.y) < 0.001, "%s pad's underside is the board plane" % key,
			"y %.4f" % sa.position.y)
		# And it must survive a press without the rim going under: the clip sinks
		# the surface 11.5 cm, so the rim has to clear the waterline by then.
		var rim_after := sa.end.y - PRESS
		_ok(rim_after > LakeWorld.WATER_Y + 0.05,
			"%s pad's rim still rides the water at the bottom of a press" % key,
			"rim %.3f vs water %.3f" % [rim_after, LakeWorld.WATER_Y])

		# One design in six colours: every pad is the same mesh.
		var sig := "%.4f %.4f %d" % [sa.position.y, sa.size.y,
			s.surface_get_array_len(0) + s.surface_get_array_len(1)]
		if geo == "":
			geo = sig
		else:
			_ok(sig == geo, "%s is the same pad as the first" % key, sig)

		# The waterline pieces are FLAT and sit at the surface, and they belong to
		# the STATIONARY frame node, so they stay put while the pad sinks through.
		var fa := f.get_aabb()
		_ok(fa.size.y < 0.02, "%s waterline is flat" % key, "%.4f tall" % fa.size.y)
		_ok(absf(fa.position.y - LakeWorld.WATER_Y) < 0.02,
			"%s waterline sits at the water" % key, "y %.4f" % fa.position.y)
		_ok(_radius(fa) > FRAME_RADIUS and _radius(fa) < AREA_RADIUS + 0.9,
			"%s halo spreads past the pad but not onto its neighbour" % key,
			"r %.3f" % _radius(fa))

		# The materials. EMISSION_OP_MULTIPLY renders BLACK under GL Compatibility
		# (tools/emis_probe.tscn), and emission_energy_multiplier scales in sRGB —
		# so ADD, everything in the colour, and the multiplier pinned at 1.
		for pair: Array in [[s, 0], [s, 1], [f, 1]]:
			var mesh: Mesh = pair[0]
			var slot: int = pair[1]
			if slot >= mesh.get_surface_count():
				continue
			var m := mesh.surface_get_material(slot) as StandardMaterial3D
			if m == null:
				_ok(false, "%s slot %d has a StandardMaterial3D" % [key, slot],
					"the emission state machine casts to one")
				continue
			_ok(m.emission_enabled, "%s slot %d emits" % [key, slot])
			_ok(m.emission_operator == BaseMaterial3D.EMISSION_OP_ADD,
				"%s slot %d uses ADD, not the black-rendering MULTIPLY" % [key, slot])
			_ok(is_equal_approx(m.emission_energy_multiplier, 1.0),
				"%s slot %d keeps the multiplier at 1" % [key, slot],
				"%.3f" % m.emission_energy_multiplier)
			_ok(m.disable_ambient_light,
				"%s slot %d cannot mirror the board's sky" % [key, slot])

	# The rim has to be BRIGHTER than the dish, or the split bought nothing.
	_ok(LILY.RIM_EMISSION > LILY.DISH_EMISSION,
		"the rim is the brighter of the two channels")
	# The pads shorten the press; the snowflakes do NOT. An ice crystal dropping into
	# its socket is what the board's stroke was authored for, and that look is signed
	# off — this is the assertion that keeps one skin's tuning out of the other's.
	_ok(float(LILY.PRESS_SCALE) > 0.2 and float(LILY.PRESS_SCALE) < 0.7,
		"the pads take a fraction of the board's press stroke",
		"%.2f" % LILY.PRESS_SCALE)
	# Through a GDScript-typed local: GDScript refuses `get()` on a class NAME at
	# parse time ("make an instance instead"), which is also why MemoryGameUI reads
	# a skin's constants off a `want: GDScript` rather than off the class.
	var ice_script: GDScript = load("res://ice_buttons.gd")
	_ok(ice_script.get("PRESS_SCALE") == null,
		"the snowflakes keep the board's full stroke")
	# And the six pads' brightness spread must be narrower than the asset's raw
	# 2.5x, which is what NORM_POWER is for.
	var lo := INF
	var hi := 0.0
	for key: String in ["Crimson", "Jade", "Cyan", "Amber", "Violet", "Magenta"]:
		var kit: Dictionary = LILY.build(key)
		if kit.is_empty():
			continue
		var m := (kit["surface"] as Mesh).surface_get_material(0) as StandardMaterial3D
		if m == null:
			continue
		var e := m.emission
		var peak: float = maxf(e.r, maxf(e.g, e.b))
		lo = minf(lo, peak)
		hi = maxf(hi, peak)
	_ok(hi / maxf(lo, 0.0001) < 2.0,
		"no pad is twice as bright as another at idle", "spread %.2fx" % (hi / lo))


# ---------------------------------------------------------------- the façade
func _facade() -> void:
	print("\n-- façade --")
	_ok(LakeWorld.has_scene(ID), "LakeWorld owns %s" % ID)
	_ok(BackgroundScenes.has_scene(ID), "and the façade forwards it")
	_ok(not BackgroundScenes.CATALOG.has(ID), "it did not leak into the Themes1 catalog")
	_ok(not WorldScenes.has_scene(ID), "nor into the Themes2 one")
	_ok(BackgroundScenes.display_name(ID) == "Magical Lake", "it has a display name",
		BackgroundScenes.display_name(ID))
	_ok(BackgroundScenes.all_order().has(ID), "and it is in all_order")

	# The lake is a SURFACE: unbounded, never seated, never scaled, always moving,
	# and its play surface is the waterline rather than y = 0.
	_ok(BackgroundScenes.is_animated(ID), "the water is never still")
	_ok(is_equal_approx(BackgroundScenes.idle_hz(ID), 30.0),
		"it is nudged at 30 Hz", "%.1f" % BackgroundScenes.idle_hz(ID))
	_ok(is_equal_approx(BackgroundScenes.seat_wanted(ID, 6.0), 0.0), "it is never seated")
	_ok(is_equal_approx(BackgroundScenes.seat_allowed(ID, 3.5), 0.0), "nor allowed to be")
	_ok(is_equal_approx(BackgroundScenes.fit_scale(ID, null, Vector2(1280, 720), 3.5), 1.0),
		"nor scaled")
	_ok(is_equal_approx(BackgroundScenes.pool_plane_y(ID), LakeWorld.WATER_Y),
		"the ground pools lie on the WATER, not on y = 0",
		"%.3f" % BackgroundScenes.pool_plane_y(ID))
	_ok(is_equal_approx(BackgroundScenes.pool_radius(ID), 0.0),
		"and are not clipped — a lake has no rim")
	_ok(BackgroundScenes.pool_gain(ID) < 1.0,
		"the pools are turned down for a bright surface",
		"%.2f" % BackgroundScenes.pool_gain(ID))

	# Nothing else may have moved. pool_gain in particular multiplies GLOW_PEAK on
	# EVERY background.
	#
	# Two of the eleven answer with less than a full pool now, and both are surfaces
	# bright enough to wash out under six of them: this lake, and Ice Kingdom since
	# its ground was rebuilt in Godot (ice_world.gd, POOL_GAIN). Every imported
	# background still keeps all of it.
	for id in BEFORE:
		var sid := String(id)
		_ok(BackgroundScenes.has_scene(sid), "%s is still a 3D background" % sid)
		if sid == "world_ice":
			_ok(BackgroundScenes.pool_gain(sid) < 1.0,
				"%s turns its pools down too — its ground is generated now" % sid,
				"%.2f" % BackgroundScenes.pool_gain(sid))
			continue
		_ok(is_equal_approx(BackgroundScenes.pool_gain(sid), 1.0),
			"%s keeps the full pool" % sid, "%.2f" % BackgroundScenes.pool_gain(sid))
	_ok(is_equal_approx(BackgroundScenes.pool_gain("default"), 1.0),
		"and so does no background at all")

	var scene := BackgroundScenes.build(ID)
	_ok(scene != null, "it builds")
	if scene != null:
		_ok(scene.has_method("set_layout") and scene.has_method("splash"),
			"and answers the two hooks the board drives it with")
		scene.free()

	# The waterline is derived from the pad, not chosen, so it has to stay inside
	# the pad's own dish — see LakeWorld.WATER_Y.
	_ok(LakeWorld.WATER_Y > 0.05 and LakeWorld.WATER_Y < 0.13,
		"the waterline crosses the pad's dish", "%.3f" % LakeWorld.WATER_Y)


# ----------------------------------------------------------------- the shelf
func _shelf() -> void:
	print("\n-- shelf --")
	_ok(CoinsManager.THEMES.has(ID), "it is an ordinary theme underneath")
	if CoinsManager.THEMES.has(ID):
		_ok(CoinsManager.theme_price(ID) == 0, "free",
			"%d" % CoinsManager.theme_price(ID))
		_ok(String(CoinsManager.THEMES[ID].get("category", "")) == "themes",
			"in the themes category")

	var defs: Array = ShopScreen.SKIN_DEFS
	var entry: Dictionary = {}
	for d in defs:
		if String((d as Dictionary).get("id", "")) == ID:
			entry = d
	_ok(not entry.is_empty(), "it has a SPECIAL SKINS card")
	if not entry.is_empty():
		_ok(bool(entry.get("released", false)), "which is released")
		_ok(String(entry.get("theme", "")) == ID,
			"and is theme-backed, so price/owned/equip come from the theme path")
		_ok(String(entry.get("chip", "")) != "",
			"and says which buttons it brings", String(entry.get("chip", "")))
	_ok(ShopScreen.SKIN_FRAME_COLORS.has(ID), "it has its own card frame colours")

	# Listed ONCE. equip_skin would set simon_mode = SKIN, and _wanted_background
	# returns "" in that mode — which would kill the lake it is selling.
	_ok(not CoinsManager.SIMON_SKINS.has(ID), "it is NOT a wheel skin")
	var items: Array = []
	for cat in ShopScreen.CATEGORIES:
		if String((cat as Dictionary).get("key", "")) == "themes":
			items = (cat as Dictionary).get("items", [])
	_ok(not items.has(ID), "and it is off the THEMES grid — one shelf, one card")
	_ok(not items.has("world_ice"), "as Ice Kingdom still is")


# ---------------------------------------------------------------- the wallet
func _wallet() -> void:
	print("\n-- wallet --")
	# Nothing may be handed out: a default that pre-owned it would rewrite the
	# meaning of every wallet already on disk.
	CoinsManager._apply_doc({"coins": 500, "owned_themes": {"midnight": true},
		"selected_theme": "midnight"})
	_ok(not CoinsManager.owns(ID), "an old wallet does not own it")
	_ok(CoinsManager.selected_theme == "midnight", "and keeps its own selection")

	_ok(CoinsManager.purchase_theme(ID), "it can be claimed")
	_ok(CoinsManager.owns(ID), "and is then owned")
	_ok(CoinsManager.balance == 500, "for nothing", "%d" % CoinsManager.balance)
	CoinsManager.select_theme(ID)
	_ok(CoinsManager.selected_theme == ID, "and equips")
	_ok(LILY.active(), "which is what puts the pads on")
	_ok(not ICE.active(), "and takes the snowflakes off")

	# A reload has to bring both halves back.
	var doc := {"coins": 500, "owned_themes": {ID: true}, "selected_theme": ID}
	CoinsManager._apply_doc(doc)
	await get_tree().process_frame
	_ok(CoinsManager.owns(ID) and CoinsManager.selected_theme == ID,
		"a saved wallet comes back owning and wearing it")

	# And switching away must not leave the pads on.
	CoinsManager.select_theme("default")
	_ok(not LILY.active(), "unequipping takes them off again")


# ---------------------------------------------------------------- the boards
func _boards() -> void:
	print("\n-- boards --")
	CoinsManager._apply_doc({"coins": 500, "owned_themes": {ID: true},
		"selected_theme": ID})
	await get_tree().process_frame
	# A frame the player owns and is wearing, so the suppression below is testing
	# something: the pads must cover it, and it must still be theirs afterwards.
	if not CoinsManager.owned_frames.has("aurora"):
		CoinsManager.owned_frames.append("aurora")
	CoinsManager.selected_frame = "aurora"

	for spec: Array in [["Easy", EasyGameUI], ["Moderate", MemoryGameUI], ["Hard", HardGameUI]]:
		var label: String = spec[0]
		var dev: MemoryGameUI = (spec[1] as GDScript).new()
		dev.input_enabled = false
		dev.size = Vector2(1280, 720)
		add_child(dev)
		await get_tree().process_frame
		dev.configure(dev._count, [])
		for _i in 6:
			await get_tree().process_frame

		_ok(dev.button_skin_id() == ID, "%s wears the pads" % label,
			dev.button_skin_id())
		var board := dev.find_child("MemoryGame_UI", true, false) as Node3D
		_ok(board != null, "%s built its board" % label)

		# Every button, and the nodes the press clips and the hit areas hang off.
		var stock: Dictionary = {}
		for key: String in dev._keys:
			var surf := board.find_child("Button_%s_Surface" % key, true, false) as MeshInstance3D
			var frame := board.find_child("Button_%s_Frame" % key, true, false) as MeshInstance3D
			var holder := board.find_child("Button_%s" % key, true, false) as Node3D
			if surf == null or frame == null or holder == null:
				_ok(false, "%s %s has its three nodes" % [label, key])
				continue
			var kit: Dictionary = LILY.build(key)
			_ok(surf.mesh == kit.get("surface"), "%s %s wears the pad mesh" % [label, key])
			_ok(frame.mesh == kit.get("frame"), "%s %s wears the waterline" % [label, key])
			_ok(surf.transform.is_equal_approx(Transform3D.IDENTITY),
				"%s %s surface keeps its identity transform" % [label, key])
			_ok(holder.get_node_or_null("Hit_%s" % key) != null,
				"%s %s still has its hit area" % [label, key])
			_ok(dev._ap != null and dev._ap.has_animation("Press_%s" % key),
				"%s %s still has its press clip" % [label, key])
			stock[key] = surf.mesh

		# --- press travel -------------------------------------------------
		# The pads take a scaled amplitude of the board's own press stroke, and
		# NOTHING else about the clip may move: same length, same key count, same
		# timing, same overshoot on the way back.
		var lily_key: String = dev._keys[0]
		var clip := dev._ap.get_animation("Press_%s" % lily_key)
		_ok(clip != null, "%s still has its press clip" % label)
		if clip != null:
			var deepest := 0.0
			var keys := 0
			for t in clip.get_track_count():
				if clip.track_get_type(t) != Animation.TYPE_POSITION_3D:
					continue
				if String(clip.track_get_path(t)).ends_with("Button_%s_Surface" % lily_key):
					keys = clip.track_get_key_count(t)
					for k in keys:
						deepest = minf(deepest, (clip.track_get_key_value(t, k) as Vector3).y)
			var want_travel: float = -0.115 * float(LILY.PRESS_SCALE)
			_ok(absf(deepest - want_travel) < 0.002,
				"%s presses %.0f mm, not the board's 115" % [label, -deepest * 1000.0],
				"%.4f vs %.4f" % [deepest, want_travel])
			_ok(is_equal_approx(clip.length, 0.2833333), "%s keeps the board's timing" % label,
				"%.4f" % clip.length)
			_ok(keys == 10, "%s keeps every key of the stroke" % label, "%d" % keys)
			# ...and the pad must still be clear of the water at the bottom of it.
			var dish_top := 0.249 + deepest
			_ok(dish_top > LakeWorld.WATER_Y + 0.04,
				"%s pad's dish stays proud of the water when pressed" % label,
				"%.0f mm above" % ((dish_top - LakeWorld.WATER_Y) * 1000.0))

		# The bezel cosmetics are suppressed: one of them would cover the meniscus.
		_ok(CoinsManager.selected_frame == "aurora", "the player still owns their frame")
		var worn_any := false
		for key: String in dev._keys:
			var frame := board.find_child("Button_%s_Frame" % key, true, false) as MeshInstance3D
			if frame != null and frame.get_parent().get_node_or_null(ButtonFrames.INSTANCE_NAME) != null:
				worn_any = true
		_ok(not worn_any, "%s wears no cosmetic bezel over the waterline" % label)

		# The lake itself, and the dressing laid through this board's own camera.
		var lake := dev._bg_scene
		_ok(lake != null, "%s is standing on a lake" % label)
		if lake != null:
			var dress := lake.find_child("Dressing", false, false)
			_ok(dress != null, "%s lake has its dressing node" % label)
			if dress != null:
				var total := 0
				for c in dress.get_children():
					if c is MultiMeshInstance3D:
						var n: int = (c as MultiMeshInstance3D).multimesh.instance_count
						_ok(n > 0, "%s lake laid its %s" % [label, c.name], "%d" % n)
						total += n
				_ok(total > 30, "%s lake is dressed" % label, "%d props" % total)
			# A press starts a splash and nothing else does.
			_ok(not lake.is_processing(), "%s lake is idle until a button moves" % label)
			dev.set_press(0, 1.0)
			_ok(lake.is_processing(), "%s a press starts the splash" % label)
			dev.set_press(0, 0.0)

		# And unequipping puts the stock board back, mesh for mesh.
		dev.preview_background = "bg_neongrid"
		dev._on_background_changed()
		await get_tree().process_frame
		_ok(dev.button_skin_id() == "", "%s goes back to stock buttons" % label)
		var restored := true
		for key: String in dev._keys:
			var surf := board.find_child("Button_%s_Surface" % key, true, false) as MeshInstance3D
			# The pad mesh must be GONE, and what replaced it must be the board's own.
			if surf == null or surf.mesh == stock.get(key) or surf.mesh == null:
				restored = false
		_ok(restored, "%s pads are gone and the board's own meshes are back" % label)
		# Keep what the stock board actually wears, for the two-skin check below.
		var stock_now: Dictionary = {}
		for key: String in dev._keys:
			var surf := board.find_child("Button_%s_Surface" % key, true, false) as MeshInstance3D
			if surf != null:
				stock_now[key] = surf.mesh
		stock = stock_now
		_ok(dev._bg_scene != null and dev._bg_scene.name != "MagicalLake",
			"%s stands on the other background instead" % label)

		# ...and straight from one SKIN to the other, which is the path that made
		# _apply_button_skin record the stock meshes only once: recording them on
		# every swap would have saved the ice meshes as "stock" and stranded the
		# board on them for the rest of the session.
		dev.preview_background = ICE.THEME_ID
		dev._on_background_changed()
		await get_tree().process_frame
		_ok(dev.button_skin_id() == ICE.THEME_ID, "%s can go straight to the ice" % label)
		dev.preview_background = ID
		dev._on_background_changed()
		await get_tree().process_frame
		_ok(dev.button_skin_id() == ID, "%s and straight back to the pads" % label)
		dev.preview_background = ""
		dev.preview_bare = true
		dev._on_background_changed()
		await get_tree().process_frame
		var back := true
		for key: String in dev._keys:
			var surf := board.find_child("Button_%s_Surface" % key, true, false) as MeshInstance3D
			if surf == null or surf.mesh != stock.get(key):
				back = false
		_ok(dev.button_skin_id() == "" and back,
			"%s still has the STOCK meshes after two skins" % label)
		# The scaled press clips are a NEW library over a shared resource. Going back
		# to stock has to restore the board's own 115 mm stroke, or every later board
		# in the session inherits the lily pad's.
		var back_clip := dev._ap.get_animation("Press_%s" % lily_key)
		var stock_deep := 0.0
		if back_clip != null:
			for t in back_clip.get_track_count():
				if back_clip.track_get_type(t) == Animation.TYPE_POSITION_3D \
						and String(back_clip.track_get_path(t)).ends_with("Button_%s_Surface" % lily_key):
					for k in back_clip.track_get_key_count(t):
						stock_deep = minf(stock_deep, (back_clip.track_get_key_value(t, k) as Vector3).y)
		_ok(absf(stock_deep + 0.115) < 0.002,
			"%s gets the board's full 115 mm stroke back" % label, "%.4f" % stock_deep)

		dev.queue_free()
		await get_tree().process_frame


# ------------------------------------------------------------------- the frog
# The every-five-rounds event (lake_world.gd, THE FROG). What a filmstrip
# (tools/frog_shot.tscn) cannot check is the part that is about state rather than
# about pictures: what fires it, what refuses to fire it twice, whether it is
# really a no-op on every other background, and whether leaving the skin mid-jump
# leaves anything behind.
func _frog() -> void:
	print("-- the frog --")

	# It reaches the lake through the SHIPPING call and no other. game.gd calls
	# `_wheel.background_milestone(level)`; if any link in that chain is missing the
	# event can still be fired by hand in a harness and will never fire in the game.
	var probe := MemoryGameUI.new()
	_ok(probe.has_method("background_milestone"), "the board takes a completed round")
	probe.free()
	# `has_method` on a class name is a parse error in GDScript ("make an instance
	# instead"), and BackgroundScenes is all static — so the façade's link is checked
	# through the script resource instead.
	var facade: GDScript = load("res://background_scenes.gd")
	var named := false
	for m: Dictionary in facade.get_script_method_list():
		if String(m.get("name", "")) == "note_milestone":
			named = true
	_ok(named, "and the façade forwards it")

	var dev := HardGameUI.new()
	dev.input_enabled = false
	dev.size = Vector2(1280, 720)
	add_child(dev)
	await get_tree().process_frame
	dev.configure(6, [])
	for _i in 6:
		await get_tree().process_frame

	dev.preview_background = ID
	dev._on_background_changed()
	for _i in 4:
		await get_tree().process_frame
	var lake := dev._bg_scene
	_ok(lake != null and lake.has_method("start_frog_event"), "the lake has the event")
	if lake == null:
		dev.queue_free()
		return

	_ok(not lake.call("frog_event_active"), "nothing is running before a round ends")
	var freeze: float = dev.background_milestone(5)
	_ok(lake.call("frog_event_active"), "round 5 starts it")
	_ok(freeze > 0.0, "and it asks the round to freeze", "%.2f s" % freeze)

	# The duplicate guard. A completion signal that fires twice for one round must
	# not restart the frog half way across the lake — and must not hand the round a
	# second freeze either, or one event would pause gameplay twice over.
	var t_before: float = lake.get("_ev_t")
	for _i in 3:
		await get_tree().process_frame
	_ok(dev.background_milestone(5) == 0.0, "a repeat of round 5 asks for no freeze")
	_ok(float(lake.get("_ev_t")) > t_before, "firing round 5 again does not restart it")
	_ok(dev.background_milestone(6) == 0.0, "and neither does a round in between")
	_ok(float(lake.get("_ev_t")) > t_before, "and neither does a round in between")

	# The lane. This is the promise the whole placement exists to keep, and it is
	# checked the way the code makes it: every point on the lane is at least
	# |c.z - z| from every button centre, so the crossing cannot pass over one.
	var cam: Camera3D = null
	for c in dev._vp.get_children():
		if c is Camera3D:
			cam = c
	var z: float = float(lake.get("_p_pad").z)
	var gap := 1e9
	for c: Vector2 in dev._centres:
		gap = minf(gap, absf(c.y - z))
	_ok(gap > FRAME_RADIUS, "the lane clears every button", "%.2f" % gap)

	# ...and that it reads RIGHT to LEFT across the frame, which is the one thing
	# about this event the brief is explicit about and the easiest to invert.
	var xs := PackedFloat32Array()
	for nm: String in ["_p_in", "_p_pad", "_p_out"]:
		xs.append(cam.unproject_position(lake.get(nm)).x)
	_ok(xs[0] > xs[1] and xs[1] > xs[2],
		"the crossing runs right to left", str(xs))
	_ok(xs[0] > 1280.0 and xs[2] < 0.0,
		"and enters and leaves outside the frame", "%.0f .. %.0f" % [xs[0], xs[2]])
	# The stop is the MIDDLE of the frame, which is the whole composition of the
	# rewritten event (RIGHT -> CENTRE -> LEFT, one landing). The tolerance is the
	# clearance window the stop is allowed to slide inside, not a soft assertion.
	_ok(absf(xs[1] / 1280.0 - 0.5) <= 0.07,
		"and it stops in the middle of the frame", "%.3f of width" % (xs[1] / 1280.0))

	# The SHAPE of the timeline, which is the half of this event the brief is most
	# specific about: one landing, one jump off, and the whole thing over in about
	# four seconds so it does not become a scene played at the player.
	var k_in: float = float(lake.get("_k_in"))
	var k_land: float = float(lake.get("_k_land"))
	var k_go: float = float(lake.get("_k_go"))
	var k_gone: float = float(lake.get("_k_gone"))
	var k_end: float = float(lake.get("_k_end"))
	_ok(k_in < k_land and k_land < k_go and k_go < k_gone and k_gone <= k_end,
		"the timeline runs in one direction")
	_ok(absf(k_end - 4.0) < 0.30, "and the whole event is about four seconds",
		"%.2f s" % k_end)
	_ok(k_go - k_land < 0.45, "the pause on the pad is a beat, not an interaction",
		"%.2f s" % (k_go - k_land))
	_ok(k_gone - k_go >= 1.0, "and the exit is ONE jump long enough to read as one",
		"%.2f s" % (k_gone - k_go))
	# THE FREEZE, which is the half of this event that is not a picture. Gameplay may
	# not resume when the frog lands, when it pushes off, or when it reaches the left
	# edge: the number handed to game.gd has to cover the LAST frame of the event,
	# which is the pad back under the water and the final ring gone.
	_ok(freeze >= k_end, "the freeze covers the whole event, not just the crossing",
		"freeze %.2f vs end %.2f" % [freeze, k_end])
	_ok(freeze > k_gone, "so nothing resumes when the frog leaves the frame",
		"freeze %.2f vs gone %.2f" % [freeze, k_gone])
	_ok(freeze - k_end < 0.40, "and it does not sit on a black screen afterwards",
		"%.2f s of margin" % (freeze - k_end))
	# There is no second stop and no bounce, and the way to prove that is that the
	# scene has nowhere to put one: the four names the old two-hop version needed
	# are gone from the script rather than merely unused.
	var lake_src: GDScript = load("res://lake_world.gd")
	var src_text: String = lake_src.source_code
	for gone: String in ["_p_mid", "_k_mid", "_k_bounce", "EV_BOUNCE"]:
		_ok(not src_text.contains(gone), "no trace of the old %s" % gone)
	# The ribbit is a real sound on the ambience channel, not a call into nothing.
	# Checked as SAMPLES, because a generator whose envelope never opens returns a
	# perfectly valid, perfectly silent stream and every other test still passes.
	_ok(AudioManager.has_method("play_frog_ribbit"), "the frog has a voice")
	var rib: AudioStreamWAV = AudioManager._make_ribbit()
	_ok(rib != null and rib.data.size() > 0, "and the ribbit is generated")
	if rib != null:
		var n := rib.data.size() / 2
		var peak := 0
		var quiet := 0
		for i in n:
			var v: int = absi(rib.data.decode_s16(i * 2))
			peak = maxi(peak, v)
			if v < 64:
				quiet += 1
		_ok(peak > 6000, "it is audible", "peak %d of 32767" % peak)
		_ok(absf(float(n) / float(AudioManager.SR) - 0.30) < 0.02,
			"it is short", "%.2f s" % (float(n) / float(AudioManager.SR)))
		# Two syllables means a gap: a single note of this length is 5-10 % quiet
		# samples (its own zero crossings), and this one has the 40 ms hole as well.
		_ok(float(quiet) / float(n) > 0.12, "and it has two syllables, not one",
			"%.0f%% silent" % (100.0 * float(quiet) / float(n)))

	# The event is drawn, and it is drawn on the BACKGROUND layer — a frog on the
	# board's layer would be lit by the board's studio and by a skin's rig, neither
	# of which knows anything about it.
	var ev := lake.get_node_or_null("FrogEvent") as Node3D
	_ok(ev != null and ev.visible, "the event is built and visible")
	if ev != null:
		var wrong := PackedStringArray()
		for n in ev.get_children():
			if (n as GeometryInstance3D).layers != LakeWorld.BG_LAYER:
				wrong.append(n.name)
		_ok(wrong.is_empty(), "every piece of it is on the background layer", str(wrong))
		# SIX nodes now, and never more than four drawing at once: the pad and the
		# frog belong to the crossing, the two party MultiMeshes belong to level 8,
		# the ripples and droplets are shared, and the two events refuse to run
		# together. Everything not in use is hidden rather than empty.
		_ok(ev.get_child_count() == 6, "and it is six nodes, not a particle system",
			str(ev.get_child_count()))
		var lit := 0
		for n in ev.get_children():
			if (n as Node3D).visible:
				lit += 1
		_ok(lit <= 4, "with at most four of them drawing at once", str(lit))
		_ok(not (ev.get_node("PartyPads") as Node3D).visible
				and not (ev.get_node("PartyFrogs") as Node3D).visible,
			"and the party's pairs are not standing in the crossing")

	# Leaving the skin mid-event. The lake is freed with the background, so the
	# frog, the pad, the ripples and the clock go with it — there is nothing to stop
	# because there is nothing left. Then coming back must be able to run it again.
	dev.preview_background = ICE.THEME_ID
	dev._on_background_changed()
	for _i in 4:
		await get_tree().process_frame
	_ok(not is_instance_valid(lake) or lake.get_parent() == null,
		"switching away takes the whole event with the lake")
	dev.background_milestone(15)          # must be a no-op, not an error
	_ok(dev.button_skin_id() == ICE.THEME_ID, "a completed round on the ice does nothing")

	dev.preview_background = ID
	dev._on_background_changed()
	for _i in 4:
		await get_tree().process_frame
	var lake2 = dev._bg_scene
	_ok(lake2 != null and not lake2.call("frog_event_active"),
		"coming back starts quiet")
	dev.background_milestone(20)
	_ok(lake2.call("frog_event_active"), "and the event works again")

	# And it ends. A cosmetic that never turns itself off is a cosmetic that keeps
	# the whole scene's _process alive for the rest of the match.
	var guard := 0
	while lake2.call("frog_event_active") and guard < 1200:
		await get_tree().process_frame
		guard += 1
	_ok(not lake2.call("frog_event_active"), "the event finishes on its own")
	# One more frame: the tick that ENDS the event has already counted itself as
	# live, so _process switches off on the one after it.
	await get_tree().process_frame
	_ok(not lake2.is_processing(), "and puts the scene back to sleep")

	dev.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------ the party
# The level-8 celebration. What a screenshot cannot show is the whole of what the
# brief is about here, so almost everything below is sampled over the RUNNING event
# rather than read off it once:
#
#   * five pads and five frogs, in five different places on screen;
#   * a frog and its pad are ONE unit — the two transforms are checked against each
#     other on every frame of the five seconds, which is what proves there is no
#     jump on, no jump off and no jump between (a frog that moved to another pad
#     would break the lateral test on the frame it left);
#   * every frog faces the player;
#   * the pairs start under the water and end under it, and no frog is left visible
#     after its pad has gone;
#   * and the freeze handed to game.gd covers all of it.
func _party() -> void:
	print("-- the level-8 party --")
	CoinsManager.selected_theme = ID
	var dev := HardGameUI.new()
	dev.input_enabled = false
	dev.size = Vector2(1280, 720)
	add_child(dev)
	await get_tree().process_frame
	dev.configure(6, [])
	for _i in 6:
		await get_tree().process_frame
	dev.preview_background = ID
	dev._on_background_changed()
	for _i in 4:
		await get_tree().process_frame

	var lake := dev._bg_scene
	_ok(lake != null and lake.has_method("start_party_event"), "the lake has the party")
	if lake == null:
		dev.queue_free()
		return
	var cam: Camera3D = null
	for c in dev._vp.get_children():
		if c is Camera3D:
			cam = c

	_ok(not lake.call("party_event_active"), "nothing is running before level 8 ends")
	var freeze: float = dev.background_celebration(8)
	_ok(lake.call("party_event_active"), "completing level 8 starts it")
	_ok(absf(freeze - 5.0) < 0.35, "and the whole party is about five seconds",
		"%.2f s" % freeze)
	_ok(freeze >= LakeWorld.PT_TOTAL,
		"the freeze covers the whole of it, cleanup included",
		"freeze %.2f vs total %.2f" % [freeze, LakeWorld.PT_TOTAL])
	# Exactly once, and nothing else may start on top of it.
	_ok(dev.background_celebration(8) == 0.0, "a repeat of level 8 asks for no freeze")
	_ok(dev.background_milestone(40) == 0.0, "and a round ending mid-party starts no frog")
	_ok(not lake.call("frog_event_active"), "so the crossing cannot run inside the party")

	var pads := lake.get_node_or_null("FrogEvent/PartyPads") as MultiMeshInstance3D
	var frogs := lake.get_node_or_null("FrogEvent/PartyFrogs") as MultiMeshInstance3D
	_ok(pads != null and frogs != null, "it draws pads and frogs")
	if pads == null or frogs == null:
		dev.queue_free()
		return
	_ok(pads.layers == LakeWorld.BG_LAYER and frogs.layers == LakeWorld.BG_LAYER,
		"both on the background layer")
	_ok(pads.multimesh.visible_instance_count == LakeWorld.PT_COUNT,
		"exactly five lily pads", str(pads.multimesh.visible_instance_count))
	_ok(frogs.multimesh.visible_instance_count == LakeWorld.PT_COUNT,
		"and exactly five frogs", str(frogs.multimesh.visible_instance_count))

	# Five DIFFERENT places, spread on screen rather than laid out in a row.
	var berths: Array = lake.get("_pt_p")
	var screen: Array[Vector2] = []
	for p: Vector3 in berths:
		screen.append(cam.unproject_position(Vector3(p.x, LakeWorld.PAD_TOP, p.z)))
	var closest := 1e9
	for i in screen.size():
		for j in range(i + 1, screen.size()):
			closest = minf(closest, screen[i].distance_to(screen[j]))
	_ok(closest > 90.0, "the five come up in five different places",
		"closest pair %.0f px apart" % closest)
	var span_x := 0.0
	var span_y := 0.0
	for i in screen.size():
		for j in screen.size():
			span_x = maxf(span_x, absf(screen[i].x - screen[j].x))
			span_y = maxf(span_y, absf(screen[i].y - screen[j].y))
	_ok(span_x > 320.0 and span_y > 120.0, "spread over the frame, not in a line",
		"%.0f x %.0f px" % [span_x, span_y])

	# Now run the whole event, checking every frame of it.
	var worst_lateral := 0.0          # how far a frog ever got from its own pad
	var worst_lift := -1e9            # ...and how far above it
	var lowest_lift := 1e9
	var worst_face := 1.0             # the least any frog ever faced the camera
	var rose := PackedFloat32Array()  # the highest each pad ever got
	var began := PackedFloat32Array() # ...and the lowest, before it came up
	for _i in LakeWorld.PT_COUNT:
		rose.append(-1e9)
		began.append(1e9)
	var last_pad := PackedFloat32Array()
	var last_frog := PackedFloat32Array()
	var frames := 0
	var cheered := false               # the woohoo actually reached the speaker
	var rippled := 0                   # ...and the water was actually disturbed
	var rings := lake.get_node_or_null("FrogEvent/Ripples") as MultiMeshInstance3D
	while lake.call("party_event_active") and frames < 1200:
		if float(lake.get("_pt_t")) > LakeWorld.PT_CHEER0 and AudioManager._amb_player.playing:
			cheered = true
		if rings != null:
			rippled = maxi(rippled, rings.multimesh.visible_instance_count)
		var n: int = pads.multimesh.visible_instance_count
		last_pad.resize(n)
		last_frog.resize(n)
		for i in n:
			var pt: Transform3D = pads.multimesh.get_instance_transform(i)
			var ft: Transform3D = frogs.multimesh.get_instance_transform(i)
			worst_lateral = maxf(worst_lateral,
				Vector2(pt.origin.x - ft.origin.x, pt.origin.z - ft.origin.z).length())
			var lift := ft.origin.y - pt.origin.y
			worst_lift = maxf(worst_lift, lift)
			lowest_lift = minf(lowest_lift, lift)
			rose[i] = maxf(rose[i], pt.origin.y)
			began[i] = minf(began[i], pt.origin.y)
			last_pad[i] = pt.origin.y
			last_frog[i] = ft.origin.y + ft.basis.get_scale().y * LakeWorld.FROG_BODY_TOP
			# Facing: the frog's local +x is its nose, so the basis's x column IS the
			# way it is looking once the squash is normalised out.
			var nose := Vector3(ft.basis.x.x, 0.0, ft.basis.x.z).normalized()
			var to_cam := cam.global_position - ft.origin
			to_cam.y = 0.0
			worst_face = minf(worst_face, nose.dot(to_cam.normalized()))
		frames += 1
		await get_tree().process_frame
	_ok(frames < 1200, "the party finishes on its own", "%d frames" % frames)
	_ok(worst_lateral < 0.02,
		"a frog never leaves its own pad — no jump on, off, or between",
		"worst %.4f m" % worst_lateral)
	_ok(lowest_lift >= -0.001 and worst_lift < 0.10,
		"and stays seated on it the whole time",
		"lift %.3f..%.3f m" % [lowest_lift, worst_lift])
	_ok(worst_face > 0.85, "every frog faces the player, always",
		"worst %.3f" % worst_face)
	_ok(cheered, "the woohoo actually plays, on the ambience channel")
	_ok(rippled >= LakeWorld.PT_COUNT,
		"and every pair disturbs the water as it comes up", "%d rings at once" % rippled)
	var under := true
	var surfaced := true
	for i in rose.size():
		if began[i] >= LakeWorld.WATER_Y:
			under = false
		if rose[i] <= LakeWorld.WATER_Y:
			surfaced = false
	_ok(under, "every pair starts under the water")
	_ok(surfaced, "and every one of them breaks the surface")
	var sank := true
	var hidden := true
	for i in last_pad.size():
		if last_pad[i] > LakeWorld.WATER_Y - 0.15:
			sank = false
		if last_frog[i] > LakeWorld.WATER_Y:
			hidden = false
	_ok(sank, "they go back under together at the end")
	_ok(hidden, "and no frog is left showing above the water after its pad has gone")

	# Cleanup, and the scene back to sleep.
	_ok(not (pads.visible or frogs.visible), "the pairs are hidden when it is over")
	_ok(pads.multimesh.visible_instance_count == 0
			and frogs.multimesh.visible_instance_count == 0,
		"and nothing of them is left drawing")
	var ev := lake.get_node_or_null("FrogEvent") as Node3D
	_ok(ev != null and not ev.visible, "the whole event root goes dark")
	await get_tree().process_frame
	_ok(not lake.is_processing(), "and it puts the scene back to sleep")

	# THE LAKE'S PARTY IS LEVEL EIGHT AND NO OTHER LEVEL, and as of the day the
	# completion hooks were widened (see BackgroundScenes.note_milestone) that is the
	# LAKE's decision rather than game.gd's — the game now offers every eighth level
	# and each background answers for itself. Ice Kingdom takes all of them; this one
	# takes the first.
	_ok(dev.background_celebration(16) == 0.0,
		"level 16 is not the lake's party — it is level eight's alone")
	# ...and the machinery is still reusable, which is what this used to check by
	# asking for level 16. Cleared through the private the guard reads, because the
	# public path can no longer ask twice.
	lake.set("_pt_last", -1)
	_ok(dev.background_celebration(8) > 0.0, "and the party can be thrown again")
	lake.call("stop_party_event")
	_ok(not lake.call("party_event_active"), "and it can be stopped outright")
	dev.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------ the wiring
# The half of both events that lives in game.gd. It cannot be exercised from here
# (a real round needs a real game screen), so it is asserted on the SOURCE — which
# is worth doing precisely because it is the half that has no picture: the previous
# version of the frog was fired and forgotten, and every visual test still passed.
func _wiring() -> void:
	print("\n-- the freeze, in game.gd --")
	var src: String = (load("res://game.gd") as GDScript).source_code
	_ok(src.contains("func _freeze_for_event") and src.contains("func _thaw_after_event"),
		"the round has a dedicated event state")
	_ok(src.contains("_state != \"input\""), "and input is still gated on the state")
	var ev_state: String = String((load("res://game.gd") as GDScript).get("EVENT_STATE"))
	_ok(ev_state != "" and ev_state != "input",
		"which the event state can never be", ev_state)
	_ok(src.contains("_wheel.background_milestone(level)"),
		"the frog's freeze is taken from the background")
	_ok(not src.contains("if level % 5 == 0:\n\t\t\tvar frog_secs"),
		"and the every-fifth-round decision is the LAKE's, not the game's")
	_ok(src.contains("await get_tree().create_timer(bg_secs).timeout"),
		"and the round waits it out before the next one starts")
	# The hook is offered every eighth level now and the BACKGROUND says whether the
	# number means anything to it — the lake answers 8 and nothing else, which is
	# asserted against the lake itself a few checks up rather than against this
	# source. What game.gd still owes is the call and the freeze around it.
	_ok(src.contains("if level % 8 == 0:")
			and src.contains("_wheel.background_celebration(level)"),
		"the party is offered on every eighth completed level")
	_ok(src.contains("await get_tree().create_timer(party_secs).timeout")
			and src.contains("_thaw_after_event()"),
		"and the round waits that one out too")
	_ok(src.contains("await get_tree().create_timer(party_secs).timeout"),
		"and the round waits that out too")
	_ok(src.contains("\"YOU ROCK!\""), "the banner says YOU ROCK!")

	# The woohoo, checked as SAMPLES like the ribbit: a generator whose envelope
	# never opens returns a perfectly valid, perfectly silent stream.
	_ok(AudioManager.has_method("play_frog_woohoo"), "five frogs have a cheer")
	var woo: AudioStreamWAV = AudioManager._make_woohoo()
	_ok(woo != null and woo.data.size() > 0, "and it is generated")
	if woo != null:
		var n := woo.data.size() / 2
		var peak := 0
		for i in n:
			peak = maxi(peak, absi(woo.data.decode_s16(i * 2)))
		_ok(peak > 6000, "it is audible", "peak %d of 32767" % peak)
		_ok(absf(float(n) / float(AudioManager.SR) - 0.55) < 0.04, "and it is short",
			"%.2f s" % (float(n) / float(AudioManager.SR)))
