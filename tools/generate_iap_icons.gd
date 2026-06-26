@tool
extends EditorScript

# One-shot generator for Play Store IAP product icons (small / medium / large).
# Run: open this script in the editor, then File → Run.
# Outputs three 1024x1024 PNGs to res://store_icons/.
#
# Why pure-CPU pixel rendering (not SubViewport): on the Compatibility (GLES3)
# renderer, SubViewport.get_texture().get_image() comes back black when called
# from an EditorScript — the offscreen readback isn't sync'd with force_draw.
# Drawing into an Image directly is renderer-agnostic and deterministic.
#
# Each coin is rendered as a tilted 3D disc: a back ellipse provides the side
# strip (visible thickness), and a front ellipse provides the top face with
# vertical gradient, inset ring, rim highlight, and specular blob.

const OUT_DIR := "res://store_icons"
const SIZE := 1024  # Play Console spec: 1:1, side between 512 and 1080 px.

# Top face — vertical gradient simulating an overhead key light.
const FACE_TOP    := Color(1.00, 0.93, 0.50)
const FACE_MID    := Color(1.00, 0.78, 0.18)
const FACE_BOTTOM := Color(0.78, 0.50, 0.08)
# Face detail layers.
const FACE_EDGE   := Color(0.52, 0.30, 0.04)  # outer contour darkening
const RIM_LIT     := Color(1.00, 0.95, 0.60)  # rim highlight (catches light)
const INSET_RING  := Color(0.55, 0.32, 0.04)  # subtle darker ring on face
# Side strip — darker overall + cylindrical L/R falloff.
const SIDE_TOP    := Color(0.72, 0.45, 0.08)
const SIDE_BOTTOM := Color(0.32, 0.18, 0.02)
const SIDE_EDGE   := Color(0.18, 0.09, 0.01)
# Specular blob.
const SPEC        := Color(1.00, 1.00, 0.88)

func _run() -> void:
	if not DirAccess.dir_exists_absolute(OUT_DIR):
		DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var t0 := Time.get_ticks_msec()
	print("[IAP icons] coin_small...")
	_generate("coin_small.png",  _coins_single())
	print("[IAP icons] coin_medium...")
	_generate("coin_medium.png", _coins_stack())
	print("[IAP icons] coin_large...")
	_generate("coin_large.png",  _coins_pile())
	print("[IAP icons] Done in %d ms — wrote 3 PNGs to %s" % [
		Time.get_ticks_msec() - t0, ProjectSettings.globalize_path(OUT_DIR)
	])

func _spec(cx: float, cy: float, r: float) -> Dictionary:
	return {"x": cx, "y": cy, "r": r}

# Coins are pre-sorted in paint order by the composition; no global sort.
func _generate(filename: String, coins: Array) -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for c in coins:
		_paint_coin(img, c)
	var err := img.save_png(OUT_DIR.path_join(filename))
	if err != OK:
		push_error("Failed to write %s (err %d)" % [filename, err])

