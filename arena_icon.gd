class_name ArenaIcon
extends Control

# A small Control that paints one custom arena icon (dice / globe / lock) via
# ArenaIcons, in place of an emoji Label. Set `kind` and `col`, add it as a child
# of a button; it redraws itself.

const ArenaIcons := preload("res://arena_icons.gd")

var kind := "dice"
var col := Color(0.9, 0.8, 0.6)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(k: String, c: Color) -> void:
	kind = k
	col = c
	queue_redraw()

func _draw() -> void:
	# size can be (0,0) on the first draw for code-built Controls; fall back to the
	# configured minimum size.
	var s := size
	if s.x < 1.0 or s.y < 1.0:
		s = custom_minimum_size
	if s.x < 1.0 or s.y < 1.0:
		return
	ArenaIcons.paint(self, kind, s, col)
