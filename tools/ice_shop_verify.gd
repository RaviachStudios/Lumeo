extends Node
# Acceptance check for the SHOP half of ICE KINGDOM: that it is on the SPECIAL SKINS
# shelf and only there, that it costs nothing, and that claiming it, equipping it,
# leaving it and coming back all go through the existing theme path rather than a
# private one. The button half is tools/ice_buttons_verify.gd.
#
# Everything here drives the REAL shop_screen.gd — the cards, their buttons and the
# purchase-confirm dialog — so a regression in the screen fails the test rather than
# only the model behind it.
#
#   Godot_..._console.exe --headless --path . tools/ice_shop_verify.tscn

const ShopScreen := preload("res://shop_screen.gd")
const ICE := preload("res://ice_buttons.gd")
const OTHER_THEME := "world_forest"     # what "switch back to another skin" means here

var _fails := 0

class StubManager extends Control:
	func show_home() -> void: pass
	func await_gl_stable() -> void: pass

func _ok(cond: bool, what: String, detail: String = "") -> void:
	if cond:
		print("  ok    %s" % what)
	else:
		_fails += 1
		print("  FAIL  %s%s" % [what, ("  [%s]" % detail) if detail != "" else ""])

func _ready() -> void:
	print("\n=== Ice Kingdom in the shop ===\n")
	_catalog()
	await _flow()
	print("\n%s  (%d failure%s)\n" % ["PASS" if _fails == 0 else "FAIL",
			_fails, "" if _fails == 1 else "s"])
	get_tree().quit(1 if _fails > 0 else 0)

# ------------------------------------------------------------- the shelf
func _catalog() -> void:
	print("-- catalog --")
	var id := ICE.THEME_ID
	var def: Dictionary = {}
	for d in ShopScreen.SKIN_DEFS:
		if String(d["id"]) == id:
			def = d
	_ok(not def.is_empty(), "listed in SKIN_DEFS (the SPECIAL SKINS tab)")
	_ok(def.get("released", false) == true, "released, so the tab is a grid not the placeholder")
	_ok(String(def.get("label", "")) == "ICE KINGDOM", "reads ICE KINGDOM")
	_ok(String(def.get("theme", "")) == id, "backed by the world_ice theme, not a wheel skin")
	# The SPECIAL SKINS tab is the one shelf it is on: a second listing in THEMES would
	# offer the same id twice, from two cards whose state has to agree.
	for c in ShopScreen.CATEGORIES:
		if String(c.get("key", "")) == "themes":
			_ok(not (c.get("items", []) as Array).has(id), "NOT also listed in the THEMES tab")
	_ok(CoinsManager.THEMES.has(id), "still an ordinary CoinsManager.THEMES entry")
	_ok(CoinsManager.theme_price(id) == 0, "costs 0 coins",
			"%d" % CoinsManager.theme_price(id))
	# Through the FAÇADE, not through one catalog. Ice Kingdom's ground moved from an
	# imported Themes2 world to a background generated in Godot (ice_world.gd) at the
	# same id; the shelf, the card, the price and the wallet did not move at all, and
	# asking WorldScenes directly was the one line here that could tell.
	_ok(BackgroundScenes.has_scene(id), "the existing Ice Kingdom background is what it equips")
	_ok(IceWorld.has_scene(id), "and it is the generated one")

