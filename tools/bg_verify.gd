extends Node
# Verification pass for the nine modelled 3D backgrounds.
#
#   Godot..._console.exe --path . res://tools/bg_verify.tscn
#
# Checks the shop wiring (catalog, order, prices), the build itself (every mesh
# found, every material replaced, every light rebuilt, no leftover imported
# lights), the persistence round-trip, and that all three difficulties can put
# each one on their board without disturbing the buttons.

const Easy := preload("res://easy_game_ui.gd")
const Medium := preload("res://memory_game_ui.gd")
const Hard := preload("res://hard_game_ui.gd")
const Data := preload("res://background_scenes_data.gd")
const ShopScreen := preload("res://shop_screen.gd")

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
	_shop()
	await _build()
	_persistence()
	await _purchase()
	await _boards()
	print("\n%d passed, %d FAILED" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)

# ---------------------------------------------------------------------------

func _catalog() -> void:
	print("\n--- catalog ---")
	_check(BackgroundScenes.CATALOG.size() == 8, "8 backgrounds in CATALOG")
	_check(BackgroundScenes.ORDER.size() == 8, "8 in ORDER")
	# Aurora was deleted outright (a rendering bug), not detached: no catalog entry,
	# no data tables, no .glb. Nothing anywhere may still refer to it.
	_check(not BackgroundScenes.CATALOG.has("bg_aurora"), "bg_aurora is gone from CATALOG")
	_check(not CoinsManager.THEMES.has("bg_aurora"), "bg_aurora is gone from THEMES")
	for id in BackgroundScenes.ORDER:
		_check(BackgroundScenes.CATALOG.has(id), "ORDER id %s is in CATALOG" % id)
		_check(CoinsManager.THEMES.has(id), "%s in CoinsManager.THEMES" % id)
		# All eight sit on one 100..800 ladder. The buy flow only needs a number it can
		# read, but the ladder itself is a design decision worth pinning: nothing may
		# drift free, and nothing may creep past the top of the band.
		_check(CoinsManager.THEMES[id].has("price"), "%s has a price" % id)
		var price := CoinsManager.theme_price(id)
		_check(price >= 100 and price <= 800, "%s is priced in 100..800 (%d)" % [id, price])
		_check(String(CoinsManager.THEMES[id]["category"]) == "themes",
			"%s is in the themes category" % id)
		_check(ResourceLoader.exists(String(BackgroundScenes.CATALOG[id]["glb"])),
			"%s glb exists" % id)
	# ORDER is the shop grid's render order and is documented as cheapest-first, so a
	# re-price that forgets to re-sort must fail here rather than in front of a player.
	var prices: Array[int] = []
	for id in BackgroundScenes.ORDER:
		prices.append(CoinsManager.theme_price(String(id)))
	var sorted_prices := prices.duplicate()
	sorted_prices.sort()
	_check(prices == sorted_prices, "ORDER is cheapest-first (%s)" % str(prices))
	# Names must be unique across the whole tab or the buy dialog is ambiguous.
	var names := {}
	for tid in CoinsManager.THEMES:
		var n := String(CoinsManager.THEMES[tid]["name"])
		_check(not names.has(n), "theme name %s is unique (also %s)" % [n, names.get(n, "")])
		names[n] = tid
	# Nothing that existed before may have moved.
	_check(CoinsManager.theme_price("deepspace") == 1600, "existing Deep Space still 1600")
	_check(CoinsManager.theme_price("midnight") == 80, "existing Midnight still 80")
	_check(CoinsManager.theme_price("reef") == 1200, "existing Coral Reef still 1200")
	# The old shader themes stay in the CATALOG even though the shop no longer lists
	# them — detaching a theme must never strip it from a wallet that already owns it.
	_check(CoinsManager.THEMES.size() == 28, "20 old themes + 8 new = 28")

func _shop() -> void:
	print("\n--- shop ---")
	var items: Array = []
	for c in ShopScreen.CATEGORIES:
		if String(c.get("key", "")) == "themes":
			items = c["items"]
	_check(not items.is_empty(), "themes category has items")
	for id in BackgroundScenes.ORDER:
		_check(items.has(id), "%s listed in the shop grid" % id)
	# The shop now sells ONLY the modelled backgrounds. "default" leads the list and is
	# the deliberate exception: it is the only way back for a player who still has a
	# detached theme equipped.
	_check(items == (["default"] as Array) + (BackgroundScenes.ORDER as Array),
		"the grid is Default followed by the eight modelled backgrounds")
	# Every older shader theme is DETACHED from the grid but still in the catalog, so
	# an existing owner keeps it. Neither half of that may quietly change.
	var detached := ["midnight", "indigo", "sunset", "crimson", "slate",
		"skybound", "forest", "desert", "clouds", "speedway", "kitty", "rainbow",
		"neon", "castle", "inferno", "fairies", "aurora", "reef", "deepspace"]
	for id in detached:
		_check(not items.has(id), "detached theme %s is off the grid" % id)
		_check(CoinsManager.THEMES.has(id), "detached theme %s is still in THEMES" % id)
	for id in items:
		_check(CoinsManager.THEMES.has(String(id)), "shop item %s exists in THEMES" % id)
	# BackgroundManager must claim every one of them, or gameplay draws its own
	# gradient over the floor.
	for id in BackgroundScenes.ORDER:
		CoinsManager.selected_theme = String(id)
		CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL
		BackgroundManager.set_active(true)
		_check(BackgroundManager.is_themed(), "is_themed() true for %s" % id)
	BackgroundManager.set_active(false)

