extends Node
# Verification pass for the two Themes2 LUME worlds.
#
#   Godot..._console.exe --path . res://tools/world_verify.tscn [-- boards]
#
# Without arguments it checks everything that does not need a gameplay board:
# the catalog, the façade BackgroundScenes presents on their behalf, the build
# (every mesh dressed, every light rebuilt and culled, nothing imported left
# behind), the animation and its loop, the shop wiring, purchase and persistence,
# and that none of the existing background data moved. `-- boards` adds the
# per-difficulty pass, which is slow enough to be worth running on its own.

const Easy := preload("res://easy_game_ui.gd")
const Medium := preload("res://memory_game_ui.gd")
const Hard := preload("res://hard_game_ui.gd")
const Data := preload("res://world_scenes_data.gd")
const ShopScreen := preload("res://shop_screen.gd")
const LumeWorlds := preload("res://lume_worlds.gd")

# The eight Themes1 floors and their prices, frozen here so a change to either
# catalog that disturbs the other one fails loudly.
const THEMES1 := {
	"bg_darkmetal": 100, "bg_hexfloor": 200, "bg_neongrid": 300, "bg_circuit": 400,
	"bg_deepspace": 500, "bg_volcanic": 600, "bg_crystal": 700, "bg_arcade": 800,
}
# Free. Kept as a table rather than a bare 0 so that pricing it later is a one-line
# edit here and the checks below follow.
#
# ONE entry since Ice Kingdom moved: `world_ice` is still a shipping background at
# the same id and the same price, but it is generated in Godot now (ice_world.gd)
# rather than imported, so it is no longer this catalog's to answer for. Its price
# and its wallet fields are still checked — by tools/lume_verify.tscn's BEFORE table
# and tools/ice_verify.tscn.
const WORLD_PRICES := {
	"world_forest": 0,
}

var _fail := 0
var _pass := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  %s" % what)

func _ready() -> void:
	for i in 40:
		await get_tree().process_frame
	_catalog()
	_facade()
	await _build()
	await _animation()
	_shop()
	_persistence()
	await _purchase()
	if OS.get_cmdline_user_args().has("boards"):
		await _boards()
	print("\n%d passed, %d FAILED" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)

# ---------------------------------------------------------------------------

func _catalog() -> void:
	print("\n--- catalog ---")
	_check(WorldScenes.CATALOG.size() == 1, "1 world in CATALOG")
	_check(WorldScenes.ORDER.size() == 1, "1 in ORDER")
	# ...and Ice Kingdom is NOT it any more, while still being a background under
	# exactly the same id. This is the check that would catch a half-done revert.
	_check(not WorldScenes.CATALOG.has("world_ice"),
		"world_ice is not an imported world any more")
	_check(BackgroundScenes.has_scene("world_ice"),
		"but it is still a background, through the same façade")
	for id in WorldScenes.ORDER:
		_check(WorldScenes.CATALOG.has(id), "ORDER id %s is in CATALOG" % id)
	for id in WorldScenes.CATALOG:
		_check(WorldScenes.ORDER.has(id), "CATALOG id %s is in ORDER" % id)
		_check(String(id).begins_with("world_"), "%s carries the world_ prefix" % id)
		# The three id namespaces in this project share one dictionary. A collision
		# would silently give a player the wrong background for their money.
		_check(not BackgroundScenes.CATALOG.has(id), "%s does not collide with Themes1" % id)
		var glb := String(WorldScenes.CATALOG[id]["glb"])
		_check(ResourceLoader.exists(glb), "%s: %s exists" % [id, glb])
		var w := String(WorldScenes.CATALOG[id]["world"])
		_check(Data.OBJECTS.has(w), "%s: data table has world %s" % [id, w])
		_check(Data.LIGHTS.has(w) and not Data.LIGHTS[w].is_empty(), "%s: %s has lights" % [id, w])
		_check(Data.EXPOSURE.has(w), "%s: %s has an exposure" % [id, w])
		_check(Data.DECK.has(w), "%s: %s has deck bounds" % [id, w])
	# Display names have to be distinguishable in one grid and in the buy popup.
	var names := {}
	for id in CoinsManager.THEMES:
		var n := String(CoinsManager.THEMES[id]["name"])
		_check(not names.has(n), "theme name '%s' is unique (%s vs %s)" % [n, id, names.get(n, "")])
		names[n] = id
	# The two modules must agree on the layer, since one declares it again rather
	# than importing it (see WorldScenes.BG_LAYER).
	_check(WorldScenes.BG_LAYER == BackgroundScenes.BG_LAYER,
		"WorldScenes.BG_LAYER matches BackgroundScenes.BG_LAYER")

