class_name PackIcons

# Procedural artwork for the coins purchase popup. Each pack gets its own
# bespoke illustration drawn straight onto the card's CanvasItem — no PNG
# assets — so the art stays crisp at any DPI and we never ship per-pack art.
#
# 8 unique icons, one per coin amount, chosen so the eye climbs the grid
# as the price climbs:
#   100   coin stack          1 000  velvet sack
#   300   loose coin pile     5 000  closed treasure chest
#   700   leather pouch       10 000 round bank safe
#                             25 000 open ornate chest with gems
#                             50 000 royal crown atop a coin pile
#
# Style brief mirrors the design lookbook: vibrant golden coins on a
# pink/purple magical glow, warm metallic palette, soft drop shadows, a
# top-edge specular sliver on every coin so the metal feels polished.

# --- palette ---

const GOLD_LIGHT := Color(1.00, 0.94, 0.55)
const GOLD := Color(1.00, 0.78, 0.18)
const GOLD_MID := Color(0.95, 0.62, 0.08)
const GOLD_DARK := Color(0.62, 0.36, 0.02)
const GOLD_RIM := Color(0.42, 0.22, 0.00)

const LEATHER := Color(0.50, 0.27, 0.10)
const LEATHER_MID := Color(0.38, 0.18, 0.06)
const LEATHER_DARK := Color(0.22, 0.10, 0.03)

const SACK_PURPLE := Color(0.52, 0.22, 0.92)
const SACK_PURPLE_MID := Color(0.36, 0.14, 0.72)
const SACK_PURPLE_DARK := Color(0.20, 0.06, 0.40)
const SACK_PURPLE_HL := Color(0.78, 0.50, 1.00)

const CHEST_WOOD := Color(0.34, 0.16, 0.07)
const CHEST_WOOD_LIGHT := Color(0.52, 0.26, 0.12)
const CHEST_DARK := Color(0.12, 0.04, 0.02)

const STEEL := Color(0.55, 0.62, 0.74)
const STEEL_LIGHT := Color(0.82, 0.88, 0.96)
const STEEL_MID := Color(0.40, 0.46, 0.56)
const STEEL_DARK := Color(0.18, 0.22, 0.30)

const GEM_RUBY := Color(1.00, 0.22, 0.34)
const GEM_RUBY_HL := Color(1.00, 0.62, 0.66)
const GEM_EMERALD := Color(0.20, 0.86, 0.46)
const GEM_EMERALD_HL := Color(0.60, 1.00, 0.78)
const GEM_SAPPHIRE := Color(0.30, 0.46, 1.00)
const GEM_SAPPHIRE_HL := Color(0.65, 0.78, 1.00)

const GLOW_BLUE := Color(0.45, 0.62, 1.00, 0.60)
const GLOW_PINK := Color(1.00, 0.34, 0.78, 0.65)
const GLOW_PURPLE := Color(0.70, 0.32, 1.00, 0.65)
const GLOW_GOLD := Color(1.00, 0.74, 0.20, 0.70)
const GLOW_CYAN := Color(0.30, 0.78, 1.00, 0.60)
const GLOW_WHITE := Color(1.00, 0.96, 0.78, 0.65)
const GLOW_RED := Color(1.00, 0.32, 0.32, 0.58)

# --- public dispatcher ---

# Picks the icon by exact coin amount. Falls back to the closest tier so
# new SKUs don't render blank if added to PACKS without updating here.
static func draw_pack_art(c: CanvasItem, size: Vector2, coins: int) -> void:
	var cx := size.x * 0.5
	var cy := size.y * 0.5
	var s := _fit_scale(size)
	match coins:
		100:   _draw_coin_stack(c, cx, cy, s)
		300:   _draw_loose_pile(c, cx, cy, s)
		700:   _draw_leather_pouch(c, cx, cy, s)
		1000:  _draw_velvet_sack(c, cx, cy, s)
		5000:  _draw_closed_chest(c, cx, cy, s)
		10000: _draw_safe(c, cx, cy, s)
		25000: _draw_open_chest(c, cx, cy, s)
		50000: _draw_crown(c, cx, cy, s)
		_:
			# Fallback by magnitude for any future pack value.
			if coins < 500:        _draw_coin_stack(c, cx, cy, s)
			elif coins < 1000:     _draw_leather_pouch(c, cx, cy, s)
			elif coins < 5000:     _draw_velvet_sack(c, cx, cy, s)
			elif coins < 15000:    _draw_closed_chest(c, cx, cy, s)
			else:                  _draw_open_chest(c, cx, cy, s)

static func draw_no_ads(c: CanvasItem, size: Vector2) -> void:
	var cx := size.x * 0.5
	var cy := size.y * 0.5
	var s := minf(size.x, size.y) / 80.0
	_draw_no_ads_shield(c, cx, cy, s)

# ====================================================================
# Pack icons — each one is a self-contained scene the popup composites
# onto its card. Drawing order is back-to-front (glow → silhouette →
# detail → coins → highlights).
# ====================================================================

# 1 — Starter (100 coins): a clean stack of three coins, the top one
# slightly turned so the player can read the face motif.
static func _draw_coin_stack(c: CanvasItem, cx: float, cy: float, s: float) -> void:
	_draw_glow(c, cx, cy + 14.0 * s, 50.0 * s, GLOW_BLUE)
	var r := 22.0 * s
	var ry := r * 0.34
	# Bottom coin (deepest)
	_draw_disc_with_edge(c, cx, cy + 18.0 * s, r, ry, 5.0 * s)
	# Middle coin (slightly offset for a hand-stacked feel)
	_draw_disc_with_edge(c, cx - 1.5 * s, cy + 4.0 * s, r * 1.02, ry, 5.0 * s)
	# Top coin — show the face, with full star motif
	_draw_disc_with_edge(c, cx + 1.0 * s, cy - 10.0 * s, r, ry, 5.0 * s, true)

