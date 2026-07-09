extends Node2D

# ArenaFX — the ambient "grand arena" flourish behind the hub UI: a row of gold
# spotlights sweeping from the rafters, a light fall of gold confetti, and — once
# in a while — a small golden winged Simon (SimonFlyer) that crosses the screen.
#
# Everything is cheap by construction: spotlights are a few additive Polygon2D
# beams swayed in _process; confetti is one CPUParticles2D; the flyer reuses the
# shared baked frames. The whole node is added between the background and the
# interactive widgets, so all of it stays BEHIND the cards and buttons.

const SimonFlyer := preload("res://simon_flyer.gd")
const GOLD := Color(1.0, 0.82, 0.30)

var _sz := Vector2.ZERO

# spotlights + confetti live in a container that is rebuilt on relayout; the flyer
# is a persistent sibling added after it, so it draws above them (but below the UI).
var _ambient: Node2D
var _spot_heads: Array[Node2D] = []
var _spot_lamps: Array[Sprite2D] = []
var _spot_base: Array[float] = []
var _spot_phase: Array[float] = []
var _t := 0.0
var _flyer: SimonFlyer

func setup(size: Vector2) -> void:
	_sz = size
	_ambient = Node2D.new()
	add_child(_ambient)
	_build()
	_flyer = SimonFlyer.new()
	add_child(_flyer)
	_flyer.setup(size, {"mode": "cross", "scale": 0.62})
	set_process(true)

func relayout(size: Vector2) -> void:
	_sz = size
	_build()
	if _flyer:
		_flyer.relayout(size)

# ---------------- spotlights + confetti ----------------

func _build() -> void:
	for c in _ambient.get_children():
		c.queue_free()
	_spot_heads.clear()
	_spot_lamps.clear()
	_spot_base.clear()
	_spot_phase.clear()

	var n := 3
	var length := _sz.y * 0.92
	for i in n:
		var head := Node2D.new()
		head.position = Vector2(_sz.x * float(i + 1) / float(n + 1), -12.0)
		head.add_child(_make_beam(length, _sz.x * 0.16, 0.055))
		head.add_child(_make_beam(length, _sz.x * 0.09, 0.10))
		var src := Sprite2D.new()      # the glowing lamp at the head
		src.texture = SimonFlyer.radial()
		src.scale = Vector2.ONE * (46.0 / 128.0)
		src.modulate = Color(GOLD.r, GOLD.g, GOLD.b, 0.7)
		var sm := CanvasItemMaterial.new()
		sm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		src.material = sm
		head.add_child(src)
		var base := (float(i) - float(n - 1) * 0.5) * 0.18   # fan the beams outward
		head.rotation = base
		_ambient.add_child(head)
		_spot_heads.append(head)
		_spot_lamps.append(src)
		_spot_base.append(base)
		_spot_phase.append(float(i) * 1.9)

	var confetti := CPUParticles2D.new()
	confetti.texture = _make_flake()
	confetti.amount = 16                                    # light fall — "not too many"
	confetti.lifetime = maxf(4.0, _sz.y / 42.0)
	confetti.preprocess = confetti.lifetime                 # pre-fill so it starts mid-air
	confetti.position = Vector2(_sz.x * 0.5, -18.0)
	confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confetti.emission_rect_extents = Vector2(_sz.x * 0.5, 8.0)
	confetti.direction = Vector2(0, 1)
	confetti.spread = 22.0
	confetti.gravity = Vector2(0, 26.0)
	confetti.initial_velocity_min = 18.0
	confetti.initial_velocity_max = 46.0
	confetti.scale_amount_min = 0.5
	confetti.scale_amount_max = 1.0
	confetti.angle_min = -180.0
	confetti.angle_max = 180.0
	confetti.angular_velocity_min = -140.0
	confetti.angular_velocity_max = 140.0
	confetti.color = GOLD
	confetti.color_ramp = _confetti_ramp()
	_ambient.add_child(confetti)

func _make_beam(length: float, base_half_w: float, base_alpha: float) -> Polygon2D:
	var w0 := 10.0
	var pg := Polygon2D.new()
	pg.polygon = PackedVector2Array([
		Vector2(-w0 * 0.5, 0.0), Vector2(w0 * 0.5, 0.0),
		Vector2(base_half_w, length), Vector2(-base_half_w, length)])
	pg.color = GOLD
	pg.vertex_colors = PackedColorArray([
		Color(GOLD.r, GOLD.g, GOLD.b, base_alpha), Color(GOLD.r, GOLD.g, GOLD.b, base_alpha),
		Color(GOLD.r, GOLD.g, GOLD.b, 0.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.0)])
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	pg.material = m
	return pg

func _confetti_ramp() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.85, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	return g

func _make_flake() -> Texture2D:
	var px := 10
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in px:
		for x in px:
			var u := absf((float(x) + 0.5) / px * 2.0 - 1.0)
			var v := absf((float(y) + 0.5) / px * 2.0 - 1.0)
			var a := clampf((1.0 - maxf(u, v)) / 0.25, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

# ---------------- process (sway) ----------------

func _process(dt: float) -> void:
	_t += dt
	for i in _spot_heads.size():
		_spot_heads[i].rotation = _spot_base[i] + sin(_t * 0.6 + _spot_phase[i]) * 0.14
		_spot_lamps[i].modulate.a = 0.55 + 0.2 * sin(_t * 1.3 + _spot_phase[i])
