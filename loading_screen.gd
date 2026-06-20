extends Control

# First-launch loading screen. Shown by GameManager before the home screen on
# every app open, so the wallet doc (coins, owned/equipped theme, daily-claim
# state, shop inventory) finishes loading from Firestore BEFORE the player lands
# on home — no more values popping in late. Solid #051438 backdrop with a small,
# elegant orbiting-orb spinner and a "Loading" caption.
#
# Built entirely from Godot nodes + tweens (no assets), matching the rest of the
# app. When the data is ready (or a safety timeout elapses) it calls
# game_manager.show_home(), which frees this screen.

var game_manager: Node

# #051438 brand navy.
const BG_COLOR := Color(0.0196, 0.0784, 0.2196)

# Soft reference to the Simon colours, same palette as the home-screen orbit.
const ORB_COLORS := [
	Color(1.00, 0.82, 0.29),  # yellow
	Color(0.90, 0.28, 0.30),  # red
	Color(0.55, 0.36, 0.96),  # purple
	Color(0.18, 0.78, 0.39),  # green
	Color(0.23, 0.51, 0.96),  # blue
]

# Minimum time the screen stays up (so it never flashes), and a hard cap so a
# stalled / silently-failing Firestore read can't trap the player here forever.
const MIN_SEC := 1.1
const MAX_SEC := 9.0

var _bg: ColorRect
var _orbit: Node2D
var _ring: Line2D
var _orbs: Array[Node2D] = []
var _orb_tex: Texture2D
var _caption: Label
var _dots_idx := 0
var _done := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # swallow taps while loading
	_orb_tex = _make_radial_texture()
	_build_background()
	_build_spinner()
	_build_caption()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_start_animations()
	_run_boot()

# ---------------- build ----------------

func _build_background() -> void:
	# Under a CanvasLayer anchors give no size, so the solid fill is sized in
	# _layout(). Opaque, so any theme BackgroundManager paints beneath stays hidden
	# until the player actually reaches home.
	_bg = ColorRect.new()
	_bg.color = BG_COLOR
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

func _build_spinner() -> void:
	_orbit = Node2D.new()
	add_child(_orbit)
	_ring = Line2D.new()
	_ring.width = 2.0
	_ring.default_color = Color(0.45, 0.55, 1.0, 0.18)
	_ring.antialiased = true
	_ring.joint_mode = Line2D.LINE_JOINT_ROUND
	_orbit.add_child(_ring)
	for i in ORB_COLORS.size():
		var orb := _make_orb(ORB_COLORS[i])
		_orbit.add_child(orb)
		_orbs.append(orb)

func _make_orb(col: Color) -> Node2D:
	var orb := Node2D.new()
	var halo := Sprite2D.new()
	halo.texture = _orb_tex
	halo.modulate = Color(col.r, col.g, col.b, 0.45)
	halo.scale = Vector2.ONE * (54.0 / 128.0)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = add_mat
	orb.add_child(halo)
	var core := Sprite2D.new()
	core.texture = _orb_tex
	core.modulate = col.lightened(0.25)
	core.scale = Vector2.ONE * (20.0 / 128.0)
	orb.add_child(core)
	return orb

func _make_radial_texture() -> Texture2D:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.0)))
	return ImageTexture.create_from_image(img)

func _build_caption() -> void:
	_caption = Label.new()
	_caption.text = "Loading"
	_caption.add_theme_font_size_override("font_size", 24)
	_caption.add_theme_color_override("font_color", Color(0.78, 0.84, 1.0, 0.92))
	_caption.add_theme_color_override("font_shadow_color", Color(0.30, 0.45, 1.0, 0.35))
	_caption.add_theme_constant_override("shadow_offset_x", 0)
	_caption.add_theme_constant_override("shadow_offset_y", 0)
	_caption.add_theme_constant_override("shadow_outline_size", 6)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)

# ---------------- layout ----------------

func _layout() -> void:
	var sz := get_viewport_rect().size
	var cx := sz.x * 0.5
	var cy := sz.y * 0.46
	if _bg:
		_bg.position = Vector2.ZERO
		_bg.size = sz
	if _orbit:
		_orbit.position = Vector2(cx, cy)
		var r := 56.0
		var pts := PackedVector2Array()
		var n := 64
		for i in n + 1:
			var a: float = TAU * float(i) / n
			pts.append(Vector2(cos(a), sin(a)) * r)
		_ring.points = pts
		for i in _orbs.size():
			var a: float = -PI * 0.5 + i * TAU / _orbs.size()
			_orbs[i].position = Vector2(cos(a), sin(a)) * r
	if _caption:
		_caption.size = Vector2(280, 32)
		_caption.position = Vector2(cx - 140, cy + 96)

# ---------------- animations ----------------

func _start_animations() -> void:
	var rot := create_tween().set_loops()
	rot.tween_property(_orbit, "rotation", TAU, 2.6).from(0.0).set_trans(Tween.TRANS_LINEAR)
	for i in _orbs.size():
		var dur := 0.7 + i * 0.05
		var pulse := create_tween().set_loops()
		pulse.tween_property(_orbs[i], "scale", Vector2.ONE * 1.12, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(_orbs[i], "scale", Vector2.ONE, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# animated trailing dots on the caption ("Loading" -> "Loading..." -> ...)
	var dots := create_tween().set_loops()
	dots.tween_interval(0.35)
	dots.tween_callback(_tick_dots)

func _tick_dots() -> void:
	if _caption == null:
		return
	_dots_idx = (_dots_idx + 1) % 4
	_caption.text = "Loading" + ".".repeat(_dots_idx)

# ---------------- boot ----------------

func _run_boot() -> void:
	var start := Time.get_ticks_msec()
	# Signed-in players have a wallet doc to fetch; guests have nothing to load,
	# so for them this is purely the minimum-display delay.
	if FirebaseManager.is_signed_in():
		while not CoinsManager.is_loaded() and _elapsed(start) < MAX_SEC:
			await get_tree().process_frame
	var remaining := MIN_SEC - _elapsed(start)
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout
	if _done or not is_inside_tree():
		return
	_done = true
	if game_manager:
		game_manager.show_home()

func _elapsed(start_ms: int) -> float:
	return float(Time.get_ticks_msec() - start_ms) / 1000.0
