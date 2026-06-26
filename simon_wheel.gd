extends Control
class_name SimonWheel

# A 3D Simon wheel rendered through a SubViewport and shown as a 2D widget.
# Geometry is generated procedurally from the segment count, so it adapts to
# 4 / 5 / 6 buttons (easy / moderate / hard) with no per-count art.
#
# Public API:
#   configure(count, colors)      -> (re)build the wheel
#   set_lit(idx, on)              -> light a segment (drives emission glow)
#   set_press(idx, amount)        -> 0..1 press-down feedback
#   segment_at_point(local_pos)   -> segment index under a tap, or -1
#
# Renderer note: project runs the Mobile (Vulkan) renderer. The look is driven
# entirely by geometry (rounded-bevel buttons), StandardMaterial3D (glossy ABS,
# no textures), and soft lighting - NOT by surface texture/noise. Emissive
# materials + a touch of bloom drive the light-up.

# ---- tunables (wheel is built in local units, ring outer radius = 1.0) ----
const OUTER_R := 1.0
const INNER_R := 0.34        # buttons reach closer to center (bigger buttons)
const SEG_H := 0.20          # segment thickness (depth) - thick, heavy buttons
const BASE_R := 1.16         # graphite base plate radius (thin frame outside buttons)
const BASE_H := 0.20
const HUB_R := 0.30          # smaller center circle (~ -25%)
const HUB_H := 0.22
const GAP_DEG := 5.0         # angular gap between segments
const ARC_STEPS := 16        # arc tessellation per segment (smooth bevel/dome)
const RADIAL_STEPS := 10     # radial tessellation of the top (smooth bevel/dome)
const DOME := 0.045          # gentle central convexity (pillowed top)
const BEVEL := 0.085         # rounded-bevel drop around the whole segment edge
const BEVEL_ZONE := 0.3      # fraction of each half-extent occupied by the bevel

const EMIT_ON := 2.0         # emission when lit: lit from within, not overexposed
const EMIT_OFF := 0.40       # idle self-illumination — bumped from 0.14 so the
							 # button colors read vivid even before being lit.
							 # Still well under the 1.1 bloom threshold.
const GLOW_LERP := 14.0      # how fast glow rises/falls
const PRESS_DROP := 0.06     # how far a pressed segment sinks (local units)
const HALO_SIZE := 1.7       # small glow that bleeds just past the segment edges
const HALO_ALPHA := 0.8      # outer-glow strength when lit (calibrating - tune down)
# Each colored button is inset inside its slot, leaving a dark frame
# border around it, and raised so it sits proud of the frame.
const BTN_ANG_MARGIN := 2.0  # degrees trimmed from each angular side
const BTN_RAD_MARGIN := 0.06 # radial inset
const BTN_RAISE := 0.09      # how far the button sits above the frame plate
# Side walls kept fairly bright so buttons never read as near-black; inner/cap
# walls only a little darker for a soft seam (gentle AO, not heavy shadow).
const SIDE_DARK := 0.7      # outer side-wall brightness vs the top
const SIDE_DARK_IN := 0.95   # inner/recessed walls a touch darker

# ---- Volcano skin (id "inferno") extras ----
# A wide raised "sulfur stone" platform is slipped under each colored button so
# the buttons read as proud blocks seated in volcanic rock. The platform nearly
# fills the slot (so a broad sulfur rim frames each button), rises to STONE_TOP,
# and the button is lifted STONE_BTN_LIFT to sit proud on top of it.
const STONE_TOP := 0.28          # height of the sulfur platform's top face
const STONE_BTN_LIFT := 0.14     # extra button raise so it sits proud on the stone
const STONE_ANG_MARGIN := 0.4    # platform nearly fills the slot (button sits in its
const STONE_RAD_MARGIN := 0.01   #   middle), so a wide sulfur rim frames each button
const STONE_DOME := 0.04         # gentle chunky-stone crown
# In Volcano mode the button is inset further than usual so a generous band of the
# sulfur platform shows around it (instead of the button covering the whole stone).
const VOLC_BTN_ANG_MARGIN := 4.0
const VOLC_BTN_RAD_MARGIN := 0.11
# Low, wide volcano cone at the hub with a recessed lava crater. Kept low so the
# glowing crater sits UNDER the centered level numeral (number sits on the crater).
const VOLC_BASE_R := HUB_R * 1.18   # cone foot radius
const VOLC_RIM_R := HUB_R * 0.62    # crater outer rim radius (cone top)
const VOLC_H := 0.30                # cone rise above the wheel top
const VOLC_CRATER_R := HUB_R * 0.40 # crater floor (lava pool) radius
const VOLC_CRATER_DROP := 0.10      # how deep the crater recesses below the rim
# The level numeral sits on the volcano crater (higher on screen than the flat
# hub), so the Volcano skin lifts the readout by this FRACTION of the widget
# height on top of CENTER_LIFT. Proportional so it tracks both the big in-game
# wheel and the small shop preview. Tune if it doesn't land dead-centre on the
# crater's top circle.
const VOLC_NUM_LIFT_FRAC := 0.05

# Camera framing (slight tilt for a 3D feel while keeping hit-testing simple).
# Pulled in so the wheel fills most of the widget (large, prominent).
const CAM_POS := Vector3(0.0, 4.0, 1.5)
const CAM_FOV := 34.0

var _colors: Array = []
var _count: int = 0
var _start_angle := -PI * 0.5   # segment 0 centered toward top of screen

var _vpc: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _wheel_root: Node3D
var _segments: Array[MeshInstance3D] = []
var _seg_mats: Array[StandardMaterial3D] = []
var _seg_base: Array[Color] = []   # enriched (richer/brighter) per-segment base color
var _emit_cur: Array[float] = []
var _emit_tgt: Array[float] = []
var _press: Array[float] = []
var _halos: Array[MeshInstance3D] = []
var _halo_mats: Array[StandardMaterial3D] = []
var _glow_tex: Texture2D
var _level_num: Label
var _num_labels: Array[Label] = []   # stacked layers (glow / main / highlight)
var _num_glow: Label                 # the soft outer-glow layer (recoloured by font packs)
var _num_holder: Control             # holds the numeral layers (scaled for the shop preview)
var _dot: Panel                      # status light below the numeral

# Equipped Simon customization (set via apply_skin). Each is a Color tint or
# null = keep the stock graphite/white look:
#   _outer_tint -> the metallic rim/frame rings around the buttons
#   _inner_tint -> the centre hub disc
#   _num_pack   -> the level numeral's font package (Dictionary) or null = stock
#   _skin_id    -> active complete skin ("" = none). Skins (e.g. "inferno") have
#                  their own bespoke metal treatment + a 2D overlay layer on top
#                  of the SubViewport, and override outer/inner/num when applied.
var _outer_tint: Variant = null
var _inner_tint: Variant = null
var _num_pack: Variant = null
var _skin_id: String = ""

# Animated 2D overlay layer painted ON TOP of the SubViewport (e.g. the inferno
# skin's ring of flames). Lives outside the 3D scene because it's a screen-space
# canvas-item shader; null until a skin that needs an overlay is equipped.
var _skin_overlay: Control
var _skin_overlay_mat: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shell()
	resized.connect(_sync_viewport_size)