# 2 — Handful (300 coins): a loose scatter of overlapping coins, with a
# hero coin tossed on top.
static func _draw_loose_pile(c: CanvasItem, cx: float, cy: float, s: float) -> void:
	_draw_glow(c, cx, cy + 8.0 * s, 58.0 * s, GLOW_BLUE)
	var r := 13.0 * s
	# Back row: 3 coins tilted away
	_draw_coin(c, cx - r * 1.85, cy - r * 0.30, r * 0.92)
	_draw_coin(c, cx - r * 0.10, cy - r * 0.55, r * 0.95)
	_draw_coin(c, cx + r * 1.85, cy - r * 0.30, r * 0.92)
	# Middle row: anchor coin slightly bigger
	_draw_coin(c, cx - r * 2.20, cy + r * 0.70, r * 0.95)
	_draw_coin(c, cx - r * 0.50, cy + r * 0.85, r * 1.10)
	_draw_coin(c, cx + r * 1.15, cy + r * 0.65, r * 1.00)
	_draw_coin(c, cx + r * 2.50, cy + r * 0.75, r * 0.92)
	# Hero coin tossed on top, mid-flip
	_draw_tilted_coin(c, cx + r * 0.4, cy - r * 1.50, r * 1.10)

# 3 — Pouch (700 coins): a small leather pouch with a corded drawstring,
# coins peeking out of the cinched mouth.
static func _draw_leather_pouch(c: CanvasItem, cx: float, cy: float, s: float) -> void:
	_draw_glow(c, cx, cy + 14.0 * s, 50.0 * s, GLOW_GOLD)
	# Tall-rather-than-wide silhouette so it reads as a pouch, not a ball.
	# body_cy is the *body's* vertical centre, not the visual centre of art.
	var body_cy := cy + 8.0 * s
	var total_h := 56.0 * s
	var half_w := 22.0 * s
	_draw_pouch_body(c, cx, body_cy, half_w, total_h, s,
		LEATHER, LEATHER_MID, LEATHER_DARK, Color(1.0, 0.78, 0.42, 0.30))
	# Mouth opening sits at body_cy - 0.40*total_h (see _draw_pouch_body).
	var mouth_y := body_cy - total_h * 0.40 - 4.0 * s
	# Three coins peeking out of the cinched mouth.
	var r := 7.5 * s
	_draw_coin(c, cx - r * 1.20, mouth_y + r * 0.20, r)
	_draw_coin(c, cx + r * 0.10, mouth_y - r * 0.55, r * 1.10)
	_draw_coin(c, cx + r * 1.30, mouth_y + r * 0.20, r)
	# One coin resting against the base on the right.
	_draw_coin(c, cx + half_w * 1.25, body_cy + total_h * 0.40 - 2.0 * s, r * 0.85)

# 4 — Sack (1000 coins): a proper velvet sack — body, cinched neck,
# drawstring band, knot, fabric folds, mouth darkened, lots of overflow.
# The teardrop silhouette is deliberately taller than wide so it reads
# as cloth, not a ball.
static func _draw_velvet_sack(c: CanvasItem, cx: float, cy: float, s: float) -> void:
	_draw_glow(c, cx, cy + 14.0 * s, 66.0 * s, GLOW_PINK)
	var body_cy := cy + 10.0 * s
	var total_h := 68.0 * s
	var half_w := 28.0 * s
	_draw_pouch_body(c, cx, body_cy, half_w, total_h, s,
		SACK_PURPLE_MID, SACK_PURPLE, SACK_PURPLE_DARK, Color(1.0, 0.86, 1.0, 0.22))
	var mouth_y := body_cy - total_h * 0.40 - 4.0 * s
	# Five coins overflowing the mouth, two stacked higher.
	var r := 9.0 * s
	_draw_coin(c, cx - r * 1.45, mouth_y + r * 0.10, r)
	_draw_coin(c, cx + r * 0.05, mouth_y - r * 0.65, r * 1.15)
	_draw_coin(c, cx + r * 1.55, mouth_y + r * 0.10, r)
	_draw_coin(c, cx - r * 0.40, mouth_y - r * 1.55, r * 0.90)
	_draw_coin(c, cx + r * 0.85, mouth_y - r * 1.30, r * 0.80)
	# A couple of loose coins around the sack's base.
	_draw_coin(c, cx - half_w * 1.45, body_cy + total_h * 0.35, r * 0.85)
	_draw_tilted_coin(c, cx + half_w * 1.30, body_cy + total_h * 0.40, r * 0.90)

