extends Control
class_name PentagonDevice

# The MODERATE ("Medium") gameplay device: the five-button pentagonal console
# authored in Blender and exported as res://models/GameDevice_Pentagon.glb.
# It replaces SimonWheel on that difficulty only — easy/hard still use the
# procedural wheel, and the shop previews are untouched.
#
# Public API is a drop-in subset of SimonWheel's, so game.gd drives it with the
# exact same calls (see game.gd's _wheel):
#   configure(count, colors)      -> build the device (colors are ignored; the
#                                    GLB carries its own authored palette)
#   apply_skin(outer, inner, number, skin_id)
#                                 -> only the level-number font package applies;
#                                    the modelled device has a fixed look
#   set_lit(idx, on)              -> LED/emission flash + press animation
#   set_press(idx, amount)        -> press animation (amount > 0 triggers it)
#   segment_at_point(local_pos)   -> button index under a tap, or -1
#   set_level(n)                  -> centre-display readout
#   erupt() / electric_pulse() / roulette_spin() / luna_light_chase() /
#   luna_celebrate() / roulette_celebrate()
#                                 -> no-ops (skin flourishes belong to the wheel)
#
# Renderer note: same approach as SimonWheel — a transparent SubViewport with its
# own World3D, one key + one fill DirectionalLight3D, and a small bloom so a lit
# button flares. The viewport only redraws while something is moving (see
# _update_render_activity), which is what keeps the mobile GL driver from leaking
# on long sessions.
#
# LOOK: the GLB's materials are the authority and are never edited here — the
# per-button duplicates below start identical to the imported ones and exist only
# so each pad's emission can be driven independently during play. Everything that
# decides whether this reads like the Blender asset lives in the environment and
# lights: a DARK NEUTRAL studio sky, very low diffuse ambient, and a LINEAR
# tonemap. Brightening any of those is what turns the chassis blue-grey and drags
# Lime and Orange toward yellow. Verified against MediumBlender/Preview_*.png.

const MODEL: PackedScene = preload("res://models/GameDevice_Pentagon.glb")

# Button index -> the GLB's node / animation names. The index order matches
# game.gd's BUTTON_COLORS (Red, Green, Blue, Yellow, Orange) so the existing
# per-index tones from AudioManager.play_button_tone keep their pairing:
#   0 Red -> Pink, 1 Green -> Lime, 2 Blue -> Cyan, 3 Yellow, 4 Orange.
const BUTTON_KEYS := ["Pink", "Lime", "Cyan", "Yellow", "Orange"]
const NUM_BUTTONS := 5

# Model is authored at real-world scale (~27cm across). Blown up to ~2.2 units so
# the directional shadow map has usable resolution over it and the lighting
# constants read the same as the wheel's.
const MODEL_SCALE := 8.0
# The GLB's footprint is not centred on its origin in Z, so recentre it.
const MODEL_Z_OFFSET := -0.095

# Camera: a raised three-quarter view — high enough that all five pads read
# clearly, low enough to keep the chassis, trim and glowing legs in frame.
const CAM_DIST := 3.75
const CAM_ELEV_DEG := 50.0
const CAM_TARGET := Vector3(0.0, 0.28, 0.0)
const CAM_FOV := 34.0

# Flash energies. Swept against the idle pad: a lit cyan pad goes (45,251,255) ->
# (123,255,255) at 5.0 — plainly brighter and blooming, while red stays about half
# of green/blue so it still reads cyan rather than washing to white (7.0 took it
# to (165,255,255), which was a wash). IDLE IS NEVER OVERRIDDEN — every material keeps exactly the
# emission, albedo, metallic and roughness the GLB was authored with, so a pad at
# rest renders as the Blender asset does. Only the lit target is ours: it drives
# the emission far past the bloom threshold so an active pad flares and bleeds
# light onto the chassis, then eases back to the authored idle.
# Godot renders these authored emissives hotter than Blender does for the same
# nominal values. The LED family (indicator dots, accent strips, centre icon,
# screen text, button rims — everything authored ABOVE energy 1.0) therefore
# clips and loses its hue: the lime dot renders (255,255,73) where Blender has
# (193,255,60), and both Lime and Orange flatten to yellow. Scaling their ENERGY
# only — never their colour, and never the geometry — lands them on the
# reference: at 0.70 that same dot renders (199,255,59). The pads' own materials
# are authored at exactly 1.0, already match, and are deliberately left alone.
const LED_EMISSION_MATCH := 0.70