func _build_shell() -> void:
	_vpc = SubViewportContainer.new()
	_vpc.stretch = true
	_vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vpc)

	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	# MSAA on a render-target SubViewport is a heavy allocation in the GL
	# Compatibility renderer and leak-prone on some mobile (Mali) drivers. The
	# wheel's look comes from geometry + lighting, not thin AA edges, so we drop
	# it — this both lightens the per-frame GPU cost and removes the leaking path.
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	# Start idle. The wheel only needs to redraw while something is moving (a flash,
	# a press, or an animated skin); _process drives the update mode from there via
	# _update_render_activity, and _kick_render forces a one-off redraw after changes
	# outside the animation loop (rebuild / skin swap / resize). Continuously
	# re-rendering a STATIC wheel every frame (the old UPDATE_ALWAYS) is what slowly
	# exhausted the mobile GL driver's heap and OOM-crashed the game on long sessions.
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vpc.add_child(_vp)

	# --- environment ---
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR   # transparent for compositing
	# A studio-ish sky drives image-based reflections so metal reads as metal.
	# It is NOT drawn (background stays transparent) - only used for IBL.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.55, 0.62, 0.85)
	sky_mat.sky_horizon_color = Color(0.16, 0.18, 0.28)
	sky_mat.ground_horizon_color = Color(0.12, 0.12, 0.16)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.45         # broad studio fill — bumped from 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 2   # tune 1.0–1.5
											# so the wheel reads brighter without
											# touching any clearcoat/specular path
	# Side glow: only the lit segment crosses the HDR threshold, so it blooms a
	# little colored light onto the surrounding frame. The bloom radius is kept
	# SMALL (fine glow levels only) so it reads as light bleed, not a neon aura.
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, 1.0)               # finest -> tight glow close to the edge
	env.set_glow_level(2, 0.9)
	env.set_glow_level(3, 0.4)
	env.set_glow_level(4, 0.0)               # zero the wide levels -> small radius
	env.set_glow_level(5, 0.0)
	env.set_glow_level(6, 0.0)   # levels are indexed 0..6 (MAX_GLOW_LEVELS = 7);
								 # set_glow_level(7, …) was out of bounds and errored
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	# --- camera ---
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = CAM_FOV
	_cam.position = CAM_POS
	_vp.add_child(_cam)
	_cam.look_at(Vector3.ZERO, Vector3.UP)  # must be in-tree before look_at

	# --- lights ---
	# One large, soft light source from nearly overhead. A directional light reads
	# as an infinitely large source, so its specular is broad and soft (no small
	# sharp hotspot) and it lays a clean highlight across the glossy tops.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-72, -18, 0)   # high overhead, slight lean
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.98, 0.95)
	key.light_specular = 0.85                      # broad, controlled highlight
	key.shadow_enabled = true                      # soft contact shadows in the seams
	key.shadow_blur = 3.0                          # softer = premium, no hard edge
	key.shadow_opacity = 0.5                       # light shadows, no heavy darkening
	_vp.add_child(key)

	# Cool, dim fill from the opposite low side: lifts the recessed/lower faces just
	# enough to read their form without flattening the contrast.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 150, 0)
	fill.light_energy = 0.45                       # lifts the shadowed inner faces
	fill.light_specular = 0.0                      # no second hotspot
	fill.light_color = Color(0.7, 0.78, 1.0)
	_vp.add_child(fill)

	_wheel_root = Node3D.new()
	_vp.add_child(_wheel_root)

	_build_center_overlay()
	_sync_viewport_size()

# Center readout styled like an illuminated hardware display: a large pure-white
# numeral (auto-shrinking as the level grows) with a soft blue outer glow, a
# circular glow behind it and a soft drop shadow, plus a small status light a
# fixed gap below - all Godot-native (no fonts). Centered on the hub.
const NUM_MAX_SIZE := 80     # font size for short numbers
const NUM_MIN_SIZE := 26     # never shrink past this
const NUM_MAX_W := 104.0     # numeral shrinks to stay within this width (the hub)
const CENTER_LIFT := 20      # px to raise the readout (hub center sits above widget
							 # center due to the camera tilt)
const DOT_GAP := 57          # px from the numeral center down to the status light
# Soft blue halo behind the level numeral (the "glow of the hub"). Lowered from
# (0.15, 30): raise HUB_GLOW_ALPHA toward ~0.15 for a stronger glow, lower toward
# 0 to fade it out; HUB_GLOW_SIZE is the halo radius in px.
const HUB_GLOW_ALPHA := 0.045
const HUB_GLOW_SIZE := 14

func _build_center_overlay() -> void:
	# Numeral holder, centered on the hub. This Control is sized to the widget, so
	# anchoring children to its center pins the numeral to the inner-circle center.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(190, 120)
	holder.size = Vector2(190, 120)
	holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	holder.offset_top -= CENTER_LIFT
	holder.offset_bottom -= CENTER_LIFT
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_num_holder = holder

	# (1) circular blue-white glow behind the numeral: invisible body, soft halo.
	var glow := Panel.new()
	glow.custom_minimum_size = Vector2(100, 100)
	glow.size = Vector2(100, 100)
	glow.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0.5, 0.68, 1.0, 0.0)
	gs.set_corner_radius_all(50)
	# Hub glow strength. This is the soft blue halo behind the level numeral — the
	# "glow of the hub". Tune HUB_GLOW_ALPHA (opacity) and HUB_GLOW_SIZE (radius)
	# to make it stronger/weaker. Lowered from (0.15, 30) so it reads as a gentle
	# inner light, not a strong bloom.
	gs.shadow_color = Color(0.45, 0.66, 1.0, HUB_GLOW_ALPHA)
	gs.shadow_size = HUB_GLOW_SIZE
	glow.add_theme_stylebox_override("panel", gs)
	holder.add_child(glow)

	_num_labels.clear()
	# (2) soft blue OUTER GLOW, glyph-shaped: transparent fill, blurred blue shadow.
	var nglow := _num_label(NUM_MAX_SIZE, Color(0.5, 0.7, 1.0, 0.0))
	nglow.add_theme_color_override("font_shadow_color", Color(0.45, 0.68, 1.0, 0.5))
	nglow.add_theme_constant_override("shadow_offset_x", 0)
	nglow.add_theme_constant_override("shadow_offset_y", 0)
	nglow.add_theme_constant_override("shadow_outline_size", 10)
	holder.add_child(nglow)
	_num_labels.append(nglow)
	_num_glow = nglow

	# (3) main numeral: pure white, thin same-color weight outline (~semi-bold),
	# and a soft dark drop shadow underneath.
	_level_num = _num_label(NUM_MAX_SIZE, Color.WHITE)
	_level_num.add_theme_color_override("font_outline_color", Color(1, 1, 1, 1))
	_level_num.add_theme_constant_override("outline_size", 2)   # weight, not a stroke
	_level_num.add_theme_color_override("font_shadow_color", Color(0.0, 0.02, 0.06, 0.5))
	_level_num.add_theme_constant_override("shadow_offset_x", 0)
	_level_num.add_theme_constant_override("shadow_offset_y", 4)
	_level_num.add_theme_constant_override("shadow_outline_size", 5)
	holder.add_child(_level_num)
	_num_labels.append(_level_num)

	# (4) faint top highlight: white copy nudged up 2px at low alpha, so the top
	# edge of the numeral catches a little extra light (illuminated-display feel).
	var hi := _num_label(NUM_MAX_SIZE, Color(1, 1, 1, 0.35))
	hi.offset_top -= 2
	hi.offset_bottom -= 2
	holder.add_child(hi)
	_num_labels.append(hi)

	# Small glowing status light, centered horizontally a fixed gap below the
	# numeral (just inside the lower hub).
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size = Vector2(12, 12)
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	dot.offset_top += DOT_GAP - CENTER_LIFT          # stays DOT_GAP below the numeral
	dot.offset_bottom += DOT_GAP - CENTER_LIFT
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.55, 0.76, 1.0)
	ds.set_corner_radius_all(6)
	ds.shadow_color = Color(0.35, 0.62, 1.0, 0.7)
	ds.shadow_size = 10
	dot.add_theme_stylebox_override("panel", ds)
	add_child(dot)
	_dot = dot

	set_level(1)

