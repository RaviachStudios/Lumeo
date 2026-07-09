extends Control

# A small Control that renders one badge medallion via BadgeIcons. Reused by the
# earn-toast and the profile badge gallery. Set it up with set_badge(); it redraws.

const BadgeIcons := preload("res://badge_icons.gd")

var art := ""
var accent := Color(0.6, 0.6, 0.7)
var earned := false
var num := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_badge(b: Dictionary, is_earned: bool) -> void:
	art = String(b.get("art", ""))
	accent = BadgeManager.cat_color(String(b.get("cat", "")))
	earned = is_earned
	num = int(b.get("num", 0))
	queue_redraw()

func _draw() -> void:
	# size can be (0,0) at first draw for code-built Controls (godot rule 3);
	# fall back to the minimum size we were configured with.
	var s := size
	if s.x < 1.0 or s.y < 1.0:
		s = custom_minimum_size
	if s.x < 1.0 or s.y < 1.0:
		return
	BadgeIcons.draw_badge(self, s, art, accent, earned, num)
