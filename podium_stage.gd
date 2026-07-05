extends Node2D

# A self-contained champions' podium — the SAME drawn stage + medal blocks + trophy
# cups + flanking spotlights used on the leaderboards screen, extracted so the Arena
# active/finished contest screens can show an identical podium. Origin is at the
# horizontal centre; the stage top-front edge sits at POD_BASE_Y (y grows down).
# Usage: add as a child, then call setup([{name, score}, ...]) (index 0 = 1st).

const GOLD := Color(1.0, 0.85, 0.2)
const SILVER := Color(0.78, 0.85, 0.98)
const BRONZE := Color(0.88, 0.55, 0.28)
const PANEL_ACCENT := Color(0.55, 0.40, 1.00)
const TOP3_COLORS := [GOLD, SILVER, BRONZE]

# Podium geometry (local space; y grows downward).
const POD_BASE_Y := 244.0
const POD_STAGE_W := 548.0
const POD_STAGE_FH := 22.0
const POD_STAGE_DEPTH := 34.0
const POD_STAGE_SKEW := 14.0
const POD_BLOCK_DEPTH := 16.0
const POD_BLOCK_SKEW := 9.0
const POD_PILLARS := {
	1: {"bw": 140.0, "bh": 60.0, "ch": 150.0},
	2: {"bw": 130.0, "bh": 42.0, "ch": 128.0},
	3: {"bw": 130.0, "bh": 30.0, "ch": 116.0},
}
const PITCH := 150.0          # horizontal spacing between cups (2nd | 1st | 3rd)

const SPOT_AIM := 0.40
const SPOT_SWAY := 0.12
const SPOT_LEN := 290.0

var _orb_tex: Texture2D
var _podium: Node2D
var _spotlights: Node2D
var _spot_heads: Array[Node2D] = []

func _init() -> void:
	_orb_tex = _make_radial_texture()

# Build (or rebuild) the stage from ranked entries [{name, score}]; index 0 = 1st.
func setup(entries: Array) -> void:
	if _spotlights == null:
		_spotlights = Node2D.new()
		_spotlights.z_index = 1     # beams spill over the cups (additive, low alpha)
		add_child(_spotlights)
	if _podium == null:
		_podium = Node2D.new()
		add_child(_podium)
	for c in _podium.get_children():
		c.queue_free()
	for c in _spotlights.get_children():
		c.queue_free()
	_spot_heads.clear()

	_podium.add_child(_build_stage())
	# 2nd under the left, 1st centre (drawn last = centrepiece), 3rd right.
	for item in [[2, -PITCH], [3, PITCH], [1, 0.0]]:
		var rank: int = item[0]
		var cx: float = item[1]
		var idx := rank - 1
		var has := idx < entries.size()
		var pname := ""
		var score := 0
		if has:
			var r: Dictionary = entries[idx]
			pname = String(r.get("name", "Player"))
			score = int(r.get("score", 0))
		_podium.add_child(_build_pillar(rank, cx, has, pname, score))

	_build_spotlights()