# Shop-preview overlay tweak: shrink the numeral and optionally hide the status
# dot so the small preview reads at the same proportions as the large in-game
# wheel. The real game wheel never calls this, so it keeps scale 1 + the dot.
func set_overlay_compact(numeral_scale: float, show_dot: bool) -> void:
	if _num_holder != null:
		_num_holder.pivot_offset = _num_holder.size * 0.5
		_num_holder.scale = Vector2(numeral_scale, numeral_scale)
	if _dot != null:
		# The Volcano skin drops the status dot entirely (it would sit on the crater).
		_dot.visible = show_dot and _skin_id != "inferno"

# One numeral layer: fills the holder and centers its glyph, so all layers align.
func _num_label(fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = "1"
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Largest size (<= NUM_MAX_SIZE) at which the number still fits NUM_MAX_W wide.
func _fit_num_size(txt: String) -> int:
	var font: Font = _level_num.get_theme_font("font") if _level_num != null else ThemeDB.fallback_font
	if font == null:
		font = ThemeDB.fallback_font
	var w := font.get_string_size(
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1, NUM_MAX_SIZE).x
	if w <= NUM_MAX_W:
		return NUM_MAX_SIZE
	return maxi(NUM_MIN_SIZE, int(floor(NUM_MAX_SIZE * NUM_MAX_W / w)))

func set_level(n: int) -> void:
	var txt := str(n)
	var fs := _fit_num_size(txt)
	for l in _num_labels:
		l.text = txt
		l.add_theme_font_size_override("font_size", fs)

func _sync_viewport_size() -> void:
	if _vpc:
		_vpc.position = Vector2.ZERO
		_vpc.size = size
	if _vp:
		_vp.size = Vector2i(maxi(2, int(size.x)), maxi(2, int(size.y)))
	_layout_numeral()   # the volcano lift is a fraction of the widget height
	_kick_render()      # a resized render target must redraw to fill the new size

# Position the level-numeral overlay (and the status dot below it) for the active
# skin. Stock skins sit CENTER_LIFT above the widget centre; the Volcano skin lifts
# the readout further so it lands on the raised crater's top circle, by a fraction
# of the widget height so it tracks both the in-game wheel and the shop preview.
func _layout_numeral() -> void:
	if _num_holder == null:
		return
	var lift := float(CENTER_LIFT)
	if _skin_id == "inferno":
		lift += size.y * VOLC_NUM_LIFT_FRAC
	_num_holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_num_holder.offset_top -= lift
	_num_holder.offset_bottom -= lift
	if _dot != null:
		# The Volcano skin removes the status dot (it would land on the crater).
		_dot.visible = _skin_id != "inferno"
		_dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
		_dot.offset_top += DOT_GAP - lift
		_dot.offset_bottom += DOT_GAP - lift

# ---------------- build ----------------

func configure(count: int, colors: Array) -> void:
	_count = count
	_colors = colors.duplicate()
	if _wheel_root == null:
		_build_shell()
	_rebuild()

func _rebuild() -> void:
	for c in _wheel_root.get_children():
		c.queue_free()
	_segments.clear()
	_seg_mats.clear()
	_seg_base.clear()
	_emit_cur.clear()
	_emit_tgt.clear()
	_press.clear()

	_halos.clear()
	_halo_mats.clear()
	if _glow_tex == null:
		_glow_tex = _make_glow_tex()

	# --- premium graphite base plate + concentric machined rings ---
	# Graphite (never pure black), satin metal so it catches soft reflections.
	# Semi-metallic graphite: enough diffuse to read as a lit gray metal surface
	# (pure metal would only show dim reflections and look black).
	# Inferno skin swaps these StandardMaterial3D rings for a single coal+lava
	# ShaderMaterial via _ring_material — the same procedural pattern runs across
	# every ring so they read as one continuous chunk of glowing coal, with the
	# `heat` param brightening the hub area relative to the cooler outer rim.
	var base := _disc_no_mat(BASE_R, BASE_H)
	base.material_override = _ring_material(Color(0.15, 0.155, 0.17), 0.4, 0.45, 0.85)
	_wheel_root.add_child(base)

	# recessed dark groove just outside the buttons - reads as ambient occlusion
	var groove := MeshInstance3D.new()
	groove.mesh = _ring_mesh(OUTER_R, OUTER_R + 0.035, 0.16, 0.0)
	groove.position.y = 0.04
	groove.material_override = _ring_material(Color(0.05, 0.05, 0.06), 0.3, 0.6, 1.10)
	_wheel_root.add_child(groove)

	# raised beveled inner ring (machined lip)
	var ring_a := MeshInstance3D.new()
	ring_a.mesh = _ring_mesh(OUTER_R + 0.035, OUTER_R + 0.10, 0.22, 0.05)
	ring_a.position.y = 0.05
	ring_a.material_override = _ring_material(Color(0.19, 0.195, 0.22), 0.45, 0.32, 1.25)
	_wheel_root.add_child(ring_a)

	# outer rounded rim ring (catches the soft top highlight); thin overall frame
	var ring_b := MeshInstance3D.new()
	ring_b.mesh = _ring_mesh(OUTER_R + 0.095, OUTER_R + 0.16, 0.2, 0.07)
	ring_b.position.y = 0.03
	ring_b.material_override = _ring_material(Color(0.23, 0.235, 0.26), 0.5, 0.26, 1.30)
	_wheel_root.add_child(ring_b)

	# Glowing hub — under the Volcano skin this becomes a low cone with a molten
	# crater and lava running down its slopes; otherwise it's the standard hub.
	if _skin_id == "inferno":
		var top_y := BASE_H * 0.5 + 0.03   # cone foot sits on the wheel top
		var volcano := MeshInstance3D.new()
		volcano.mesh = _volcano_mesh()
		volcano.position.y = top_y
		volcano.material_override = _volcano_material()
		_wheel_root.add_child(volcano)
	else:
		var hub := _disc_no_mat(HUB_R, HUB_H)
		# Hub wears the INNER tint (the "CENTER HUB" shop slot); _ring_material is
		# routed through _outer() and would otherwise tint the hub with the rim
		# colour, so equipping a centre-hub colour produced no visible change.
		hub.material_override = _metal_mat(_inner(Color(0.11, 0.11, 0.14)), 0.5, 0.3)
		hub.position.y = 0.06
		_wheel_root.add_child(hub)

	var step := TAU / _count
	var gap := deg_to_rad(GAP_DEG)
	for i in _count:
		var a0 := _start_angle + i * step + gap * 0.5
		var a1 := _start_angle + (i + 1) * step - gap * 0.5
		var raw: Color = _colors[i % _colors.size()] if not _colors.is_empty() else Color.GRAY
		# Inferno burns each button: same hue, lower value + saturation so it reads
		# as a charred plastic that's been licked by flame. The colour stays clearly
		# recognisable (red is red, green is green) but no longer "fresh out of the
		# mould". Non-skin mode keeps the existing enriched look.
		var col := _burn_color(_enrich(raw)) if _skin_id == "inferno" else _enrich(raw)
		# dark metallic frame plate filling this slot (the button's own frame).
		# Inferno: the frame becomes another coal slab (same coal shader) so the
		# gaps between burnt buttons glow with embers rather than dark graphite.
		var frame := MeshInstance3D.new()
		frame.mesh = _sector_mesh(a0, a1, INNER_R, OUTER_R, SEG_H)
		frame.position.y = BASE_H * 0.5
		frame.material_override = _ring_material(Color(0.08, 0.08, 0.095), 0.3, 0.45, 1.40)
		_wheel_root.add_child(frame)
		# Volcano: a wide raised sulfur-stone platform under the button (smaller
		# margins than the button) so a broad rim of yellow volcanic rock frames it,
		# and STONE_BTN_LIFT raises the button to sit proud on top of the stone.
		var stone_lift := 0.0
		if _skin_id == "inferno":
			var sa0 := a0 + deg_to_rad(STONE_ANG_MARGIN)
			var sa1 := a1 - deg_to_rad(STONE_ANG_MARGIN)
			var stone := MeshInstance3D.new()
			# Wide slab rising from the wheel top (y≈0) to STONE_TOP — a sulfur
			# platform the button is seated into so a broad rim of rock frames it.
			stone.mesh = _sector_mesh(sa0, sa1, INNER_R + STONE_RAD_MARGIN, OUTER_R - STONE_RAD_MARGIN,
				STONE_TOP, STONE_DOME, SIDE_DARK, BEVEL)
			stone.position.y = STONE_TOP * 0.5
			stone.material_override = _sulfur_material()
			_wheel_root.add_child(stone)
			stone_lift = STONE_BTN_LIFT
		# inset, raised, glossy colored button sitting inside the frame: thick body,
		# a gently pillowed top and a soft rounded bevel wrapping the whole edge.
		# Volcano insets it further so the sulfur platform frames it generously.
		var bam := VOLC_BTN_ANG_MARGIN if _skin_id == "inferno" else BTN_ANG_MARGIN
		var brm := VOLC_BTN_RAD_MARGIN if _skin_id == "inferno" else BTN_RAD_MARGIN
		var ba0 := a0 + deg_to_rad(bam)
		var ba1 := a1 - deg_to_rad(bam)
		var mesh := _sector_mesh(ba0, ba1, INNER_R + brm, OUTER_R - brm,
			SEG_H * 2.0, DOME, SIDE_DARK, BEVEL)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position.y = BASE_H * 0.5 + BTN_RAISE + stone_lift
		var mat := _seg_material(col, true)
		mi.material_override = mat
		_wheel_root.add_child(mi)
		_segments.append(mi)
		_seg_mats.append(mat)
		_seg_base.append(col)
		_emit_cur.append(EMIT_OFF)
		_emit_tgt.append(EMIT_OFF)
		_press.append(0.0)
		# soft additive glow halo over this segment (blooms outward when lit)
		var am := (a0 + a1) * 0.5
		var rm := (INNER_R + OUTER_R) * 0.5
		var halo := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(HALO_SIZE, HALO_SIZE)
		halo.mesh = q
		halo.rotation_degrees = Vector3(-90, 0, 0)   # lie flat, facing up
		# Sit above the frame (~0.20) but below the button's edge top (~0.305): the
		# button hides the bright core, only the soft outer falloff spills onto the
		# surrounding frame = light bleed.
		halo.position = Vector3(cos(am) * rm, 0.26 + stone_lift, sin(am) * rm)
		var gmat := _halo_material(col)
		halo.material_override = gmat
		_wheel_root.add_child(halo)
		_halos.append(halo)
		_halo_mats.append(gmat)
	# Geometry/materials just changed — force the (otherwise idle) viewport to draw
	# at least one frame so the rebuilt wheel actually appears.
	_kick_render()

# Glossy injection-molded ABS plastic. No textures, no triplanar, no rim - the
# form is carried entirely by geometry and lighting. A clearcoat gives the thin
# clear-gloss top layer real buttons have; vertex colors only darken the side
# walls (baked-in AO), never adding visible pattern.
func _seg_material(col: Color, use_vcol: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.vertex_color_use_as_albedo = use_vcol  # darkens side/recessed faces only
	m.metallic = 0.0                         # dielectric ABS plastic, not metal
	m.roughness = 0.3                        # clean satin gloss (broad highlight)
	m.specular = 0.65
	m.clearcoat_enabled = true               # thin clear gloss coat
	m.clearcoat = 0.3
	m.clearcoat_roughness = 0.1
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = EMIT_OFF
	return m

# Richer, brighter version of a base color (more saturation + value, with a
# brightness floor) so inactive buttons read clearly and look premium instead of
# dark/desaturated.
func _enrich(c: Color) -> Color:
	var s := clampf(c.s * 1.1, 0.0, 1.0)
	var v := clampf(maxf(c.v * 1.35, 0.55), 0.0, 1.0)
	return Color.from_hsv(c.h, s, v, c.a)

# The lit-state albedo: a moderately brighter, slightly more saturated version of
# the (already enriched) base - never lerped toward white, so it stays the color.
func _lit_color(c: Color) -> Color:
	var s := clampf(c.s * 1.05, 0.0, 1.0)
	var v := clampf(c.v * 1.18, 0.0, 1.0)
	return Color.from_hsv(c.h, s, v, c.a)

func _metal_mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

# ---------------- customization (shop "SIMON" colours + SPECIAL SKINS) ----------------

# Equip the player's chosen look. `outer`/`inner` are a Color or null (= stock
# graphite). `number` is a font-package Dictionary or null (= stock white numeral).
# `skin_id` is the active complete-skin id ("" = none); when non-empty the skin
# fully overrides outer/inner/number with its own bespoke palette and spawns any
# 2D overlay (e.g. the inferno ring of flames).
# Rebuilds the wheel meshes and restyles the numeral so it shows immediately.
func apply_skin(outer: Variant, inner: Variant, number: Variant, skin_id: String = "") -> void:
	_skin_id = skin_id
	# A skin owns the whole look — caller tints/num pack are ignored when one is
	# active so manual + skin choices don't fight each other.
	if _skin_id != "":
		_outer_tint = null
		_inner_tint = null
		_num_pack = _skin_num_pack(_skin_id)
	else:
		_outer_tint = outer
		_inner_tint = inner
		_num_pack = number
	if _wheel_root != null:
		_rebuild()
	_apply_num_pack()
	_sync_skin_overlay()
	_layout_numeral()   # move the readout onto the volcano crater (or back to centre)

# Resolve a rim mesh's stock graphite colour through the equipped outer tint.
# Inferno is handled separately via _ring_material (it uses a coal shader rather
# than a tinted StandardMaterial3D), so this only matters in non-skin mode.
func _outer(gray: Color) -> Color:
	return _tint_metal(gray, _outer_tint) if _outer_tint is Color else gray

# Resolve the hub's stock graphite colour through the equipped inner tint.
func _inner(gray: Color) -> Color:
	return _tint_metal(gray, _inner_tint) if _inner_tint is Color else gray

# A metallic shade of `tint` whose brightness tracks the part's original graphite
# value (so the rings keep their relative light-to-dark relationship), lifted into
# a visible range. Saturation is eased back slightly for a metallic, premium feel —
# silver/gold read naturally because their catalog colours are near-neutral/warm.
func _tint_metal(gray: Color, tint: Color) -> Color:
	var v := clampf(gray.v * 2.2 + 0.30, 0.0, 1.0)
	var s := clampf(tint.s * 0.85, 0.0, 1.0)
	return Color.from_hsv(tint.h, s, v)

# Skin's numeral font package, or null = leave the numeral as-is. Each complete
# skin restyles the level numeral so the readout matches the overall vibe.
func _skin_num_pack(skin: String) -> Variant:
	if skin == "inferno":
		return {
			"font": "", "color": Color(1.0, 0.88, 0.45),
			"glow": Color(1.0, 0.32, 0.06, 0.95), "glow_size": 22,
			"outline": Color(0.08, 0.0, 0.0, 1.0), "outline_size": 5,
		}
	return null

# Burnt version of a button colour: same hue, dropped value + saturation so it
# reads as a piece of plastic that's been licked by flame. The hue is preserved
# so red still looks red, yellow still looks yellow, etc.
func _burn_color(col: Color) -> Color:
	var v := clampf(col.v * 0.60, 0.0, 1.0)
	var s := clampf(col.s * 0.82, 0.0, 1.0)
	return Color.from_hsv(col.h, s, v, col.a)

# Pick the right material for a metallic ring/hub based on the active skin.
# Inferno → a shared coal+lava ShaderMaterial parameterised by `heat` (lets the
# hub glow brighter than the base plate while running the same shader across
# every ring, so the cracks / hot stones look continuous).
# No skin → the regular satin-metal StandardMaterial3D used since launch.
func _ring_material(stock: Color, metal: float, rough: float, heat: float) -> Material:
	if _skin_id == "inferno":
		return _coal_material(heat)
	return _metal_mat(_outer(stock), metal, rough)

# Shared 3D shader compiled lazily — every ring/hub material for inferno points
# at the same Shader resource, so the GPU only compiles it once.
var _coal_shader: Shader

func _coal_material(heat: float) -> ShaderMaterial:
	if _coal_shader == null:
		_coal_shader = Shader.new()
		_coal_shader.code = _COAL_SHADER
	var m := ShaderMaterial.new()
	m.shader = _coal_shader
	m.set_shader_parameter("heat", heat)
	return m

# ---------------- Volcano skin: hub cone + sulfur stones ----------------

# Low, wide volcano cone with a recessed lava crater, built in local units with
# its foot at y = 0. A ring of quads sweeps the outer slope (base -> crater rim),
# then drops down a short inner wall to a small crater floor (the lava pool). The
# crater is left deliberately shallow/wide so the molten floor glows out from
# UNDER the centered level numeral rather than being hidden behind a tall peak.
func _volcano_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 64
	var rim_y := VOLC_H
	var floor_y := VOLC_H - VOLC_CRATER_DROP
	for j in steps:
		var a0: float = TAU * float(j) / steps
		var a1: float = TAU * float(j + 1) / steps
		# outer slope: foot (base radius, y=0) up to the crater rim
		var s00 := Vector3(cos(a0) * VOLC_BASE_R, 0.0, sin(a0) * VOLC_BASE_R)
		var s10 := Vector3(cos(a1) * VOLC_BASE_R, 0.0, sin(a1) * VOLC_BASE_R)
		var s11 := Vector3(cos(a1) * VOLC_RIM_R, rim_y, sin(a1) * VOLC_RIM_R)
		var s01 := Vector3(cos(a0) * VOLC_RIM_R, rim_y, sin(a0) * VOLC_RIM_R)
		var ns := (s10 - s00).cross(s01 - s00).normalized()
		if ns.y < 0.0:
			ns = -ns
		_quad(st, s00, s10, s11, s01, ns)
		# inner crater wall: rim down to the crater floor (faces inward/up)
		var w00 := s01
		var w10 := s11
		var w11 := Vector3(cos(a1) * VOLC_CRATER_R, floor_y, sin(a1) * VOLC_CRATER_R)
		var w01 := Vector3(cos(a0) * VOLC_CRATER_R, floor_y, sin(a0) * VOLC_CRATER_R)
		var nw := (w10 - w00).cross(w01 - w00).normalized()
		if nw.y < 0.0:
			nw = -nw
		_quad(st, w00, w10, w11, w01, nw)
		# crater floor (lava pool), facing straight up
		var c := Vector3(0.0, floor_y, 0.0)
		_quad(st, w01, w11, c, c, Vector3.UP)
	return st.commit()

# Shared lava-cone shader, compiled once like the coal shader.
var _volcano_shader: Shader

func _volcano_material() -> ShaderMaterial:
	if _volcano_shader == null:
		_volcano_shader = Shader.new()
		_volcano_shader.code = _VOLCANO_SHADER
	var m := ShaderMaterial.new()
	m.shader = _volcano_shader
	m.set_shader_parameter("rim_y", VOLC_H)
	m.set_shader_parameter("rim_r", VOLC_RIM_R)
	return m

# Sulfur-rock material for the raised button stones. A plain StandardMaterial3D —
# the SAME opaque path as the colored buttons — so the stones are guaranteed to
# render solid (an earlier custom ShaderMaterial read as see-through). A triplanar
# noise texture mottles the yellow rock so it reads as stone, not flat plastic.
var _sulfur_tex: Texture2D

func _sulfur_material() -> StandardMaterial3D:
	if _sulfur_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.frequency = 0.05
		var nt := NoiseTexture2D.new()
		nt.width = 96
		nt.height = 96
		nt.seamless = true
		nt.noise = n
		_sulfur_tex = nt
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.92, 0.80, 0.26)        # sulfur yellow
	m.albedo_texture = _sulfur_tex                   # mottled darker crevices
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(2.5, 2.5, 2.5)
	m.vertex_color_use_as_albedo = true              # bakes the side-wall AO darkening
	m.metallic = 0.0
	m.roughness = 0.95
	m.specular = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true                        # faint warmth ties it to the lava
	m.emission = Color(0.7, 0.30, 0.06)
	m.emission_energy_multiplier = 0.08
	return m

# Volcano cone shader: dark basalt rock with bright lava rivulets that flow
# DOWNHILL from the crater, and a molten, pooling crater floor. Uses the same
# fbm/gnoise noise style as the coal shader. The lava channels are vertical
# ridged-noise veins whose sampling Y scrolls with TIME so the hot rock appears
# to creep down the slope; emission is strongest at the top and fades downward.
const _VOLCANO_SHADER := "
shader_type spatial;
render_mode cull_disabled;

uniform float rim_y = 0.30;
uniform float rim_r = 0.186;
varying vec3 v_pos;

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
		 dot(p, vec3(269.5, 183.3, 246.1)),
		 dot(p, vec3(113.5, 271.9, 124.6)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453);
}
float gnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = dot(hash3(i + vec3(0.0, 0.0, 0.0)), f - vec3(0.0, 0.0, 0.0));
	float n100 = dot(hash3(i + vec3(1.0, 0.0, 0.0)), f - vec3(1.0, 0.0, 0.0));
	float n010 = dot(hash3(i + vec3(0.0, 1.0, 0.0)), f - vec3(0.0, 1.0, 0.0));
	float n110 = dot(hash3(i + vec3(1.0, 1.0, 0.0)), f - vec3(1.0, 1.0, 0.0));
	float n001 = dot(hash3(i + vec3(0.0, 0.0, 1.0)), f - vec3(0.0, 0.0, 1.0));
	float n101 = dot(hash3(i + vec3(1.0, 0.0, 1.0)), f - vec3(1.0, 0.0, 1.0));
	float n011 = dot(hash3(i + vec3(0.0, 1.0, 1.0)), f - vec3(0.0, 1.0, 1.0));
	float n111 = dot(hash3(i + vec3(1.0, 1.0, 1.0)), f - vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		   mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z) * 0.5 + 0.5;
}
float fbm(vec3 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * gnoise(p); p = p * 2.0; a *= 0.5; }
	return v;
}

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	// Cylindrical coords on the cone: angle around the axis, radius from it, and
	// normalized height up the slope. Streams are placed by ANGLE and run along
	// HEIGHT, so they read as channels flowing straight down the slope.
	float ang = atan(v_pos.z, v_pos.x);
	float rad = length(vec2(v_pos.x, v_pos.z));
	float h = clamp(v_pos.y / max(rim_y, 1e-4), 0.0, 1.2);  // 0 at foot, 1 at rim
	vec2 ac = vec2(cos(ang), sin(ang)) * 1.7;               // seamless angular coord

	// Black-brown basalt ground — kept clearly visible; lava only threads over it.
	float rock = fbm(v_pos * 9.0);
	vec3 rock_dark = vec3(0.030, 0.020, 0.015);
	vec3 rock_light = vec3(0.105, 0.060, 0.040);
	vec3 albedo = mix(rock_dark, rock_light, rock);

	// Keep streams on the OUTER slope only (not inside the crater bowl).
	float outer = smoothstep(rim_r * 0.9, rim_r * 1.1, rad);

	// A few NARROW lava channels at fixed angular positions ('chan'), each running
	// the full height of the slope. 'flow' makes the glow creep DOWN over time
	// (height coord scrolls with +TIME), so the lava streams downhill.
	float place = fbm(vec3(ac, 3.0));
	float pridge = 1.0 - abs(2.0 * place - 1.0);
	float chan = smoothstep(0.80, 0.97, pridge);
	float flow = fbm(vec3(ac, h * 5.0 + TIME * 0.6));
	flow = 0.55 + 0.45 * smoothstep(0.30, 0.80, flow);
	float streams = chan * flow * outer * smoothstep(0.03, 0.25, h);
	float breath = 0.7 + 0.3 * sin(TIME * 1.6 + place * 12.0);

	// Molten pool filling the crater bowl (everything inside the rim radius).
	float crater = smoothstep(rim_r * 1.0, rim_r * 0.55, rad);
	float bubble = 0.7 + 0.3 * sin(TIME * 2.2 + rock * 20.0);

	vec3 lava_col = vec3(1.00, 0.30, 0.04);
	vec3 hot_col = vec3(1.00, 0.78, 0.30);
	vec3 emission = lava_col * streams * breath * 2.6;
	emission += mix(lava_col, hot_col, 0.6) * crater * bubble * 4.5;

	ALBEDO = albedo;
	EMISSION = emission;
	METALLIC = 0.0;
	ROUGHNESS = 0.9;
	SPECULAR = 0.05;
}
"

