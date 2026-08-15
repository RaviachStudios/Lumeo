extends Control

# Modal popup for buying coin packs via Google Play Billing. Mounted as a
# child of whichever screen opened it (home / shop).
#
# Layout: 8 coin packs arranged in a 4×2 grid, each card carries a coin
# illustration, the coin amount, a pack label, and a buy button stamped
# with the localized Play price. A "Processing…" overlay covers the dialog
# during a purchase; the result overlay (success / pending / failed) is
# shown afterward.
#
# A full-width "Remove Ads" card used to sit under the grid. The product was
# delisted (see PurchaseManager.REMOVE_ADS_SKU) once the interstitials it
# suppressed left the game, so the card and DIALOG_H's room for it are gone.

const DIALOG_W := 920.0
const DIALOG_H := 550.0
const CARD_W := 198.0
const CARD_H := 170.0
const CARD_GAP_X := 12.0
const CARD_GAP_Y := 14.0
const ART_H := 74.0

# Card tints by tier — value climbs from a calm navy face for the small
# packs, through a purple mid-tier, to a warm gold face for the headline
# packs so the eye climbs the grid as the price climbs.
const TIER_NAVY := Color(0.07, 0.10, 0.24, 0.95)
const TIER_PURPLE := Color(0.20, 0.13, 0.42, 0.96)
const TIER_GOLD := Color(0.28, 0.18, 0.04, 0.96)
const RIM_GOLD := Color(1.00, 0.78, 0.22)
const RIM_PURPLE := Color(0.72, 0.50, 1.00)
const RIM_NAVY := Color(0.45, 0.55, 1.00, 0.45)

var _backdrop: ColorRect
var _dialog: Panel
var _cards_by_sku: Dictionary = {}        # sku -> {root, btn, btn_col, sku}
var _status_label: Label
var _processing_overlay: Control
# Result overlay covers the dialog with a success / pending / failure card
# after the purchase resolves. Built lazily because each result needs custom
# copy + accent colour and we'd rather rebuild than juggle three child sets.
var _result_overlay: Control = null
var _is_closing := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_layout()
	get_viewport().size_changed.connect(_layout)

	PurchaseManager.products_loaded.connect(_on_products_loaded)
	PurchaseManager.purchase_started.connect(_on_purchase_started)
	PurchaseManager.purchase_succeeded.connect(_on_purchase_succeeded)
	PurchaseManager.purchase_failed.connect(_on_purchase_failed)
	PurchaseManager.purchase_pending.connect(_on_purchase_pending)

	# Lazy-init the Play Billing connection on first popup open. WHY: doing it
	# in PurchaseManager._ready races with Firebase auth's Activity-callback
	# wiring on Android and breaks Google Sign-In on some devices.
	PurchaseManager.ensure_initialised()

	_refresh_cards()

	# Pop-in entrance, same beat as the daily-claim popup.
	_dialog.pivot_offset = _dialog.size * 0.5
	_dialog.scale = Vector2.ONE * 0.88
	_dialog.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dialog, "modulate:a", 1.0, 0.20)
	tw.tween_property(_backdrop, "modulate:a", 1.0, 0.20).from(0.0)

