extends Control

# Standalone harness to preview the 3D Simon wheel in isolation.
# Run this scene directly in the editor (open wheel_test.tscn, press F6).
#   - auto-cycles lighting each segment
#   - tap/click a segment to light + press it
#   - buttons top-left switch 4 / 5 / 6 segments (easy/moderate/hard)

const COLORS := [
	Color(0.9, 0.15, 0.15),   # Red
	Color(0.15, 0.8, 0.15),   # Green
	Color(0.15, 0.35, 0.95),  # Blue
	Color(0.95, 0.85, 0.1),   # Yellow
	Color(0.95, 0.5,  0.1),   # Orange
	Color(0.95, 0.3,  0.7),   # Pink
]

var _wheel: SimonWheel
var _count := 5
var _cycle_idx := 0

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_wheel = SimonWheel.new()
	add_child(_wheel)
	_layout_wheel()
	get_viewport().size_changed.connect(_layout_wheel)
	_wheel.configure(_count, COLORS)

	for n in [4, 5, 6]:
		var b := Button.new()
		b.text = "%d" % n
		b.position = Vector2(20 + (n - 4) * 60, 20)
		b.size = Vector2(50, 44)
		b.pressed.connect(func() -> void: _set_count(n))
		add_child(b)

	var t := Timer.new()
	t.wait_time = 0.7
	t.autostart = true
	t.timeout.connect(_cycle)
	add_child(t)

func _layout_wheel() -> void:
	var vp := get_viewport_rect().size
	var s: float = minf(vp.x, vp.y) * 0.92
	_wheel.size = Vector2(s, s)
	_wheel.position = (vp - _wheel.size) * 0.5

func _set_count(n: int) -> void:
	_count = n
	_cycle_idx = 0
	_wheel.configure(_count, COLORS)

func _cycle() -> void:
	var idx := _cycle_idx % _count
	_wheel.set_lit(idx, true)
	get_tree().create_timer(0.4).timeout.connect(func() -> void: _wheel.set_lit(idx, false))
	_cycle_idx += 1

func _gui_input(event: InputEvent) -> void:
	var pos := Vector2(-1, -1)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
	if pos.x < 0:
		return
	var local := pos - _wheel.position
	var idx := _wheel.segment_at_point(local)
	if idx >= 0:
		_wheel.set_lit(idx, true)
		_wheel.set_press(idx, 1.0)
		get_tree().create_timer(0.25).timeout.connect(func() -> void:
			_wheel.set_lit(idx, false)
			_wheel.set_press(idx, 0.0))