# 5 — Chest (5000 coins): a closed wooden treasure chest with gold trim,
# a padlock on the front, and a coin or two leaning against the corners.
static func _draw_closed_chest(c: CanvasItem, cx: float, cy: float, s: float) -> void:
	_draw_glow(c, cx, cy + 8.0 * s, 58.0 * s, GLOW_GOLD)
	var w := 64.0 * s
	var box_h := 26.0 * s
	var lid_h := 16.0 * s
	var box_x := cx - w * 0.5
	var box_y := cy - 2.0 * s
	var lid_y := box_y - lid_h
	# Ground shadow puddle
	c.draw_colored_polygon(_ellipse_polygon(Vector2(cx, box_y + box_h + 6.0 * s),
		w * 0.55, 6.0 * s, 24), Color(0, 0, 0, 0.45))
	# Box body
	c.draw_rect(Rect2(box_x, box_y, w, box_h), CHEST_WOOD, true)
	# Box vertical highlight strip on the left
	c.draw_rect(Rect2(box_x + 3.0 * s, box_y + 3.0 * s, 4.0 * s, box_h - 6.0 * s),
		CHEST_WOOD_LIGHT, true)
	# Wood plank seam (vertical) for texture
	c.draw_rect(Rect2(cx - 0.5 * s, box_y + 3.0 * s, 1.0 * s, box_h - 6.0 * s),
		CHEST_DARK, true)
	# Lid (closed, rounded top via a trapezoid + chamfered ellipse)
	var lid := PackedVector2Array()
	lid.append(Vector2(box_x, lid_y + lid_h))
	lid.append(Vector2(box_x + w, lid_y + lid_h))
	lid.append(Vector2(box_x + w - 2.0 * s, lid_y + 4.0 * s))
	lid.append(Vector2(box_x + 2.0 * s, lid_y + 4.0 * s))
	c.draw_colored_polygon(lid, CHEST_WOOD_LIGHT)
	c.draw_colored_polygon(_ellipse_polygon(Vector2(cx, lid_y + 4.0 * s),
		w * 0.49, 5.0 * s, 28), CHEST_WOOD_LIGHT)
	# Gold trim — top, bottom, lid-front
	var trim := 3.0 * s
	c.draw_rect(Rect2(box_x, box_y, w, trim), GOLD_DARK, true)
	c.draw_rect(Rect2(box_x, box_y + box_h - trim, w, trim), GOLD_DARK, true)
	c.draw_rect(Rect2(box_x, lid_y + lid_h - 1.5 * s, w, 2.5 * s), GOLD_DARK, true)
	# Vertical gold straps
	c.draw_rect(Rect2(box_x + w * 0.18, box_y, trim * 0.7, box_h), GOLD_DARK, true)
	c.draw_rect(Rect2(box_x + w * 0.82 - trim * 0.7, box_y, trim * 0.7, box_h), GOLD_DARK, true)
	# Padlock — keyhole on the lid/body join
	var lock_w := 12.0 * s
	var lock_h := 14.0 * s
	var lock_x := cx - lock_w * 0.5
	var lock_y := lid_y + lid_h - 3.0 * s
	# Lock shackle (above the body of the lock)
	c.draw_arc(Vector2(cx, lock_y - 1.0 * s), lock_w * 0.42, PI, TAU, 16,
		STEEL_LIGHT, 2.0 * s, true)
	# Lock body (golden)
	c.draw_rect(Rect2(lock_x, lock_y, lock_w, lock_h), GOLD_MID, true)
	c.draw_rect(Rect2(lock_x + 1.0 * s, lock_y + 1.0 * s, lock_w - 2.0 * s, 2.0 * s),
		GOLD_LIGHT, true)
	# Keyhole on the lock face
	c.draw_circle(Vector2(cx, lock_y + lock_h * 0.55), 1.6 * s, CHEST_DARK)
	c.draw_rect(Rect2(cx - 0.6 * s, lock_y + lock_h * 0.55, 1.2 * s, 4.0 * s), CHEST_DARK, true)
	# Coin leaning against the bottom-right corner
	_draw_tilted_coin(c, cx + w * 0.55, box_y + box_h, 10.0 * s)
	_draw_coin(c, cx - w * 0.55, box_y + box_h - 2.0 * s, 9.0 * s)

# 6 — Vault (10000 coins): a round bank safe door with a spoked handle
# and combo dial, a couple of coin stacks beside it.
static func _draw_safe(c: CanvasItem, cx: float, cy: float, s: float) -> void:
	_draw_glow(c, cx, cy, 60.0 * s, GLOW_CYAN)
	var rr := 32.0 * s
	# Drop shadow
	c.draw_colored_polygon(_ellipse_polygon(Vector2(cx + 2.0 * s, cy + 4.0 * s),
		rr * 1.05, rr * 1.05, 36), Color(0, 0, 0, 0.40))
	# Outer rim (thick steel ring)
	c.draw_circle(Vector2(cx, cy), rr, STEEL_DARK)
	c.draw_circle(Vector2(cx, cy), rr - 1.5 * s, STEEL)
	# Bolt heads around the rim
	var bolts := 8
	for i in bolts:
		var a: float = TAU * float(i) / float(bolts) + PI * 0.0625
		var bx := cx + cos(a) * (rr - 4.5 * s)
		var by := cy + sin(a) * (rr - 4.5 * s)
		c.draw_circle(Vector2(bx, by), 1.6 * s, STEEL_DARK)
		c.draw_circle(Vector2(bx, by), 1.0 * s, STEEL_LIGHT)
	# Inner door panel
	c.draw_circle(Vector2(cx, cy), rr - 8.0 * s, STEEL_MID)
	c.draw_circle(Vector2(cx, cy), rr - 9.5 * s, STEEL)
	# Catchlight on the door (top-left highlight)
	c.draw_arc(Vector2(cx, cy), rr - 11.0 * s, PI + 0.4, TAU - 0.4, 24,
		STEEL_LIGHT, 1.5 * s, true)
	# Spoked handle (5 arms radiating from a center hub)
	var spokes := 5
	var handle_r := rr - 12.0 * s
	for i in spokes:
		var a: float = TAU * float(i) / float(spokes) - PI * 0.5
		var ex := cx + cos(a) * handle_r
		var ey := cy + sin(a) * handle_r
		c.draw_line(Vector2(cx, cy), Vector2(ex, ey), STEEL_DARK, 4.0 * s, true)
		c.draw_circle(Vector2(ex, ey), 2.6 * s, STEEL_LIGHT)
		c.draw_circle(Vector2(ex, ey), 1.4 * s, STEEL_DARK)
	# Center hub
	c.draw_circle(Vector2(cx, cy), 5.0 * s, STEEL_LIGHT)
	c.draw_circle(Vector2(cx, cy), 3.0 * s, STEEL_DARK)
	c.draw_circle(Vector2(cx, cy), 1.4 * s, GOLD)
	# Coin stacks flanking the safe
	_draw_short_stack(c, cx - rr - 14.0 * s, cy + rr - 4.0 * s, 8.0 * s, 3)
	_draw_short_stack(c, cx + rr + 14.0 * s, cy + rr - 2.0 * s, 8.0 * s, 4)