func _build() -> void:
	print("\n--- build ---")
	for id in BackgroundScenes.ORDER:
		var coll := String(BackgroundScenes.CATALOG[id]["coll"])
		var root := BackgroundScenes.build(id)
		_check(root != null, "%s builds" % id)
		if root == null:
			continue
		add_child(root)
		# every authored mesh present, dressed, and on the background layer
		var want: Array = Data.OBJECTS[coll]
		var dressed := 0
		var undressed := 0
		for spec: Dictionary in want:
			var mi := root.find_child(String(spec["name"]), true, false) as MeshInstance3D
			_check(mi != null, "%s: mesh %s present" % [id, spec["name"]])
			if mi == null:
				continue
			_check(mi.layers == BackgroundScenes.BG_LAYER,
				"%s: %s on the background layer" % [id, spec["name"]])
			for si in mi.mesh.get_surface_count():
				if mi.get_surface_override_material(si) is ShaderMaterial:
					dressed += 1
				else:
					undressed += 1
					print("      %s surface %d kept its imported material" % [spec["name"], si])
		_check(undressed == 0, "%s: every surface re-materialled (%d done)" % [id, dressed])
		# lights: rebuilt from the table, culled to the background, none imported
		var n_lights := 0
		for c in root.get_children():
			if c is Light3D:
				n_lights += 1
				_check(c.light_cull_mask == BackgroundScenes.BG_LAYER,
					"%s: light %s culled to the background" % [id, c.name])
		_check(n_lights >= Data.LIGHTS[coll].size(),
			"%s: %d lights rebuilt from %d authored" % [id, n_lights, Data.LIGHTS[coll].size()])
		_check(_imported_lights(root.get_child(1)) == 0,
			"%s: no glTF light survived the strip" % id)
		_check(root.find_child("Backdrop", false, false) != null, "%s: has a backdrop" % id)
		root.queue_free()
		await get_tree().process_frame

