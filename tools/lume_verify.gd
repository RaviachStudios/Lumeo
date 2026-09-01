extends Node
# Verification pass for the eight LUMEO worlds (lume_worlds.gd).
#
#   Godot..._console.exe --path . res://tools/lume_verify.tscn
#   Godot..._console.exe --path . res://tools/lume_verify.tscn -- boards
#
# Two halves, and the FIRST one matters more than the second: this feature is
# additive, so most of what is worth checking is that nothing already in the shop
# moved. BEFORE holds the whole pre-existing theme catalog — every id and every
# price — as a frozen literal, and the run fails if any of it differs by one coin
# or one entry. The rest checks that the eight new ones actually work: catalog,
# shop wiring, shader compilation, the plate/dyn/props render path, the preview
# card, purchase, equip, persistence, and (with `-- boards`) that each of them
# lands on all three difficulties without touching a button.

const Easy := preload("res://easy_game_ui.gd")
const Medium := preload("res://memory_game_ui.gd")
const Hard := preload("res://hard_game_ui.gd")
const ShopScreen := preload("res://shop_screen.gd")
const LumeWorlds := preload("res://lume_worlds.gd")

# The catalog exactly as it stood before the eight were added. Nothing in here may
# change: not a price, not a name key, not the set. A theme leaving this list is
# a background someone already paid for that has stopped existing.
const BEFORE := {
	"default": 0, "midnight": 80, "indigo": 80, "sunset": 80, "crimson": 80,
	"slate": 80, "skybound": 80, "forest": 350, "desert": 350, "clouds": 400,
	"speedway": 450, "kitty": 550, "rainbow": 600, "neon": 800, "castle": 900,
	"inferno": 1000, "fairies": 1000, "aurora": 1050, "reef": 1200,
	"deepspace": 1600,
	"bg_darkmetal": 100, "bg_hexfloor": 200, "bg_neongrid": 300, "bg_circuit": 400,
	"bg_deepspace": 500, "bg_volcanic": 600, "bg_crystal": 700, "bg_arcade": 800,
	"world_forest": 0, "world_ice": 0,
}

# The shop's THEMES tab exactly as it stood before, in order.
#
# "world_ice" is NOT here, and never was in this sense: Ice Kingdom is sold on the
# SPECIAL SKINS shelf, because it dresses the gameplay buttons as well as the ground.
# Its catalog entry, its price and its wallet fields are untouched — BEFORE above
# still holds it — so this list is about the GRID, and the grid does not carry it.
# tools/ice_shop_verify.tscn owns that shelf.
const BEFORE_ITEMS := ["default",
	"bg_darkmetal", "bg_hexfloor", "bg_neongrid", "bg_circuit",
	"bg_deepspace", "bg_volcanic", "bg_crystal", "bg_arcade",
	"world_forest"]

# Themes that are in the catalog but deliberately off the THEMES grid because they
# sell somewhere else in the shop.
const OFF_GRID := ["world_ice"]