# 7 — Treasury (25000 coins): open ornate chest with gems mixed into
# the spilling coins. Bigger, more lavish than the 5k closed chest.
static func _draw_open_chest(c: CanvasItem, cx: float, cy: float, s: float) -> void:
	_draw_glow(c, cx, cy + 6.0 * s, 74.0 * s, GLOW_GOLD)
	var w := 68.0 * s
	var h := 32.0 * s
	var box_x := cx - w * 0.5
	var box_y := cy + 8.0 * s
	# Shadow under the chest
	c.draw_colored_polygon(_ellipse_polygon(Vector2(cx, box_y + h + 4.0 * s),
		w * 0.55, 6.0 * s, 24), Color(0, 0, 0, 0.45))
	# Box body
	c.draw_rect(Rect2(box_x, box_y, w, h), CHEST_WOOD, true)
	c.draw_rect(Rect2(box_x + 3.0 * s, box_y + 3.0 * s, 4.5 * s, h - 6.0 * s),
		CHEST_WOOD_LIGHT, true)
	# Gold trim
	var trim := 3.5 * s
	c.draw_rect(Rect2(box_x, box_y, w, trim), GOLD_DARK, true)
	c.draw_rect(Rect2(box_x, box_y + h - trim, w, trim), GOLD_DARK, true)
	c.draw_rect(Rect2(box_x, box_y + (h - trim) * 0.5, w, trim * 0.6), GOLD_DARK, true)
	# Vertical straps + corner studs
	for vx in [box_x + 5.0 * s, box_x + w - 5.0 * s - trim * 0.7]:
		c.draw_rect(Rect2(vx, box_y, trim * 0.7, h), GOLD_DARK, true)
	for stud_x in [box_x + 6.0 * s, box_x + w - 7.0 * s]:
		for stud_y in [box_y + 2.0 * s, box_y + h - 4.0 * s]:
			c.draw_circle(Vector2(stud_x + trim * 0.35, stud_y + 1.0 * s), 1.6 * s, GOLD_LIGHT)
	# Lid (tilted back, open)
	var lid_h := 16.0 * s
	var lid_back_y := box_y - lid_h - 16.0 * s
	var lid_front_y := box_y - 2.0 * s
	var lid := PackedVector2Array()
	lid.append(Vector2(box_x, lid_front_y))
	lid.append(Vector2(box_x + w, lid_front_y))
	lid.append(Vector2(box_x + w - 5.0 * s, lid_back_y))
	lid.append(Vector2(box_x + 5.0 * s, lid_back_y))
	c.draw_colored_polygon(lid, CHEST_WOOD)
	# Lid underside (darker — in shadow)
	var lid_inside := PackedVector2Array()
	lid_inside.append(Vector2(box_x + 3.0 * s, lid_front_y - 1.0 * s))
	lid_inside.append(Vector2(box_x + w - 3.0 * s, lid_front_y - 1.0 * s))
	lid_inside.append(Vector2(box_x + w - 8.0 * s, lid_back_y + 4.0 * s))
	lid_inside.append(Vector2(box_x + 8.0 * s, lid_back_y + 4.0 * s))
	c.draw_colored_polygon(lid_inside, CHEST_DARK)
	# Lid gold trim
	var lid_trim := PackedVector2Array()
	lid_trim.append(Vector2(box_x, lid_front_y))
	lid_trim.append(Vector2(box_x + w, lid_front_y))
	lid_trim.append(Vector2(box_x + w - 1.0 * s, lid_front_y + trim))
	lid_trim.append(Vector2(box_x + 1.0 * s, lid_front_y + trim))
	c.draw_colored_polygon(lid_trim, GOLD_DARK)
	# Magical glow spilling from inside the chest
	_draw_glow(c, cx, box_y - 4.0 * s, 28.0 * s, Color(1.0, 0.86, 0.40, 0.85))
	# Gems hidden among the gold
	_draw_gem(c, cx - 18.0 * s, box_y - 4.0 * s, 4.5 * s, GEM_RUBY, GEM_RUBY_HL)
	_draw_gem(c, cx + 20.0 * s, box_y - 2.0 * s, 4.0 * s, GEM_EMERALD, GEM_EMERALD_HL)
	_draw_gem(c, cx + 4.0 * s, box_y - 12.0 * s, 4.0 * s, GEM_SAPPHIRE, GEM_SAPPHIRE_HL)
	# Coins spilling from the mouth and tumbling out the front
	var r := 10.0 * s
	_draw_coin(c, cx - r * 2.40, box_y + 1.0 * s, r * 0.95)
	_draw_coin(c, cx - r * 0.85, box_y - r * 0.30, r * 1.05)
	_draw_coin(c, cx + r * 1.10, box_y - r * 0.10, r * 1.00)
	_draw_coin(c, cx + r * 2.50, box_y + 4.0 * s, r * 0.95)
	_draw_coin(c, cx + r * 0.10, box_y - r * 1.40, r * 0.85)
	_draw_tilted_coin(c, cx - r * 2.60, box_y + h - r * 0.10, r * 0.95)
	_draw_tilted_coin(c, cx + r * 2.40, box_y + h + r * 0.10, r * 0.95)
	# Center lock plate — a gold diamond on the front centre band
	var plate_r := 4.5 * s
	var diamond := PackedVector2Array()
	diamond.append(Vector2(cx, box_y + h * 0.5 - plate_r))
	diamond.append(Vector2(cx + plate_r, box_y + h * 0.5))
	diamond.append(Vector2(cx, box_y + h * 0.5 + plate_r))
	diamond.append(Vector2(cx - plate_r, box_y + h * 0.5))
	c.draw_colored_polygon(diamond, GOLD_LIGHT)