func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.68)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_click)
	add_child(_backdrop)

	_dialog = Panel.new()
	_dialog.size = Vector2(DIALOG_W, DIALOG_H)
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	var ds := StyleBoxFlat.new()
	# Deep navy face with a subtle vertical gradient and a gold rim — gives
	# the popup a premium "showcase" feel without competing with the cards.
	ds.bg_color = Color(0.045, 0.060, 0.180, 0.98)
	ds.set_corner_radius_all(26)
	ds.border_color = Color(1.0, 0.78, 0.22, 0.85)
	ds.set_border_width_all(2)
	ds.shadow_color = Color(1.0, 0.78, 0.22, 0.30)
	ds.shadow_size = 32
	_dialog.add_theme_stylebox_override("panel", ds)
	add_child(_dialog)

	var title := Label.new()
	title.text = "GET COINS"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.55))
	title.add_theme_color_override("font_shadow_color", Color(0.70, 0.42, 0.0, 0.65))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_constant_override("shadow_outline_size", 10)
	title.position = Vector2(0, 22)
	title.size = Vector2(DIALOG_W, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog.add_child(title)

	var sub := Label.new()
	sub.text = "Top up your wallet to unlock more themes, colours and skins."
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.82, 0.86, 1.0, 0.85))
	sub.position = Vector2(0, 70)
	sub.size = Vector2(DIALOG_W, 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog.add_child(sub)

	# Coin pack grid (4 columns × 2 rows). Cards are positioned individually
	# so headline tiers can carry their own tag pill that pops slightly out.
	var packs: Array = PurchaseManager.PACKS
	var grid_w := 4.0 * CARD_W + 3.0 * CARD_GAP_X
	var grid_x := (DIALOG_W - grid_w) * 0.5
	var grid_y := 100.0
	for i in packs.size():
		var p: Dictionary = packs[i]
		var col := i % 4
		var row := i / 4
		var card := _make_pack_card(p)
		card["root"].position = Vector2(
			grid_x + col * (CARD_W + CARD_GAP_X),
			grid_y + row * (CARD_H + CARD_GAP_Y))
		_dialog.add_child(card["root"])
		_cards_by_sku[String(p["sku"])] = card

	# Inline status text (transient).
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.55))
	_status_label.position = Vector2(0, DIALOG_H - 56)
	_status_label.size = Vector2(DIALOG_W, 22)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.text = ""
	_dialog.add_child(_status_label)

	# Footer hint (legal-ish microcopy).
	var foot := Label.new()
	foot.text = "Secure payment via Google Play. Coins are non-refundable and non-transferable."
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.68, 0.72, 0.92, 0.7))
	foot.position = Vector2(0, DIALOG_H - 32)
	foot.size = Vector2(DIALOG_W, 18)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog.add_child(foot)

	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.size = Vector2(38, 38)
	close.position = Vector2(DIALOG_W - 50, 14)
	close.add_theme_font_size_override("font_size", 22)
	close.add_theme_color_override("font_color", Color(0.85, 0.88, 1.0, 0.75))
	close.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.45))
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close)
	_dialog.add_child(close)

	# Processing overlay covers the dialog while a purchase is mid-flight so
	# the user can't double-tap a buy button. Created hidden.
	_processing_overlay = _build_processing_overlay()
	_processing_overlay.visible = false
	_dialog.add_child(_processing_overlay)

# ---------------- pack card ----------------

# Pack tier — picks the card face tint, rim, and buy-button colour from
# the coin amount. Higher value packs get warmer treatments so the eye
# climbs the grid as the price climbs (navy → purple → gold).
func _pack_tier(coins: int) -> Dictionary:
	if coins < 500:
		return {"bg": TIER_NAVY,   "rim": RIM_NAVY,   "btn": Color(0.22, 0.55, 1.00)}
	if coins < 7000:
		return {"bg": TIER_PURPLE, "rim": RIM_PURPLE, "btn": Color(0.62, 0.42, 0.96)}
	return {"bg": TIER_GOLD,   "rim": RIM_GOLD,   "btn": Color(1.00, 0.66, 0.10)}

func _make_pack_card(pack: Dictionary) -> Dictionary:
	var sku := String(pack["sku"])
	var coins := int(pack["coins"])
	var pretty := String(pack.get("label", ""))
	var tier := _pack_tier(coins)
	var bg: Color = tier["bg"]
	var rim: Color = tier["rim"]
	var btn_col: Color = tier["btn"]

	var root := Panel.new()
	root.size = Vector2(CARD_W, CARD_H)
	root.custom_minimum_size = root.size
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var cs := StyleBoxFlat.new()
	cs.bg_color = bg
	cs.set_corner_radius_all(18)
	cs.border_color = Color(rim.r, rim.g, rim.b, 0.80)
	cs.set_border_width_all(2)
	cs.shadow_color = Color(rim.r, rim.g, rim.b, 0.30)
	cs.shadow_size = 14
	root.add_theme_stylebox_override("panel", cs)

	# Coin illustration — drawn procedurally onto a transparent Control so
	# every pack gets its own bespoke artwork (stack → pile → pouch → sack →
	# chest → safe → ornate chest → crown) without shipping per-pack PNGs.
	var art_w := CARD_W - 24.0
	var art := Control.new()
	art.position = Vector2(12, 6)
	art.size = Vector2(art_w, ART_H)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(_draw_pack_art.bind(art, coins))
	root.add_child(art)

	# Coin amount — comma-formatted for readability.
	var amount_lbl := Label.new()
	amount_lbl.text = _comma(coins)
	amount_lbl.add_theme_font_size_override("font_size", 22)
	amount_lbl.add_theme_color_override("font_color", Color(1.0, 0.94, 0.55))
	amount_lbl.add_theme_color_override("font_shadow_color", Color(0.6, 0.40, 0.0, 0.65))
	amount_lbl.add_theme_constant_override("shadow_offset_x", 0)
	amount_lbl.add_theme_constant_override("shadow_offset_y", 2)
	amount_lbl.add_theme_constant_override("shadow_outline_size", 6)
	amount_lbl.position = Vector2(0, 84)
	amount_lbl.size = Vector2(CARD_W, 26)
	amount_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(amount_lbl)

	# Pack label below the amount.
	var name_lbl := Label.new()
	name_lbl.text = pretty.to_upper()
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color(0.78, 0.82, 1.0, 0.78))
	name_lbl.position = Vector2(0, 112)
	name_lbl.size = Vector2(CARD_W, 14)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_lbl)

	# BUY button — label updated by _refresh_cards once prices land.
	var btn := Button.new()
	btn.size = Vector2(CARD_W - 20, 34)
	btn.position = Vector2(10, CARD_H - 34 - 8)
	btn.add_theme_font_size_override("font_size", 16)
	btn.focus_mode = Control.FOCUS_NONE
	_style_buy_button(btn, btn_col, true)
	btn.pressed.connect(func() -> void: _on_buy(sku))
	root.add_child(btn)

	return {"root": root, "btn": btn, "btn_col": btn_col, "sku": sku}