const EMIT_LIT_SURFACE := 5.0
const EMIT_LIT_LED := 8.0
const GLOW_LERP := 16.0          # how fast the flash rises/falls
const LIT_ALBEDO_MIX := 0.12     # how far the pad's albedo brightens when lit
								 # (kept small — the punch comes from emission and
								 # bloom, so a lit pad flares without losing its hue)

# Centre readout. The live stage number is the ONE thing Godot adds to the centre
# module; the housing, display face, waveform icon and five indicator dots are all
# the GLB's authored geometry and are left exactly as exported.
#
# It is a Label3D parented to the GLB's own Center_Module and laid FLAT on the
# display face, standing in for the authored "12" placeholder mesh. That means it
# shares the device's perspective, lighting and bloom — it recedes with the
# display like the Blender text does, instead of floating over the render as a
# screen-aligned 2D label (which is what made the old one look pasted on).
#
# Placement below is measured off the placeholder mesh's own ink bounds, taken
# from the GLB and expressed in Center_Module local space (metres).
# X is nudged off the raw ink centre by the measured 2px: the placeholder's face
# and Arial carry different side bearings on "1", so centring the string lands
# fractionally right of where the authored glyphs sit.
const READOUT_POS := Vector3(0.00030, 0.01160, 0.00140)
const READOUT_DIGIT_H := 0.00933   # authored digit height ("12" ink, Z extent)
const READOUT_MAX_W := 0.0265      # long numbers shrink to stay on the display
const READOUT_FONT_SIZE := 64      # glyph atlas resolution; scale comes from pixel_size
# Digit ink height as a fraction of font_size. Calibrated against the placeholder
# mesh's rendered height — see _fit_readout.
const READOUT_DIGIT_RATIO := 0.72
# MAT_Screen_Text's authored emissive tint, and a little HDR so the number glows
# like the rest of the display rather than reading as flat paint.
const READOUT_COLOR := Color(0.889, 0.965, 1.0)
const READOUT_ENERGY := 1.55
# The placeholder's digits are thin and geometric; Godot's default UI face is far
# heavier and read as a sticker stuck on the display. Arial is the closest of the
# project's own fonts.
const READOUT_FONT_PATH := "res://fonts/arial.ttf"

var _vpc: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _model_root: Node3D          # scaled + recentred holder for the GLB instance
var _device: Node3D              # the instantiated GLB scene
var _ap: AnimationPlayer         # the GLB's own AnimationPlayer (Press_* clips)

# Per-button state, all indexed by button index (0..4).
var _surf_mats: Array[StandardMaterial3D] = []
var _led_mats: Array[StandardMaterial3D] = []
var _surf_base_albedo: Array[Color] = []
var _surf_base_emit: Array[float] = []
var _led_base_emit: Array[float] = []
var _emit_cur: Array[float] = []   # 0 = idle, 1 = fully lit
var _emit_tgt: Array[float] = []
var _areas: Dictionary = {}        # Area3D instance id -> button index

# Guard so a press that arrives as BOTH set_press() and set_lit() in the same
# frame (game.gd's _press_feedback does exactly that) only restarts the clip once.
var _anim_idx := -1
var _anim_frame := -1

# The live stage number, laid on the authored display face (see READOUT_* above).
var _level3d: Label3D
var _num_pack: Variant = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _vpc == null:
		_build_shell()
	resized.connect(_sync_viewport_size)

# ---------------- build ----------------