# 8 — Jackpot (50000 coins): a royal crown with gems sitting atop a
# generous coin pile. The headline visual of the popup.
static func _draw_crown(c: CanvasItem, cx: float, cy: float, s: float) -> void:
	_draw_glow(c, cx, cy + 6.0 * s, 76.0 * s, GLOW_WHITE)
	# Coin pile beneath the crown (so the crown reads as resting on it)
	var pr := 9.0 * s
	_draw_coin(c, cx - 26.0 * s, cy + 28.0 * s, pr)
	_draw_coin(c, cx - 10.0 * s, cy + 32.0 * s, pr * 1.05)
	_draw_coin(c, cx + 8.0 * s,  cy + 32.0 * s, pr * 1.05)
	_draw_coin(c, cx + 26.0 * s, cy + 28.0 * s, pr)
	_draw_coin(c, cx - 18.0 * s, cy + 18.0 * s, pr * 0.95)
	_draw_coin(c, cx + 18.0 * s, cy + 18.0 * s, pr * 0.95)
	_draw_coin(c, cx, cy + 20.0 * s, pr * 1.10)
	# Crown — a base band with 5 spires and a gem on each spire tip.
	var w := 56.0 * s
	var bh := 10.0 * s
	var band_x := cx - w * 0.5
	var band_y := cy - 6.0 * s
	# Spires (5 points, middle one tallest).
	var spire_heights: Array[float] = [18.0, 24.0, 30.0, 24.0, 18.0]
	var spire_xs: Array[float] = []
	var crown_poly := PackedVector2Array()
	crown_poly.append(Vector2(band_x, band_y + bh))           # bottom-left
	# Walk the top of the crown spire-by-spire (V shape between spires).
	for i in 5:
		var sx: float = band_x + (float(i) + 0.5) * (w / 5.0)
		var top_y: float = band_y - spire_heights[i] * s
		spire_xs.append(sx)
		if i == 0:
			crown_poly.append(Vector2(band_x, band_y))
		crown_poly.append(Vector2(sx - 6.0 * s, band_y))
		crown_poly.append(Vector2(sx, top_y))
		crown_poly.append(Vector2(sx + 6.0 * s, band_y))
	crown_poly.append(Vector2(band_x + w, band_y))            # right side of band
	crown_poly.append(Vector2(band_x + w, band_y + bh))       # bottom-right
	c.draw_colored_polygon(crown_poly, GOLD)
	# Darker shading along the bottom of the band.
	c.draw_rect(Rect2(band_x, band_y + bh * 0.55, w, bh * 0.45), GOLD_MID, true)
	# Top-edge highlight along the band.
	c.draw_line(Vector2(band_x + 1.0 * s, band_y + 1.0 * s),
		Vector2(band_x + w - 1.0 * s, band_y + 1.0 * s), GOLD_LIGHT, 1.2 * s, true)
	# Big centre gem on the band.
	_draw_gem(c, cx, band_y + bh * 0.5, 4.0 * s, GEM_RUBY, GEM_RUBY_HL)
	# Smaller gem on each spire tip — alternating colours.
	var spire_gems: Array[Color] = [GEM_EMERALD, GEM_SAPPHIRE, GEM_RUBY, GEM_SAPPHIRE, GEM_EMERALD]
	var spire_gem_hls: Array[Color] = [GEM_EMERALD_HL, GEM_SAPPHIRE_HL, GEM_RUBY_HL, GEM_SAPPHIRE_HL, GEM_EMERALD_HL]
	for i in 5:
		var sx: float = spire_xs[i]
		var top_y: float = band_y - spire_heights[i] * s + 1.5 * s
		c.draw_circle(Vector2(sx, top_y), 2.6 * s, spire_gems[i])
		c.draw_circle(Vector2(sx - 0.6 * s, top_y - 0.6 * s), 1.0 * s, spire_gem_hls[i])
	# Sparkle bursts above the crown
	_draw_sparkle(c, cx - 24.0 * s, band_y - 28.0 * s, 3.5 * s)
	_draw_sparkle(c, cx + 26.0 * s, band_y - 24.0 * s, 3.0 * s)
	_draw_sparkle(c, cx + 4.0 * s, band_y - 36.0 * s, 4.0 * s)

# ====================================================================
# no_ads emblem — a glowing golden shield with a banner-ad icon being
# crossed out, kept legible at thumbnail size.
# ====================================================================

static func _draw_no_ads_shield(c: CanvasItem, cx: float, cy: float, s: float) -> void:
	_draw_glow(c, cx, cy, 50.0 * s, GLOW_RED)
	# Shield silhouette — a classic heater shield, drop-shadowed.
	var w := 50.0 * s
	var h := 60.0 * s
	var shield_pts := _shield_polygon(cx, cy + 1.0 * s, w * 1.05, h * 1.05)
	c.draw_colored_polygon(shield_pts, Color(0, 0, 0, 0.40))
	shield_pts = _shield_polygon(cx, cy, w, h)
	c.draw_colored_polygon(shield_pts, GOLD_DARK)
	# Inner shield face (slightly inset, dark plum so the gold reads as a rim)
	var inner := _shield_polygon(cx, cy - 1.0 * s, w * 0.84, h * 0.84)
	c.draw_colored_polygon(inner, Color(0.18, 0.06, 0.16))
	# Tiny ad-banner glyph inside the shield (greyed out)
	var bw := w * 0.50
	var bh := h * 0.22
	var banner := Rect2(cx - bw * 0.5, cy - bh * 0.5, bw, bh)
	c.draw_rect(banner, Color(0.92, 0.86, 0.62), true)
	# Suggestion of banner text — two darker bars
	c.draw_rect(Rect2(banner.position.x + 3.0 * s, banner.position.y + 3.0 * s,
		banner.size.x * 0.6, 2.0 * s), Color(0.30, 0.20, 0.08), true)
	c.draw_rect(Rect2(banner.position.x + 3.0 * s, banner.position.y + 7.0 * s,
		banner.size.x * 0.4, 2.0 * s), Color(0.30, 0.20, 0.08), true)
	# Prohibition ring + diagonal slash overlay — the clear "no ads" signal.
	var r := w * 0.42
	c.draw_arc(Vector2(cx, cy), r, 0.0, TAU, 48, Color(1.0, 0.30, 0.26, 0.98),
		4.5 * s, true)
	var sa := -PI * 0.25
	var d := Vector2(cos(sa), sin(sa)) * r
	c.draw_line(Vector2(cx, cy) - d, Vector2(cx, cy) + d,
		Color(1.0, 0.30, 0.26, 0.98), 4.5 * s, true)
	# Inner ring highlight (soft white sliver on the top-left quarter)
	c.draw_arc(Vector2(cx, cy), r - 2.5 * s, PI + 0.4, TAU - 0.4, 24,
		Color(1, 1, 1, 0.45), 1.2, true)
	# Sparkle accents
	_draw_sparkle(c, cx + w * 0.5, cy - h * 0.4, 2.5 * s)
	_draw_sparkle(c, cx - w * 0.55, cy + h * 0.1, 2.0 * s)

