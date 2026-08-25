extends Node
# Acceptance check for the BUTTON FRAMES cosmetics: the catalog, the purchase /
# equip / persist flow, the three SKIN-BOUND frames and their priority over an
# equipped one, and how the Blender frames actually land on a live board (companion
# to mgui_verify / hgui_verify).
#
# Runs against CoinsManager's editor simulation store (the same code path the real
# Firestore write takes, minus the network). Not shipped with the game.
#   godot --headless --path . tools/frame_flow_test.tscn

var _fails := 0

func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1

func _ready() -> void:
	# Stand in for a signed-in user; CoinsManager's editor branch keeps the wallet
	# in its own in-memory store keyed by this uid.
	FirebaseManager.uid = "frametest"
	CoinsManager._apply_doc({})

	_catalog()
	_purchase()
	_persistence()
	await _device_checks()
	await _library_checks()

	print("\n%s (%d failed)" % ["ALL PASS" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)

# ---------------------------------------------------------------------------
# The catalog: exactly DEFAULT + the fifteen, correct ids, correct names, free.
# ---------------------------------------------------------------------------
const EXPECTED := [
	["default", "Default"],
	["purple_neon", "Purple Neon"],
	["cyan_neon", "Cyan Neon"],
	["magenta_neon", "Magenta Neon"],
	["electric_blue", "Electric Blue"],
	["emerald_neon", "Emerald Neon"],
	["golden_chrome", "Golden Chrome"],
	["rose_gold", "Rose Gold"],
	["obsidian_chrome", "Obsidian Chrome"],
	["zebra_glow", "Zebra Glow"],
	["tiger_glow", "Tiger Glow"],
	["aurora", "Aurora"],
	["circuit", "Circuit"],
	["holographic", "Holographic"],
	["arctic_glow", "Arctic Glow"],
	["volcanic_glow", "Volcanic Glow"],
]

func _catalog() -> void:
	print("--- catalog ---")
	_check(ButtonFrames.ORDER.size() == 16, "DEFAULT + exactly 15 cosmetics (%d)"
		% ButtonFrames.ORDER.size())
	var ids_ok := true
	var names_ok := true
	var free_ok := true
	var meshes_ok := true
	for i in EXPECTED.size():
		var want_id: String = EXPECTED[i][0]
		var want_name: String = EXPECTED[i][1]
		if i >= ButtonFrames.ORDER.size() or ButtonFrames.ORDER[i] != want_id:
			ids_ok = false
			continue
		if ButtonFrames.frame_name(want_id) != want_name:
			names_ok = false
		if ButtonFrames.frame_price(want_id) != 0:
			free_ok = false
		# Everything but DEFAULT must point at a real object in the library.
		if (want_id != "default") != ButtonFrames.is_cosmetic(want_id):
			meshes_ok = false
	_check(ids_ok, "ids are the stable ones, in order")
	_check(names_ok, "display names are correct")
	_check(free_ok, "every frame costs 0 coins")
	_check(meshes_ok, "all 15 (and only those 15) carry a library mesh")
	# The storefront lists the sixteen buyable frames and nothing else. The three
	# skin frames are catalog entries with no shop presence at all: they are worn
	# because a skin is active, never because they were bought.
	var stray := []
	for id: String in ButtonFrames.FRAMES.keys():
		var in_order: bool = ButtonFrames.ORDER.has(id)
		if in_order == ButtonFrames.is_skin_frame(id):
			stray.append(id)
	_check(stray.is_empty(),
		"every catalog entry is either in the display order or skin-bound %s" % str(stray))
	_check(ButtonFrames.SKIN_FRAMES.size() == 3
		and ButtonFrames.ORDER.size() + ButtonFrames.SKIN_FRAMES.size() == ButtonFrames.FRAMES.size(),
		"16 shop frames + 3 skin frames = the whole catalog (%d)" % ButtonFrames.FRAMES.size())

	# The priority ladder, which is the whole point of the skin frames.
	var pri_ok := true
	for skin: String in ButtonFrames.SKIN_FRAMES.keys():
		# an active skin outranks whatever is equipped, including DEFAULT...
		if ButtonFrames.effective_frame("circuit", skin) != ButtonFrames.SKIN_FRAMES[skin]:
			pri_ok = false
		if ButtonFrames.effective_frame(ButtonFrames.DEFAULT_ID, skin) != ButtonFrames.SKIN_FRAMES[skin]:
			pri_ok = false
	# ...a skin with no frame of its own, or none at all, leaves the equipment alone...
	if ButtonFrames.effective_frame("circuit", "inferno") != "circuit": pri_ok = false
	if ButtonFrames.effective_frame("circuit", "") != "circuit": pri_ok = false
	if ButtonFrames.effective_frame(ButtonFrames.DEFAULT_ID, "") != ButtonFrames.DEFAULT_ID: pri_ok = false
	# ...and a junk or skin-bound id in the equipped slot resolves to the stock bezel.
	if ButtonFrames.effective_frame("not_a_frame", "") != ButtonFrames.DEFAULT_ID: pri_ok = false
	if ButtonFrames.effective_frame("skin_arcade", "") != ButtonFrames.DEFAULT_ID: pri_ok = false
	_check(pri_ok, "skin frame > equipped frame > default, and only while that skin is on")
	var uniq := {}
	for id: String in ButtonFrames.ORDER:
		uniq[id] = true
	_check(uniq.size() == ButtonFrames.ORDER.size(), "no duplicate entries")
	# The retired procedural cosmetics must be gone, not lingering alongside.
	_check(not ButtonFrames.has_frame("glow_zebra") and not ButtonFrames.has_frame("glow_tiger"),
		"the old procedural ids are gone from the catalog")

# ---------------------------------------------------------------------------
# Buying and equipping.
# ---------------------------------------------------------------------------
func _purchase() -> void:
	print("--- free purchase ---")
	CoinsManager.balance = 0
	var equips := [0]
	CoinsManager.frames_changed.connect(func() -> void: equips[0] += 1)
	_check(CoinsManager.purchase_frame("tiger_glow"), "buys with a zero balance")
	_check(CoinsManager.balance == 0, "no coins deducted")
	_check(CoinsManager.owns_frame("tiger_glow"), "owned after purchase")
	_check(not CoinsManager.purchase_frame("tiger_glow"), "cannot re-buy what is owned")

	# Every one of the fifteen has to be buyable, not just the one above.
	var all_bought := true
	for id: String in ButtonFrames.ORDER:
		if id == ButtonFrames.DEFAULT_ID or CoinsManager.owns_frame(id):
			continue
		if not CoinsManager.purchase_frame(id):
			all_bought = false
	_check(all_bought and CoinsManager.balance == 0,
		"all 15 can be bought, and the wallet never moves")

	print("--- equip is exclusive ---")
	CoinsManager._apply_doc({})                       # back to a fresh wallet
	CoinsManager.purchase_frame("tiger_glow")
	_check(CoinsManager.select_frame("tiger_glow"), "equips an owned frame")
	_check(CoinsManager.selected_frame == "tiger_glow", "tiger is the equipped one")
	_check(not CoinsManager.select_frame("purple_neon"), "cannot equip an unowned frame")
	CoinsManager.purchase_frame("purple_neon")
	CoinsManager.select_frame("purple_neon")
	_check(CoinsManager.selected_frame == "purple_neon", "switching replaces the old one")
	_check(CoinsManager.owns_frame("tiger_glow"), "the old one stays owned")
	_check(equips[0] >= 4, "every change emitted frames_changed (%d)" % equips[0])

func _persistence() -> void:
	print("--- persistence ---")
	# Reload the wallet from what was actually written to storage.
	var doc: Dictionary = CoinsManager._sim_db.get("frametest", {})
	print("  saved doc keys: ", doc.keys())
	CoinsManager._apply_doc(doc)
	_check(CoinsManager.selected_frame == "purple_neon", "equipped frame survives a reload")
	_check(CoinsManager.owns_frame("tiger_glow") and CoinsManager.owns_frame("purple_neon"),
		"ownership survives a reload")
	_check(not CoinsManager.owns_frame("aurora"), "unbought frame is still unowned")
	# ...and DEFAULT survives being the deliberate choice.
	CoinsManager.select_frame(ButtonFrames.DEFAULT_ID)
	CoinsManager._apply_doc(CoinsManager._sim_db.get("frametest", {}))
	_check(CoinsManager.selected_frame == ButtonFrames.DEFAULT_ID,
		"an explicit DEFAULT survives a reload too")
	CoinsManager.select_frame("purple_neon")

	print("--- defensive load ---")
	CoinsManager._apply_doc({"selected_frame": "circuit"})
	_check(CoinsManager.selected_frame == "default", "equipped-but-unowned falls back to default")
	CoinsManager._apply_doc({"owned_frames": {"not_a_frame": true}, "selected_frame": "not_a_frame"})
	_check(CoinsManager.selected_frame == "default" and not CoinsManager.owns_frame("not_a_frame"),
		"unknown ids are dropped on load")
	# The ids the old procedural set used are exactly such unknowns now.
	CoinsManager._apply_doc({"owned_frames": {"glow_tiger": true}, "selected_frame": "glow_tiger"})
	_check(CoinsManager.selected_frame == "default" and not CoinsManager.owns_frame("glow_tiger"),
		"a wallet saved against the OLD catalog degrades to default")

# ---------------------------------------------------------------------------
# The live board. One equipped frame must reach ALL of a board's buttons, as the
# real Blender mesh, and touch nothing else.
# ---------------------------------------------------------------------------
const EASY_KEYS := ["Cyan", "Yellow", "Magenta"]
const MED_KEYS := ["Crimson", "Jade", "Cyan", "Amber", "Violet"]
const HARD_KEYS := ["Crimson", "Jade", "Cyan", "Amber", "Violet", "Magenta"]

func _device_checks() -> void:
	# Let any in-flight wallet load settle BEFORE seeding the state under test —
	# CoinsManager re-applies the stored doc when the editor sign-in lands, which
	# would otherwise overwrite the seed a frame later.
	for _i in 5:
		await get_tree().process_frame
	# Each board leaves the wallet on DEFAULT (that is the last thing _one_board
	# checks), so the seed is re-applied before each one rather than once.
	await _one_board("EASY", EasyGameUI.new(), EASY_KEYS)
	await _one_board("MEDIUM", MemoryGameUI.new(), MED_KEYS)
	await _one_board("HARD", HardGameUI.new(), HARD_KEYS)

func _one_board(label: String, dev: MemoryGameUI, keys: Array) -> void:
	print("--- live board: %s (%d buttons) ---" % [label, keys.size()])
	CoinsManager._apply_doc({"owned_frames": {"tiger_glow": true, "zebra_glow": true},
		"selected_frame": "tiger_glow"})
	dev.input_enabled = false
	dev.size = Vector2(1280, 720)
	# The device builds synchronously inside add_child -> _ready, so the snapshot
	# below is genuinely "what it wore the moment it was built".
	add_child(dev)

	# Snapshot what the coloured surfaces wear, so we can prove nothing touched them.
	var before := {}
	for k: String in keys:
		var s_mi := dev.surface_mesh(k)
		before[k] = [s_mi.get_surface_override_material(0), s_mi.get_surface_override_material(1),
			dev.frame_mesh(k).get_surface_override_material(1)]

	var worn: Array[MeshInstance3D] = []
	var present := true
	for k: String in keys:
		var mi := dev.cosmetic_frame(k)
		if mi == null:
			present = false
		else:
			worn.append(mi)
	_check(present, "the equipped frame reaches all %d buttons at build time" % keys.size())
	if not present:
		dev.queue_free()
		return

	var one_mesh := true
	var one_matset := true
	var at_identity := true
	var right_parent := true
	var stock_hidden := true
	for i in worn.size():
		var mi := worn[i]
		if mi.mesh != worn[0].mesh:
			one_mesh = false
		for si in mi.mesh.get_surface_count():
			if mi.get_surface_override_material(si) != worn[0].get_surface_override_material(si):
				one_matset = false
			if not (mi.get_surface_override_material(si) is ShaderMaterial):
				one_matset = false
		if mi.transform != Transform3D.IDENTITY:
			at_identity = false
		var pn := String(mi.get_parent().name)
		if not pn.begins_with("Button_") or pn.ends_with("_Surface") or pn.ends_with("_Frame"):
			right_parent = false
		if dev.frame_mesh(keys[i]).get_surface_override_material(0) != ButtonFrames.hidden_material():
			stock_hidden = false
	_check(one_mesh, "all %d share ONE mesh (no per-button copy)" % keys.size())
	_check(one_matset, "...and ONE set of ShaderMaterials")
	_check(at_identity, "placed at the identity transform, exactly over the stock bezel")
	_check(right_parent, "parented to the Button_<Colour> holder, not to the mesh the clip moves")
	_check(stock_hidden, "the stock bezel's metal is hidden on all %d" % keys.size())

	# Fit: the cosmetic's bore must clear the coloured surface at every height the
	# press can take it to. Both are measured off the meshes, not assumed.
	var cos_aabb: AABB = worn[0].mesh.get_aabb()
	var surf_aabb: AABB = dev.surface_mesh(keys[0]).mesh.get_aabb()
	var cos_r: float = maxf(cos_aabb.size.x, cos_aabb.size.z) * 0.5
	var surf_r: float = maxf(surf_aabb.size.x, surf_aabb.size.z) * 0.5
	print("  cosmetic outer r=%.3f height=%.3f | surface r=%.3f y=%.3f..%.3f"
		% [cos_r, cos_aabb.size.y, surf_r, surf_aabb.position.y, surf_aabb.end.y])
	_check(surf_r < ButtonFrames.INNER_OPENING_R,
		"the button surface (r=%.3f) fits the cosmetic's r>=%.3f opening"
			% [surf_r, ButtonFrames.INNER_OPENING_R])
	_check(absf(cos_r - 0.960) < 0.002 and absf(cos_aabb.size.y - 0.300) < 0.002,
		"the mesh is the authored 1.920 x 0.300 solid, unscaled")

	# Press: the coloured surface moves, the cosmetic does not. Both halves matter —
	# a cosmetic that stays put on a button that never moved proves nothing.
	var t_before: Transform3D = worn[0].transform
	var surf_before: Transform3D = dev.surface_mesh(keys[0]).transform
	dev.set_press(0, 1.0)
	for _i in 12:
		await get_tree().process_frame
	_check(dev.surface_mesh(keys[0]).transform != surf_before,
		"the press clip still sinks the coloured surface")
	_check(worn[0].transform == t_before, "the cosmetic is stationary through a press")
	var others_still := true
	for mi in worn:
		if mi.transform != Transform3D.IDENTITY:
			others_still = false
	_check(others_still, "...and so is every other button's")
	dev.set_press(0, 0.0)
	for _i in 20:
		await get_tree().process_frame

	# Equip something else in the shop: the board must follow immediately.
	var old_mesh: Mesh = worn[0].mesh
	CoinsManager.select_frame("zebra_glow")
	var swapped_all := true
	var swapped_mesh: Mesh = null
	for k: String in keys:
		var mi := dev.cosmetic_frame(k)
		if mi == null:
			swapped_all = false
		else:
			swapped_mesh = mi.mesh
	_check(swapped_all, "switching the equipped frame updates all %d immediately" % keys.size())
	_check(swapped_mesh != null and swapped_mesh != old_mesh, "...to a different mesh")

	# Back to default: the cosmetic must be GONE and the override cleared.
	CoinsManager.select_frame("default")
	await get_tree().process_frame
	var cleared := true
	var authored := true
	var removed := true
	for k: String in keys:
		var mi := dev.frame_mesh(k)
		if mi.get_surface_override_material(0) != null:
			cleared = false
		if dev.cosmetic_frame(k) != null:
			removed = false
		var m := mi.mesh.surface_get_material(0)
		if not (m is StandardMaterial3D) or not String(m.resource_name).ends_with("_Frame"):
			authored = false
	_check(cleared, "default clears the override on all %d" % keys.size())
	_check(removed, "default frees the cosmetic mesh on all %d" % keys.size())
	_check(authored, "the GLB's own Mat_<Colour>_Frame is what comes back")

	var untouched := true
	for k: String in keys:
		var s_mi := dev.surface_mesh(k)
		if s_mi.get_surface_override_material(0) != before[k][0]: untouched = false
		if s_mi.get_surface_override_material(1) != before[k][1]: untouched = false
		if dev.frame_mesh(k).get_surface_override_material(1) != before[k][2]: untouched = false
	_check(untouched, "button surfaces, rims and under-glows are never touched")
	dev.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------------------
# The library itself: every id resolves to a mesh, the idle is wired, and nothing
# but the frames actually asked for stays resident.
# ---------------------------------------------------------------------------
# Every id with a mesh behind it: the fifteen shop cosmetics and the three skin
# frames. DEFAULT is not one — it is the absence of a cosmetic.
func _every_cosmetic() -> Array:
	var out: Array = []
	for id: String in ButtonFrames.FRAMES.keys():
		if ButtonFrames.is_cosmetic(id):
			out.append(id)
	return out

func _library_checks() -> void:
	print("--- library ---")
	ButtonFrames.trim_cache([])
	var all_built := true
	var surfaces_ok := true
	var shared_shader := true
	var shader: Shader = null
	var animated := 0
	for id: String in _every_cosmetic():
		var entry := ButtonFrames.build(id)
		if entry.is_empty():
			all_built = false
			print("    (no mesh for %s)" % id)
			continue
		var mesh: Mesh = entry["mesh"]
		var mats: Array = entry["mats"]
		if mesh.get_surface_count() != 3 or mats.size() != 3:
			surfaces_ok = false
		for m: ShaderMaterial in mats:
			if shader == null:
				shader = m.shader
			elif m.shader != shader:
				shared_shader = false
		if ButtonFrames.animates(id):
			animated += 1
	var n := _every_cosmetic().size()
	_check(all_built, "all %d ids resolve to a mesh in the GLB" % n)
	_check(surfaces_ok, "each frame is the authored 3 surfaces (body / accent / trim)")
	_check(shared_shader, "all %d materials share ONE compiled shader" % (n * 3))
	_check(animated == n, "all %d have a live idle (%d)" % [n, animated])
	_check(ButtonFrames.build(ButtonFrames.DEFAULT_ID).is_empty(),
		"DEFAULT has no mesh — it is the absence of a cosmetic")
	_check(ButtonFrames.build("not_a_frame").is_empty(), "an unknown id builds nothing")

	# The idle must be emission-only: no geometry, no transform, no scale anywhere.
	var geo_ok := true
	for id: String in _every_cosmetic():
		var mi := ButtonFrames.make_frame_instance(id)
		if mi == null or mi.transform != Transform3D.IDENTITY or mi.scale != Vector3.ONE:
			geo_ok = false
		if mi != null:
			mi.free()
	_check(geo_ok, "every instance is born at identity, scale 1 — the idle moves no geometry")

	# ...and the cache actually lets go.
	ButtonFrames.trim_cache(["circuit"])
	_check(ButtonFrames._cache.size() == 1 and ButtonFrames._cache.has("circuit"),
		"trim_cache keeps only what is still worn (%d entries)" % ButtonFrames._cache.size())
	await get_tree().process_frame