func _build_shell() -> void:
	_vpc = SubViewportContainer.new()
	_vpc.stretch = true
	_vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vpc)

	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	# Matches SimonWheel: MSAA on a render-target SubViewport is a heavy
	# allocation on mobile GL drivers and buys little here.
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	# Start idle; _process/_kick_render drive the redraw cadence from there.
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vpc.add_child(_vp)

	# --- environment ---
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR   # transparent for compositing
	# A DARK, NEUTRAL studio — this is what the Blender scene is lit by, and
	# getting it wrong is what washed the device out. A bright blue sky here
	# reflects off every surface: it lifts the near-black chassis to blue-grey and
	# lays a pale sheen over the pads that desaturates them. Kept dark and neutral,
	# reflections read as the soft grey sheen the reference has, and the chassis
	# stays black.
	var sky_mat := ProceduralSkyMaterial.new()
	# Brightness here is felt almost entirely by the chassis, not the pads: the
	# chassis is metallic 0.25 so it reflects ~25% of the sky, while a pad is a
	# dielectric reflecting ~4%. That is the lever for the chassis's sheen and
	# edge highlights without lifting the pad colours.
	# HDR values (>1): with the key kept this dim, the sky is what supplies the
	# chassis's sheen and its bright bevel edges. Values sampled against
	# MediumBlender/Preview_Perspective.png — the chassis lands on (22,25,31)
	# against the reference's (23,24,28).
	sky_mat.sky_top_color = Color(2.20, 2.28, 2.48)
	sky_mat.sky_horizon_color = Color(1.04, 1.08, 1.20)
	sky_mat.ground_horizon_color = Color(0.56, 0.56, 0.64)
	sky_mat.ground_bottom_color = Color(0.20, 0.20, 0.22)
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve = 0.15
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	# Diffuse ambient and reflections are split on purpose. Diffuse stays very low
	# so each pad renders essentially at its authored base colour (piling light on
	# a fully saturated colour clips its strongest channel while the others keep
	# climbing — that is what dragged Lime and Orange toward yellow). Specular
	# still comes off the sky above, which is what gives the chassis its sheen and
	# the pads their gloss.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.86)
	env.ambient_light_energy = 0.07
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# LINEAR, not FILMIC. Blender rendered this asset on a Standard view
	# transform: pure, fully saturated pads with a hard specular streak. Godot's
	# filmic curve rolls the highlights off and desaturates as it does so, which
	# is the other half of the washed-out pastel look.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	# The pads sit right at full brightness at rest (that is the authored look), so
	# a flash has almost no headroom left in the pixel itself — the "which button
	# lit up" cue has to come from the bloom instead. Hence the wider glow levels
	# and the big lit-emission targets above: an active pad halos out onto the
	# black chassis, which reads clearly without altering the resting look.
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	# Threshold sits ABOVE the authored idle emissives (dots 1.5, accent strips and
	# screen text 2.0-2.4) so they stay crisp, saturated points of light instead of
	# smearing into each other — at 1.1 the five indicator dots bloomed together and
	# lime/orange washed to yellow. A lit pad (7.0) still clears it by miles.
	env.glow_hdr_threshold = 1.5
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 0.9)
	env.set_glow_level(3, 0.5)
	env.set_glow_level(4, 0.25)
	env.set_glow_level(5, 0.0)
	env.set_glow_level(6, 0.0)
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	# --- camera ---
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = CAM_FOV
	_cam.near = 0.1
	_cam.far = 40.0
	var elev := deg_to_rad(CAM_ELEV_DEG)
	var cam_pos := CAM_TARGET + Vector3(0.0, sin(elev), cos(elev)) * CAM_DIST
	_vp.add_child(_cam)
	# look_at_from_position works off-tree too (see SimonWheel's note).
	_cam.look_at_from_position(cam_pos, CAM_TARGET, Vector3.UP)

	# --- lights ---
	# Diffuse is deliberately tiny. Each pad already carries ~55% of its own colour
	# as authored emission, so the key only has to supply the remainder for the pad
	# to land on its base colour — any more and the strongest channel clips while
	# the others keep climbing, which is exactly how Lime and Orange turn yellow.
	# Swept against the reference: 0.12 puts all five pads within ~12/255 of the
	# Blender values, where 0.45 overshot every secondary channel by 40-60.
	# light_specular scales ONLY the specular lobe, so it is the one knob that adds
	# gloss, highlights and depth WITHOUT adding diffuse — which is exactly the
	# trade this asset needs: strong studio highlights on the dark chassis and a
	# crisp streak across each pad, while the pads' saturated colour is untouched.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58, -22, 0)
	key.light_energy = 0.12
	key.light_color = Color(1.0, 0.98, 0.95)
	key.light_specular = 6.0
	key.shadow_enabled = true
	key.shadow_blur = 2.0
	key.shadow_opacity = 0.75
	# The device is ~2.2 units across; the default 100-unit shadow range would
	# spend the whole shadow map on empty space.
	key.directional_shadow_max_distance = 12.0
	_vp.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-26, 150, 0)
	fill.light_energy = 0.04
	fill.light_specular = 0.0
	fill.light_color = Color(0.72, 0.78, 0.95)
	_vp.add_child(fill)

	# Rim: a cool grazing light from behind and to the far side. Almost no diffuse
	# (it barely touches any surface facing the camera), but a high specular lobe,
	# so it picks out the chassis bevels, the trim ring and the leg chrome as
	# bright edges — the separation that reads as "premium" in the reference.
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, 152, 0)
	rim.light_energy = 0.06
	rim.light_specular = 9.0
	rim.light_color = Color(0.80, 0.86, 1.0)
	_vp.add_child(rim)

	# --- the device itself ---
	_model_root = Node3D.new()
	_model_root.scale = Vector3(MODEL_SCALE, MODEL_SCALE, MODEL_SCALE)
	_model_root.position = Vector3(0.0, 0.0, MODEL_Z_OFFSET)
	_vp.add_child(_model_root)

	_device = MODEL.instantiate() as Node3D
	_model_root.add_child(_device)
	_ap = _device.find_child("AnimationPlayer", true, false) as AnimationPlayer

	# The GLB ships a placeholder "12" on the centre display; the live level is
	# drawn by the 2D overlay below instead.
	var placeholder := _device.find_child("Temporary_Display_Text", true, false)
	if placeholder is Node3D:
		(placeholder as Node3D).visible = false

	_calibrate_emissives(_device)
	_build_buttons()
	_build_center_readout()
	_sync_viewport_size()