# Start the idle spotlight sway/pulse. Call after the node is inside the tree.
func start_anim() -> void:
	for i in _spot_heads.size():
		var head: Node2D = _spot_heads[i]
		var base_rot: float = head.rotation
		var phase := 1.0 if i % 2 == 0 else -1.0
		var sway := create_tween().set_loops()
		sway.tween_property(head, "rotation", base_rot + phase * SPOT_SWAY, 2.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sway.tween_property(head, "rotation", base_rot - phase * SPOT_SWAY, 2.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var glow := create_tween().set_loops()
		glow.tween_property(head, "modulate:a", 0.72, 1.7 + i * 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		glow.tween_property(head, "modulate:a", 1.0, 1.7 + i * 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ---------------- spotlights ----------------

func _build_spotlights() -> void:
	var off_x := POD_STAGE_W * 0.5 - 32.0
	var base_y := POD_BASE_Y - 40.0
	for dir in [1.0, -1.0]:
		var head := _make_spotlight(dir)
		head.position = Vector2(-dir * off_x, base_y)
		_spotlights.add_child(head)
		_spot_heads.append(head)

func _make_spotlight(dir: float) -> Node2D:
	var head := Node2D.new()
	head.add_child(_make_beam(SPOT_LEN, 150.0, 0.07))
	head.add_child(_make_beam(SPOT_LEN, 82.0, 0.12))
	var bloom := Sprite2D.new()
	bloom.texture = _orb_tex
	bloom.modulate = Color(1.0, 1.0, 1.0, 0.55)
	bloom.scale = Vector2.ONE * (52.0 / 128.0)
	var bm := CanvasItemMaterial.new()
	bm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	bloom.material = bm
	head.add_child(bloom)
	head.add_child(_build_projector())
	head.rotation = dir * SPOT_AIM
	return head

func _make_beam(length: float, top_half_w: float, base_alpha: float) -> Polygon2D:
	var w0 := 12.0
	var pg := Polygon2D.new()
	pg.polygon = PackedVector2Array([
		Vector2(-w0 * 0.5, 0.0), Vector2(w0 * 0.5, 0.0),
		Vector2(top_half_w, -length), Vector2(-top_half_w, -length),
	])
	pg.color = Color.WHITE
	pg.vertex_colors = PackedColorArray([
		Color(1, 1, 1, base_alpha), Color(1, 1, 1, base_alpha),
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0),
	])
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	pg.material = m
	return pg

func _build_projector() -> Node2D:
	var p := Node2D.new()
	var body := Color(0.12, 0.13, 0.20)
	p.add_child(_poly(PackedVector2Array([
		Vector2(-13, 0), Vector2(13, 0), Vector2(17, 26), Vector2(-17, 26)]), body))
	p.add_child(_poly(PackedVector2Array([
		Vector2(3, 0), Vector2(13, 0), Vector2(17, 26), Vector2(8, 26)]), body.darkened(0.35)))
	p.add_child(_poly_at(_ellipse_poly(14.0, 4.6, 22), Vector2(0, 0), Color(0.34, 0.37, 0.5)))
	p.add_child(_poly_at(_ellipse_poly(10.5, 3.1, 22), Vector2(0, 0.6), Color(1.0, 1.0, 0.97, 0.92)))
	p.add_child(_poly(PackedVector2Array([
		Vector2(-9, 26), Vector2(9, 26), Vector2(12, 35), Vector2(-12, 35)]), Color(0.07, 0.08, 0.13)))
	return p

# ---------------- stage ----------------

func _build_stage() -> Node2D:
	var n := Node2D.new()
	var hw := POD_STAGE_W * 0.5
	var by := POD_BASE_Y
	var d := POD_STAGE_DEPTH
	var sk := POD_STAGE_SKEW
	var glow := Sprite2D.new()
	glow.texture = _orb_tex
	glow.modulate = Color(PANEL_ACCENT.r, PANEL_ACCENT.g, PANEL_ACCENT.b, 0.16)
	glow.scale = Vector2(POD_STAGE_W * 1.15 / 128.0, 70.0 / 128.0)
	glow.position = Vector2(sk * 0.5, by + 4.0)
	var gm := CanvasItemMaterial.new()
	gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gm
	n.add_child(glow)
	n.add_child(_poly(PackedVector2Array([
		Vector2(-hw, by), Vector2(hw, by),
		Vector2(hw + sk, by - d), Vector2(-hw + sk, by - d)]), Color(0.11, 0.13, 0.28, 0.97)))
	n.add_child(_poly(PackedVector2Array([
		Vector2(-hw, by), Vector2(hw, by),
		Vector2(hw, by + POD_STAGE_FH), Vector2(-hw, by + POD_STAGE_FH)]), Color(0.05, 0.06, 0.16, 0.98)))
	n.add_child(_poly(PackedVector2Array([
		Vector2(hw, by), Vector2(hw + sk, by - d),
		Vector2(hw + sk, by - d + POD_STAGE_FH), Vector2(hw, by + POD_STAGE_FH)]), Color(0.03, 0.04, 0.11, 0.98)))
	var edge := Line2D.new()
	edge.width = 2.0
	edge.default_color = Color(PANEL_ACCENT.r, PANEL_ACCENT.g, PANEL_ACCENT.b, 0.55)
	edge.antialiased = true
	edge.points = PackedVector2Array([Vector2(-hw, by), Vector2(hw, by)])
	n.add_child(edge)
	return n

func _build_pillar(rank: int, cx: float, has: bool, player_name: String, score: int) -> Node2D:
	var spec: Dictionary = POD_PILLARS[rank]
	var bw: float = spec["bw"]
	var bh: float = spec["bh"]
	var ch: float = spec["ch"]
	var medal: Color = TOP3_COLORS[rank - 1]
	var n := Node2D.new()
	n.position = Vector2(cx, 0.0)
	var hw := bw * 0.5
	var base_y := POD_BASE_Y - 4.0
	var top_y := base_y - bh
	var d := POD_BLOCK_DEPTH
	var sk := POD_BLOCK_SKEW
	n.add_child(_poly(PackedVector2Array([
		Vector2(-hw, base_y), Vector2(hw, base_y),
		Vector2(hw, top_y), Vector2(-hw, top_y)]), medal.darkened(0.72)))
	n.add_child(_poly(PackedVector2Array([
		Vector2(-hw, top_y), Vector2(hw, top_y),
		Vector2(hw + sk, top_y - d), Vector2(-hw + sk, top_y - d)]), medal.darkened(0.46)))
	n.add_child(_poly(PackedVector2Array([
		Vector2(hw, base_y), Vector2(hw, top_y),
		Vector2(hw + sk, top_y - d), Vector2(hw + sk, base_y - d)]), medal.darkened(0.82)))
	var edge := Line2D.new()
	edge.width = 2.0
	edge.default_color = Color(medal.r, medal.g, medal.b, 0.7)
	edge.antialiased = true
	edge.points = PackedVector2Array([Vector2(-hw, top_y), Vector2(hw, top_y)])
	n.add_child(edge)
	var num := Label.new()
	num.text = str(rank)
	var nf := int(bh * 0.62)
	num.add_theme_font_size_override("font_size", nf)
	num.add_theme_color_override("font_color", medal.lightened(0.25))
	num.add_theme_color_override("font_shadow_color", Color(medal.r, medal.g, medal.b, 0.55))
	num.add_theme_constant_override("shadow_offset_x", 0)
	num.add_theme_constant_override("shadow_offset_y", 0)
	num.add_theme_constant_override("shadow_outline_size", 7)
	num.size = Vector2(bw, bh)
	num.position = Vector2(-hw, top_y)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_child(num)
	if has:
		var cup := _build_cup(ch, medal, player_name, score)
		cup.position = Vector2(sk * 0.4, top_y - 4.0)
		n.add_child(cup)
	else:
		var dash := Label.new()
		dash.text = "—"
		dash.add_theme_font_size_override("font_size", 26)
		dash.add_theme_color_override("font_color", Color(medal.r, medal.g, medal.b, 0.4))
		dash.size = Vector2(bw, 40)
		dash.position = Vector2(-hw, top_y - 48)
		dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.add_child(dash)
	return n

func _build_cup(ch: float, medal: Color, player_name: String, score: int) -> Node2D:
	var u := ch
	var cup := Node2D.new()
	var dark := medal.darkened(0.45)
	var halo := Sprite2D.new()
	halo.texture = _orb_tex
	halo.modulate = Color(medal.r, medal.g, medal.b, 0.28)
	halo.scale = Vector2.ONE * (u * 2.6 / 128.0)
	halo.position = Vector2(0, -u * 0.62)
	var hm := CanvasItemMaterial.new()
	hm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = hm
	cup.add_child(halo)
	for sgn in [-1.0, 1.0]:
		var ctrl := PackedVector2Array([
			Vector2(sgn * 0.21 * u, -0.58 * u),
			Vector2(sgn * 0.37 * u, -0.63 * u),
			Vector2(sgn * 0.40 * u, -0.74 * u),
			Vector2(sgn * 0.35 * u, -0.85 * u),
			Vector2(sgn * 0.22 * u, -0.885 * u),
		])
		cup.add_child(_poly(_ribbon(_catmull(ctrl, 12), 0.045 * u), medal.darkened(0.08)))
	cup.add_child(_poly_at(_ellipse_poly(0.30 * u, 0.072 * u, 30), Vector2(0, -0.03 * u), dark))
	cup.add_child(_poly_at(_ellipse_poly(0.205 * u, 0.05 * u, 28), Vector2(0, -0.115 * u), medal.darkened(0.3)))
	cup.add_child(_poly_at(_ellipse_poly(0.13 * u, 0.038 * u, 24), Vector2(0, -0.165 * u), medal.darkened(0.18)))
	cup.add_child(_poly(PackedVector2Array([
		Vector2(-0.05 * u, -0.165 * u), Vector2(0.05 * u, -0.165 * u),
		Vector2(0.04 * u, -0.22 * u), Vector2(0.05 * u, -0.30 * u),
		Vector2(0.055 * u, -0.36 * u), Vector2(-0.055 * u, -0.36 * u),
		Vector2(-0.05 * u, -0.30 * u), Vector2(-0.04 * u, -0.22 * u),
	]), medal.darkened(0.06)))
	cup.add_child(_poly_at(_ellipse_poly(0.072 * u, 0.058 * u, 22), Vector2(0, -0.25 * u), medal.lightened(0.08)))
	cup.add_child(_build_bowl(u, medal))
	var sheen := _poly_at(_ellipse_poly(0.05 * u, 0.19 * u, 18), Vector2(-0.135 * u, -0.64 * u), Color(1, 1, 1, 0.18))
	sheen.rotation = -0.2
	cup.add_child(sheen)
	cup.add_child(_poly_at(_ellipse_poly(0.345 * u, 0.06 * u, 32), Vector2(0, -0.93 * u), medal.lightened(0.45)))
	cup.add_child(_poly_at(_ellipse_poly(0.275 * u, 0.042 * u, 32), Vector2(0, -0.923 * u), medal.darkened(0.5)))
	cup.add_child(_score_badge(Vector2(0, -0.62 * u), maxi(16, int(round(0.16 * u))), score, medal))
	var nfs := maxi(15, int(round(0.15 * u)))
	var name_h := float(nfs + 8)
	var name_w := 1.5 * u
	var name_cy := -0.99 * u - 4.0 - name_h * 0.5
	var nglow := Sprite2D.new()
	nglow.texture = _orb_tex
	nglow.modulate = Color(medal.r, medal.g, medal.b, 0.65)
	nglow.scale = Vector2(name_w * 0.62 / 128.0, name_h * 1.7 / 128.0)
	nglow.position = Vector2(0, name_cy)
	var ngm := CanvasItemMaterial.new()
	ngm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	nglow.material = ngm
	cup.add_child(nglow)
	var name_lbl := Label.new()
	name_lbl.text = player_name
	name_lbl.add_theme_font_size_override("font_size", nfs)
	name_lbl.add_theme_color_override("font_color", Color.BLACK)
	name_lbl.add_theme_color_override("font_outline_color", medal)
	name_lbl.add_theme_constant_override("outline_size", maxi(3, int(round(0.028 * u))))
	name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	name_lbl.add_theme_constant_override("shadow_offset_x", 0)
	name_lbl.add_theme_constant_override("shadow_offset_y", 1)
	name_lbl.add_theme_constant_override("shadow_outline_size", 2)
	name_lbl.size = Vector2(name_w, name_h)
	name_lbl.position = Vector2(-name_w * 0.5, name_cy - name_h * 0.5)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cup.add_child(name_lbl)
	return cup

func _build_bowl(u: float, medal: Color) -> Polygon2D:
	var segs := 26
	var y0 := -0.34 * u
	var y1 := -0.93 * u
	var dark := medal.darkened(0.42)
	var lite := medal.lightened(0.42)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in segs + 1:
		var t := float(i) / segs
		var r := u * (0.12 + 0.225 * sin(t * PI * 0.5))
		pts.append(Vector2(r, lerp(y0, y1, t)))
		cols.append(dark.lerp(lite, t))
	for i in range(segs, -1, -1):
		var t := float(i) / segs
		var r := u * (0.12 + 0.225 * sin(t * PI * 0.5))
		pts.append(Vector2(-r, lerp(y0, y1, t)))
		cols.append(dark.lerp(lite, t).lightened(0.10))
	var pg := Polygon2D.new()
	pg.polygon = pts
	pg.color = Color.WHITE
	pg.vertex_colors = cols
	return pg

func _score_badge(center: Vector2, font_size: int, score: int, medal: Color) -> Node2D:
	var n := Node2D.new()
	n.position = center
	var l := Label.new()
	l.text = _fmt(score)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", medal.lightened(0.55))
	l.add_theme_color_override("font_outline_color", medal.darkened(0.62))
	l.add_theme_constant_override("outline_size", maxi(3, int(round(font_size * 0.16))))
	l.add_theme_color_override("font_shadow_color",
		Color(medal.darkened(0.7).r, medal.darkened(0.7).g, medal.darkened(0.7).b, 0.5))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 1)
	var lw := float(font_size) * 7.0
	var lh := float(font_size + 8)
	l.size = Vector2(lw, lh)
	l.position = Vector2(-lw * 0.5, -lh * 0.5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_child(l)
	return n

# ---------------- geometry helpers ----------------

func _poly(pts: PackedVector2Array, col: Color) -> Polygon2D:
	var pg := Polygon2D.new()
	pg.polygon = pts
	pg.color = col
	return pg

func _poly_at(pts: PackedVector2Array, off: Vector2, col: Color) -> Polygon2D:
	var pg := _poly(pts, col)
	pg.position = off
	return pg

func _ellipse_poly(rx: float, ry: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / n
		p.append(Vector2(cos(a) * rx, sin(a) * ry))
	return p

func _catmull_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((p1 * 2.0) + (p2 - p0) * t
		+ (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
		+ (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3)

func _catmull(points: PackedVector2Array, seg: int) -> PackedVector2Array:
	var n := points.size()
	if n < 2:
		return points
	var out := PackedVector2Array()
	for i in n - 1:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, n - 1)]
		for s in seg:
			out.append(_catmull_point(p0, p1, p2, p3, float(s) / seg))
	out.append(points[n - 1])
	return out

func _ribbon(center: PackedVector2Array, hw: float) -> PackedVector2Array:
	var n := center.size()
	if n < 2:
		return PackedVector2Array()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var dir: Vector2
		if i == 0:
			dir = center[1] - center[0]
		elif i == n - 1:
			dir = center[n - 1] - center[n - 2]
		else:
			dir = center[i + 1] - center[i - 1]
		if dir.length() < 0.0001:
			dir = Vector2(1, 0)
		dir = dir.normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var t := float(i) / float(n - 1)
		var w := hw * (0.35 + 0.65 * sin(t * PI))
		right.append(center[i] + nrm * w)
		left.append(center[i] - nrm * w)
	var poly := PackedVector2Array()
	for v in right:
		poly.append(v)
	for i in range(n - 1, -1, -1):
		poly.append(left[i])
	return poly

func _make_radial_texture() -> Texture2D:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.0)))
	return ImageTexture.create_from_image(img)

func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