# ====================================================================
# Reusable container body — a teardrop / gourd silhouette used by both
# the pouch and the velvet sack. Tightly cinched neck reads as fabric.
# ====================================================================

static func _draw_pouch_body(c: CanvasItem, cx: float, body_cy: float,
		half_w: float, total_h: float, s: float,
		body: Color, hl: Color, dark: Color, sheen: Color) -> void:
	# Drop shadow — flat oval beneath the sack.
	c.draw_colored_polygon(_ellipse_polygon(
		Vector2(cx, body_cy + total_h * 0.40),
		half_w * 1.05, 5.0 * s, 24), Color(0, 0, 0, 0.40))
	# Body silhouette — sampled along a teardrop profile, then mirrored.
	var pts := _teardrop_outline(cx, body_cy, half_w, total_h, 14)
	c.draw_colored_polygon(pts, dark)
	# Highlight side — inset offset oval suggesting the lit face of the cloth.
	var hl_pts := _teardrop_outline(cx - half_w * 0.10, body_cy - 2.0 * s,
		half_w * 0.80, total_h * 0.82, 14)
	c.draw_colored_polygon(hl_pts, body)
	# Soft top-left sheen (catchlight on velvet).
	c.draw_colored_polygon(_ellipse_polygon(
		Vector2(cx - half_w * 0.30, body_cy - total_h * 0.18),
		half_w * 0.32, total_h * 0.16, 20), sheen)
	# Vertical fabric folds — three faint dark lines down the body.
	for i in 3:
		var fx: float = cx + (float(i) - 1.0) * half_w * 0.32
		var top_y: float = body_cy - total_h * 0.08
		var bot_y: float = body_cy + total_h * 0.30
		c.draw_line(Vector2(fx, top_y), Vector2(fx, bot_y), dark, 1.0, true)
	# Drawstring band — sits at the cinched neck (top of the body).
	var band_y := body_cy - total_h * 0.40
	var band_w := half_w * 1.05
	var band_h := 4.5 * s
	c.draw_rect(Rect2(cx - band_w * 0.5, band_y, band_w, band_h), GOLD_DARK, true)
	c.draw_rect(Rect2(cx - band_w * 0.5, band_y, band_w, 1.3 * s), GOLD_MID, true)
	# Dark mouth opening above the band — a sliver of shadow inside the sack.
	c.draw_colored_polygon(_ellipse_polygon(
		Vector2(cx, band_y - 1.0 * s),
		band_w * 0.40, 3.5 * s, 20), CHEST_DARK)
	# Two drawstring cords poking up from the band, ending in a knot.
	var knot_y := band_y - 7.0 * s
	c.draw_line(Vector2(cx - 4.0 * s, band_y), Vector2(cx - 2.0 * s, knot_y),
		GOLD_DARK, 1.4 * s, true)
	c.draw_line(Vector2(cx + 4.0 * s, band_y), Vector2(cx + 2.0 * s, knot_y),
		GOLD_DARK, 1.4 * s, true)
	c.draw_circle(Vector2(cx, knot_y), 2.0 * s, GOLD)
	c.draw_circle(Vector2(cx - 0.5 * s, knot_y - 0.5 * s), 0.9 * s, GOLD_LIGHT)

# ====================================================================
# Primitive drawers
# ====================================================================

# A single round coin, viewed face-on, with rim, face, and a soft highlight.
static func _draw_coin(c: CanvasItem, cx: float, cy: float, r: float) -> void:
	# Drop shadow — small downward offset, very soft.
	c.draw_circle(Vector2(cx + r * 0.10, cy + r * 0.20), r * 1.02, Color(0, 0, 0, 0.40))
	# Outer rim (dark gold) → mid band → face. Three concentric circles fake
	# a gradient cheaply and read as a coin even at thumbnail size.
	c.draw_circle(Vector2(cx, cy), r, GOLD_RIM)
	c.draw_circle(Vector2(cx, cy), r * 0.92, GOLD_DARK)
	c.draw_circle(Vector2(cx, cy), r * 0.82, GOLD_MID)
	c.draw_circle(Vector2(cx, cy), r * 0.72, GOLD)
	# Off-centre face highlight ("catchlight") to suggest a polished surface.
	c.draw_circle(Vector2(cx - r * 0.20, cy - r * 0.22), r * 0.40, GOLD_LIGHT)
	# Inset star motif (darker, on the face) so the coin reads as "valuable".
	var pts := _star_polygon(Vector2(cx, cy), r * 0.36, r * 0.16, 5, -PI * 0.5)
	c.draw_colored_polygon(pts, GOLD_DARK)
	# Top-edge specular arc — thin white sliver, gives the coin its sheen.
	c.draw_arc(Vector2(cx, cy), r * 0.92, PI + 0.55, TAU - 0.55, 24,
		Color(1, 1, 1, 0.55), 1.5, true)