# 3D coal+lava shader for the inferno skin. The wheel reads as a chunk of black
# coal with bright orange cracks running across it, plus rarer "hot stones" that
# glow yellow-white — patterns sampled in object space so all the rings + hub
# share one continuous, calm-breathing surface (no per-mesh seams).
const _COAL_SHADER := "
shader_type spatial;
render_mode cull_disabled;

uniform float heat = 1.0;
varying vec3 v_pos;

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
		 dot(p, vec3(269.5, 183.3, 246.1)),
		 dot(p, vec3(113.5, 271.9, 124.6)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453);
}

float gnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = dot(hash3(i + vec3(0.0, 0.0, 0.0)), f - vec3(0.0, 0.0, 0.0));
	float n100 = dot(hash3(i + vec3(1.0, 0.0, 0.0)), f - vec3(1.0, 0.0, 0.0));
	float n010 = dot(hash3(i + vec3(0.0, 1.0, 0.0)), f - vec3(0.0, 1.0, 0.0));
	float n110 = dot(hash3(i + vec3(1.0, 1.0, 0.0)), f - vec3(1.0, 1.0, 0.0));
	float n001 = dot(hash3(i + vec3(0.0, 0.0, 1.0)), f - vec3(0.0, 0.0, 1.0));
	float n101 = dot(hash3(i + vec3(1.0, 0.0, 1.0)), f - vec3(1.0, 0.0, 1.0));
	float n011 = dot(hash3(i + vec3(0.0, 1.0, 1.0)), f - vec3(0.0, 1.0, 1.0));
	float n111 = dot(hash3(i + vec3(1.0, 1.0, 1.0)), f - vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		   mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z) * 0.5 + 0.5;
}