# Bring every authored emissive that sits above energy 1.0 onto the brightness
# Blender renders it at (see LED_EMISSION_MATCH). Works through per-instance
# overrides, so the imported materials themselves are never written to, and
# nothing but the energy scalar is touched.
func _calibrate_emissives(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for sfc in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(sfc) as StandardMaterial3D
				if m != null and m.emission_enabled and m.emission_energy_multiplier > 1.0:
					var dup := m.duplicate() as StandardMaterial3D
					dup.emission_energy_multiplier = m.emission_energy_multiplier * LED_EMISSION_MATCH
					mi.set_surface_override_material(sfc, dup)
	for c in n.get_children():
		_calibrate_emissives(c)

# Per button: give the pad + LED their OWN material copies (the GLB shares each
# MAT_LED_* with the centre indicator pips and the chassis accent strips, so
# driving the shared resource would light half the device), and hang an Area3D
# with a convex shape off the pad so taps hit that button and nothing else.
func _build_buttons() -> void:
	_surf_mats.clear()
	_led_mats.clear()
	_surf_base_albedo.clear()
	_surf_base_emit.clear()
	_led_base_emit.clear()
	_emit_cur.clear()
	_emit_tgt.clear()
	_areas.clear()

	for idx in NUM_BUTTONS:
		var key: String = BUTTON_KEYS[idx]
		var surf := _device.find_child("%s_Surface" % key, true, false) as MeshInstance3D
		var led := _device.find_child("%s_LED" % key, true, false) as MeshInstance3D

		# Nothing about the authored look is changed here — the duplicate starts
		# life identical to the imported material and its values become the idle
		# baseline we return to after every flash.
		var sm := _own_material(surf)
		var lm := _own_material(led)
		_surf_mats.append(sm)
		_led_mats.append(lm)
		_surf_base_albedo.append(sm.albedo_color if sm else Color.WHITE)
		_surf_base_emit.append(sm.emission_energy_multiplier if sm else 1.0)
		_led_base_emit.append(lm.emission_energy_multiplier if lm else 1.5)
		_emit_cur.append(0.0)
		_emit_tgt.append(0.0)

		if surf != null:
			_add_button_area(surf, idx)

# Duplicate a MeshInstance3D's surface-0 material into a per-instance override so
# changing its emission can't bleed into every other mesh sharing that material.
func _own_material(mi: MeshInstance3D) -> StandardMaterial3D:
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return null
	var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
	if src == null:
		return null
	var dup := src.duplicate() as StandardMaterial3D
	# Same brightness match the rest of the emissives get, so a pad's LED rim sits
	# at the calibrated idle its flash returns to.
	if dup.emission_enabled and dup.emission_energy_multiplier > 1.0:
		dup.emission_energy_multiplier *= LED_EMISSION_MATCH
	mi.set_surface_override_material(0, dup)
	return dup

# One Area3D per pad, shaped from that pad's own mesh — five independent targets,
# never a single area over the whole device.
func _add_button_area(surf: MeshInstance3D, idx: int) -> void:
	var shape := surf.mesh.create_convex_shape(true, true)
	if shape == null:
		return
	var area := Area3D.new()
	area.name = "Hit_%s" % BUTTON_KEYS[idx]
	area.monitoring = false        # we only ever query it with a ray
	area.monitorable = false
	area.input_ray_pickable = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	area.add_child(cs)
	# Parented to the pad so it follows the press animation; the pad's transform
	# already places it under the right corner of the pentagon.
	surf.add_child(area)
	_areas[area.get_instance_id()] = idx

# The live stage number, laid flat on the GLB's own display face. Nothing in the
# centre module is replaced or redrawn — this only stands in for the authored
# "12" placeholder mesh, which is the one element that cannot show a live value.
func _build_center_readout() -> void:
	var centre := _device.find_child("Center_Module", true, false) as Node3D
	if centre == null:
		return
	var l := Label3D.new()
	l.name = "StageReadout"
	l.text = "1"
	l.font_size = READOUT_FONT_SIZE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A lit display emits its own light — shading it would sink it into the
	# housing's shadow and it would stop reading as part of the screen.
	l.shaded = false
	l.double_sided = false
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.modulate = READOUT_COLOR * READOUT_ENERGY
	l.font = _stock_font()
	l.position = READOUT_POS
	# Lie the text down onto the display face: -90° about X puts the glyph plane's
	# normal along +Y (up, out of the screen) and its top toward -Z (the far edge,
	# which is up on screen), so it reads the right way round under this camera.
	l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	centre.add_child(l)
	_level3d = l
	_fit_readout()

# Size the readout so a digit is exactly as tall as the authored placeholder's,
# shrinking only when a long number would overrun the display face.
func _fit_readout() -> void:
	if _level3d == null:
		return
	var f: Font = _level3d.font if _level3d.font != null else ThemeDB.fallback_font
	var digit_px := float(READOUT_FONT_SIZE) * READOUT_DIGIT_RATIO
	var ps := READOUT_DIGIT_H / maxf(1.0, digit_px)
	var w: float = f.get_string_size(
		_level3d.text, HORIZONTAL_ALIGNMENT_LEFT, -1, READOUT_FONT_SIZE).x * ps
	if w > READOUT_MAX_W:
		ps *= READOUT_MAX_W / w
	_level3d.pixel_size = ps

# ---------------- SimonWheel-compatible API ----------------

# `count` and `colors` come from game.gd's difficulty setup. The device is a
# fixed five-button model with its own authored palette, so both are accepted
# and ignored — the signature exists so game.gd can drive either device.
func configure(_count: int, _colors: Array) -> void:
	if _vpc == null:
		_build_shell()
	_kick_render()

# Only the level-number font package applies to this device; the modelled
# chassis/pad colours and the special skins belong to SimonWheel.
func apply_skin(_outer: Variant, _inner: Variant, number: Variant, _skin_id: String = "") -> void:
	_num_pack = number
	_apply_num_pack()

func set_lit(idx: int, on: bool) -> void:
	if idx < 0 or idx >= _emit_tgt.size():
		return
	_emit_tgt[idx] = 1.0 if on else 0.0
	# Sequence playback only lights buttons (game.gd's _flash) — the physical
	# press must follow it, so the player sees which pad is being played.
	if on:
		_trigger_press(idx)

# game.gd sinks a pad with set_press(idx, 1.0) and releases it 0.18s later with
# 0.0. The GLB's clip already presses AND releases, so a release is a no-op.
func set_press(idx: int, amount: float) -> void:
	if idx < 0 or idx >= NUM_BUTTONS:
		return
	if amount > 0.0:
		_trigger_press(idx)

# Play exactly one Press_* clip. Each clip holds the other four pads at their
# rest pose, so only the named button ever moves.
func _trigger_press(idx: int) -> void:
	if _ap == null or idx < 0 or idx >= NUM_BUTTONS:
		return
	var frame := Engine.get_process_frames()
	if _anim_idx == idx and _anim_frame == frame:
		return   # same press arriving twice in one frame (set_press + set_lit)
	_anim_idx = idx
	_anim_frame = frame
	var anim := "Press_%s" % BUTTON_KEYS[idx]
	if not _ap.has_animation(anim):
		return
	if _ap.current_animation == anim and _ap.is_playing():
		_ap.seek(0.0, true)
	else:
		# A short blend keeps a retrigger from snapping the previous pad back up.
		_ap.play(anim, 0.06)
	_kick_render()

func set_level(n: int) -> void:
	if _level3d == null:
		return
	_level3d.text = str(n)
	_fit_readout()

# Maps a tap (in this Control's local coords) to a button index, or -1.
# Casts the camera ray through the SubViewport's own physics space and reads
# which pad's Area3D it struck, so each button is hit-tested independently and
# the gaps between them are correctly dead.
func segment_at_point(local_pos: Vector2) -> int:
	if _cam == null or _vp == null or size.x <= 0.0 or size.y <= 0.0:
		return -1
	var vpp := local_pos * (Vector2(_vp.size) / size)
	var origin := _cam.project_ray_origin(vpp)
	var dir := _cam.project_ray_normal(vpp)
	# find_world_3d(), not world_3d — the latter is the (unset) override slot and
	# reads back null even though the SubViewport owns a world.
	var world := _vp.find_world_3d()
	if world == null:
		return -1
	var space := world.direct_space_state
	if space == null:
		return -1
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 100.0)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -1
	var collider: Object = hit.get("collider")
	if collider == null:
		return -1
	return int(_areas.get(collider.get_instance_id(), -1))