# Draw callback for a pack card's art area. Bound from _make_pack_card so
# Godot re-invokes it on resize/redraw without us needing a custom subclass.
func _draw_pack_art(art: Control, coins: int) -> void:
	PackIcons.draw_pack_art(art, art.size, coins)

func _style_buy_button(btn: Button, bg_col: Color, enabled: bool) -> void:
	var bg: Color = bg_col if enabled else Color(0.30, 0.30, 0.40)
	var fg: Color = Color(0.04, 0.04, 0.12) if enabled and bg.v > 0.55 else Color(1, 1, 1, 0.95)
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(13)
	s.border_color = bg.lightened(0.35)
	s.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = bg.lightened(0.12)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = bg.darkened(0.20)
	btn.add_theme_stylebox_override("pressed", sp)
	var sd := s.duplicate() as StyleBoxFlat
	sd.bg_color = bg.darkened(0.05)
	btn.add_theme_stylebox_override("disabled", sd)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_disabled_color", fg)
	btn.disabled = not enabled

# ---------------- comma + processing overlay ----------------

func _comma(n: int) -> String:
	# 1234567 -> "1,234,567". Cheap and correct for the int range we ever pass.
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out

func _build_processing_overlay() -> Control:
	var c := Control.new()
	c.size = _dialog.size
	c.mouse_filter = Control.MOUSE_FILTER_STOP    # eat clicks during purchase

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = c.size
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(dim)

	var spinner := Control.new()
	spinner.size = Vector2(64, 64)
	spinner.position = (c.size - spinner.size) * 0.5 - Vector2(0, 16)
	spinner.pivot_offset = spinner.size * 0.5
	spinner.draw.connect(_draw_spinner.bind(spinner))
	c.add_child(spinner)

	# Spin forever while visible — overlay is queue_free'd if the screen unloads.
	var rot := create_tween().set_loops()
	rot.tween_property(spinner, "rotation", TAU, 1.1) \
		.from(0.0).set_trans(Tween.TRANS_LINEAR)

	var msg := Label.new()
	msg.text = "Processing purchase…"
	msg.add_theme_font_size_override("font_size", 18)
	msg.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	msg.position = Vector2(0, c.size.y * 0.5 + 36)
	msg.size = Vector2(c.size.x, 28)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(msg)
	return c

func _draw_spinner(c: Control) -> void:
	var ctr := Vector2(32, 32)
	var r := 26.0
	c.draw_arc(ctr, r, 0.0, TAU, 64, Color(1, 1, 1, 0.18), 5.0, true)
	c.draw_arc(ctr, r, -PI * 0.5, -PI * 0.5 + PI * 0.7, 32, Color(1.0, 0.85, 0.30), 5.0, true)

# ---------------- state refresh ----------------