float fbm(vec3 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * gnoise(p); p = p * 2.0; a *= 0.5; }
	return v;
}

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	// Sample noise in object space so every ring/hub of the wheel reads as a
	// SINGLE chunk of coal (no per-mesh seam where the noise pattern resets).
	vec3 p = v_pos * 7.0;

	// Coal base: rocky variation between near-black and a slightly warmer dark
	// brown, so the rim doesn't look like a flat colour.
	float coal = fbm(p);
	vec3 coal_dark = vec3(0.020, 0.010, 0.006);
	vec3 coal_light = vec3(0.085, 0.040, 0.022);
	vec3 albedo = mix(coal_dark, coal_light, coal);

	// Cracks via ridged noise (1 - |2n-1|): sharp lines where the noise crosses
	// the midpoint. Slow drift gives the impression of glow seeping along veins.
	float cn = fbm(p * 0.55 + vec3(0.0, TIME * 0.10, 0.0));
	float ridge = 1.0 - abs(2.0 * cn - 1.0);
	float cracks = smoothstep(0.74, 0.95, ridge);

	// Per-position pulse phase so different cracks breathe at different times —
	// reads as living embers, not a synchronised flicker.
	float breath = 0.55 + 0.45 * sin(TIME * 1.4 + cn * 14.0);

	// Rare 'hot stones': large-scale low-frequency noise selects a few zones
	// that glow extra-bright yellow-white, like coals that just shifted to the
	// surface.
	float hot_noise = fbm(p * 0.32 + vec3(TIME * 0.07, 0.0, 0.0));
	float hot = smoothstep(0.72, 0.88, hot_noise);

	// Emission: cracks are red-orange, hot stones push toward yellow-white.
	vec3 crack_col = vec3(1.00, 0.30, 0.05);
	vec3 stone_col = vec3(1.00, 0.72, 0.22);
	vec3 emission = crack_col * cracks * breath * 2.6;
	emission += stone_col * hot * 4.0;
	emission *= heat;

	ALBEDO = albedo;
	EMISSION = emission;
	METALLIC = 0.0;
	ROUGHNESS = 0.88;
	SPECULAR = 0.05;
}
"