func _facade() -> void:
	print("\n--- facade ---")
	for idv in WorldScenes.ORDER:
		var id := String(idv)
		_check(BackgroundScenes.has_scene(id), "%s: BackgroundScenes.has_scene" % id)
		_check(BackgroundScenes.display_name(id) == WorldScenes.display_name(id),
			"%s: display_name forwards" % id)
		# A world in WorldScenes.STILL is built with its clip dropped, so the façade
		# has to report it as still — that is what stops the board nudging a redraw
		# for it at IDLE_HZ.
		_check(BackgroundScenes.is_animated(id) == not WorldScenes.STILL.has(id),
			"%s: is_animated matches STILL" % id)
		_check(BackgroundScenes.idle_hz(id) == WorldScenes.IDLE_HZ, "%s: idle_hz forwards" % id)
		# A world is a closed composition and is never slid along the ground.
		_check(BackgroundScenes.seat_wanted(id, 5.0) == 0.0, "%s: never seated" % id)
		_check(BackgroundScenes.seat_allowed(id, 3.0) == 0.0, "%s: no seat allowance" % id)
		_check(BackgroundManager._has_theme(id), "%s: BackgroundManager claims it" % id)
		var cam := BackgroundScenes.make_preview_camera(1.97, id)
		_check(is_equal_approx(cam.fov, Data.REF_CAM_FOV), "%s: preview camera is the reference lens" % id)
		_check(cam.position.is_equal_approx(Data.REF_CAM_ORIGIN), "%s: preview camera pose" % id)
		cam.free()
		var we := BackgroundScenes.make_preview_environment(id)
		_check(we.environment.tonemap_mode == Environment.TONE_MAPPER_AGX, "%s: preview tonemap" % id)
		we.free()
		# A world is an ISLAND, so it has to answer both of the "where is the ground"
		# questions the board asks before it lays the buttons' pools on it. A deck top
		# of 0 would bury the pool sheet under the whole play surface; an edge of 0
		# would let it hang over the abyss and stripe the far rim.
		var deck: Dictionary = Data.DECK[WorldScenes.world_of(id)]
		_check(is_equal_approx(BackgroundScenes.pool_plane_y(id),
			float(deck["top"]) + WorldScenes.POOL_DECK_BIAS),
			"%s: pool plane sits on the deck, not on y=0" % id)
		_check(BackgroundScenes.pool_plane_y(id) > float(deck["top"]),
			"%s: pool plane clears the deck it lies on" % id)
		_check(is_equal_approx(BackgroundScenes.pool_radius(id),
			minf(float(deck["far"]), float(deck["radius"]))),
			"%s: pool stops at the deck's tightest edge" % id)
	# The eight Themes1 floors must be unaffected by any of it.
	for idv in BackgroundScenes.ORDER:
		var id := String(idv)
		_check(BackgroundScenes.has_scene(id), "Themes1 %s still resolves" % id)
		_check(BackgroundScenes.idle_hz(id) == BackgroundScenes.BG_IDLE_HZ,
			"Themes1 %s keeps its own idle rate" % id)
		_check(not WorldScenes.has_scene(id), "Themes1 %s is not a world" % id)
		# A floor IS the plane y = 0 and has no edge, so it answers 0 to both — which
		# is what tells the board to keep its own defaults. Anything else here would
		# move the ground pools on backgrounds that were never wrong.
		_check(BackgroundScenes.pool_plane_y(id) == 0.0,
			"Themes1 %s leaves the pool plane alone" % id)
		_check(BackgroundScenes.pool_radius(id) == 0.0,
			"Themes1 %s puts no edge on the pool" % id)
	_check(BackgroundScenes.all_order().size() == 11, "all_order lists all eleven")

