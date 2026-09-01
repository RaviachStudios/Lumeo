extends Node
# Acceptance harness for the generated ICE KINGDOM background (ice_world.gd).
#
# It checks the half a screenshot cannot: that the id moved from one catalog to
# another WITHOUT moving anywhere the player can see, that the façade answers for it
# the same way it answers for every other background, that the board drives it, and
# that the things the design rule forbids are structurally impossible rather than
# merely absent from one render. tools/ice_shot.tscn owns the pixels.
#
# Headless is fine — nothing here reads back a rendered image:
#
#   Godot_..._console.exe --headless --path . tools/ice_verify.tscn

const ID := "world_ice"
const ICE_BTN := preload("res://ice_buttons.gd")
# shop_screen.gd is a Control with no class_name, so its tables are reached through
# the script resource — the same way tools/lake_verify.gd does it.
const ShopScreen := preload("res://shop_screen.gd")

# Every 3D background that existed before this one changed hands. None of their
# answers may move.
const OTHERS := ["bg_darkmetal", "bg_hexfloor", "bg_neongrid", "bg_circuit",
	"bg_deepspace", "bg_volcanic", "bg_crystal", "bg_arcade",
	"world_forest", "world_lake"]

var _fails := 0

func _ok(cond: bool, what: String, detail: String = "") -> void:
	if cond:
		print("  ok    %s" % what)
	else:
		_fails += 1
		print("  FAIL  %s%s" % [what, ("   [%s]" % detail) if detail != "" else ""])