# --- skin flourishes: SimonWheel-only, accepted as no-ops so game.gd's
# every-3rd/5th/8th-round calls stay untouched on this difficulty. ---
func erupt() -> void: pass
func electric_pulse() -> void: pass
func roulette_spin() -> void: pass
func roulette_celebrate() -> void: pass
func luna_light_chase() -> void: pass
func luna_celebrate() -> void: pass
func set_overlay_compact(_numeral_scale: float, _show_dot: bool) -> void: pass
func set_static_preview(_on: bool) -> void: pass
func set_preview_paused(_paused: bool) -> void: pass

# ---------------- layout / per-frame ----------------

func _sync_viewport_size() -> void:
	if _vpc:
		_vpc.position = Vector2.ZERO
		_vpc.size = size
	if _vp:
		_vp.size = Vector2i(maxi(2, int(size.x)), maxi(2, int(size.y)))
	# The readout lives in the 3D scene now, so a resize needs no relayout — it
	# is carried by the camera like the rest of the device.
	_kick_render()

# Model-space (metres, as authored) -> the world the render camera sees.
func _model_to_world(m: Vector3) -> Vector3:
	return m * MODEL_SCALE + Vector3(0.0, 0.0, MODEL_Z_OFFSET)

# A world point projected into this Control's local coordinates.
func _project(world: Vector3) -> Vector2:
	var p := _cam.unproject_position(world)
	if _vp != null and _vp.size.x > 0 and _vp.size.y > 0:
		p *= size / Vector2(_vp.size)
	return p