func _build() -> void:
	print("\n--- build ---")
	for idv in WorldScenes.ORDER:
		var id := String(idv)
		var w := WorldScenes.world_of(id)
		var root := BackgroundScenes.build(id)
		_check(root != null, "%s builds" % id)
		if root == null:
			continue
		_check(root.get_node_or_null("Backdrop") != null, "%s has a backdrop" % id)
		var meshes := {}
		var lights: Array = []
		var stray := 0
		_walk(root, meshes, lights)
		for spec: Dictionary in Data.OBJECTS[w]:
			var n := String(spec["name"])
			var mi: MeshInstance3D = meshes.get(n, null)
			_check(mi != null, "%s: mesh %s present" % [id, n])
			if mi == null:
				continue
			_check(mi.layers == WorldScenes.BG_LAYER, "%s: %s on the background layer" % [id, n])
			_check(mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s: %s casts no shadow" % [id, n])
			var slots: Array = spec["slots"]
			for si in mini(slots.size(), mi.mesh.get_surface_count()):
				if String(slots[si]).is_empty():
					continue
				_check(mi.get_surface_override_material(si) is ShaderMaterial,
					"%s: %s slot %d dressed" % [id, n, si])
		# Every light is rebuilt from the data table; none is left as the importer
		# made it, because glTF's photometric intensities and missing cull mask
		# would put a 3800-unit omni on the buttons.
		_check(lights.size() >= Data.LIGHTS[w].size(),
			"%s: at least as many lights as the table (%d >= %d)"
				% [id, lights.size(), Data.LIGHTS[w].size()])
		for l in lights:
			var L: Light3D = l
			_check(L.light_cull_mask == WorldScenes.BG_LAYER,
				"%s: light %s culled to the background layer" % [id, L.name])
			_check(not L.shadow_enabled, "%s: light %s casts no shadow" % [id, L.name])
			_check(L.light_specular == 0.0, "%s: light %s adds no specular" % [id, L.name])
			_check(L.light_energy < 100.0,
				"%s: light %s is not a raw glTF intensity (%.1f)" % [id, L.name, L.light_energy])
		root.free()
		await get_tree().process_frame

func _walk(n: Node, meshes: Dictionary, lights: Array) -> void:
	if n is MeshInstance3D and n.name != "Backdrop":
		meshes[String(n.name)] = n
	if n is Light3D:
		lights.append(n)
	for c in n.get_children():
		_walk(c, meshes, lights)

func _animation() -> void:
	print("\n--- animation ---")
	for idv in WorldScenes.ORDER:
		var id := String(idv)
		var root := BackgroundScenes.build(id)
		if root == null:
			continue
		add_child(root)
		var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if WorldScenes.STILL.has(id):
			# A still world must have NO player left at all, not a paused one: that is
			# what makes set_playing and the idle nudge inert without either of them
			# knowing about STILL.
			_check(ap == null, "%s: is still, so the clip was dropped" % id)
			root.queue_free()
			continue
		_check(ap != null, "%s: has an AnimationPlayer" % id)
		if ap == null:
			root.queue_free()
			continue
		var anim := ap.get_animation(WorldScenes.CLIP)
		_check(anim != null, "%s: has the '%s' clip" % [id, WorldScenes.CLIP])
		_check(ap.is_playing(), "%s: the clip is running" % id)
		if anim != null:
			_check(anim.loop_mode == Animation.LOOP_LINEAR, "%s: loops" % id)
			_check(absf(anim.length - Data.LOOP_SECONDS) < 0.05,
				"%s: %.3f s long (authored %.3f)" % [id, anim.length, Data.LOOP_SECONDS])
			_check(anim.get_track_count() >= 14, "%s: %d animated channels" % [id, anim.get_track_count()])
			# What makes the loop seamless is a property of the KEYS. The .blend keys
			# frame 301 identical to frame 1 and exports frames 1..300, so a player
			# running 1 -> 300 -> 1 sees one authored frame of motion at the seam and
			# nothing else. Godot's importer re-bases the clip onto 0 .. length and
			# drops redundant keys, so what has to hold here is that every track
			# still spans the WHOLE clip: a track that stopped short would leave a
			# dead zone at one end, which is what a broken loop actually looks like.
			#
			# It deliberately does NOT compare the value at 0 with the value at
			# `length`. The drifting fields (snow, embers, motes, pollen) wrap by
			# travelling an exact tile of their own pattern, so their TRANSFORM jumps
			# a whole tile at the seam while the picture does not change at all.
			var worst := 0.0
			for t in anim.get_track_count():
				var n := anim.track_get_key_count(t)
				if n < 2:
					continue
				worst = maxf(worst, absf(anim.track_get_key_time(t, 0)))
				worst = maxf(worst, absf(anim.track_get_key_time(t, n - 1) - anim.length))
			if OS.get_cmdline_user_args().has("keys"):
				for t in mini(3, anim.get_track_count()):
					print("    %s track %d keys=%d first=%.4f last=%.4f len=%.4f"
						% [id, t, anim.track_get_key_count(t), anim.track_get_key_time(t, 0),
							anim.track_get_key_time(t, maxi(0, anim.track_get_key_count(t) - 1)),
							anim.length])
			_check(worst < 0.002,
				"%s: every track spans the whole clip (worst end off by %.4f s)" % [id, worst])
		# It has to actually MOVE, not merely be playing.
		var probe := _first_animated(root, ap)
		var before := probe.transform if probe != null else Transform3D()
		ap.seek(3.3, true)
		await get_tree().process_frame
		var after := probe.transform if probe != null else Transform3D()
		_check(probe != null and not before.is_equal_approx(after),
			"%s: seeking moves %s" % [id, probe.name if probe else "<none>"])
		# ...and stop when the board stops being looked at.
		WorldScenes.set_playing(root, false)
		_check(not ap.is_playing(), "%s: set_playing(false) pauses it" % id)
		WorldScenes.set_playing(root, true)
		_check(ap.is_playing(), "%s: set_playing(true) resumes it" % id)
		root.queue_free()
		await get_tree().process_frame

func _first_animated(root: Node3D, ap: AnimationPlayer) -> Node3D:
	var anim := ap.get_animation(WorldScenes.CLIP)
	if anim == null:
		return null
	for t in anim.get_track_count():
		var path := anim.track_get_path(t)
		var n := ap.get_node_or_null(ap.root_node) as Node
		if n == null:
			n = root
		var target := n.get_node_or_null(NodePath(String(path).get_slice(":", 0)))
		if target is Node3D:
			return target
	return null

# Worlds that are catalogued here but sold on the SPECIAL SKINS shelf: a complete look
# (its world AND the buttons that world wears) rather than a backdrop. Listed in exactly
# one place so a player is never offered the same id from two cards. See
# ShopScreen.SKIN_DEFS and tools/ice_shop_verify.tscn.
const MOVED := ["world_ice", "world_lake"]

# Is `id` sold as a released, theme-backed card on the SPECIAL SKINS tab?
func _on_skins_shelf(id: String) -> bool:
	for d in ShopScreen.SKIN_DEFS:
		if String(d.get("theme", "")) == id and d.get("released", false):
			return true
	return false

func _shop() -> void:
	print("\n--- shop ---")
	var items: Array = []
	for c in ShopScreen.CATEGORIES:
		if String(c.get("key", "")) == "themes":
			items = c["items"]
	for idv in WorldScenes.ORDER:
		var id := String(idv)
		# Which SHELF the card is on is the only thing that differs between the two
		# worlds; every check below applies to both, which is what pins that moving
		# Ice Kingdom to SPECIAL SKINS changed the card and nothing else.
		if MOVED.has(id):
			_check(not items.has(id),
				"%s is off the THEMES grid — it sells in SPECIAL SKINS" % id)
			_check(_on_skins_shelf(id), "%s is on the SPECIAL SKINS shelf instead" % id)
		else:
			_check(items.has(id), "%s listed in the shop grid" % id)
		_check(CoinsManager.THEMES.has(id), "%s in CoinsManager.THEMES" % id)
		_check(String(CoinsManager.THEMES[id]["category"]) == "themes", "%s is a theme" % id)
		_check(int(CoinsManager.THEMES[id]["price"]) == int(WORLD_PRICES[id]),
			"%s costs %d" % [id, WORLD_PRICES[id]])
		_check(String(CoinsManager.THEMES[id]["name"]) == WorldScenes.display_name(id),
			"%s: shop name matches the catalog" % id)
		_check(not CoinsManager.owned_themes.has(id), "%s is not owned by default" % id)
	# The PAID half of the grid still reads cheapest first — that ladder is what the
	# eight Themes1 floors are ordered by and it must not drift. The worlds are all
	# free, so their own order is the authored one (least happening in frame to
	# most) and a price comparison across the two groups means nothing.
	var last := -1
	for idv in BackgroundScenes.ORDER:
		var id := String(idv)
		var p := int(CoinsManager.THEMES[id]["price"])
		_check(p > last, "grid price order: %s (%d) dearer than the card before it" % [id, p])
		last = p
	# The two worlds close the MODELLED half of the grid, in their authored order.
	# They are no longer last outright: the eight LUMEO worlds (lume_worlds.gd) are
	# appended after them, so the slice is taken from where the 3D block ends rather
	# than from the end of the list. Everything up to that point is what this
	# harness owns; tools/lume_verify.tscn owns the rest.
	var grid_worlds: Array = []
	for idv in WorldScenes.ORDER:
		if not MOVED.has(String(idv)):
			grid_worlds.append(idv)
	var modelled := 1 + BackgroundScenes.all_order().size() - MOVED.size()   # + "default"
	_check(items.slice(modelled - grid_worlds.size(), modelled) == grid_worlds,
		"the grid's worlds close the modelled block, in their authored order")
	_check(items.size() == modelled + LumeWorlds.ORDER.size(),
		"the grid is Default, eleven 3D backgrounds and %d LUMEO worlds"
		% LumeWorlds.ORDER.size())
	# NOTHING about the existing catalog may have moved.
	for id in THEMES1:
		_check(items.has(id), "Themes1 %s still on the grid" % id)
		_check(int(CoinsManager.THEMES[id]["price"]) == int(THEMES1[id]),
			"Themes1 %s still costs %d" % [id, THEMES1[id]])
	for id in ["midnight", "rainbow", "inferno", "aurora", "deepspace", "reef"]:
		_check(CoinsManager.THEMES.has(id), "detached shader theme %s is still in THEMES" % id)
		_check(not items.has(id), "detached shader theme %s stays off the grid" % id)

func _persistence() -> void:
	print("\n--- persistence ---")
	# The save shape is a map of owned ids and the load rebuilds the array from it,
	# so the round trip is exercised through exactly that path.
	var frame_before: String = CoinsManager.selected_frame
	var saved := {}
	for idv in WorldScenes.ORDER:
		saved[String(idv)] = true
	saved["bg_crystal"] = true
	saved["midnight"] = true
	CoinsManager._apply_doc({"coins": 9999, "owned_themes": saved,
		"selected_theme": "world_forest", "selected_frame": frame_before})
	for idv in WorldScenes.ORDER:
		var id := String(idv)
		_check(CoinsManager.owned_themes.has(id), "%s survives the save/load round trip" % id)
		_check(CoinsManager.owns(id), "%s: owns() true after load" % id)
	_check(CoinsManager.selected_theme == "world_forest", "a world selection round-trips")
	# Nothing about an existing wallet changes.
	_check(CoinsManager.owned_themes.has("bg_crystal"), "a Themes1 floor still loads beside them")
	_check(CoinsManager.owned_themes.has("midnight"), "a shader theme still loads beside them")
	# Equipping a world must never disturb a button-frame cosmetic. The two are
	# independent stores and the frame's own priority chain is untouched.
	_check(CoinsManager.selected_frame == frame_before,
		"loading a world selection left the button frame alone")

	# A wallet that predates both must still load, with neither owned.
	CoinsManager._apply_doc({"coins": 10, "owned_themes": {"midnight": true},
		"selected_theme": "midnight"})
	_check(CoinsManager.owned_themes.has("midnight"), "old wallet keeps its theme")
	for idv in WorldScenes.ORDER:
		_check(not CoinsManager.owns(String(idv)), "old wallet owns no %s" % idv)
	_check(CoinsManager.selected_theme == "midnight", "old wallet keeps its selection")
	# Selecting one the wallet does not own falls back, as it always did.
	CoinsManager._apply_doc({"coins": 10, "owned_themes": {"midnight": true},
		"selected_theme": "world_forest"})
	_check(CoinsManager.selected_theme == CoinsManager.DEFAULT_THEME,
		"an unowned world selection falls back to default")

func _purchase() -> void:
	print("\n--- purchase / equip ---")
	FirebaseManager.uid = "worldverify"
	_check(FirebaseManager.is_signed_in(), "simulated sign-in")
	CoinsManager._apply_doc({"coins": 0, "owned_themes": {}, "selected_theme": "default"})
	var frame_before: String = CoinsManager.selected_frame
	for idv in WorldScenes.ORDER:
		var id := String(idv)
		var cost := CoinsManager.theme_price(id)
		_check(cost == int(WORLD_PRICES[id]), "%s is free (price %d)" % [id, cost])
		_check(not CoinsManager.owns(id), "%s starts unowned" % id)
		# Free, so an empty wallet is no obstacle — but it is still a BUY, and the
		# tap is still what puts the id in the wallet. Nothing is handed over until
		# the player asks for it.
		_check(CoinsManager.can_afford(id), "%s affordable at a zero balance" % id)
		_check(CoinsManager.purchase_theme(id), "%s: the free unlock goes through" % id)
		_check(CoinsManager.balance == 0, "%s: it charged nothing" % id)
		_check(CoinsManager.owns(id), "%s owned after the unlock" % id)
		_check(not CoinsManager.purchase_theme(id), "%s: unlocking it twice is refused" % id)
		# ...and equipping it is the ordinary theme path, with the button frame
		# untouched on the way through.
		_check(CoinsManager.select_theme(id), "%s equips" % id)
		_check(CoinsManager.selected_theme == id, "%s is the selected theme" % id)
		_check(CoinsManager.is_simon_manual(), "%s: equipping returns to manual mode" % id)
		_check(CoinsManager.selected_frame == frame_before,
			"%s: equipping left the button frame alone" % id)
		await get_tree().process_frame
	# Every Themes1 floor still behaves exactly as it did.
	CoinsManager.balance = 700
	_check(CoinsManager.purchase_theme("bg_crystal"), "Themes1 bg_crystal still buys at 700")
	_check(CoinsManager.balance == 0, "and still charges 700")

func _boards() -> void:
	print("\n--- boards ---")
	CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL
	CoinsManager.selected_skin = ""
	for board in ["easy", "moderate", "hard"]:
		for idv in WorldScenes.ORDER:
			var id := String(idv)
			CoinsManager.selected_theme = id
			var dev: Control = (Easy.new() if board == "easy"
				else (Hard.new() if board == "hard" else Medium.new()))
			dev.input_enabled = false
			dev.set_anchors_preset(Control.PRESET_FULL_RECT)
			add_child(dev)
			dev.configure(dev._count, [])
			dev.set_level(12)
			for i in 14:
				await get_tree().process_frame
			_check(dev._bg_id == id, "%s/%s equipped on the board" % [board, id])
			_check(dev._bg_scene != null and dev._bg_scene.is_inside_tree(),
				"%s/%s is in the board's viewport" % [board, id])
			if dev._bg_scene != null:
				var sc: float = dev._bg_scene.scale.x
				var deck: Dictionary = Data.DECK[WorldScenes.world_of(id)]
				# fit_scale never grows a world, so its floor is clamped to 1.0 too —
				# which is where Hard lands on both, its buttons having no room to
				# spare inside the deck at the authored scale.
				var floor_s: float = minf(
					(dev._board_reach() + WorldScenes.DECK_MARGIN) / float(deck["radius"]), 1.0)
				_check(sc <= 1.0001, "%s/%s never grown (%.3f)" % [board, id, sc])
				_check(sc >= floor_s - 0.001,
					"%s/%s deck still clears the buttons (%.3f >= %.3f)" % [board, id, sc, floor_s])
				_check(dev._bg_scene.position.is_equal_approx(Vector3.ZERO),
					"%s/%s not slid" % [board, id])
				# And the pool sheet actually followed it. Both numbers scale with the
				# world, so this is the check that catches a fit_scale that ran after
				# the sheet was placed.
				var sheet := dev._vp.find_child("GroundGlow", true, false) as Node3D
				_check(sheet != null, "%s/%s has a pool sheet" % [board, id])
				if sheet != null:
					_check(sheet.position.y > float(deck["top"]) * sc,
						"%s/%s pool sheet is above the deck (%.4f > %.4f)"
						% [board, id, sheet.position.y, float(deck["top"]) * sc])
					_check(is_equal_approx(sheet.position.y,
						(float(deck["top"]) + WorldScenes.POOL_DECK_BIAS) * sc
						+ Medium.GLOW_PLANE_Y),
						"%s/%s pool sheet at the fitted deck height" % [board, id])
					var edge: float = dev._glow_mat.get_shader_parameter("deck_r")
					_check(is_equal_approx(edge, WorldScenes.pool_radius(id) * sc),
						"%s/%s pool is clipped to the fitted deck edge" % [board, id])
			# The buttons are untouched: still on the board's own layer, where no
			# background light can reach them, and still answering taps.
			var holder := dev._board.find_child("Button_%s" % dev._keys[0], true, false) as Node3D
			var surf := holder.find_child("Button_%s_Surface" % dev._keys[0], true, false) as MeshInstance3D
			_check(surf != null and surf.layers == 1, "%s/%s buttons still on layer 1" % [board, id])
			_check(dev.segment_at_point(_button_screen(dev, 0)) == 0,
				"%s/%s button 0 still hit-tests" % [board, id])
			# The HUD keeps its corners: LEVEL on the left, and the board's own
			# silhouette clear of the column it holds.
			_check(dev._tab != null and dev._tab.visible, "%s/%s LEVEL tab present" % [board, id])
			_check(dev._board_rect.position.x >= 0.0, "%s/%s board rect resolved" % [board, id])
			dev.queue_free()
			await get_tree().process_frame

func _button_screen(dev: Control, idx: int) -> Vector2:
	var holder := dev._board.find_child("Button_%s" % dev._keys[idx], true, false) as Node3D
	var top := holder.global_position + Vector3(0.0, 0.5, 0.0)
	var px: Vector2 = dev._cam.unproject_position(top)
	var vp := Vector2(dev._vp.size)
	if vp.x <= 0.0 or vp.y <= 0.0:
		return px
	return px * (dev.size / vp)