func _ready() -> void:
	for _i in 8:
		await get_tree().process_frame
	_catalog()
	_facade()
	_palette()
	_scene()
	await _boards()
	_shelf()
	print("\n%s  (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# ------------------------------------------------------------------ catalog
# The whole point of the change is that it is invisible from outside: the id is what
# saved wallets contain, and a player who owned Ice Kingdom before owns it now.
func _catalog() -> void:
	print("-- catalog --")
	_ok(IceWorld.CATALOG.has(ID) and IceWorld.ORDER == [ID], "one id, and it is %s" % ID)
	_ok(IceWorld.display_name(ID) == "Ice Kingdom", "still called Ice Kingdom")
	_ok(not WorldScenes.CATALOG.has(ID), "it is no longer an imported world")
	_ok(not WorldScenes.ORDER.has(ID), "and not in that catalog's order")
	_ok(not BackgroundScenes.CATALOG.has(ID), "nor a Themes1 floor")
	_ok(not LakeWorld.CATALOG.has(ID), "nor the lake")
	# The wallet and the shop are the two places the id is a promise to a player.
	_ok(CoinsManager.THEMES.has(ID), "it is still a theme in the wallet's catalog")
	_ok(int(CoinsManager.THEMES[ID]["price"]) == 0, "still free")
	_ok(String(CoinsManager.THEMES[ID]["name"]) == BackgroundScenes.display_name(ID),
		"and the shop name still matches the catalog")
	# A wallet written before the change must still resolve to a background.
	CoinsManager._apply_doc({"coins": 40, "owned_themes": {ID: true},
		"selected_theme": ID})
	_ok(CoinsManager.selected_theme == ID, "an old wallet's Ice Kingdom still equips")
	_ok(BackgroundScenes.has_scene(CoinsManager.selected_theme),
		"and still resolves to a background")
	_ok(ICE_BTN.active(), "so the snowflake buttons are still worn with it")


# ------------------------------------------------------------------- façade
func _facade() -> void:
	print("\n-- façade --")
	_ok(BackgroundScenes.has_scene(ID), "the façade knows it")
	_ok(BackgroundScenes.all_order().has(ID), "it is in the full order")
	_ok(BackgroundScenes.all_order().size() == 11, "which is still 11 backgrounds",
		str(BackgroundScenes.all_order().size()))
	_ok(BackgroundScenes.display_name(ID) == "Ice Kingdom", "the name comes back")
	_ok(BackgroundScenes.is_animated(ID), "it is animated (the snow)")
	_ok(IceWorld.EVENT_HZ > IceWorld.IDLE_HZ * 2.0,
		"a milestone redraws far faster than the resting snow does",
		"%.0f vs %.0f Hz" % [IceWorld.EVENT_HZ, IceWorld.IDLE_HZ])
	_ok(is_equal_approx(BackgroundScenes.idle_hz(ID), IceWorld.IDLE_HZ),
		"and asks for its own redraw rate", "%.0f Hz" % BackgroundScenes.idle_hz(ID))
	_ok(BackgroundScenes.idle_hz(ID) < LakeWorld.IDLE_HZ,
		"which is slower than the lake's — nothing here moves quickly")
	# It is a floor, not an island: the board's pools want their own defaults.
	_ok(is_equal_approx(BackgroundScenes.pool_plane_y(ID), 0.0),
		"the pools lie on the board's own plane")
	_ok(is_equal_approx(BackgroundScenes.pool_radius(ID), 0.0), "and are not clipped")
	_ok(BackgroundScenes.pool_gain(ID) < 1.0,
		"the pools are turned down — a lit flake must out-glow its own light on the ice",
		"%.2f" % BackgroundScenes.pool_gain(ID))
	# Neither seating nor scaling applies: both are for imported compositions.
	_ok(is_equal_approx(BackgroundScenes.seat_wanted(ID, 0.0), 0.0), "it is never seated")
	_ok(is_equal_approx(BackgroundScenes.fit_scale(ID, null, Vector2(1280, 720), 3.5), 1.0),
		"and never scaled")
	_ok(BackgroundScenes.make_preview_camera(1.78, ID) != null, "a shop card can frame it")
	var env := BackgroundScenes.make_preview_environment(ID)
	_ok(env != null and is_equal_approx(env.environment.tonemap_exposure, 0.40),
		"through the BOARD's exposure, which is what its palette was solved against")

	# Nothing else moved.
	for other: String in OTHERS:
		_ok(BackgroundScenes.has_scene(other), "%s is still a 3D background" % other)


# ------------------------------------------------------------------ palette
# The design rule, as far as it can be checked without a render: everything the ice
# is made of is darker than a button, and the tone table it is solved through is the
# same measurement the lake uses.
func _palette() -> void:
	print("\n-- palette --")
	_ok(IceWorld.TONE_RAMP.size() == LakeWorld.TONE_RAMP.size(),
		"the tone ramp is the same length as the lake's")
	var same := true
	for i in mini(IceWorld.TONE_RAMP.size(), LakeWorld.TONE_RAMP.size()):
		if not is_equal_approx(float(IceWorld.TONE_RAMP[i]), float(LakeWorld.TONE_RAMP[i])):
			same = false
	# The two files hold the same measured table on purpose (see the note on either).
	# If one is ever re-measured and the other is not, this is what says so.
	_ok(same, "and every entry of it is identical — one measurement, two copies")
	var mid := IceWorld.tone(Color8(128, 128, 128))
	_ok(mid.x > 0.60 and mid.x < 0.95, "screen 128 still needs 0.6-0.95 of radiance",
		"%.3f" % mid.x)

	# The palette, split by what a colour is FOR, because "nothing may be brighter
	# than a button" is a claim about area rather than about a constant.
	#
	# AREA colours are the ones that cover ground at full strength — the sheet
	# itself, the fog, a crystal in shadow, the middle of a plate. The snowflakes
	# render at a mean of 160-190 counts (tools/flake_look.tscn), so an area colour
	# that came anywhere near that would put the background level with the buttons
	# before anything is even lit.
	var area := {
		"NEAR": IceWorld.NEAR, "MID": IceWorld.MID, "HAZE": IceWorld.HAZE,
		"SHARD_LO": IceWorld.SHARD_LO, "PLATE_LO": IceWorld.PLATE_LO,
		"BANK_LO": IceWorld.BANK_LO, "BERM_LO": IceWorld.BERM_LO,
	}
	# The ceiling went 130 -> 145 with THE ARENA, and the reason is a change in what
	# the picture is rather than a relaxation of the rule.
	#
	# Before the shore, the ice was one unbounded sheet that had to stay dark
	# everywhere, because everywhere was where it went. The rink is a BOUNDED,
	# smooth, low-saturation area with a bank around it that falls away — which is
	# the arrangement the reference has, and its ice measures brighter than its
	# snowflakes do (L 145-168 against L 122-167). This one deliberately stops short
	# of that: the buttons still have to be the strongest thing on screen. But NEAR
	# is the lightest large area in the frame on purpose now, and a bound written
	# when nothing was allowed to be would fail it for being right.
	#
	# 145 is still comfortably under a flake's 160-190 mean (tools/flake_look.tscn),
	# which is the claim this check exists to make. The number that actually governs
	# is tools/ice_shot.tscn's RULE line, measured on the render.
	for nm: String in area:
		var c: Color = area[nm]
		var peak: float = maxf(c.r, maxf(c.g, c.b)) * 255.0
		_ok(peak <= 145.0, "area colour %s is far under a button" % nm,
			"peak channel %.0f" % peak)
	# ACCENT colours never cover ground at full strength: FROST is used at gains of
	# 0.075 and 0.14, AURORA at 0.105 in a band well behind the buttons, SHEEN
	# through a fresnel capped at 0.13 plus a narrow specular lobe, SNOW at alpha
	# 0.34 on a three-pixel quad, and the two _HI ends are one end of a gradient a
	# prop only reaches where it faces the light and which the fog then takes. So
	# they are checked for being COLD and for staying below a button's own bright
	# rim; what actually lands on screen is ice_shot's measurement, not a constant.
	var accent := {
		"FROST": IceWorld.FROST, "SHEEN": IceWorld.SHEEN, "SNOW": IceWorld.SNOW,
		"AURORA": IceWorld.AURORA,
		"SHARD_HI": IceWorld.SHARD_HI, "PLATE_HI": IceWorld.PLATE_HI,
	}
	for nm: String in accent:
		var c: Color = accent[nm]
		var peak: float = maxf(c.r, maxf(c.g, c.b)) * 255.0
		_ok(peak <= 245.0, "accent %s stays under a button's rim" % nm,
			"peak channel %.0f" % peak)
		# Blue dominates. Not "b >= g >= r", which AURORA fails on purpose: it is the
		# one violet in the palette and its red channel is meant to sit above its
		# green. What makes a colour cold here is that nothing beats the blue.
		_ok(c.b > c.g and c.b > c.r, "accent %s is a cold colour" % nm)
	# What the rendered result actually measures is tools/ice_shot.tscn's job: it
	# reports the background's mean and peak as a percentage of a button's, over
	# every pixel of the frame that is not inside a button.

	# The cracks are the detail the old background put under the buttons. Structural
	# guarantee, not a render: the mask cannot open inside the play area.
	# THE SKY IS COMPILED TWICE AND WRITTEN ONCE. The ice reflects it by calling the
	# same sky_at, and the whole point of that is that a reflection cannot drift out
	# of step with what it reflects — so the shared block has to actually be shared.
	_ok(IceWorld.SKY_SHADER.contains("sky_at") and IceWorld.ICE_SHADER.contains("sky_at"),
		"the ice and the sky card compile the same sky function")
	_ok(IceWorld.ICE_SHADER.contains(IceWorld.SKY_COMMON),
		"and it is one string, not two that look alike")
	_ok(IceWorld.REFL_GAIN > 0.0 and IceWorld.REFL_SPAN > 0.0,
		"the ice reflects it")

	# THE FRAMING. This is the only hook in the background system that moves the
	# BOARD, and it exists for this background alone.
	var fb := BackgroundScenes.frame_bias(ID)
	_ok(fb.x < 0.0 and fb.y > 0.0,
		"Ice Kingdom asks for a smaller board, seated lower", str(fb))
	for other: String in ["world_lake", "bg_neongrid", "world_forest", ""]:
		_ok(BackgroundScenes.frame_bias(other) == Vector2.ZERO,
			"%s is framed exactly as it always was" % (other if other != "" else "(none)"))

	_ok(IceWorld.CRACK_IN > 1.0,
		"cracks cannot start until past the outermost button", "%.2f of reach" % IceWorld.CRACK_IN)
	_ok(IceWorld.CRACK_OUT > IceWorld.CRACK_IN, "and fade in outward from there")
	_ok(IceWorld.DRESS_CLEAR > 1.0, "and no prop is laid inside the play area either",
		"%.2f of reach" % IceWorld.DRESS_CLEAR)


# -------------------------------------------------------------------- scene
func _scene() -> void:
	print("\n-- the scene --")
	var scene := BackgroundScenes.build(ID)
	_ok(scene != null, "it builds")
	if scene == null:
		return
	_ok(scene.has_method("set_layout"), "and answers the hook the board drives it with")
	# NINE draw calls and no more: the sky card, the ice, four MultiMeshes, the snow
	# sheet, and the milestone burst's two (a MultiMesh of crystals and a batched
	# quad sheet of puffs, both built once and both drawing NOTHING between events —
	# visible_instance_count 0 and an empty mesh cost a cull and no more).
	#
	# It was four before the environment pass, six after it, and nine after the sky.
	# Everything that has ever been added to this background has been added as a
	# shader term, a MultiMesh instance or a batched quad, and that is the whole
	# reason it can go on gaining detail: the last two passes together cost less per
	# frame than the first version did.
	#
	# The sleigh is NOT in this count and must not be: it exists only during a
	# level-8 celebration and is freed at the end of one.
	var pieces: Array = []
	var lights := 0
	_walk(scene, pieces, [lights])
	var geo := 0
	for n in pieces:
		if n is GeometryInstance3D:
			geo += 1
			_ok((n as GeometryInstance3D).layers == IceWorld.BG_LAYER,
				"%s is on the background layer" % (n as Node).name)
			_ok((n as GeometryInstance3D).cast_shadow
					== GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s casts no shadow" % (n as Node).name)
	# Ten since THE ARENA: the shore berm is the tenth, and it is one generated
	# mesh rebuilt per layout rather than a ring of instances.
	_ok(geo == 10, "it is ten draw calls, not a particle system", str(geo))
	_ok(scene.get_node_or_null("AuroraSleigh") == null,
		"and the reindeer is not one of them — it is built per celebration and freed")
	_ok(_count_lights(scene) == 0, "and it builds no lights at all — nothing here may "
		+ "reach a button")
	# Nothing per-frame on the CPU. Every animation is a function of TIME in a shader.
	_ok(not scene.is_processing(), "and no per-frame CPU cost")
	scene.free()


func _walk(n: Node, out: Array, _acc: Array) -> void:
	for c in n.get_children():
		out.append(c)
		_walk(c, out, _acc)


func _count_lights(n: Node) -> int:
	var k := 0
	for c in n.get_children():
		if c is Light3D:
			k += 1
		k += _count_lights(c)
	return k


# ------------------------------------------------------------------- boards
# The one thing that can only be found by building the real thing: the dressing is
# placed through the CAMERA, and a placement bug shows up as ZERO props on the
# difficulty nobody re-rendered.
func _boards() -> void:
	print("\n-- the three boards --")
	CoinsManager.selected_theme = ID
	for which: String in ["easy", "medium", "hard"]:
		var dev: MemoryGameUI
		match which:
			"easy": dev = EasyGameUI.new()
			"medium": dev = MemoryGameUI.new()
			_: dev = HardGameUI.new()
		dev.input_enabled = false
		dev.size = Vector2(1280, 720)
		add_child(dev)
		await get_tree().process_frame
		dev.configure(dev._count, [])
		for _i in 8:
			await get_tree().process_frame
		var ice: Node3D = dev._bg_scene
		_ok(ice != null and ice.get_class() == "Node3D" or ice != null,
			"%s: the board built the ice" % which)
		if ice != null:
			var reach := float(ice.get("_reach"))
			_ok(reach > 1.0, "%s: it was told the board's reach" % which, "%.2f" % reach)
			# Every prop type, on every board. This is the check the far ice wall
			# actually needed: its first placement asked for a world DEPTH and Easy's
			# visible ground never reaches it, so the wall was placed zero times
			# there while Hard looked perfect.
			for nm: String in ["Crystals", "Plates", "Ridges", "Rocks",
					"StreakCrystals"]:
				var mm := ice.find_child(nm, true, false) as MultiMeshInstance3D
				var n := mm.multimesh.instance_count if mm != null else 0
				_ok(n > 0, "%s: %s were placed" % [which, nm], "%d" % n)
			# NO BUTTON MAY STAND ON THE SKYLINE, which is the whole reason the
			# framing hook exists and is the one thing about this background that
			# cannot be checked by looking at one board: the fit solves its own
			# distance per difficulty, so Easy, Medium and Hard each land somewhere
			# different against the same horizon line.
			var cam: Camera3D = null
			for c in dev._vp.get_children():
				if c is Camera3D:
					cam = c
			if cam != null:
				# Measured off the SAME points the fit is solved against
				# (MemoryGameUI._collect_fit_points: each button's frame rim and the
				# top edge of its raised surface), which is the authority on where a
				# button ends.
				#
				# It used to ask each Button_<key> node for `h.position` and inflate
				# it by 1.15 m and a 0.62 fudge. `position` is LOCAL to the board
				# node, so that measure was never the button's place on screen; it
				# reported the topmost button 26 px ABOVE the board's own silhouette,
				# which is not a number a subset of the silhouette can produce. It
				# happened to pass while the board sat low and failed the moment the
				# board was re-framed (game.gd's HUD lanes), which is the worst way
				# for a wrong measurement to behave. Same defect, same fix, as the
				# arena check below.
				var top := 1e9
				var centres: PackedVector2Array = dev.get("_centres")
				for c: Vector2 in centres:
					for i in 24:
						var a := TAU * float(i) / 24.0
						for p: Vector3 in [
								Vector3(c.x + cos(a), 0.0, c.y + sin(a)),
								Vector3(c.x + cos(a) * 0.745, 0.525,
									c.y + sin(a) * 0.745)]:
							if cam.is_position_behind(p):
								continue
							top = minf(top, cam.unproject_position(p).y)
				var hz := 720.0 * IceWorld.HORIZON_FY
				_ok(top > hz, "%s: no button stands on the skyline" % which,
					"topmost %.0f px vs horizon %.0f" % [top, hz])
			# THE ARENA, and this is the check the whole shape hangs on.
			#
			# The shore is solved against the buttons' own projected discs so that it
			# CANNOT be drawn through the play area (see _solve_arena). That is a
			# structural claim and this is what makes it one: every button on every
			# board, at its widest, has to come out inside the shoreline with the
			# clearance the solve promised — including the bottom-corner squeeze,
			# which is the one term that pulls the shore back toward the board.
			#
			# It asks the ICE for the board's geometry rather than reading transforms
			# off the button nodes, and that is not laziness. Written the other way
			# first, against `Button_<key>.position` and a 1.15 m radius borrowed
			# from the skyline check, it reported every button at 0.94-0.98 of the
			# way to the shore on all three boards while the renders plainly showed
			# a wide band of clean ice around them: `position` is LOCAL to the board
			# node and 1.15 is not the plate's radius. A check that measures the
			# wrong thing precisely is worse than no check.
			if cam != null:
				var rad: Vector2 = ice.get("_arena")
				var at: Vector2 = ice.get("_arena_at")
				var centres: PackedVector2Array = ice.get("_centres")
				_ok(rad.x > 0.05 and rad.y > 0.05 and centres.size() > 0,
					"%s: the arena was solved" % which,
					"r (%.3f, %.3f) at (%.3f, %.3f)" % [rad.x, rad.y, at.x, at.y])
				var vps := Vector2(1280.0, 720.0)
				var furthest := 0.0
				for c: Vector2 in centres:
					furthest = maxf(furthest, c.length())
				var brad := maxf(reach - furthest, 0.05)
				var worst := 0.0
				for c: Vector2 in centres:
					var w := Vector3(c.x, IceWorld.ICE_Y, c.y)
					var cs := cam.unproject_position(w) / vps
					var ex := cam.unproject_position(
						w + Vector3(brad, 0.0, 0.0)) / vps
					var ez := cam.unproject_position(
						w + Vector3(0.0, 0.0, brad)) / vps
					var D := cs - at
					var g := (D / rad).length()
					if g < 0.0001:
						continue
					# How much further out the plate's outermost point is, along the
					# direction the arena coordinate actually grows in — the same
					# first-order term _solve_arena sizes the ellipse with.
					#
					# Charging max(rx, ry) instead, which is what this did first,
					# bills the TOP button its horizontal radius; on a keystoned
					# ground plane that is roughly twice its vertical one, and the
					# button that decides `worst` is exactly the one directly above
					# the centre. It reported 0.945 where the true figure is 0.90.
					var rx: float = absf(ex.x - cs.x)
					var ry: float = absf(ez.y - cs.y)
					var out: float = g + (absf(D.x) * rx / (rad.x * rad.x)
						+ absf(D.y) * ry / (rad.y * rad.y)) / g
					out += IceWorld._corner_bias(cs) * IceWorld.ARENA_CORNER
					worst = maxf(worst, out)
				# 1 is the shoreline; the ice starts giving way at 1 - SHORE_BAND and
				# the wobble can bring that in by another ARENA_WOB. A button has to
				# clear ALL of that, not just the nominal line.
				# 1 is the shoreline. The ice begins giving way at 1 - SHORE_BAND
				# and the wobble moves that line by up to ARENA_WOB either way, so
				# HALF the wobble is the amount a button may be asked to absorb —
				# the noise is symmetric and a button's rim standing where the
				# shoreline happens to have wandered its full amplitude inward is a
				# few per cent of a few per cent of the frame.
				var bar := 1.0 - IceWorld.SHORE_BAND - IceWorld.ARENA_WOB * 0.5
				_ok(worst < bar,
					"%s: no button reaches the shoreline" % which,
					"worst %.3f vs %.3f" % [worst, bar])
			# ...and the berm stands on the shore it was solved for.
			var berm := ice.find_child("Berm", true, false) as MeshInstance3D
			_ok(berm != null and berm.mesh != null
					and berm.mesh.get_surface_count() > 0,
				"%s: the shore berm was built" % which)
			var snow := ice.find_child("Snow", true, false) as MeshInstance3D
			_ok(snow != null and snow.mesh != null and snow.mesh.get_surface_count() > 0,
				"%s: the snow sheet was built" % which)
			_ok(dev.button_skin_id() == ID, "%s: and it is wearing the snowflakes" % which)
		dev.queue_free()
		await get_tree().process_frame


# -------------------------------------------------------------------- shelf
# Where it sells is unchanged, and the checks that own that shelf live in
# tools/ice_shop_verify.tscn — this is only the pair of facts that would break if
# the move had touched the shop at all.
func _shelf() -> void:
	print("\n-- the shelf --")
	var items: Array = []
	for cat in ShopScreen.CATEGORIES:
		if String((cat as Dictionary).get("key", "")) == "themes":
			items = (cat as Dictionary).get("items", [])
	_ok(not items.has(ID), "it is still off the THEMES grid")
	var on_skins := false
	for d in ShopScreen.SKIN_DEFS:
		if String((d as Dictionary).get("theme", "")) == ID:
			on_skins = true
	_ok(on_skins, "and still on the SPECIAL SKINS shelf, backed by the same theme id")