func _paint_coin(img: Image, c: Dictionary) -> void:
	var cx: float = c.x
	var cy: float = c.y
	var r: float = c.r

	var ry := r * 0.42       # ellipse vertical squash (tilt amount)
	var thick := r * 0.22    # visible side strip height

	# Inset-ring band (normalized radius).
	var ring_lo := 0.77
	var ring_hi := 0.83
	var ring_mid := (ring_lo + ring_hi) * 0.5

	# Specular ellipse: soft top-left blob on the face.
	var sp_x := cx - r * 0.22
	var sp_y := cy - ry * 0.45
	var sp_rx := r * 0.45
	var sp_ry := ry * 0.55

	var xmin := maxi(0, int(cx - r) - 2)
	var ymin := maxi(0, int(cy - ry) - 2)
	var xmax := mini(SIZE - 1, int(cx + r) + 2)
	var ymax := mini(SIZE - 1, int(cy + ry + thick) + 2)

	for y in range(ymin, ymax + 1):
		var fy := float(y)
		var dy_f := fy - cy
		var dy_b := fy - cy - thick
		for x in range(xmin, xmax + 1):
			var fx := float(x)
			var dx := fx - cx
			var nx := dx / r
			var nyf := dy_f / ry
			var nyb := dy_b / ry
			var d_front := sqrt(nx * nx + nyf * nyf)
			var d_back := sqrt(nx * nx + nyb * nyb)

			if d_front > 1.0 and d_back > 1.0:
				continue

			var sR := 0.0
			var sG := 0.0
			var sB := 0.0
			var sA := 0.0

			# --- Side strip (back ellipse) drawn first so face can composite over it ---
			if d_back <= 1.0:
				var h_shade := pow(absf(nx), 1.4)  # cylinder darkens toward L/R edges
				var ellipse_h := ry * sqrt(maxf(0.0, 1.0 - nx * nx))
				var strip_t := clampf((fy - cy - ellipse_h) / thick, 0.0, 1.0)
				var top_blend := SIDE_TOP.lerp(SIDE_EDGE, h_shade * 0.85)
				var bot_blend := SIDE_BOTTOM.lerp(SIDE_EDGE, h_shade * 0.9)
				var side_col := top_blend.lerp(bot_blend, strip_t)
				sR = side_col.r
				sG = side_col.g
				sB = side_col.b
				sA = clampf((1.0 - d_back) * r / 2.0, 0.0, 1.0)

			# --- Top face (front ellipse) composited over the side strip ---
			if d_front <= 1.0:
				var v := clampf((dy_f + ry) / (2.0 * ry), 0.0, 1.0)
				var face_col: Color
				if v < 0.5:
					face_col = FACE_TOP.lerp(FACE_MID, v * 2.0)
				else:
					face_col = FACE_MID.lerp(FACE_BOTTOM, (v - 0.5) * 2.0)

				# Inset darker ring — real coins have an inset border around the face.
				var ring_a := smoothstep(ring_lo, ring_mid, d_front) * (1.0 - smoothstep(ring_mid, ring_hi, d_front))
				face_col = face_col.lerp(INSET_RING, ring_a * 0.45)

				# Outer rim highlight (the literal lip of the disc catches light).
				var rim_a := smoothstep(0.90, 0.97, d_front)
				face_col = face_col.lerp(RIM_LIT, rim_a * 0.55)

				# Hard outer contour so the silhouette doesn't bloom into the side.
				var contour_a := smoothstep(0.96, 1.0, d_front)
				face_col = face_col.lerp(FACE_EDGE, contour_a * 0.55)

				# Soft specular blob (top-left).
				var sdx := (fx - sp_x) / sp_rx
				var sdy := (fy - sp_y) / sp_ry
				var sd := sqrt(sdx * sdx + sdy * sdy)
				if sd < 1.0:
					var st := pow(1.0 - sd, 1.4) * 0.55
					face_col = face_col.lerp(SPEC, st)

				# AA at the face's outer edge against side strip / background.
				var face_a := clampf((1.0 - d_front) * r / 1.2, 0.0, 1.0)

				# Composite face over side via Porter-Duff over.
				var na := face_a + sA * (1.0 - face_a)
				if na > 0.0:
					var inv := 1.0 / na
					sR = (face_col.r * face_a + sR * sA * (1.0 - face_a)) * inv
					sG = (face_col.g * face_a + sG * sA * (1.0 - face_a)) * inv
					sB = (face_col.b * face_a + sB * sA * (1.0 - face_a)) * inv
					sA = na

			if sA < 0.001:
				continue

			# Composite source over what's already in the image (lets overlapping
			# coins blend, instead of harsh seams).
			var existing := img.get_pixel(x, y)
			var ea := existing.a
			var na2 := sA + ea * (1.0 - sA)
			if na2 <= 0.0:
				continue
			var inv2 := 1.0 / na2
			img.set_pixel(x, y, Color(
				(sR * sA + existing.r * ea * (1.0 - sA)) * inv2,
				(sG * sA + existing.g * ea * (1.0 - sA)) * inv2,
				(sB * sA + existing.b * ea * (1.0 - sA)) * inv2,
				na2
			))

# ---------- tier compositions ----------
# Differentiate by visible quantity, not numbers: single coin → flush stack →
# small tidy pile. Each composition returns coins in back-to-front paint order.

func _coins_single() -> Array:
	# One large coin, shifted up by half-thickness so it reads as centered
	# (the side strip extends below the geometric center).
	var r := 340.0
	return [_spec(SIZE * 0.5, SIZE * 0.5 - r * 0.11, r)]

func _coins_stack() -> Array:
	# Three coins flush-stacked vertically. The lowest is drawn first; each
	# higher coin's side strip overlaps onto the coin beneath it.
	var cx := SIZE * 0.5
	var r := 220.0
	var ry := r * 0.42
	var thick := r * 0.22
	var step := 2.0 * ry + thick
	# Center the stack on canvas.
	var top_visual_y := -ry  # relative to top coin center
	var bot_visual_y := step * 2.0 + ry + thick  # relative to top coin center
	var stack_center := (top_visual_y + bot_visual_y) * 0.5
	var top_cy := SIZE * 0.5 - stack_center
	return [
		_spec(cx, top_cy + step * 2.0, r),
		_spec(cx, top_cy + step,       r),
		_spec(cx, top_cy,              r),
	]

func _coins_pile() -> Array:
	# Six coins in three rows, painted back-to-front. Bounds chosen so the
	# leftmost/rightmost coin edges sit ~200 px inside the canvas margins.
	var cx := SIZE * 0.5
	var cy := SIZE * 0.5
	var r := 165.0
	return [
		# Back row.
		_spec(cx - 140, cy - 145, r),
		_spec(cx + 140, cy - 145, r),
		# Middle row.
		_spec(cx -  70, cy -  25, r),
		_spec(cx +  70, cy -  25, r),
		# Front row.
		_spec(cx -  55, cy + 110, r),
		_spec(cx +  55, cy + 110, r),
	]