func _refresh_cards() -> void:
	var available := PurchaseManager.is_available()
	for sku in _cards_by_sku:
		var c: Dictionary = _cards_by_sku[sku]
		var btn: Button = c["btn"]
		var btn_col: Color = c["btn_col"]
		var price := PurchaseManager.price_for(sku)
		if not available:
			btn.text = "ON DEVICE"
			_style_buy_button(btn, btn_col, false)
		elif price.is_empty():
			btn.text = "LOADING…"
			_style_buy_button(btn, btn_col, false)
		else:
			btn.text = "BUY  %s" % price
			_style_buy_button(btn, btn_col, true)

func _on_products_loaded() -> void:
	_refresh_cards()

func _on_buy(sku: String) -> void:
	_set_status("", false)
	PurchaseManager.buy(sku)

func _on_purchase_started(_sku: String) -> void:
	_processing_overlay.visible = true

func _on_purchase_succeeded(sku: String, coins: int) -> void:
	_processing_overlay.visible = false
	# Brief card pop so the eye tracks where the credit landed before the
	# success overlay covers the dialog.
	var c: Variant = _cards_by_sku.get(sku, null)
	if c is Dictionary:
		var root: Panel = (c as Dictionary)["root"]
		root.pivot_offset = root.size * 0.5
		var pop := create_tween()
		pop.tween_property(root, "scale", Vector2.ONE * 1.06, 0.14) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		pop.tween_property(root, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_show_result(
		"success",
		"Purchase Successful!",
		"+%s coins added.\nYour balance is now %s coins." \
			% [_comma(coins), _comma(CoinsManager.balance)])

func _on_purchase_pending(_sku: String) -> void:
	_processing_overlay.visible = false
	# Slow payment methods (cash, family approval, slow test card) — Play has
	# accepted the order but coins won't land until the payment clears, often
	# minutes later when the app may not even be open.
	_show_result(
		"pending",
		"Purchase Processing",
		"Your payment is still clearing.\nThis will arrive once Google Play confirms it.")

func _on_purchase_failed(_sku: String, reason: String) -> void:
	_processing_overlay.visible = false
	if reason == "user_canceled":
		# Explicit cancel (user backed out of the sheet) — say nothing, just
		# leave the dialog in its idle state so they can try a different pack.
		_set_status("", false)
		return
	# Decline / network / already-owned / generic — surface it. We can't
	# distinguish "card declined" from "user closed the sheet" via the plugin
	# (its onPurchasesUpdated is OK-only), so the message is intentionally
	# generic for the recovery path.
	_show_result("failed", "Purchase Not Completed", _friendly_reason(reason))

func _set_status(text: String, is_error: bool) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color",
		Color(0.95, 0.55, 0.55) if is_error else Color(0.78, 0.82, 1.0, 0.85))

func _friendly_reason(reason: String) -> String:
	match reason:
		"no_network":           return "No connection. Check your network and try again."
		"billing_unavailable":  return "Google Play Billing is unavailable on this device."
		"editor_unavailable":   return "Purchases require an Android build."
		"item_unavailable":     return "This item isn't available right now."
		"already_owned":        return "You already own this — try restarting the app if it isn't reflected yet."
		_:                      return "Your payment was declined or canceled.\nNothing was charged. Please try again."

# ---------------- result overlay (success / pending / failed) ----------------

# `kind` is one of "success", "pending", "failed". Each picks the accent
# colour, glyph, and CTA copy. The overlay sits above the processing overlay
# (which we hide first) and is the popup's only path to closing on a resolved
# purchase — the OK button frees the dialog.
func _show_result(kind: String, headline: String, body: String) -> void:
	if _result_overlay != null and is_instance_valid(_result_overlay):
		_result_overlay.queue_free()
	_result_overlay = _build_result_overlay(kind, headline, body)
	_dialog.add_child(_result_overlay)
	_result_overlay.modulate.a = 0.0
	create_tween().tween_property(_result_overlay, "modulate:a", 1.0, 0.18)