func _process(dt: float) -> void:
	var animating := _ap != null and _ap.is_playing()
	var k := clampf(dt * GLOW_LERP, 0.0, 1.0)
	for i in _emit_cur.size():
		_emit_cur[i] = lerp(_emit_cur[i], _emit_tgt[i], k)
		# lerp never lands exactly — snap once we're within a hair so the flash
		# truly settles and the viewport is allowed to go idle again.
		if absf(_emit_cur[i] - _emit_tgt[i]) <= 0.003:
			_emit_cur[i] = _emit_tgt[i]
		else:
			animating = true
		var lit: float = _emit_cur[i]
		var sm: StandardMaterial3D = _surf_mats[i]
		if sm != null:
			sm.emission_energy_multiplier = lerpf(_surf_base_emit[i], EMIT_LIT_SURFACE, lit)
			# Lit = illuminated from within: brighten the pad without washing it
			# out to white, so it still reads as its own colour.
			sm.albedo_color = _surf_base_albedo[i].lerp(
				_lit_color(_surf_base_albedo[i]), lit * LIT_ALBEDO_MIX)
		var lm: StandardMaterial3D = _led_mats[i]
		if lm != null:
			lm.emission_energy_multiplier = lerpf(_led_base_emit[i], EMIT_LIT_LED, lit)
	_update_render_activity(animating)