# The eight, with the prices they ship at.
const NEW := {
	"lume_candy": 500, "lume_space": 600,
	"lume_forest": 800, "lume_volcano": 900, "lume_arcade": 1000,
	"lume_kingdom": 1500,
	# The two free ones. Price 0 is a real price here, not "unset": the card shows a
	# FREE buy button and the tap is still what puts the id in the wallet.
	"lume_rainbow": 0, "lume_ocean": 0,
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
	_nothing_moved()
	_catalog()
	_shop()
	await _shaders()
	await _preview()
	_persistence()
	await _purchase()
	if OS.get_cmdline_user_args().has("boards"):
		await _boards()
	else:
		print("\n(skipping the per-board pass; add `-- boards` to run it)")
	print("\n%d passed, %d FAILED" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)

# ---------------------------------------------------------------------------
# Non-regression. The whole point of the feature.
# ---------------------------------------------------------------------------

func _nothing_moved() -> void:
	print("\n--- nothing already in the shop moved ---")
	for id in BEFORE:
		var sid := String(id)
		_check(CoinsManager.THEMES.has(sid), "%s is still in THEMES" % sid)
		if CoinsManager.THEMES.has(sid):
			_check(CoinsManager.theme_price(sid) == int(BEFORE[id]),
				"%s still costs %d (is %d)" % [sid, int(BEFORE[id]), CoinsManager.theme_price(sid)])
			_check(String(CoinsManager.THEMES[sid].get("category", "")) == "themes",
				"%s is still a themes-tab item" % sid)
	# +1 for Magical Lake (world_lake), added later and sold on SPECIAL SKINS. This
	# harness owns the LUMEO block; the lake is tools/lake_verify.tscn's, and all
	# this one has to know is that exactly one id arrived that is not one of NEW.
	_check(CoinsManager.THEMES.size() == BEFORE.size() + NEW.size() + 1,
		"THEMES holds exactly the old %d, the new %d and Magical Lake (is %d)"
		% [BEFORE.size(), NEW.size(), CoinsManager.THEMES.size()])
	# The pre-existing shop tab, unchanged and in the same order, as a prefix of
	# the new one — appended to, never interleaved or reordered.
	var items: Array = ShopScreen.CATEGORIES[0]["items"]
	_check(items.size() == BEFORE_ITEMS.size() + NEW.size(),
		"the THEMES tab grew by exactly ten (is %d)" % items.size())
	for i in BEFORE_ITEMS.size():
		_check(i < items.size() and String(items[i]) == BEFORE_ITEMS[i],
			"shop slot %d is still %s" % [i, BEFORE_ITEMS[i]])
	for id in OFF_GRID:
		_check(not items.has(id), "%s stays off the THEMES grid" % id)
		_check(CoinsManager.THEMES.has(id), "%s is still in the catalog though" % id)
	# Nothing new may have been quietly pre-owned: a wallet with none of them saved
	# must come back owning none of them.
	CoinsManager._apply_doc({"coins": 10, "owned_themes": {"midnight": true},
		"selected_theme": "midnight"})
	for id in NEW:
		_check(not CoinsManager.owns(String(id)), "%s is not handed out for free" % id)
	_check(CoinsManager.selected_theme == "midnight", "an old wallet keeps its selection")
	# And the 3D backgrounds must not have picked any of them up: these are canvas
	# themes, and a board that tried to build one as geometry would draw nothing.
	for id in NEW:
		_check(not BackgroundScenes.has_scene(String(id)),
			"%s is not mistaken for a modelled background" % id)
	_check(BackgroundScenes.all_order().size() == 11, "the 11 modelled backgrounds are untouched")
	# Button-frame cosmetics are a different category with its own wallet key.
	_check(ButtonFrames.ORDER.size() > 0, "button frames still have a catalog")
	for id in NEW:
		_check(not ButtonFrames.has_frame(String(id)), "%s did not leak into frames" % id)

# ---------------------------------------------------------------------------

func _catalog() -> void:
	print("\n--- the eight ---")
	_check(LumeWorlds.ORDER.size() == 8, "8 ids in LumeWorlds.ORDER")
	var seen := {}
	for id in LumeWorlds.ORDER:
		var sid := String(id)
		_check(not seen.has(sid), "%s appears once in ORDER" % sid)
		seen[sid] = true
		_check(sid.begins_with("lume_"), "%s carries the lume_ prefix" % sid)
		_check(NEW.has(sid), "%s is one of the eight" % sid)
		_check(CoinsManager.THEMES.has(sid), "%s is in CoinsManager.THEMES" % sid)
		_check(CoinsManager.theme_price(sid) == int(NEW.get(sid, -1)),
			"%s costs %d" % [sid, int(NEW.get(sid, -1))])
		_check(not BEFORE.has(sid), "%s does not collide with an existing id" % sid)
		_check(LumeWorlds.has_world(sid), "has_world(%s)" % sid)
		# Every one must have a name, and it must be unique across the whole tab —
		# the buy flow has no way to disambiguate two cards with one name.
		var name := String(CoinsManager.THEMES[sid].get("name", ""))
		_check(name != "", "%s has a display name" % sid)
		var dupes := 0
		for other in CoinsManager.THEMES:
			if String(CoinsManager.THEMES[other].get("name", "")) == name:
				dupes += 1
		_check(dupes == 1, "the name %s is unique in the catalog" % name)
	# The ladder is ascending, which is what the shop's order means. NON-STRICTLY:
	# the two free worlds lead the block and 0 is not dearer than 0. What the shop
	# order has to mean is that nothing cheaper ever comes after something dearer,
	# not that no two items may cost the same.
	var last := -1
	for id in LumeWorlds.ORDER:
		var p := CoinsManager.theme_price(String(id))
		_check(p >= last, "%s (%d) is not cheaper than the one before it" % [id, p])
		last = p
	_check(not LumeWorlds.has_world("lume_nope"), "has_world rejects an unknown id")

func _shop() -> void:
	print("\n--- shop wiring ---")
	var items: Array = ShopScreen.CATEGORIES[0]["items"]
	for id in LumeWorlds.ORDER:
		_check(items.has(id), "%s is on the THEMES tab" % id)
	# In the same order the catalog lists them.
	var idx := -1
	for id in LumeWorlds.ORDER:
		var at := items.find(id)
		_check(at > idx, "%s comes after the one before it on the tab" % id)
		idx = at
	# And after everything that was already there.
	for old_id in BEFORE_ITEMS:
		_check(items.find(old_id) < items.find(LumeWorlds.ORDER[0]),
			"%s still comes before the new block" % old_id)
	for id in LumeWorlds.ORDER:
		_check(BackgroundManager._has_theme(String(id)), "_has_theme(%s)" % id)
		_check(BackgroundManager._SHADERS.has(id), "%s has a full shader" % id)
		_check(BackgroundManager._NODE_PLATE.has(id), "%s has a plate shader" % id)
		_check(BackgroundManager._NODE_DYN.has(id), "%s has a dyn shader" % id)
		# All three are the SAME authored scene under three wrappers, so each must
		# carry that world's own function block.
		var full: String = BackgroundManager._SHADERS[id]
		_check(full.contains("lumeStatic") and full.contains("lumeDyn") and full.contains("lumeHaze"),
			"%s's full shader has the whole trio" % id)
		_check(String(BackgroundManager._NODE_DYN[id]).contains("static_tex"),
			"%s's dyn samples the plate" % id)
		_check(not String(BackgroundManager._NODE_PLATE[id]).contains("TIME"),
			"%s's plate has no TIME in it (it is baked once)" % id)

# Every shader has to actually COMPILE. A Shader with bad code still loads and
# still draws — as a flat magenta — so the only way to know is to render one and
# look at what came out.
func _shaders() -> void:
	print("\n--- shaders compile and render ---")
	for id in LumeWorlds.ORDER:
		for which in ["plate", "dyn", "full"]:
			var code: String = ""
			if which == "plate":
				code = BackgroundManager._NODE_PLATE[id]
			elif which == "dyn":
				code = BackgroundManager._NODE_DYN[id]
			else:
				code = BackgroundManager._SHADERS[id]
			var img := await _render(code, which == "dyn")
			if img == null:
				_check(false, "%s/%s rendered nothing" % [id, which])
				continue
			# Godot's fallback for a shader that failed to compile is a flat
			# magenta fill, and every one of these worlds has real variation in it,
			# so both tests below catch a failure the log alone would not.
			var uniform := true
			var first := img.get_pixel(0, 0)
			var magenta := 0
			for y in range(0, img.get_height(), 7):
				for x in range(0, img.get_width(), 7):
					var c := img.get_pixel(x, y)
					if absf(c.r - first.r) + absf(c.g - first.g) + absf(c.b - first.b) > 0.02:
						uniform = false
					if c.r > 0.9 and c.b > 0.9 and c.g < 0.2:
						magenta += 1
			_check(not uniform, "%s/%s renders a scene, not a flat fill" % [id, which])
			_check(magenta == 0, "%s/%s is not the shader-error magenta" % [id, which])

func _render(code: String, needs_plate: bool) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(240, 135)
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.size = Vector2(240, 135)
	rect.color = Color(1, 1, 1, 1)
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("aspect", 240.0 / 135.0)
	if needs_plate:
		# A dyn shader without its plate samples an unbound texture, which is black
		# everywhere — indistinguishable from a compile failure. Give it a plate
		# with something in it: a gradient, so a working dyn is never uniform.
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				img.set_pixel(x, y, Color(float(x) / 64.0, float(y) / 64.0, 0.5))
		mat.set_shader_parameter("static_tex", ImageTexture.create_from_image(img))
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := vp.get_texture().get_image()
	vp.queue_free()
	return out

# The card the shop shows: a baked still of the world with the real board on it.
func _preview() -> void:
	print("\n--- preview cards ---")
	var size := Vector2(300, 152)
	# THE EQUIPPED THEME MUST NOT LEAK INTO A CARD. The preview board is the real
	# gameplay board, and asked for a background it used to fall back to the wallet:
	# with any of the ten MODELLED backgrounds equipped, that floor rendered
	# inside every LUMEO card and hid the world the card was selling — eight cards,
	# one picture. So the cards are baked here with a modelled theme deliberately
	# ON, and two different worlds have to come out looking different.
	var was: String = CoinsManager.selected_theme
	CoinsManager.selected_theme = "bg_arcade"
	var a := await BackgroundManager._render_scene_plate("lume_ocean", size)
	var b := await BackgroundManager._render_scene_plate("lume_candy", size)
	_check(a != null and b != null, "cards bake with a modelled theme equipped")
	if a != null and b != null:
		var ia := a.get_image()
		var ib := b.get_image()
		var moved := 0
		for y in range(0, ia.get_height(), 2):
			for x in range(0, ia.get_width(), 2):
				var ca := ia.get_pixel(x, y)
				var cb := ib.get_pixel(x, y)
				if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.10:
					moved += 1
		_check(moved > 1200,
			"two worlds' cards differ while bg_arcade is equipped (%d px)" % moved)
	CoinsManager.selected_theme = was
	for id in LumeWorlds.ORDER:
		var ctrl: Control = BackgroundManager.make_preview(String(id), size)
		_check(ctrl != null, "%s returns a preview control" % id)
		var tex: ImageTexture = await BackgroundManager._render_scene_plate(String(id), size)
		_check(tex != null, "%s bakes a card" % id)
		if tex == null:
			continue
		_check(Vector2i(tex.get_size()) == Vector2i(300, 152), "%s's card is card-sized" % id)
		var img := tex.get_image()
		# It must show the WORLD (varied) and the BOARD (a dark bezel somewhere in
		# the middle band, which no world paints).
		var dark := 0
		var varied := false
		var first := img.get_pixel(4, 4)
		for y in range(0, img.get_height(), 3):
			for x in range(0, img.get_width(), 3):
				var c := img.get_pixel(x, y)
				if absf(c.r - first.r) + absf(c.g - first.g) + absf(c.b - first.b) > 0.03:
					varied = true
				if y > img.get_height() / 3 and c.r < 0.10 and c.g < 0.10 and c.b < 0.12:
					dark += 1
		_check(varied, "%s's card is not a flat fill" % id)
		_check(dark > 40, "%s's card has the board standing in it (%d bezel px)" % [id, dark])
		if ctrl != null:
			ctrl.queue_free()

func _persistence() -> void:
	print("\n--- persistence ---")
	var saved := {}
	for id in LumeWorlds.ORDER:
		saved[String(id)] = true
	CoinsManager._apply_doc({"coins": 9999, "owned_themes": saved,
		"selected_theme": "lume_kingdom"})
	for id in LumeWorlds.ORDER:
		_check(CoinsManager.owns(String(id)), "%s survives the save/load round-trip" % id)
	_check(CoinsManager.selected_theme == "lume_kingdom", "an equipped world round-trips")
	# A wallet that predates them loads with none of them owned and its own choice
	# intact — the case that decides whether this feature is safe to ship.
	CoinsManager._apply_doc({"coins": 10, "owned_themes": {"bg_arcade": true},
		"selected_theme": "bg_arcade"})
	_check(CoinsManager.owns("bg_arcade"), "an old wallet keeps what it bought")
	_check(CoinsManager.selected_theme == "bg_arcade", "and what it had equipped")
	for id in LumeWorlds.ORDER:
		_check(not CoinsManager.owns(String(id)), "%s is not owned by an old wallet" % id)
	# Equipping one it does not own falls back, exactly as any other id does.
	CoinsManager._apply_doc({"coins": 10, "owned_themes": {"bg_arcade": true},
		"selected_theme": "lume_candy"})
	_check(CoinsManager.selected_theme == CoinsManager.DEFAULT_THEME,
		"an unowned world falls back to default")

# The real buy-and-equip path (FirebaseManager runs a simulated auth off-device,
# so purchase_theme / select_theme execute exactly what the shop calls).
func _purchase() -> void:
	print("\n--- purchase / equip ---")
	FirebaseManager.uid = "lumeverify"
	_check(FirebaseManager.is_signed_in(), "simulated sign-in")
	CoinsManager._apply_doc({"coins": 0, "owned_themes": {}, "selected_theme": "default"})
	var id := "lume_candy"
	var cost := CoinsManager.theme_price(id)
	_check(cost == 500, "%s costs %d" % [id, cost])
	_check(not CoinsManager.can_afford(id), "unaffordable at a zero balance")
	_check(not CoinsManager.purchase_theme(id), "buy refused with no coins")
	_check(not CoinsManager.owns(id), "the refused buy granted nothing")
	CoinsManager.balance = cost
	_check(CoinsManager.purchase_theme(id), "buy succeeds when funded")
	_check(CoinsManager.owns(id), "owned after buying")
	_check(CoinsManager.balance == 0, "the price was deducted in full")
	_check(not CoinsManager.purchase_theme(id), "buying it twice is refused")
	_check(CoinsManager.select_theme(id), "equip succeeds")
	_check(CoinsManager.selected_theme == id, "it is the equipped theme")
	_check(CoinsManager.is_simon_manual(), "equipping drops any skin")
	_check(not CoinsManager.select_theme("lume_kingdom"), "equipping an unowned one is refused")
	# It reaches the wallet in the shape the loader reads back.
	var doc: Dictionary = CoinsManager._sim_db.get("lumeverify", {})
	_check(Dictionary(doc.get("owned_themes", {})).has(id), "the purchase was saved")
	_check(String(doc.get("selected_theme", "")) == id, "the equip was saved")
	# An older background must still buy and equip with one of these on.
	CoinsManager.balance = 800
	_check(CoinsManager.purchase_theme("bg_arcade"), "an existing background still buys")
	_check(CoinsManager.select_theme("bg_arcade"), "and still equips")
	_check(CoinsManager.select_theme(id), "and the world equips back")
	FirebaseManager.uid = ""

# Each world on each board: the plate bakes, the props build, the render path is
# the cheap one, and no button moved.
func _boards() -> void:
	print("\n--- boards ---")
	CoinsManager.simon_mode = CoinsManager.SIMON_MODE_MANUAL
	CoinsManager.selected_skin = ""
	CoinsManager._apply_doc({"coins": 0, "owned_themes": {}, "selected_theme": "default"})
	BackgroundManager.set_active(true)
	for board in ["easy", "moderate", "hard"]:
		for id in LumeWorlds.ORDER:
			var sid := String(id)
			CoinsManager.owned_themes.append(sid)
			CoinsManager.selected_theme = sid
			BackgroundManager._on_themes_changed()
			var dev: Control = (Easy.new() if board == "easy"
				else (Hard.new() if board == "hard" else Medium.new()))
			dev.input_enabled = false
			dev.set_anchors_preset(Control.PRESET_FULL_RECT)
			add_child(dev)
			dev.configure(dev._count, [])
			for i in 30:
				await get_tree().process_frame
			# A canvas theme must NOT build geometry into the board's viewport: that
			# is the other kind of background, and one of these arriving there would
			# be a silent double-draw.
			_check(dev._bg_id == "", "%s/%s puts no geometry in the board" % [board, sid])
			_check(dev._bg_scene == null, "%s/%s has no 3D scene" % [board, sid])
			# The buttons are untouched.
			var holder := dev._board.find_child("Button_%s" % dev._keys[0], true, false) as Node3D
			var surf := holder.find_child("Button_%s_Surface" % dev._keys[0], true, false) as MeshInstance3D
			_check(surf != null and surf.layers == 1, "%s/%s buttons still on layer 1" % [board, sid])
			_check(dev.segment_at_point(_button_screen(dev, 0)) == 0,
				"%s/%s button 0 still hit-tests" % [board, sid])
			dev.queue_free()
			await get_tree().process_frame
		# One theme is enough to prove the render path per board; check it once.
		_check(BackgroundManager.is_themed(), "%s: the theme paints" % board)
		_check(BackgroundManager._render_mode == "NODES",
			"%s: on the cheap plate+props path (is %s)" % [board, BackgroundManager._render_mode])
		_check(is_instance_valid(BackgroundManager._props_node),
			"%s: the props layer is up" % board)
	# Leaving gameplay must take all of it down: no plate blitting, no props ticking.
	BackgroundManager.set_active(false)
	await get_tree().process_frame
	_check(not BackgroundManager.is_themed(), "off gameplay, nothing paints")
	_check(not is_instance_valid(BackgroundManager._props_node),
		"off gameplay, the props layer is gone")

func _button_screen(dev: Control, idx: int) -> Vector2:
	var holder := dev._board.find_child("Button_%s" % dev._keys[idx], true, false) as Node3D
	return dev._cam.unproject_position(holder.global_position + Vector3(0, 0.35, 0))