func _imported_lights(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is Light3D:
			c += 1
		c += _imported_lights(ch)
	return c

func _persistence() -> void:
	print("\n--- persistence ---")
	# The save shape is a map of owned ids; the load rebuilds the array from it.
	# Round-trip each new id through exactly that path.
	for id in BackgroundScenes.ORDER:
		var sid := String(id)
		if not CoinsManager.owned_themes.has(sid):
			CoinsManager.owned_themes.append(sid)
	var saved := {}
	for t in CoinsManager.owned_themes:
		if t != CoinsManager.DEFAULT_THEME:
			saved[t] = true
	CoinsManager.selected_theme = "bg_crystal"
	var doc := {"coins": 9999, "owned_themes": saved, "selected_theme": "bg_crystal"}
	CoinsManager._apply_doc(doc)
	for id in BackgroundScenes.ORDER:
		_check(CoinsManager.owned_themes.has(String(id)),
			"%s survives the save/load round-trip" % id)
	_check(CoinsManager.selected_theme == "bg_crystal", "selected_theme round-trips")
	_check(CoinsManager.owns("bg_crystal"), "owns() true after load")
	# A wallet that predates these must still load, with none of them owned.
	CoinsManager._apply_doc({"coins": 10, "owned_themes": {"midnight": true},
		"selected_theme": "midnight"})
	_check(CoinsManager.owned_themes.has("midnight"), "old wallet keeps its theme")
	_check(not CoinsManager.owns("bg_crystal"), "old wallet owns none of the new ones")
	_check(CoinsManager.selected_theme == "midnight", "old wallet keeps its selection")
	# Selecting something the wallet does not own falls back, as it always did.
	CoinsManager._apply_doc({"coins": 10, "owned_themes": {"midnight": true},
		"selected_theme": "bg_crystal"})
	_check(CoinsManager.selected_theme == CoinsManager.DEFAULT_THEME,
		"an unowned selected_theme falls back to default")
	# A wallet holding an id this build no longer ships must still be playable: the
	# board finds no scene for it, BackgroundManager claims no shader for it, and
	# gameplay simply draws its own background as it did before any of this.
	CoinsManager._apply_doc({"coins": 10, "owned_themes": {"bg_retired": true},
		"selected_theme": "bg_retired"})
	_check(CoinsManager.selected_theme == "bg_retired", "a retired id still loads")
	_check(not BackgroundScenes.has_scene("bg_retired"), "no scene for a retired id")
	BackgroundManager.set_active(true)
	_check(not BackgroundManager.is_themed(), "a retired id paints nothing")
	BackgroundManager.set_active(false)

# The real buy-and-equip path, not a simulation of it: FirebaseManager runs a
# simulated auth off-device (uid set = signed in) and CoinsManager writes to its
# in-memory _sim_db, so purchase_theme / select_theme execute exactly the code the
# shop calls on a phone.
func _purchase() -> void:
	print("\n--- purchase / equip ---")
	FirebaseManager.uid = "bgverify"
	_check(FirebaseManager.is_signed_in(), "simulated sign-in")
	CoinsManager._apply_doc({"coins": 0, "owned_themes": {}, "selected_theme": "default"})

	var id := "bg_neongrid"
	var cost := CoinsManager.theme_price(id)        # 300 on the current ladder
	_check(cost > 0, "%s carries a real price (%d)" % [id, cost])
	# Priced, so an empty wallet must be refused outright — and refused WITHOUT
	# quietly entering owned_themes, which would hand it over for nothing.
	_check(not CoinsManager.owns(id), "starts unowned")
	_check(not CoinsManager.can_afford(id), "unaffordable at a zero balance")
	_check(not CoinsManager.purchase_theme(id), "buy is refused with no coins")
	_check(not CoinsManager.owns(id), "the refused buy granted nothing")

	# Funded to the exact price: it buys once, charges in full, and refuses a re-buy.
	CoinsManager.balance = cost
	_check(CoinsManager.can_afford(id), "affordable once funded to the exact price")
	_check(CoinsManager.purchase_theme(id), "buy succeeds when funded")
	_check(CoinsManager.owns(id), "owned after buying")
	_check(CoinsManager.balance == 0, "the price was deducted in full (%d left)" % CoinsManager.balance)
	_check(not CoinsManager.purchase_theme(id), "buying it twice is refused")
	_check(CoinsManager.balance == 0, "the refused re-buy charged nothing")

	# A far dearer legacy theme must still behave exactly as it did.
	_check(not CoinsManager.can_afford("deepspace"), "a 1600-coin theme is still unaffordable at 0")
	_check(not CoinsManager.purchase_theme("deepspace"), "and still cannot be bought")
	CoinsManager.balance = 1600
	_check(CoinsManager.purchase_theme("deepspace"), "it buys once funded")
	_check(CoinsManager.balance == 0, "and its price was deducted in full")

	_check(CoinsManager.select_theme(id), "equip succeeds")
	_check(CoinsManager.selected_theme == id, "it is the equipped theme")
	_check(CoinsManager.is_simon_manual(), "equipping a theme drops any skin")
	_check(not CoinsManager.select_theme("bg_crystal"), "equipping an unowned one is refused")
	_check(CoinsManager.selected_theme == id, "the refused equip changed nothing")

	# It must reach the disk in the shape the loader reads back.
	var doc: Dictionary = CoinsManager._sim_db.get("bgverify", {})
	var owned: Dictionary = doc.get("owned_themes", {})
	_check(owned.has(id), "the purchase was saved as a map entry")
	_check(String(doc.get("selected_theme", "")) == id, "the equip was saved")

	# Reverting to an older theme must still work with one of these equipped.
	CoinsManager.owned_themes.append("midnight")
	_check(CoinsManager.select_theme("midnight"), "can revert to an existing theme")
	_check(CoinsManager.select_theme(id), "and back again")
	FirebaseManager.uid = ""

func _boards() -> void:
	print("\n--- boards ---")
	CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL
	CoinsManager.selected_skin = ""
	for board in ["easy", "moderate", "hard"]:
		for id in BackgroundScenes.ORDER:
			CoinsManager.selected_theme = String(id)
			var dev: Control = (Easy.new() if board == "easy"
				else (Hard.new() if board == "hard" else Medium.new()))
			dev.input_enabled = false
			dev.set_anchors_preset(Control.PRESET_FULL_RECT)
			add_child(dev)
			dev.configure(dev._count, [])
			for i in 12:
				await get_tree().process_frame
			_check(dev._bg_id == String(id), "%s/%s equipped on the board" % [board, id])
			_check(dev._bg_scene != null and dev._bg_scene.is_inside_tree(),
				"%s/%s scene is in the board's viewport" % [board, id])
			# The buttons must be untouched: still on the board layer, so no theme
			# light can reach them, and still answering hit tests.
			var holder := dev._board.find_child("Button_%s" % dev._keys[0], true, false) as Node3D
			var surf := holder.find_child("Button_%s_Surface" % dev._keys[0], true, false) as MeshInstance3D
			_check(surf.layers == 1, "%s/%s buttons still on layer 1" % [board, id])
			_check(dev.segment_at_point(_button_screen(dev, 0)) == 0,
				"%s/%s button 0 still hit-tests" % [board, id])
			dev.queue_free()
			await get_tree().process_frame

# Where button `idx` lands on the device's own local coordinates, so the hit test
# can be driven the way a real tap drives it.
func _button_screen(dev: Control, idx: int) -> Vector2:
	var holder := dev._board.find_child("Button_%s" % dev._keys[idx], true, false) as Node3D
	var top := holder.global_position + Vector3(0.0, 0.5, 0.0)
	var px: Vector2 = dev._cam.unproject_position(top)
	var vp := Vector2(dev._vp.size)
	if vp.x <= 0.0 or vp.y <= 0.0:
		return px
	return px * (dev.size / vp)