# ---------------- skin overlay (animated 2D layer on top of the SubViewport) ----------------

# Pick the right overlay shader for a skin and (re)spawn it. Called from
# apply_skin every time the skin changes. No current skin paints a 2D overlay —
# the Volcano skin dropped the rim flames — but the machinery is kept for any
# future skin that needs one.
func _sync_skin_overlay() -> void:
	_destroy_skin_overlay()

func _ensure_skin_overlay(shader_code: String) -> void:
	if _skin_overlay == null:
		_skin_overlay = ColorRect.new()
		_skin_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_skin_overlay.color = Color.WHITE
		_skin_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_skin_overlay)
		# Keep the numeral overlay + status dot ON TOP of the flames — flames are
		# transparent in the wheel interior anyway, but this guarantees the level
		# readout is never composited under a stray ember.
		move_child(_skin_overlay, 1 if _vpc != null else 0)
		_skin_overlay_mat = ShaderMaterial.new()
		_skin_overlay.material = _skin_overlay_mat
	var sh := Shader.new()
	sh.code = shader_code
	_skin_overlay_mat.shader = sh

func _destroy_skin_overlay() -> void:
	if _skin_overlay and is_instance_valid(_skin_overlay):
		_skin_overlay.queue_free()
	_skin_overlay = null
	_skin_overlay_mat = null

