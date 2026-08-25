extends CanvasLayer

# The badge-earned GESTURE. A compact card slides in from the LEFT edge of the
# screen, holds briefly, then slides back out. Deliberately non-intrusive:
#   • LEFT side only — never covers the centred wheel during a game.
#   • MUTED — plays no sound, so it never competes with the game tones.
#   • Queued — multiple awards earned at once show one after another.
# Spawned once by BadgeManager and parented to the scene-tree root, so it floats
# over whatever screen is active.

const BadgeIconControl := preload("res://badge_icon_control.gd")

const CARD_W := 300.0
const CARD_H := 92.0
const HOLD := 2.4
# Resting position: tucked into the TOP-LEFT corner with a comfortable margin from
# both edges (never flush against the corner, and clear of a phone's status bar /
# notch). The card still slides in horizontally from off the left edge.
const LEFT_MARGIN := 18.0
const TOP_MARGIN := 58.0

var _layer_root: Control
var _queue: Array[String] = []
var _showing := false

func _ready() -> void:
	layer = 128
	_layer_root = Control.new()
	_layer_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer_root)
	BadgeManager.badge_earned.connect(_on_badge_earned)

func _on_badge_earned(id: String) -> void:
	_queue.append(id)
	if not _showing:
		_next()

func _next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var id: String = _queue.pop_front()
	var b: Dictionary = BadgeManager.badge(id)
	if b.is_empty():
		_next()
		return
	_show_card(b)

func _show_card(b: Dictionary) -> void:
	var accent: Color = BadgeManager.cat_color(String(b.get("cat", "")))
	# Pinned near the top-left corner (with a margin) — clear of the centred wheel.
	var y := TOP_MARGIN

	var card := Panel.new()
	card.size = Vector2(CARD_W, CARD_H)
	card.position = Vector2(-CARD_W - 8, y)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.16, 0.96)
	sb.set_corner_radius_all(18)
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
	sb.shadow_size = 16
	sb.content_margin_left = 12
	card.add_theme_stylebox_override("panel", sb)
	_layer_root.add_child(card)

	# Medallion.
	var icon := BadgeIconControl.new()
	icon.custom_minimum_size = Vector2(68, 68)
	icon.size = Vector2(68, 68)
	icon.position = Vector2(12, (CARD_H - 68) * 0.5)
	icon.set_badge(b, true)
	card.add_child(icon)

	# "BADGE EARNED" eyebrow.
	var eyebrow := Label.new()
	eyebrow.text = "BADGE EARNED"
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", accent)
	eyebrow.position = Vector2(92, 18)
	eyebrow.size = Vector2(CARD_W - 104, 18)
	eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(eyebrow)

	# Badge name.
	var name_lbl := Label.new()
	name_lbl.text = String(b.get("name", ""))
	name_lbl.add_theme_font_size_override("font_size", 21)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.position = Vector2(92, 38)
	name_lbl.size = Vector2(CARD_W - 104, 30)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	# Slide in → hold → slide out, then advance the queue. No audio (muted).
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "position:x", LEFT_MARGIN, 0.42)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_interval(HOLD)
	tw.tween_property(card, "position:x", -CARD_W - 8.0, 0.35)
	tw.tween_callback(card.queue_free)
	tw.tween_callback(_next)
