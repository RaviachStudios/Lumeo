extends Control

# Modal "Are you sure?" confirmation, shown before a shop coin spend lands.
# Mounted as a child of the shop screen. Same visual language as the coin-pack
# and daily-claim popups: gold-trimmed dark dialog, scale-and-fade entrance,
# dim backdrop closes on tap (treated as cancel).
#
# API: instantiate, set `item_name` and `price`, optionally `item_preview`
# (a Control to embed at the top), connect to `confirmed`, then add_child.
# A successful confirm emits `confirmed` and closes; cancel / backdrop tap
# closes silently without emitting.

signal confirmed

const DIALOG_W := 420.0
const DIALOG_H := 260.0

# Set by the caller before add_child. Read at _ready.
var item_name: String = ""
var price: int = 0
var item_preview: Control = null     # optional: a Control to show centred up top

var _backdrop: ColorRect
var _dialog: Panel
var _is_closing := false
var _did_confirm := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_layout()
	get_viewport().size_changed.connect(_layout)

	# Pop-in entrance.
	_dialog.pivot_offset = _dialog.size * 0.5
	_dialog.scale = Vector2.ONE * 0.88
	_dialog.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", Vector2.ONE, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dialog, "modulate:a", 1.0, 0.18)
	tw.tween_property(_backdrop, "modulate:a", 1.0, 0.18).from(0.0)

func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.62)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_click)
	add_child(_backdrop)

	_dialog = Panel.new()
	_dialog.size = Vector2(DIALOG_W, DIALOG_H)
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.04, 0.06, 0.18, 0.98)
	ds.set_corner_radius_all(22)
	ds.border_color = Color(1.0, 0.78, 0.22, 0.85)
	ds.set_border_width_all(2)
	ds.shadow_color = Color(1.0, 0.78, 0.22, 0.35)
	ds.shadow_size = 22
	_dialog.add_theme_stylebox_override("panel", ds)
	add_child(_dialog)

	var title := Label.new()
	title.text = "CONFIRM PURCHASE"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	title.add_theme_color_override("font_shadow_color", Color(0.6, 0.40, 0.0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 8)
	title.position = Vector2(0, 16)
	title.size = Vector2(DIALOG_W, 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog.add_child(title)

	# Item being purchased — name reads as a confirmation question.
	var name_lbl := Label.new()
	name_lbl.text = ("Buy %s?" % item_name) if not item_name.is_empty() else "Confirm?"
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	name_lbl.position = Vector2(0, 60)
	name_lbl.size = Vector2(DIALOG_W, 26)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog.add_child(name_lbl)

	# Price line: coin medallion + amount, centred.
	var price_row := Control.new()
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin_d := 30.0
	var amount_text := _comma(price) + " coins"
	var amount_w := ThemeDB.fallback_font.get_string_size(
		amount_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 22).x
	var row_w := coin_d + 10.0 + amount_w
	price_row.size = Vector2(row_w, 36)
	price_row.position = Vector2((DIALOG_W - row_w) * 0.5, 104)
	var coin := _make_coin_medallion(coin_d)
	coin.position = Vector2(coin_d * 0.5, 18)
	price_row.add_child(coin)
	var amount_lbl := Label.new()
	amount_lbl.text = amount_text
	amount_lbl.add_theme_font_size_override("font_size", 22)
	amount_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	amount_lbl.position = Vector2(coin_d + 10.0, 4)
	amount_lbl.size = Vector2(amount_w, 28)
	amount_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	amount_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_row.add_child(amount_lbl)
	_dialog.add_child(price_row)

	# Two-button row: Cancel / Buy.
	var btn_w := 158.0
	var btn_h := 46.0
	var btn_gap := 18.0
	var btn_y := DIALOG_H - btn_h - 20.0
	var row_total := btn_w * 2 + btn_gap
	var row_x := (DIALOG_W - row_total) * 0.5

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.size = Vector2(btn_w, btn_h)
	cancel.position = Vector2(row_x, btn_y)
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.focus_mode = Control.FOCUS_NONE
	_style_button(cancel, false)
	cancel.pressed.connect(_close)
	_dialog.add_child(cancel)

	var buy := Button.new()
	buy.text = "BUY"
	buy.size = Vector2(btn_w, btn_h)
	buy.position = Vector2(row_x + btn_w + btn_gap, btn_y)
	buy.add_theme_font_size_override("font_size", 18)
	buy.focus_mode = Control.FOCUS_NONE
	_style_button(buy, true)
	buy.pressed.connect(_on_buy_pressed)
	_dialog.add_child(buy)

	# Close X in the corner for the "I changed my mind" muscle memory.
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.size = Vector2(30, 30)
	close.position = Vector2(DIALOG_W - 38, 10)
	close.add_theme_font_size_override("font_size", 18)
	close.add_theme_color_override("font_color", Color(0.8, 0.82, 1.0, 0.7))
	close.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.45))
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close)
	_dialog.add_child(close)

func _style_button(btn: Button, primary: bool) -> void:
	var bg: Color = Color(1.00, 0.66, 0.10) if primary else Color(0.18, 0.22, 0.42)
	var fg: Color = Color(0.18, 0.10, 0.0) if primary else Color(0.88, 0.90, 1.0)
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(14)
	btn.add_theme_stylebox_override("normal", s)
	var sh := s.duplicate() as StyleBoxFlat
	sh.bg_color = bg.lightened(0.12)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := s.duplicate() as StyleBoxFlat
	sp.bg_color = bg.darkened(0.20)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_color_override("font_color", fg)

func _make_coin_medallion(d: float) -> Node2D:
	# Same recipe as the coin pack popup so the brand feels continuous.
	var n := Node2D.new()
	var rim := Polygon2D.new()
	rim.polygon = _circle_polygon(d * 0.5 + 3.0, 24)
	rim.color = Color(1.0, 0.92, 0.55, 0.95)
	n.add_child(rim)
	var disc := Polygon2D.new()
	disc.polygon = _circle_polygon(d * 0.5, 24)
	disc.color = Color(1.0, 0.78, 0.20)
	n.add_child(disc)
	var glyph := Label.new()
	glyph.text = "$"
	glyph.add_theme_font_size_override("font_size", int(d * 0.7))
	glyph.add_theme_color_override("font_color", Color(0.45, 0.30, 0.05))
	glyph.position = Vector2(-d * 0.5, -d * 0.5)
	glyph.size = Vector2(d, d)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_child(glyph)
	return n

func _circle_polygon(r: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / n
		p.append(Vector2(cos(a), sin(a)) * r)
	return p

func _comma(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out

func _on_buy_pressed() -> void:
	if _did_confirm:
		return
	_did_confirm = true
	confirmed.emit()
	_close()

func _on_backdrop_click(ev: InputEvent) -> void:
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
		_dialog.position = (sz - _dialog.size) * 0.5
		_dialog.pivot_offset = _dialog.size * 0.5