# A richly shaded, genuinely 3D-looking gold coin disc — no glyph, so callers
# overlay their own "$"/mark on top. Light source sits at the top-left: the
# face carries a directional gradient from a bright catchlight down to a dark
# lower rim, and a visible edge/thickness peeking out below the face gives the
# disc real depth (vs. the old flat single-colour circle). Used by the HUD
# coin pills so the currency reads as a solid minted coin at any size.
static func draw_coin_3d(c: CanvasItem, ctr: Vector2, r: float) -> void:
	var cx := ctr.x
	var cy := ctr.y
	# Soft contact shadow on the ground, offset down-right.
	c.draw_circle(Vector2(cx + r * 0.12, cy + r * 0.24), r * 1.05, Color(0, 0, 0, 0.30))
	# Coin thickness: two rim discs peeking out below the face sell the depth.
	c.draw_circle(Vector2(cx, cy + r * 0.14), r, GOLD_RIM)
	c.draw_circle(Vector2(cx, cy + r * 0.07), r, GOLD_DARK)
	# Face gradient — concentric discs whose centre drifts toward the top-left
	# light, fading dark rim → mid → gold → pale catchlight.
	var steps := 12
	for i in steps:
		var t := float(i) / float(steps - 1)      # 0 = rim, 1 = centre
		var rr := r * (1.0 - 0.86 * t)
		var off := Vector2(-r * 0.16, -r * 0.20) * t
		c.draw_circle(Vector2(cx, cy) + off, rr, _sample_gold(t))
	# Raised rim ridge: a bright ring just inside the edge where the light
	# catches it (top-left), turning to a soft dark ring on the shadowed
	# lower-right so the edge reads as rounded rather than a flat outline.
	var ridge_w := maxf(1.0, r * 0.06)
	c.draw_arc(Vector2(cx, cy), r * 0.86, PI * 0.72, PI * 1.9, 28,
		Color(1, 1, 1, 0.45), ridge_w, true)
	c.draw_arc(Vector2(cx, cy), r * 0.86, PI * 1.9, TAU + PI * 0.72, 28,
		Color(0, 0, 0, 0.22), ridge_w, true)
	# Tight specular catchlight on the upper-left face.
	c.draw_circle(Vector2(cx - r * 0.30, cy - r * 0.32), r * 0.15,
		Color(1, 1, 1, 0.55))

# Samples the gold palette as a rim→catchlight ramp for draw_coin_3d.
static func _sample_gold(t: float) -> Color:
	var stops: Array[Color] = [GOLD_DARK, GOLD_MID, GOLD, GOLD_LIGHT, Color(1, 1, 0.86)]
	var seg := clampf(t, 0.0, 1.0) * float(stops.size() - 1)
	var i := int(seg)
	if i >= stops.size() - 1:
		return stops[stops.size() - 1]
	return stops[i].lerp(stops[i + 1], seg - float(i))

# Coin in an ellipse silhouette (side / mid-flip view).
static func _draw_tilted_coin(c: CanvasItem, cx: float, cy: float, r: float) -> void:
	var ry := r * 0.42
	c.draw_colored_polygon(_ellipse_polygon(
		Vector2(cx + 1.5, cy + 3.0), r * 1.02, ry * 1.05, 28), Color(0, 0, 0, 0.35))
	c.draw_colored_polygon(_ellipse_polygon(Vector2(cx, cy), r, ry, 28), GOLD_RIM)
	c.draw_colored_polygon(_ellipse_polygon(Vector2(cx, cy), r * 0.84, ry * 0.78, 28), GOLD)
	c.draw_colored_polygon(_ellipse_polygon(
		Vector2(cx - r * 0.25, cy - ry * 0.25), r * 0.40, ry * 0.45, 20), GOLD_LIGHT)
	c.draw_arc(Vector2(cx, cy), r * 0.95, PI + 0.6, TAU - 0.6, 16,
		Color(1, 1, 1, 0.55), 1.2, true)

# A small face-on coin disc viewed in mild oblique — top ellipse + side
# rectangle joining it to the bottom edge. Used inside the coin stack.
# When `show_face` is true the top disc gets the full coin treatment
# (highlight, star). When false it just shows the rim from above.
static func _draw_disc_with_edge(c: CanvasItem, cx: float, cy: float,
		r: float, ry: float, edge_h: float, show_face: bool = false) -> void:
	# Drop shadow
	c.draw_colored_polygon(_ellipse_polygon(
		Vector2(cx + 1.0, cy + edge_h + 4.0), r * 1.02, ry * 1.05, 28),
		Color(0, 0, 0, 0.35))
	# Side wall — rectangle between the two ellipses, dark gold.
	var side := PackedVector2Array()
	side.append(Vector2(cx - r, cy))
	side.append(Vector2(cx + r, cy))
	side.append(Vector2(cx + r, cy + edge_h))
	side.append(Vector2(cx - r, cy + edge_h))
	c.draw_colored_polygon(side, GOLD_MID)
	# Highlight strip across the side
	var hl := PackedVector2Array()
	hl.append(Vector2(cx - r, cy + edge_h * 0.20))
	hl.append(Vector2(cx + r, cy + edge_h * 0.20))
	hl.append(Vector2(cx + r, cy + edge_h * 0.45))
	hl.append(Vector2(cx - r, cy + edge_h * 0.45))
	c.draw_colored_polygon(hl, GOLD_LIGHT)
	# Bottom rim ellipse (darker — shadowed underside)
	c.draw_colored_polygon(_ellipse_polygon(
		Vector2(cx, cy + edge_h), r, ry, 28), GOLD_RIM)
	# Top face
	c.draw_colored_polygon(_ellipse_polygon(Vector2(cx, cy), r, ry, 28), GOLD_RIM)
	c.draw_colored_polygon(_ellipse_polygon(
		Vector2(cx, cy), r * 0.90, ry * 0.85, 28), GOLD)
	if show_face:
		# Catchlight + star motif so the player can read "coin face"
		c.draw_colored_polygon(_ellipse_polygon(
			Vector2(cx - r * 0.20, cy - ry * 0.25),
			r * 0.36, ry * 0.40, 20), GOLD_LIGHT)
		var pts := _star_polygon(Vector2(cx, cy), r * 0.34, r * 0.14, 5, -PI * 0.5)
		# Squash the star vertically to match the oblique view
		for i in pts.size():
			pts[i] = Vector2(pts[i].x, cy + (pts[i].y - cy) * (ry / r))
		c.draw_colored_polygon(pts, GOLD_DARK)
	# Top edge specular sliver
	c.draw_arc(Vector2(cx, cy), r * 0.95, PI + 0.5, TAU - 0.5, 24,
		Color(1, 1, 1, 0.55), 1.2, true)

# Short coin stack (used by the safe scene) — `count` coins stacked tall.
static func _draw_short_stack(c: CanvasItem, cx: float, cy: float,
		r: float, count: int) -> void:
	var ry := r * 0.35
	var step := ry * 1.5
	for i in count:
		var y: float = cy - float(i) * step
		_draw_disc_with_edge(c, cx, y, r, ry, ry * 0.7,
			i == count - 1)  # top coin shows face