func _lit_color(c: Color) -> Color:
	var h := c.h
	var s := clampf(c.s * 1.05, 0.0, 1.0)
	var v := clampf(c.v * 1.5 + 0.12, 0.0, 1.0)
	return Color.from_hsv(h, s, v, c.a)

# Redraw only while something moves. Once the press clip has ended and the flash
# has settled we render one final frame (UPDATE_ONCE self-disables) and stop —
# continuously re-rendering static 3D content is what leaked the mobile GL
# driver's heap on long sessions (see SimonWheel's note).
func _update_render_activity(animating: bool) -> void:
	if _vp == null:
		return
	if animating:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	elif _vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

# Force one redraw after something changed outside the per-frame loop (build,
# resize, a press that starts on an idle frame).
func _kick_render() -> void:
	if _vp == null:
		return
	if _vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

# Apply the equipped level-number font package (shop "SIMON" tab). Only the
# typeface and tint carry over to this device — the numeral is part of a modelled
# display here, so it keeps the display's own emissive brightness rather than the
# hub-sized glow/outline treatment SimonWheel gives it.
func _apply_num_pack() -> void:
	if _level3d == null:
		return
	var pack: Dictionary = _num_pack if (_num_pack is Dictionary) else {}

	var font: Font = null
	var fp := String(pack.get("font", ""))
	if fp != "" and ResourceLoader.exists(fp):
		var f := load(fp)
		if f is Font:
			font = f
	_level3d.font = font if font != null else _stock_font()

	var tint: Color = pack.get("color", READOUT_COLOR)
	_level3d.modulate = Color(tint.r, tint.g, tint.b) * READOUT_ENERGY
	_fit_readout()

# The readout's default typeface (see READOUT_FONT_PATH); null falls back to the
# engine font if the project's copy is ever missing.
func _stock_font() -> Font:
	if ResourceLoader.exists(READOUT_FONT_PATH):
		var f := load(READOUT_FONT_PATH)
		if f is Font:
			return f
	return null
