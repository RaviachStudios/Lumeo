extends Node
# Acceptance check for the 2026-09-20 repricing: LIVING FOREST, RAINBOW SKYWAY and
# DEEP OCEAN went from FREE to 650 coins.
#
# The three were free since they shipped, which means every one of them was on the
# `price == 0` side of a fork that runs through the card, the buy button and the
# confirm dialog (ShopScreen._style_card_button). So the question is not only "does
# the number say 650" but "does each of them now take the OTHER branch, end to
# end" — the card draws a coin price instead of the word FREE, the buy is refused
# one coin short, it charges exactly 650, and the equip behind it is unchanged.
#
# It drives the REAL shop_screen.gd, so a regression in the screen fails the test
# rather than only the model behind it.
#
#   Godot_..._console.exe --path . res://tools/reprice_verify.tscn

const ShopScreen := preload("res://shop_screen.gd")

const PRICE := 650

# id -> the name the card must still carry. The names are checked because the brief
# for this change was "price only": a rename here would be a silent product change.
const REPRICED := {
	"world_forest": "Living Forest",
	"lume_rainbow": "Rainbow Skyway",
	"lume_ocean": "Deep Ocean",
}

# THE REST OF THE CATALOGUE, FROZEN. Every other theme, at the price it had before
# this change, so that "do not change the prices of any other themes" is a check and
# not a promise. Taken from CoinsManager.THEMES as it stood at the previous commit.
const UNTOUCHED := {
	"default": 0,
	"midnight": 80, "indigo": 80, "sunset": 80, "crimson": 80, "slate": 80,
	"skybound": 80, "forest": 350, "desert": 350, "clouds": 400, "speedway": 450,
	"kitty": 550, "rainbow": 600, "neon": 800, "castle": 900, "inferno": 1000,
	"fairies": 1000, "aurora": 1050, "reef": 1200, "deepspace": 1600,
	"bg_darkmetal": 100, "bg_hexfloor": 200, "bg_neongrid": 300, "bg_circuit": 400,
	"bg_deepspace": 500, "bg_volcanic": 600, "bg_crystal": 700, "bg_arcade": 800,
	"world_ice": 4000, "world_lake": 4000, "world_casino": 4000,
	"lume_candy": 500, "lume_space": 600, "lume_forest": 800, "lume_volcano": 900,
	"lume_arcade": 1000, "lume_kingdom": 1500,
}

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
	print("\n=== Living Forest / Rainbow Skyway / Deep Ocean at %d ===\n" % PRICE)
	_catalog()
	_untouched()
	await _cards()
	await _purchase()
	print("\n%s  (%d failure%s)\n" % ["PASS" if _fails == 0 else "FAIL",
			_fails, "" if _fails == 1 else "s"])
	get_tree().quit(1 if _fails > 0 else 0)

# --------------------------------------------------------------- the catalogue
func _catalog() -> void:
	print("-- the three, individually --")
	for id in REPRICED:
		var sid := String(id)
		_ok(CoinsManager.THEMES.has(sid), "%s is in CoinsManager.THEMES" % sid)
		_ok(CoinsManager.theme_price(sid) == PRICE,
				"%s costs %d" % [sid, PRICE], "%d" % CoinsManager.theme_price(sid))
		# theme_price() is the accessor the shop and the buy flow both go through;
		# the raw entry is what the save path and every harness table read. They are
		# the same number by construction, and this is the line that says so.
		_ok(int(CoinsManager.THEMES[sid]["price"]) == PRICE,
				"...and the raw THEMES entry agrees")
		_ok(String(CoinsManager.THEMES[sid]["name"]) == String(REPRICED[sid]),
				"...and is still called %s" % REPRICED[sid])
		_ok(String(CoinsManager.THEMES[sid]["category"]) == "themes",
				"...and is still a theme")
		_ok(not CoinsManager.owned_themes.has(sid), "...and is not pre-owned")

func _untouched() -> void:
	print("-- nothing else moved --")
	var moved: Array[String] = []
	for id in UNTOUCHED:
		var sid := String(id)
		if CoinsManager.theme_price(sid) != int(UNTOUCHED[sid]):
			moved.append("%s %d->%d" % [sid, int(UNTOUCHED[sid]),
					CoinsManager.theme_price(sid)])
	_ok(moved.is_empty(), "the other %d themes are at their old prices" % UNTOUCHED.size(),
			", ".join(moved))
	# And the catalogue did not gain or lose an entry on the way through.
	_ok(CoinsManager.THEMES.size() == UNTOUCHED.size() + REPRICED.size(),
			"THEMES still holds %d entries" % (UNTOUCHED.size() + REPRICED.size()),
			"%d" % CoinsManager.THEMES.size())