# --------------------------------------------------------------- the flow
func _flow() -> void:
	FirebaseManager.sign_in()
	FirebaseManager.set_display_name("Tester")
	for _i in 30:
		await get_tree().process_frame
	var id := ICE.THEME_ID
	# A brand-new wallet: nothing owned, and a balance small enough that a card which
	# actually charged for this would be unable to complete.
	CoinsManager._apply_doc({"coins": 0})
	_ok(not CoinsManager.owns(id), "a new wallet does not own it")

	var stub := StubManager.new()
	stub.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(stub)
	var shop: Control = ShopScreen.new()
	shop.game_manager = stub
	shop.set_anchors_preset(Control.PRESET_FULL_RECT)
	stub.add_child(shop)
	for _i in 90:
		await get_tree().process_frame

	print("-- the card --")
	shop._on_tab("skins")
	await get_tree().process_frame
	_ok(not shop._skins_coming_soon(), "the tab shows its grid, not Coming soon")
	var card: Dictionary = shop._skins_by_id.get(id, {})
	_ok(not card.is_empty(), "a card was built for it")
	if card.is_empty():
		return
	var btn: Button = card["btn"]
	_ok(card.get("preview") == null, "no wheel is built for a theme-backed card")
	_ok(btn.text == "FREE", "the button says FREE", btn.text)
	_ok(not (card["price_box"] as Control).visible, "and shows no coin price beside it")

	print("-- claim --")
	var before := CoinsManager.balance
	btn.emit_signal("pressed")
	await get_tree().process_frame
	# Free or not, a buy is a buy: the same confirm dialog every other card raises.
	var popup: Node = null
	for c in shop.get_children():
		if c.has_signal("confirmed"):
			popup = c
	_ok(popup != null, "tapping it raises the standard purchase confirm")
	if popup != null:
		popup.emit_signal("confirmed")
		await get_tree().process_frame
	_ok(CoinsManager.owns(id), "claiming puts it in owned_themes")
	_ok(CoinsManager.balance == before, "and costs nothing", "%d -> %d" % [before, CoinsManager.balance])
	_ok(CoinsManager.selected_theme == id, "a fresh claim auto-equips")
	# Not refreshed by hand: the card is expected to follow CoinsManager.themes_changed
	# on its own, which is what keeps it honest while the player is looking at it.
	await get_tree().process_frame
	_ok(btn.text == "EQUIPPED", "the card follows the equip on its own, and reads EQUIPPED",
			btn.text)

	print("-- the board follows --")
	var dev := await _board()
	_ok(dev.button_skin_id() == ICE.THEME_ID, "a board built while it is equipped wears the snowflakes")
	dev.get_parent().queue_free()

	print("-- switch away and back --")
	# select_theme refuses a world the wallet does not hold, so claim the other one
	# first — it is free too, and this is exactly the tap a player would make.
	CoinsManager.purchase_theme(OTHER_THEME)
	CoinsManager.select_theme(OTHER_THEME)
	_ok(CoinsManager.selected_theme == OTHER_THEME, "another world equips over it",
			CoinsManager.selected_theme)
	await get_tree().process_frame
	_ok(btn.text == "EQUIP", "equipping another world drops it back to EQUIP", btn.text)
	_ok(CoinsManager.owns(id), "but it stays owned")
	var dev2 := await _board()
	_ok(dev2.button_skin_id() == "", "and that board wears the STOCK buttons")
	dev2.get_parent().queue_free()
	# Re-equipping is a tap on the same button, not a second purchase.
	btn.emit_signal("pressed")
	await get_tree().process_frame
	_ok(CoinsManager.selected_theme == id, "tapping EQUIP puts it back on")
	_ok(CoinsManager.balance == before, "and still costs nothing")

	print("-- persistence --")
	# What the save path would write, read back the way a fresh launch reads it.
	CoinsManager._apply_doc({"coins": CoinsManager.balance,
		"owned_themes": {id: true}, "selected_theme": id})
	_ok(CoinsManager.owns(id) and CoinsManager.selected_theme == id,
			"the claim and the equip survive a reload")
	_ok(ICE.active(), "and the snowflakes are on after it")

# One live Hard board, configured the way gameplay configures it.
func _board() -> MemoryGameUI:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child(vp)
	var dev := HardGameUI.new()
	vp.add_child(dev)
	dev.size = Vector2(1920, 1080)
	await get_tree().process_frame
	dev.configure(0, [])
	return dev