# Diamond gem with a top-left bright triangle (catchlight).
static func _draw_gem(c: CanvasItem, cx: float, cy: float, r: float,
		body: Color, hl: Color) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(cx, cy - r))
	pts.append(Vector2(cx + r * 0.85, cy))
	pts.append(Vector2(cx, cy + r))
	pts.append(Vector2(cx - r * 0.85, cy))
	c.draw_colored_polygon(pts, body)
	# Highlight wedge (top-left quadrant of the diamond)
	var hl_pts := PackedVector2Array()
	hl_pts.append(Vector2(cx, cy - r))
	hl_pts.append(Vector2(cx - r * 0.85, cy))
	hl_pts.append(Vector2(cx - r * 0.20, cy - r * 0.25))
	c.draw_colored_polygon(hl_pts, hl)
	# Centre sparkle dot
	c.draw_circle(Vector2(cx - r * 0.10, cy - r * 0.20), r * 0.18,
		Color(1, 1, 1, 0.85))

# 4-pointed sparkle (a thin cross of two elongated diamonds).
static func _draw_sparkle(c: CanvasItem, cx: float, cy: float, r: float) -> void:
	var v := PackedVector2Array()
	v.append(Vector2(cx, cy - r * 1.4))
	v.append(Vector2(cx + r * 0.35, cy))
	v.append(Vector2(cx, cy + r * 1.4))
	v.append(Vector2(cx - r * 0.35, cy))
	c.draw_colored_polygon(v, Color(1, 1, 1, 0.85))
	var h := PackedVector2Array()
	h.append(Vector2(cx - r * 1.4, cy))
	h.append(Vector2(cx, cy + r * 0.35))
	h.append(Vector2(cx + r * 1.4, cy))
	h.append(Vector2(cx, cy - r * 0.35))
	c.draw_colored_polygon(h, Color(1, 1, 1, 0.85))
	c.draw_circle(Vector2(cx, cy), r * 0.30, Color(1, 1, 1, 0.95))

# Radial glow — concentric circles with quick alpha falloff. Cheaper and
# crisper at small sizes than a shader and avoids shipping a material.
static func _draw_glow(c: CanvasItem, cx: float, cy: float, r: float, color: Color) -> void:
	var rings := 10
	for i in range(rings, 0, -1):
		var t: float = float(i) / float(rings)
		var rr: float = r * t
		var alpha: float = color.a * pow(1.0 - t, 1.4) * 0.85
		c.draw_circle(Vector2(cx, cy), rr, Color(color.r, color.g, color.b, alpha))

# ====================================================================
# Geometry helpers
# ====================================================================

static func _star_polygon(center: Vector2, outer: float, inner: float,
		points: int, rot: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var step: float = PI / float(points)
	for i in points * 2:
		var rr: float = outer if i % 2 == 0 else inner
		var a: float = rot + step * float(i)
		p.append(center + Vector2(cos(a), sin(a)) * rr)
	return p

static func _ellipse_polygon(center: Vector2, rx: float, ry: float,
		n: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		p.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return p

# A teardrop / gourd silhouette. Wider in the bottom third, pinched at
# the top to form the cinched neck of a sack. `n` is half the resolution
# (one side); the function mirrors back so you get 2*n points.
static func _teardrop_outline(cx: float, body_cy: float,
		half_w: float, total_h: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	# Walk down the right side from neck → body bottom.
	for i in n + 1:
		var t: float = float(i) / float(n)  # 0 = neck, 1 = bottom
		var y: float = body_cy - total_h * 0.40 + t * total_h * 0.80
		var w_t: float = _sack_profile(t)
		pts.append(Vector2(cx + half_w * w_t, y))
	# Walk up the left side back to the neck.
	for i in range(n, -1, -1):
		var t: float = float(i) / float(n)
		var y: float = body_cy - total_h * 0.40 + t * total_h * 0.80
		var w_t: float = _sack_profile(t)
		pts.append(Vector2(cx - half_w * w_t, y))
	return pts

# Width profile of the teardrop, parameterised by vertical position t
# (0 = neck/top, 1 = body bottom). Returns a fraction of half_w.
static func _sack_profile(t: float) -> float:
	# Hand-tuned: narrow neck (~0.55), bulge in the middle/lower section
	# peaking near t=0.55, gentle taper to a rounded bottom.
	if t < 0.10:
		return 0.55
	if t < 0.95:
		# Smooth bulge — sin wave biased toward the lower half.
		var bt: float = (t - 0.10) / 0.85
		return 0.55 + 0.45 * sin(bt * PI * 0.95 + 0.05)
	# Bottom round-off (quick taper into a soft point).
	var bt: float = (t - 0.95) / 0.05
	return lerp(0.92, 0.40, bt)

# Heraldic shield outline (classic heater shape).
static func _shield_polygon(cx: float, cy: float, w: float, h: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.append(Vector2(cx, cy - h * 0.50))
	p.append(Vector2(cx + w * 0.45, cy - h * 0.42))
	p.append(Vector2(cx + w * 0.50, cy - h * 0.20))
	p.append(Vector2(cx + w * 0.42, cy + h * 0.15))
	p.append(Vector2(cx + w * 0.20, cy + h * 0.42))
	p.append(Vector2(cx, cy + h * 0.50))
	p.append(Vector2(cx - w * 0.20, cy + h * 0.42))
	p.append(Vector2(cx - w * 0.42, cy + h * 0.15))
	p.append(Vector2(cx - w * 0.50, cy - h * 0.20))
	p.append(Vector2(cx - w * 0.45, cy - h * 0.42))
	return p

# Picks a uniform scale so the icon fits the art rect with breathing room.
# Reference rect is the standard pack art area (~194 × 96).
static func _fit_scale(size: Vector2) -> float:
	var sx := size.x / 194.0
	var sy := size.y / 96.0
	return minf(sx, sy)