# --------------------------------------------------------------- the cards
# The card must read as an ordinary priced card: a coin and the number, and NOT the
# word FREE. Driven through the real screen because _style_card_button is where the
# free/priced fork actually lives.
func _cards() -> void:
	print("-- the cards --")
	FirebaseManager.uid = "repriceverify"
	CoinsManager._apply_doc({"coins": 0, "owned_themes": {}, "selected_theme": "default"})

	var stub := StubManager.new()
	stub.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(stub)
	var shop: Control = ShopScreen.new()
	shop.game_manager = stub
	shop.set_anchors_preset(Control.PRESET_FULL_RECT)
	stub.add_child(shop)
	for _i in 90:
		await get_tree().process_frame

	shop._on_tab("themes")
	await get_tree().process_frame
	for id in REPRICED:
		var sid := String(id)
		var card: Dictionary = shop._cards_by_id.get(sid, {})
		_ok(not card.is_empty(), "%s has a card on the THEMES tab" % sid)
		if card.is_empty():
			continue
		var btn: Button = card["btn"]
		var box: Control = card["price_box"]
		var lbl: Label = card["price_label"]
		_ok(btn.text != "FREE", "%s: the button no longer says FREE" % sid, btn.text)
		_ok(box.visible, "%s: the coin price block is shown" % sid)
		_ok(lbl.text == str(PRICE), "%s: and it reads %d" % [sid, PRICE], lbl.text)
	# "-- shot[:<px>]" saves the grid at that scroll, for eyeballing the row. The
	# wallet here owns nothing, which is the point: tools/world_shop.tscn equips
	# Living Forest and so can only ever show that card as EQUIPPED.
	for x in OS.get_cmdline_user_args():
		if String(x).begins_with("shot"):
			var to := 1010
			if String(x).begins_with("shot:"):
				to = int(String(x).substr(5))
			for c in _scrolls(shop):
				c.scroll_vertical = to
			for _i in 600:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var p := "user://reprice_at%d.png" % to
			get_viewport().get_texture().get_image().save_png(p)
			print("shot %s" % ProjectSettings.globalize_path(p))
	stub.queue_free()
	await get_tree().process_frame

func _scrolls(n: Node) -> Array:
	var out := []
	if n is ScrollContainer:
		out.append(n)
	for c in n.get_children():
		out += _scrolls(c)
	return out

# --------------------------------------------------------------- the buy
func _purchase() -> void:
	print("-- the buy --")
	FirebaseManager.uid = "repriceverify"
	_ok(FirebaseManager.is_signed_in(), "simulated sign-in")
	for id in REPRICED:
		var sid := String(id)
		CoinsManager._apply_doc({"coins": 0, "owned_themes": {},
				"selected_theme": "default"})
		var frame_before: String = CoinsManager.selected_frame

		# ONE COIN SHORT. The boundary, not an empty wallet: an empty wallet would
		# pass even if the comparison were wrong by 649.
		CoinsManager.balance = PRICE - 1
		_ok(not CoinsManager.can_afford(sid), "%s: refused at %d" % [sid, PRICE - 1])
		_ok(not CoinsManager.purchase_theme(sid), "%s: ...the buy does not go through" % sid)
		_ok(not CoinsManager.owns(sid), "%s: ...and it stays unowned" % sid)
		_ok(CoinsManager.balance == PRICE - 1, "%s: ...and nothing was charged" % sid)

		# EXACTLY ENOUGH.
		CoinsManager.balance = PRICE
		_ok(CoinsManager.can_afford(sid), "%s: affordable at exactly %d" % [sid, PRICE])

		# And with change, so that "exactly 650" is what the balance proves.
		CoinsManager.balance = PRICE + 25
		_ok(CoinsManager.purchase_theme(sid), "%s: the buy goes through" % sid)
		_ok(CoinsManager.balance == 25, "%s: charged exactly %d" % [sid, PRICE],
				"%d left" % CoinsManager.balance)
		_ok(CoinsManager.owns(sid), "%s: owned after the buy" % sid)
		_ok(not CoinsManager.purchase_theme(sid), "%s: buying it twice is refused" % sid)

		# ...and the equip behind it is the ordinary theme path, untouched.
		_ok(CoinsManager.select_theme(sid), "%s: equips" % sid)
		_ok(CoinsManager.selected_theme == sid, "%s: is the selected theme" % sid)
		_ok(CoinsManager.selected_frame == frame_before,
				"%s: equipping left the button frame alone" % sid)
		# A save/load round-trip, the way a fresh launch reads it.
		CoinsManager._apply_doc({"coins": CoinsManager.balance,
				"owned_themes": {sid: true}, "selected_theme": sid})
		_ok(CoinsManager.owns(sid) and CoinsManager.selected_theme == sid,
				"%s: the buy and the equip survive a reload" % sid)
		await get_tree().process_frame