# Apply the equipped level-number font package (typeface + colour + glow + outline)
# across the numeral layers; a null/empty package restores the stock white look.
func _apply_num_pack() -> void:
	if _level_num == null:
		return
	var pack: Dictionary = _num_pack if (_num_pack is Dictionary) else {}

	# Typeface: applied to every layer so glow/main/highlight stay aligned.
	var font: Font = null
	var fp := String(pack.get("font", ""))
	if fp != "" and ResourceLoader.exists(fp):
		var f := load(fp)
		if f is Font:
			font = f
	for l in _num_labels:
		if font != null:
			l.add_theme_font_override("font", font)
		else:
			l.remove_theme_font_override("font")

	# Main numeral colour + weight/outline.
	_level_num.add_theme_color_override("font_color", pack.get("color", Color.WHITE))
	_level_num.add_theme_color_override("font_outline_color", pack.get("outline", Color(1, 1, 1, 1)))
	_level_num.add_theme_constant_override("outline_size", int(pack.get("outline_size", 2)))

	# Soft outer glow lives on the dedicated glow layer.
	if _num_glow != null:
		_num_glow.add_theme_color_override("font_shadow_color", pack.get("glow", Color(0.45, 0.68, 1.0, 0.5)))
		_num_glow.add_theme_constant_override("shadow_outline_size", int(pack.get("glow_size", 10)))

	# Re-fit in case the typeface changed the numeral's width.
	set_level(int(str(_level_num.text)) if _level_num.text.is_valid_int() else 1)

func _disc(radius: float, height: float, col: Color, rough: float) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 48
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.2
	m.roughness = rough
	mi.material_override = m
	return mi

# Same disc mesh as _disc, but without auto-assigning a material — the caller
# always overrides material_override (e.g. with the coal shader for inferno),
# so creating + immediately replacing the StandardMaterial3D was wasted work.
func _disc_no_mat(radius: float, height: float) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 48
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	return mi

# Full-circle rounded rim (domed across the radius only -> no seam).
func _ring_mesh(ri: float, ro: float, h: float, dome_h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := h * 0.5
	var bot := -h * 0.5
	var steps := 96
	for j in steps:
		var a0: float = TAU * float(j) / steps
		var a1: float = TAU * float(j + 1) / steps
		for jr in RADIAL_STEPS:
			var t0 := float(jr) / RADIAL_STEPS
			var t1 := float(jr + 1) / RADIAL_STEPS
			var r0: float = lerp(ri, ro, t0)
			var r1: float = lerp(ri, ro, t1)
			var y0: float = top + dome_h * sin(PI * t0)
			var y1: float = top + dome_h * sin(PI * t1)
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p10 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var p01 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var n := (p10 - p00).cross(p01 - p00).normalized()
			if n.y < 0.0:
				n = -n
			_quad(st, p00, p10, p11, p01, n)
		var nrm := (Vector3(cos(a0), 0, sin(a0)) + Vector3(cos(a1), 0, sin(a1))).normalized()
		# outer wall
		_quad(st,
			Vector3(cos(a0) * ro, bot, sin(a0) * ro), Vector3(cos(a1) * ro, bot, sin(a1) * ro),
			Vector3(cos(a1) * ro, top, sin(a1) * ro), Vector3(cos(a0) * ro, top, sin(a0) * ro), nrm)
		# inner wall
		_quad(st,
			Vector3(cos(a0) * ri, top, sin(a0) * ri), Vector3(cos(a1) * ri, top, sin(a1) * ri),
			Vector3(cos(a1) * ri, bot, sin(a1) * ri), Vector3(cos(a0) * ri, bot, sin(a0) * ri), -nrm)
	return st.commit()

# Soft radial gradient (white center -> transparent edge) for glow billboards.
func _make_glow_tex() -> Texture2D:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.5)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func _halo_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _glow_tex
	m.albedo_color = Color(col.r, col.g, col.b, 0.0)   # invisible until lit
	return m

