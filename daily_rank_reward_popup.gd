extends Control

# Modal shown on login when the previous day's daily-leaderboard standing reward
# is surfaced (see CoinsManager.consume_pending_daily_rewards). The coins are
# ALREADY banked server-side (the midnight Cloud Function credited them) by the
# time this opens — this popup is purely the celebratory receipt, so its button
# just closes. Self-built (no scene, no PNGs), overlaid on the home screen,
# mirroring daily_claim_popup.gd's construction.
#
# Inputs (set by the caller before add_child):
#   total   : int    summed coins granted
#   results : Array  of { diff: String, rank: int, reward: int }

var total: int = 0
var results: Array = []

const DIALOG_W := 560.0
const ROW_H := 46.0
const _DIFF_LABEL := {"easy": "EASY", "moderate": "MODERATE", "hard": "HARD"}
const _DIFF_COLOR := {
	"easy": Color(0.45, 0.85, 0.55),
	"moderate": Color(0.55, 0.72, 1.0),
	"hard": Color(1.0, 0.55, 0.45),
}

var _backdrop: ColorRect
var _dialog: Panel

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_dialog.pivot_offset = _dialog.size * 0.5
	_dialog.scale = Vector2.ONE * 0.85
	_dialog.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dialog, "modulate:a", 1.0, 0.18)
	tw.tween_property(_backdrop, "modulate:a", 1.0, 0.18).from(0.0)

func _build() -> void:
	# Height grows with the number of placement rows.
	var rows_h := maxi(1, results.size()) * ROW_H
	var dialog_h := 210.0 + rows_h + 96.0

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.6)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_click)
	add_child(_backdrop)

	_dialog = Panel.new()
	_dialog.size = Vector2(DIALOG_W, dialog_h)
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
	title.text = "YESTERDAY'S RANKINGS"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	title.add_theme_color_override("font_shadow_color", Color(0.6, 0.40, 0.0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 7)
	title.position = Vector2(0, 20)
	title.size = Vector2(DIALOG_W, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog.add_child(title)

	var sub := Label.new()
	sub.text = "Rewards for where you finished"
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.78, 0.82, 1.0, 0.85))
	sub.position = Vector2(0, 62)
	sub.size = Vector2(DIALOG_W, 22)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog.add_child(sub)

	# One row per placement: difficulty chip · rank · reward.
	var y := 104.0
	for r in results:
		_build_row(r, y)
		y += ROW_H

	# Total banner.
	var total_lbl := Label.new()
	total_lbl.text = "+%d 🪙" % total
	total_lbl.add_theme_font_size_override("font_size", 44)
	total_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	total_lbl.add_theme_color_override("font_shadow_color", Color(0.6, 0.40, 0.0, 0.7))
	total_lbl.add_theme_constant_override("shadow_offset_x", 0)
	total_lbl.add_theme_constant_override("shadow_offset_y", 3)
	total_lbl.add_theme_constant_override("shadow_outline_size", 9)
	total_lbl.position = Vector2(0, y + 8)
	total_lbl.size = Vector2(DIALOG_W, 56)
	total_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog.add_child(total_lbl)

	var btn := Button.new()
	btn.text = "COLLECT"
	btn.size = Vector2(240, 60)
	btn.position = Vector2((DIALOG_W - 240) * 0.5, dialog_h - 60 - 24)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 24)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(1.00, 0.66, 0.10)
	bs.set_corner_radius_all(16)
	btn.add_theme_stylebox_override("normal", bs)
	var bh := bs.duplicate() as StyleBoxFlat
	bh.bg_color = bs.bg_color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", bh)
	var bp := bs.duplicate() as StyleBoxFlat
	bp.bg_color = bs.bg_color.darkened(0.2)
	btn.add_theme_stylebox_override("pressed", bp)
	btn.add_theme_color_override("font_color", Color(0.18, 0.10, 0.0))
	btn.pressed.connect(_close)
	_dialog.add_child(btn)

func _build_row(r: Dictionary, y: float) -> void:
	var diff := String(r.get("diff", ""))
	var rank := int(r.get("rank", 0))
	var reward := int(r.get("reward", 0))
	var col: Color = _DIFF_COLOR.get(diff, Color(0.8, 0.8, 0.9))

	var chip := Label.new()
	chip.text = _DIFF_LABEL.get(diff, diff.to_upper())
	chip.add_theme_font_size_override("font_size", 18)
	chip.add_theme_color_override("font_color", col)
	chip.position = Vector2(36, y)
	chip.size = Vector2(160, ROW_H - 8)
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dialog.add_child(chip)

	var rank_lbl := Label.new()
	rank_lbl.text = "#%d" % rank
	rank_lbl.add_theme_font_size_override("font_size", 20)
	rank_lbl.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	rank_lbl.position = Vector2(196, y)
	rank_lbl.size = Vector2(120, ROW_H - 8)
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dialog.add_child(rank_lbl)

	var rw := Label.new()
	rw.text = "+%d" % reward
	rw.add_theme_font_size_override("font_size", 20)
	rw.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	rw.position = Vector2(DIALOG_W - 196, y)
	rw.size = Vector2(160, ROW_H - 8)
	rw.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rw.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dialog.add_child(rw)

func _on_backdrop_click(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		_close()
	elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
		_close()

func _close() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_dialog, "scale", Vector2.ONE * 0.85, 0.15) \
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