func _build_result_overlay(kind: String, headline: String, body: String) -> Control:
	var accent: Color
	var glyph_text: String
	var cta: String
	match kind:
		"success":
			accent = Color(0.34, 0.86, 0.50)
			glyph_text = "✓"
			cta = "AWESOME"
		"pending":
			accent = Color(0.45, 0.70, 1.00)
			glyph_text = "⌛"
			cta = "GOT IT"
		_:
			accent = Color(0.95, 0.45, 0.45)
			glyph_text = "!"
			cta = "TRY AGAIN" if kind == "failed" else "OK"

	var c := Control.new()
	c.size = _dialog.size
	c.mouse_filter = Control.MOUSE_FILTER_STOP    # block any click-through to cards

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.18, 0.92)
	dim.size = c.size
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(dim)

	# Accent ring + centred glyph
	var ring_r := 48.0
	var ring := Node2D.new()
	ring.position = Vector2(c.size.x * 0.5, c.size.y * 0.32)
	var outer := Polygon2D.new()
	outer.polygon = _circle_polygon(ring_r + 5.0, 32)
	outer.color = Color(accent.r, accent.g, accent.b, 0.30)
	ring.add_child(outer)
	var inner := Polygon2D.new()
	inner.polygon = _circle_polygon(ring_r, 32)
	inner.color = accent
	ring.add_child(inner)
	var glyph := Label.new()
	glyph.text = glyph_text
	glyph.add_theme_font_size_override("font_size", 56)
	glyph.add_theme_color_override("font_color", Color(0.04, 0.06, 0.18))
	glyph.position = Vector2(-ring_r, -ring_r)
	glyph.size = Vector2(ring_r * 2.0, ring_r * 2.0)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.add_child(glyph)
	c.add_child(ring)

	var head := Label.new()
	head.text = headline
	head.add_theme_font_size_override("font_size", 32)
	head.add_theme_color_override("font_color", Color(1.0, 0.94, 0.60))
	head.position = Vector2(0, c.size.y * 0.32 + ring_r + 24.0)
	head.size = Vector2(c.size.x, 40)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(head)

	var body_lbl := Label.new()
	body_lbl.text = body
	body_lbl.add_theme_font_size_override("font_size", 18)
	body_lbl.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0, 0.92))
	body_lbl.position = Vector2(60, c.size.y * 0.32 + ring_r + 72.0)
	body_lbl.size = Vector2(c.size.x - 120, 110)
	body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(body_lbl)

	var ok := Button.new()
	ok.text = cta
	ok.size = Vector2(240, 56)
	ok.position = Vector2((c.size.x - 240) * 0.5, c.size.y - 56 - 48)
	ok.add_theme_font_size_override("font_size", 19)
	ok.focus_mode = Control.FOCUS_NONE
	var bg := StyleBoxFlat.new()
	bg.bg_color = accent
	bg.set_corner_radius_all(14)
	ok.add_theme_stylebox_override("normal", bg)
	var bgh := bg.duplicate() as StyleBoxFlat
	bgh.bg_color = accent.lightened(0.10)
	ok.add_theme_stylebox_override("hover", bgh)
	var bgp := bg.duplicate() as StyleBoxFlat
	bgp.bg_color = accent.darkened(0.18)
	ok.add_theme_stylebox_override("pressed", bgp)
	ok.add_theme_color_override("font_color", Color(0.04, 0.06, 0.18))
	# Success / pending close the popup; failed dismisses the overlay so the
	# player can pick a different pack (or the same one) without reopening.
	if kind == "failed":
		ok.pressed.connect(_dismiss_result_overlay)
	else:
		ok.pressed.connect(_close)
	c.add_child(ok)
	return c

func _circle_polygon(r: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / n
		p.append(Vector2(cos(a), sin(a)) * r)
	return p

func _dismiss_result_overlay() -> void:
	if _result_overlay == null or not is_instance_valid(_result_overlay):
		return
	_result_overlay.queue_free()
	_result_overlay = null

# ---------------- backdrop / close ----------------

func _on_backdrop_click(ev: InputEvent) -> void:
	# Tap-to-close — but only when nothing's mid-flight, so the player can't
	# accidentally walk away from a purchase the Play sheet is still resolving.
	if PurchaseManager.is_busy():
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		_close()
	elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
		_close()

func _close() -> void:
	if _is_closing:
		return
	_is_closing = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", Vector2.ONE * 0.88, 0.15) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_dialog, "modulate:a", 0.0, 0.15)
	tw.tween_property(_backdrop, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(queue_free)

func _layout() -> void:
	var sz := get_viewport_rect().size
	if _backdrop:
		_backdrop.position = Vector2.ZERO
		_backdrop.size = sz
	if _dialog:
		# Pivot at center so the entrance scale animation grows from the
		# middle of the dialog, not the top-left corner.
		_dialog.pivot_offset = _dialog.size * 0.5
		_dialog.position = (sz - _dialog.size) * 0.5