# Annular sector shaped like a real molded button: a gently pillowed top that
# rolls off into a soft rounded bevel around the entire edge, then drops to a
# short vertical wall and end caps. The bevel ends at y = wall_top, so the top
# surface meets the walls smoothly (no hard crease).
func _sector_mesh(a0: float, a1: float, ri: float, ro: float, h: float,
		dome: float = DOME, side_dark: float = 1.0, bevel: float = 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := h * 0.5
	var bot := -h * 0.5
	var wall_top := top - bevel                          # bevel ends here, wall begins
	var side := Color(side_dark, side_dark, side_dark)   # outer side-wall tint
	# inner + cap walls are more occluded -> darker (baked-in ambient occlusion)
	var k_in := side_dark * 0.72
	var side_in := Color(k_in, k_in, k_in)
	# pillowed + beveled top face (radial x arc grid). Vertices move in Y only;
	# the dense grid + smoothly varying normals read as a rounded bevel.
	for jr in RADIAL_STEPS:
		var r0: float = lerp(ri, ro, float(jr) / RADIAL_STEPS)
		var r1: float = lerp(ri, ro, float(jr + 1) / RADIAL_STEPS)
		for ja in ARC_STEPS:
			var aa0: float = lerp(a0, a1, float(ja) / ARC_STEPS)
			var aa1: float = lerp(a0, a1, float(ja + 1) / ARC_STEPS)
			var p00 := _dome_pt(aa0, r0, a0, a1, ri, ro, top, dome, bevel)
			var p10 := _dome_pt(aa1, r0, a0, a1, ri, ro, top, dome, bevel)
			var p11 := _dome_pt(aa1, r1, a0, a1, ri, ro, top, dome, bevel)
			var p01 := _dome_pt(aa0, r1, a0, a1, ri, ro, top, dome, bevel)
			var n := (p10 - p00).cross(p01 - p00).normalized()
			if n.y < 0.0:
				n = -n
			_quad(st, p00, p10, p11, p01, n)
	# walls + caps - the bevel drops onto these short vertical faces
	for j in ARC_STEPS:
		var b0: float = lerp(a0, a1, float(j) / ARC_STEPS)
		var b1: float = lerp(a0, a1, float(j + 1) / ARC_STEPS)
		var nrm := (Vector3(cos(b0), 0, sin(b0)) + Vector3(cos(b1), 0, sin(b1))).normalized()
		# outer wall
		_quad(st, _p(b0, ro, bot), _p(b1, ro, bot), _p(b1, ro, wall_top), _p(b0, ro, wall_top), nrm, side)
		# inner wall (recessed, near the hub -> darker)
		_quad(st, _p(b0, ri, wall_top), _p(b1, ri, wall_top), _p(b1, ri, bot), _p(b0, ri, bot), -nrm, side_in)
	# end caps (sit in the gaps between buttons -> recessed, darker)
	var tan0 := Vector3(-sin(a0), 0, cos(a0))
	_quad(st, _p(a0, ri, bot), _p(a0, ro, bot), _p(a0, ro, wall_top), _p(a0, ri, wall_top), -tan0, side_in)
	var tan1 := Vector3(-sin(a1), 0, cos(a1))
	_quad(st, _p(a1, ri, wall_top), _p(a1, ro, wall_top), _p(a1, ro, bot), _p(a1, ri, bot), tan1, side_in)
	return st.commit()

func _p(angle: float, r: float, y: float) -> Vector3:
	return Vector3(cos(angle) * r, y, sin(angle) * r)

# Rounded-shoulder falloff: 1.0 across the plateau, easing to 0.0 at an edge with
# a vertical tangent (quarter-circle), so the bevel meets the wall smoothly. `d`
# is the normalized distance to the nearest edge along one axis (0 = at edge).
func _shoulder(d: float) -> float:
	if d >= BEVEL_ZONE:
		return 1.0
	var u := d / BEVEL_ZONE                  # 0 at edge -> 1 at plateau
	return sqrt(maxf(0.0, 1.0 - (1.0 - u) * (1.0 - u)))

# A point on the button top. `f` is a rounded square-plateau mask (0 at every
# edge/corner, 1 over the middle): edges drop by `bevel` (rounded shoulder),
# while a gentle `dome` pillow lifts the plateau center. Walls stay flush at
# y = top - bevel because f = 0 there.
func _dome_pt(angle: float, r: float, a0: float, a1: float,
		ri: float, ro: float, top: float, dome: float = DOME,
		bevel: float = 0.0) -> Vector3:
	var tr := (r - ri) / (ro - ri)
	var ta := (angle - a0) / (a1 - a0)
	var f := _shoulder(minf(tr, 1.0 - tr)) * _shoulder(minf(ta, 1.0 - ta))
	var pillow := sin(PI * tr) * sin(PI * ta)
	var y := top - bevel * (1.0 - f) + dome * pillow
	return Vector3(cos(angle) * r, y, sin(angle) * r)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
		col: Color = Color.WHITE) -> void:
	for v in [a, b, c]:
		st.set_color(col); st.set_normal(n); st.add_vertex(v)
	for v in [a, c, d]:
		st.set_color(col); st.set_normal(n); st.add_vertex(v)

# ---------------- runtime ----------------

func set_lit(idx: int, on: bool) -> void:
	if idx < 0 or idx >= _emit_tgt.size():
		return
	_emit_tgt[idx] = EMIT_ON if on else EMIT_OFF

func set_press(idx: int, amount: float) -> void:
	if idx < 0 or idx >= _press.size():
		return
	_press[idx] = clampf(amount, 0.0, 1.0)

func _process(dt: float) -> void:
	# Track whether anything is still moving this frame; when nothing is, the
	# viewport can stop redrawing (see _update_render_activity below).
	var animating := false
	for i in _seg_mats.size():
		var k := clampf(dt * GLOW_LERP, 0.0, 1.0)
		_emit_cur[i] = lerp(_emit_cur[i], _emit_tgt[i], k)
		# lerp never reaches the target exactly — snap once we're within a hair so
		# the glow truly settles and the wheel is allowed to go idle.
		if absf(_emit_cur[i] - _emit_tgt[i]) <= 0.003:
			_emit_cur[i] = _emit_tgt[i]
		else:
			animating = true
		var mat := _seg_mats[i]
		mat.emission_energy_multiplier = _emit_cur[i]
		var base: Color = _seg_base[i] if i < _seg_base.size() else Color.GRAY
		# lit_amount is measured ABOVE the idle floor, so idle = 0 (no halo / no
		# extra brightening) while the emission floor still keeps colors visible.
		var lit_amount := clampf((_emit_cur[i] - EMIT_OFF) / (EMIT_ON - EMIT_OFF), 0.0, 1.0)
		# Lit = illuminated from within: brighten + slightly saturate the whole
		# surface (not toward white), so it glows richly without washing out. The
		# emission energy above does the internal-glow part; gloss/specular survive.
		mat.albedo_color = base.lerp(_lit_color(base), lit_amount)
		# fade the glow halo in/out
		if i < _halo_mats.size():
			var hc := _halo_mats[i].albedo_color
			hc.a = lit_amount * HALO_ALPHA
			_halo_mats[i].albedo_color = hc
		# press sink (Volcano keeps the button lifted on its sulfur stone)
		var stone_lift := STONE_BTN_LIFT if _skin_id == "inferno" else 0.0
		_segments[i].position.y = BASE_H * 0.5 + BTN_RAISE + stone_lift - _press[i] * PRESS_DROP
		if _press[i] > 0.0001:
			animating = true
	_update_render_activity(animating)

# Animated skins drive their look from shader TIME (the coal cracks / lava flow),
# so they must keep redrawing every frame. Stock looks are static once the glow
# has settled, so they can idle the viewport.
func _animated_skin() -> bool:
	return _skin_id == "inferno"

# Drive the SubViewport's redraw cadence from whether anything is moving. While a
# flash/press is animating (or an animated skin is equipped) we render every frame;
# once everything is still we render one final settling frame (UPDATE_ONCE, which
# self-disables) and then stop. An idle wheel no longer re-renders ~30×/s — that
# continuous redraw of static 3D content is what leaked memory in the mobile GL
# driver until it OOM-crashed mid-game.
func _update_render_activity(animating: bool) -> void:
	if _vp == null:
		return
	if _animated_skin() or animating:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	elif _vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		# Draw the final settled frame, then idle.
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

# Force at least one redraw of the otherwise-idle viewport after something changed
# it outside the per-frame animation loop (rebuild, skin swap, resize).
func _kick_render() -> void:
	if _vp == null:
		return
	if _animated_skin():
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	elif _vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

# ---------------- hit testing ----------------

# Maps a tap (in this Control's local coords) to a segment index, or -1.
# Works regardless of camera tilt by intersecting the camera ray with the
# wheel's top plane and reading polar coords in wheel space.
func segment_at_point(local_pos: Vector2) -> int:
	if _cam == null or _count == 0:
		return -1
	var vp_scale := Vector2(_vp.size) / size
	var vpp := local_pos * vp_scale
	var origin := _cam.project_ray_origin(vpp)
	var dir := _cam.project_ray_normal(vpp)
	var plane_y := BASE_H * 0.5 + SEG_H * 0.5
	if absf(dir.y) < 0.0001:
		return -1
	var dist := (plane_y - origin.y) / dir.y
	if dist <= 0.0:
		return -1
	var hit := origin + dir * dist
	var r := sqrt(hit.x * hit.x + hit.z * hit.z)
	if r < INNER_R or r > OUTER_R:
		return -1
	var ang := atan2(hit.z, hit.x) - _start_angle
	ang = fposmod(ang, TAU)
	return int(ang / (TAU / _count)) % _count
