extends RefCounted
class_name ButtonFrames

# Cosmetic BUTTON FRAMES for the modelled boards — the bezel that rings each
# coloured button on Medium's five-button board and Hard's six.
#
# The eighteen frames are real Blender-authored MESHES, shipped in
# res://models/Button_Frame_Cosmetics.glb. Nothing here is procedural: this file
# is the catalog, the loader, and the small amount of material work Godot has to do
# because glTF cannot carry the idle animation the frames were authored with.
#
# Fifteen of them are shop cosmetics the player buys and equips. The other three are
# SKIN FRAMES: one each for the Arcade, Jackpot and Luna Park Special Skins, worn
# automatically while that skin is the active look and never sold, owned or equipped.
# They are the same kind of object in every other respect — same library, same
# silhouette, same three surfaces, same idle — so they live in the same catalog and
# go through the same loader. See SKIN_FRAMES / effective_frame for the priority.
#
# ---------------------------------------------------------------------------
# How a cosmetic is worn
# ---------------------------------------------------------------------------
# It is NOT a material swap. Each frame is a separate solid with
# its own profile (24% narrower than the stock housing, and undercut at the base),
# so wearing one means showing that mesh and hiding the stock one:
#
#   * a `Cosmetic_Frame` MeshInstance3D is added under `Button_<Colour>` at the
#     IDENTITY transform — the GLB authors every frame at the origin with
#     transforms applied, and the stock `Button_<Colour>_Frame` sits at identity
#     under the same parent, so the two occupy exactly the same place with no
#     measuring and no per-board or per-difficulty fudge;
#   * the stock frame's surface 0 (the black metal) is covered with an invisible
#     material rather than the whole MeshInstance3D being hidden, because its
#     surface 1 is the button's UNDER-GLOW — the lit pool inside the bore that the
#     emission state machine drives. Hiding the node would take the glow with it.
#     The under-glow lives at r <= 0.698, well inside the cosmetic's r >= 0.766
#     opening, so it stays completely visible through the new bezel.
#
# "default" is the absence of all of that: the cosmetic node is freed and the
# override cleared, and the GLB's own `Mat_<Colour>_Frame` comes straight back.
#
# The press clips animate the SURFACE mesh only — the cosmetic is not in any clip
# and is not a child of anything that moves, so it is stationary through a press by
# construction, exactly like the stock frame it replaces.
#
# ---------------------------------------------------------------------------
# Fit (measured, from the asset's own README)
# ---------------------------------------------------------------------------
#   outer diameter 1.920 (r 0.960)   height 0.300 (y 0.000 -> 0.300)
#   inner opening  r >= 0.766, and r >= 0.782 across the button's own z-range
#   button surface max r 0.745, y 0.245 -> 0.525, press travel 0.115
# => at least 0.037 of radial clearance at every height the button can reach, on
# every board. All eighteen share one origin, rotation, scale and silhouette — the
# three skin frames are the same lathe as the other fifteen and differ only in their
# materials — so a cosmetic that fits one button fits all of them and no frame is
# ever rescaled. frame_flow_test measures this against the real meshes.
#
# ---------------------------------------------------------------------------
# Why the imported materials are rebuilt as one shader
# ---------------------------------------------------------------------------
# Two reasons, both structural:
#
# 1. THE IDLE. glTF animates node transforms and morph weights only, so the 6 s
#    material loop authored in Blender does not survive the export. It is
#    reproduced here as `S(t) = S0 * (1 + a*cos(TAU*t/6 + phase))` on the emission,
#    plus a UV drift applied to the EMISSIVE sampler alone. That last part is the
#    reason a StandardMaterial3D cannot do it: `uv1_offset` moves every sampler at
#    once, which would drag the zebra's stripes and the circuit's traces around the
#    ring. Drifting only the emissive leaves the pattern stationary and moves the
#    light through it, which is what the asset was authored to do.
#
# 2. EMISSIVE STRENGTH. `KHR_materials_emissive_strength` is imported into
#    `emission_energy_multiplier`, and in GL Compatibility that multiplier scales
#    the emission colour in sRGB before converting to linear — so a strength of 3.2
#    renders about 17x the light, not 3.2x, and every neon in this set clips to
#    white. Multiplying in the shader (`emis_col` under `source_color`, times a
#    plain float) is a linear multiply and reproduces Blender's authored level.
#
# The geometry is never touched by any of this: the idle is emission and UV only.
#
# ---------------------------------------------------------------------------
# Memory
# ---------------------------------------------------------------------------
# The library is loaded on demand and only the frames actually asked for are kept.
# `build()` pulls ONE frame's mesh out of a throwaway instance of the GLB and drops
# the PackedScene, so the other seventeen meshes and their textures are collected;
# `trim_cache()` then releases everything but the ids named. Gameplay keeps exactly
# one entry (the equipped frame) and shares its mesh and its three materials across
# all of the board's buttons, so Medium costs 5 MeshInstance3D + 1 Mesh + 3
# ShaderMaterials + 1 Shader, and Hard the same with six.

const DEFAULT_ID := "default"

# The node name a worn cosmetic goes by, under `Button_<Colour>`.
const INSTANCE_NAME := "Cosmetic_Frame"

# The Blender library. Authoritative for geometry AND materials — nothing in this
# file recreates or edits either.
const LIBRARY_PATH := "res://models/Button_Frame_Cosmetics.glb"

# How hard the painted Fresnel sheen runs, and the roughness it has faded out by.
# See the note in the shader: this exists because the board's studio is too dark for
# a mirror to reflect anything, not as a stylistic choice.
const SHEEN_MAX := 0.90
const SHEEN_ROUGH_CUTOFF := 0.25

# The idle loop, in seconds. The asset is authored at 30 fps over frames 1..180 and
# is seamless (frame 181 is frame 1 exactly), so 6.0 is not a taste value.
const CYCLE := 6.0

# The narrowest point of every frame's inner opening, from the asset's README. The
# button surface it has to clear tops out at r = 0.745 on both boards, so this is
# the number the fit rests on; the acceptance test asserts it against the real
# meshes rather than trusting it.
const INNER_OPENING_R := 0.766

# ---------------------------------------------------------------------------
# The catalog
# ---------------------------------------------------------------------------
# `node` is the object name in the GLB. `accent`/`glow` are the 2D colours the shop
# card wears (border + drop shadow) so each card reads as the frame it previews.
#
# `anim` is one entry per MESH SURFACE, in the GLB's own slot order —
# [0] Body (90% of the area), [1] Accent (the cut channel), [2] Trim (the raised
# lip) — each `[amplitude, phase, drift]`:
#   amplitude  the +-fraction the emission breathes by (0.10..0.18 as authored)
#   phase      radians, different per frame so no two frames pulse together
#   drift      how far the EMISSIVE sampler's u advances over one 6 s loop. It is
#              always exactly one pattern period (0.50 for most, 0.25 for Circuit,
#              1/3 for Holographic and Volcanic), which is why the pattern appears
#              to stand still and only the hot-spots travel. 0 = no drift at all.
const FRAMES := {
	"default": {
		"name": "Default", "price": 0, "blurb": "Smooth black metal.",
		"accent": Color(0.60, 0.64, 0.76), "glow": Color(0.24, 0.28, 0.40),
	},
	# --- 01-05 neon: a dark chassis with a lit channel. Breathing only. ---
	"purple_neon": {
		"name": "Purple Neon", "price": 0, "blurb": "Lit from the inside.",
		"node": "Frame_01_PurpleNeon",
		"accent": Color(0.70, 0.32, 1.00), "glow": Color(0.44, 0.08, 0.96),
		"anim": [[0.00, 0.00, 0.00], [0.14, 0.00, 0.00], [0.08, 2.10, 0.00]],
	},
	"cyan_neon": {
		"name": "Cyan Neon", "price": 0, "blurb": "Cold light in a groove.",
		"node": "Frame_02_CyanNeon",
		"accent": Color(0.30, 0.90, 1.00), "glow": Color(0.05, 0.62, 0.90),
		"anim": [[0.00, 0.00, 0.00], [0.14, 0.83, 0.00], [0.08, 2.93, 0.00]],
	},
	"magenta_neon": {
		"name": "Magenta Neon", "price": 0, "blurb": "Loud, in one colour.",
		"node": "Frame_03_MagentaNeon",
		"accent": Color(1.00, 0.30, 0.80), "glow": Color(0.88, 0.05, 0.55),
		"anim": [[0.00, 0.00, 0.00], [0.15, 1.66, 0.00], [0.08, 3.76, 0.00]],
	},
	"electric_blue": {
		"name": "Electric Blue", "price": 0, "blurb": "Straight off the mains.",
		"node": "Frame_04_ElectricBlue",
		"accent": Color(0.36, 0.62, 1.00), "glow": Color(0.10, 0.32, 1.00),
		"anim": [[0.00, 0.00, 0.00], [0.16, 2.49, 0.00], [0.08, 4.59, 0.00]],
	},
	"emerald_neon": {
		"name": "Emerald Neon", "price": 0, "blurb": "Green, and expensive.",
		"node": "Frame_05_EmeraldNeon",
		"accent": Color(0.24, 1.00, 0.66), "glow": Color(0.02, 0.72, 0.44),
		"anim": [[0.00, 0.00, 0.00], [0.14, 3.32, 0.00], [0.08, 5.42, 0.00]],
	},
	# --- 06-08 polished metal: no neon, just a highlight walking the trim. ---
	"golden_chrome": {
		"name": "Golden Chrome", "price": 0, "blurb": "Mirror-polished gold.",
		"node": "Frame_06_GoldenChrome",
		"accent": Color(1.00, 0.86, 0.46), "glow": Color(0.82, 0.56, 0.10),
		"anim": [[0.00, 0.00, 0.00], [0.06, 4.15, 0.50], [0.06, 5.15, 0.50]],
	},
	"rose_gold": {
		"name": "Rose Gold", "price": 0, "blurb": "Warm metal, quiet finish.",
		"node": "Frame_07_RoseGold",
		"accent": Color(1.00, 0.78, 0.72), "glow": Color(0.86, 0.44, 0.42),
		"anim": [[0.00, 0.00, 0.00], [0.06, 4.98, 0.50], [0.06, 5.98, 0.50]],
	},
	"obsidian_chrome": {
		"name": "Obsidian Chrome", "price": 0, "blurb": "Black, and very shiny.",
		"node": "Frame_08_ObsidianChrome",
		"accent": Color(0.72, 0.76, 0.86), "glow": Color(0.24, 0.26, 0.36),
		"anim": [[0.00, 0.00, 0.00], [0.06, 5.81, 0.50], [0.06, 0.53, 0.50]],
	},
	# --- 09/10 hides: the stripes hold still, two accents shimmer. ---
	"zebra_glow": {
		"name": "Zebra Glow", "price": 0, "blurb": "Wild, in monochrome.",
		"node": "Frame_09_ZebraGlow",
		"accent": Color(0.94, 0.95, 1.00), "glow": Color(0.52, 0.66, 0.95),
		"anim": [[0.12, 0.36, 0.00], [0.12, 1.16, 0.00], [0.06, 2.06, 0.00]],
	},
	"tiger_glow": {
		"name": "Tiger Glow", "price": 0, "blurb": "Molten stripes.",
		"node": "Frame_10_TigerGlow",
		"accent": Color(1.00, 0.62, 0.18), "glow": Color(1.00, 0.36, 0.04),
		"anim": [[0.12, 1.19, 0.00], [0.12, 1.99, 0.00], [0.06, 2.89, 0.00]],
	},
	# --- 11-15 patterned: the light travels, the pattern does not. ---
	"aurora": {
		"name": "Aurora", "price": 0, "blurb": "Slow colour, moving.",
		"node": "Frame_11_Aurora",
		"accent": Color(0.56, 0.92, 0.86), "glow": Color(0.34, 0.42, 0.96),
		"anim": [[0.00, 0.00, 0.00], [0.13, 2.02, 0.50], [0.08, 3.42, 0.00]],
	},
	"circuit": {
		"name": "Circuit", "price": 0, "blurb": "Pulses down the traces.",
		"node": "Frame_12_Circuit",
		"accent": Color(0.30, 0.94, 0.86), "glow": Color(0.06, 0.60, 0.66),
		"anim": [[0.10, 2.85, 0.25], [0.12, 3.45, 0.25], [0.06, 4.75, 0.00]],
	},
	"holographic": {
		"name": "Holographic", "price": 0, "blurb": "Every colour, faintly.",
		"node": "Frame_13_Holographic",
		"accent": Color(0.86, 0.80, 1.00), "glow": Color(0.52, 0.72, 1.00),
		"anim": [[0.08, 3.68, 0.3333], [0.10, 4.38, 0.3333], [0.07, 5.18, 0.3333]],
	},
	"arctic_glow": {
		"name": "Arctic Glow", "price": 0, "blurb": "Cold shimmer on ice.",
		"node": "Frame_14_ArcticGlow",
		"accent": Color(0.78, 0.94, 1.00), "glow": Color(0.34, 0.68, 0.94),
		"anim": [[0.10, 4.51, 0.50], [0.12, 5.41, 0.50], [0.07, 0.14, 0.50]],
	},
	"volcanic_glow": {
		"name": "Volcanic Glow", "price": 0, "blurb": "Fire under the crust.",
		"node": "Frame_15_VolcanicGlow",
		"accent": Color(1.00, 0.52, 0.16), "glow": Color(0.86, 0.16, 0.02),
		"anim": [[0.14, 5.34, 0.3333], [0.13, 0.14, 0.3333], [0.08, 1.44, 0.00]],
	},
	# --- 16-18 SKIN FRAMES: not sold, not owned, not equippable. Each one belongs to
	# one Special Skin and is worn automatically while that skin is active (see
	# SKIN_FRAMES / effective_frame). They are in this table because they are frames
	# in every other respect — same library, same mesh, same three surfaces, same
	# idle — and duplicating the loader for them would be three systems where the
	# brief asked for one. `skin` is what keeps them out of the storefront.
	"skin_arcade": {
		"name": "Arcade Cabinet", "price": 0, "skin": "arcade",
		"blurb": "Cabinet steel and marquee neon.",
		"node": "Frame_16_ArcadeCabinet",
		"accent": Color(0.30, 0.92, 1.00), "glow": Color(0.86, 0.10, 0.66),
		# the chassis breathes in place (its louvres and ticks are too fine to drift
		# without smearing); the marquee lamps march one cyan/magenta PAIR per loop,
		# which is exactly the 1/8 their pattern repeats on
		"anim": [[0.10, 0.62, 0.00], [0.16, 1.45, 0.125], [0.09, 2.60, 0.00]],
	},
	"skin_casino": {
		"name": "House Gold", "price": 0, "skin": "casino",
		"blurb": "Engraved brass and oxblood.",
		"node": "Frame_17_CasinoGold",
		"accent": Color(1.00, 0.84, 0.42), "glow": Color(0.62, 0.06, 0.10),
		# the gold body carries no light at all — the movement is one highlight
		# walking the channel and another walking the polished lip, half a turn each
		"anim": [[0.00, 0.00, 0.00], [0.09, 3.10, 0.50], [0.07, 4.20, 0.50]],
	},
	"skin_lunapark": {
		"name": "Fairground Lights", "price": 0, "skin": "lunapark",
		"blurb": "Twenty-four bulbs, chasing.",
		"node": "Frame_18_LunaCarnival",
		"accent": Color(1.00, 0.86, 0.62), "glow": Color(1.00, 0.52, 0.22),
		# the canopy glows on the spot; the bulbs' light walks six sockets a loop
		# (one quarter of twenty-four), which is what makes it a chase and not a hum
		"anim": [[0.08, 5.05, 0.00], [0.10, 0.35, 0.25], [0.07, 1.90, 0.00]],
	},
}

# Special Skin id -> the frame that skin brings with it. A skin's own frame OUTRANKS
# whatever the player has equipped, for as long as that skin is the active look; take
# the skin off and the equipped frame comes straight back (see effective_frame).
#
# Nothing is stored for any of this. The equipped frame in the wallet never changes,
# so there is no migration, no way to lose a purchase, and no state to get out of sync
# with `selected_skin`.
const SKIN_FRAMES := {
	"arcade": "skin_arcade",
	"casino": "skin_casino",
	"lunapark": "skin_lunapark",
}

# Display order in the shop. "default" leads so reverting is the obvious first card,
# and the fifteen follow in the library's own numbering.
const ORDER := [
	"default",
	"purple_neon", "cyan_neon", "magenta_neon", "electric_blue", "emerald_neon",
	"golden_chrome", "rose_gold", "obsidian_chrome",
	"zebra_glow", "tiger_glow",
	"aurora", "circuit", "holographic", "arctic_glow", "volcanic_glow",
]

static func has_frame(frame_id: String) -> bool:
	return FRAMES.has(frame_id)

# True for the three skin-bound frames. They are never bought, owned, equipped or
# shown in the BUTTON FRAMES tab — a wallet that somehow names one is treated as
# naming nothing, so this is what the ownership and equip paths test against.
static func is_skin_frame(frame_id: String) -> bool:
	return FRAMES.has(frame_id) and FRAMES[frame_id].has("skin")

# The frame a board should actually wear, given what the player has equipped.
#
#   a Special Skin with its own frame is active  -> that skin's frame
#   otherwise                                    -> the equipped cosmetic
#   ...and "default" is what falls out of both   -> the stock black bezel
#
# `skin_id` is the ACTIVE complete skin ("" when the player is on a manual per-part
# look or has never equipped one). Callers pass CoinsManager's resolution of that
# rather than reading it here, so this file stays free of autoload dependencies and
# stays testable on its own.
static func effective_frame(equipped: String, skin_id: String) -> String:
	if SKIN_FRAMES.has(skin_id):
		return String(SKIN_FRAMES[skin_id])
	return equipped if FRAMES.has(equipped) and not is_skin_frame(equipped) else DEFAULT_ID

# The frame `skin_id` brings with it, or "" if that skin has none.
static func frame_for_skin(skin_id: String) -> String:
	return String(SKIN_FRAMES.get(skin_id, ""))

# True for everything except "default" that actually has a mesh behind it in the
# library — the fifteen shop frames and the three skin frames alike.
static func is_cosmetic(frame_id: String) -> bool:
	return FRAMES.has(frame_id) and FRAMES[frame_id].has("node")

static func frame_name(frame_id: String) -> String:
	return String(FRAMES.get(frame_id, {}).get("name", frame_id.capitalize()))

static func frame_price(frame_id: String) -> int:
	return int(FRAMES.get(frame_id, {}).get("price", 0))

static func frame_blurb(frame_id: String) -> String:
	return String(FRAMES.get(frame_id, {}).get("blurb", ""))

static func frame_accent(frame_id: String) -> Color:
	return FRAMES.get(frame_id, {}).get("accent", Color(0.6, 0.64, 0.76))

static func frame_glow(frame_id: String) -> Color:
	return FRAMES.get(frame_id, {}).get("glow", Color(0.24, 0.28, 0.40))

# ---------------------------------------------------------------------------
# The idle shader
# ---------------------------------------------------------------------------
# A plain metallic-roughness surface with the two authored idle channels folded in.
# Both samplers default to WHITE when unset, so one shader covers a material with
# textures and one without: an untextured slot is just `white * factor`.
#
# Cost per fragment: two texture fetches (the same count StandardMaterial3D would
# do) and two cosines. Nothing is added per vertex and no pass is added anywhere.
const _SHADER_SRC := """
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D emis_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform vec4 emis_col : source_color = vec4(0.0);
uniform float emis_energy = 1.0;
uniform float metal : hint_range(0.0, 1.0) = 1.0;
uniform float rough : hint_range(0.0, 1.0) = 0.3;
uniform float breathe = 0.0;     // +- fraction the emission swells by
uniform float phase = 0.0;       // radians, so no two frames pulse together
uniform float drift = 0.0;       // u advance of the EMISSIVE sampler per loop
uniform float cycle = 6.0;
uniform float sheen = 0.0;       // grazing-angle lift for POLISHED metal only

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * albedo_col.rgb;
	METALLIC = metal;
	ROUGHNESS = rough;

	// The authored breath: a fundamental plus a third of a second harmonic, which
	// is what gives it the uneven, alive feel instead of a metronome. Seamless by
	// construction — both terms have an integer number of periods in `cycle`.
	float w = TAU * TIME / cycle + phase;
	float s = 1.0 + breathe * cos(w) + 0.3 * breathe * cos(2.0 * w + 1.1);

	// ...and the drift, on the emissive sampler ONLY. The albedo keeps its own UV,
	// so the stripes/traces stay exactly where they were painted and only the light
	// inside them travels around the ring.
	vec2 euv = vec2(UV.x + fract(TIME / cycle) * drift, UV.y);
	EMISSION = texture(emis_tex, euv).rgb * emis_col.rgb * (emis_energy * s);

	// The chrome problem. A fully metallic surface has no diffuse at all, so all it
	// can show is what it reflects — and this board's studio is deliberately almost
	// black (ambient 0.13, two directional lights at 0.14), because the coloured
	// buttons are self-lit and anything brighter lifts the chassis to grey. The
	// authored near-black frames never noticed; Golden Chrome, Rose Gold and
	// Obsidian are mirrors with nothing to be a mirror OF, and rendered as mud.
	//
	// So their highlight is painted rather than lit, the same way this project draws
	// its halos instead of using the (useless) Compatibility glow pass: a Fresnel
	// lift in the metal's OWN colour, which is what a polished ring picks up off a
	// room at grazing angles. `sheen` is derived from the material's own metallic
	// and roughness and is exactly ZERO for every frame that isn't polished metal,
	// so nothing else in the set is touched by it.
	if (sheen > 0.0) {
		float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.6);
		// A flat term (the room it stands in) plus a grazing term (the bright edge a
		// polished ring always has). Fresnel alone was not enough: this frame's top
		// land faces the camera almost squarely, so a pure edge lift left the part
		// the player actually looks at as dark as before.
		EMISSION += ALBEDO * (sheen * (0.34 + 0.66 * f));
	}
}
"""

# One compiled Shader for the whole library: every material of every frame is the
# same program with different uniforms, so a frame costs zero extra compiles.
static var _shader: Shader

static func _idle_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = _SHADER_SRC
	return _shader

# The material that makes the STOCK bezel disappear while leaving the rest of its
# mesh alone. Alpha-scissor at threshold 1.0 over an alpha of 0 discards every
# fragment: no colour, no depth write, no sorting to get wrong — and, unlike hiding
# the MeshInstance3D, it leaves surface 1 (the under-glow) drawing normally.
# One shared resource for every button on every board.
static var _hidden: StandardMaterial3D

static func hidden_material() -> StandardMaterial3D:
	if _hidden == null:
		_hidden = StandardMaterial3D.new()
		_hidden.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_hidden.alpha_scissor_threshold = 1.0
		_hidden.albedo_color = Color(0, 0, 0, 0)
		_hidden.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hidden.no_depth_test = false
		_hidden.resource_name = "FrameCosmetic_HiddenStock"
	return _hidden

# ---------------------------------------------------------------------------
# The library
# ---------------------------------------------------------------------------

# frame_id -> {"mesh": Mesh, "mats": Array[ShaderMaterial]}. Populated on demand;
# see the memory note at the top for why this is not a preload of all fifteen.
static var _cache: Dictionary = {}

# The library scene, held only between the first build() of a batch and the
# trim_cache() that closes it. It has to be held for at least that long: the shop
# asks for all sixteen cards back to back, and reloading a 2.2 MB scene with 32
# textures once per card is the difference between opening the tab and hanging on
# it. It has to be RELEASED at the end, because a live PackedScene references all
# fifteen meshes and every texture in the set — which is exactly what gameplay must
# not be carrying.
static var _lib: PackedScene

# The mesh + materials for one cosmetic, loading it if this is the first ask.
# Returns an EMPTY dictionary for "default" and for anything not in the catalog —
# which is the caller's signal to put the stock bezel back.
static func build(frame_id: String) -> Dictionary:
	if not is_cosmetic(frame_id):
		return {}
	if _cache.has(frame_id):
		return _cache[frame_id]

	if _lib == null:
		_lib = load(LIBRARY_PATH)
	var ps: PackedScene = _lib
	if ps == null:
		push_warning("ButtonFrames: cannot load %s" % LIBRARY_PATH)
		return {}
	var root := ps.instantiate()
	var node_name := String(FRAMES[frame_id]["node"])
	var src := root.find_child(node_name, true, false) as MeshInstance3D
	var out: Dictionary = {}
	if src != null and src.mesh != null:
		var mesh: Mesh = src.mesh
		var anim: Array = FRAMES[frame_id].get("anim", [])
		var mats: Array[ShaderMaterial] = []
		for i in mesh.get_surface_count():
			var spec: Array = anim[i] if i < anim.size() else [0.0, 0.0, 0.0]
			mats.append(_material_for(mesh.surface_get_material(i), spec))
		out = {"mesh": mesh, "mats": mats}
		_cache[frame_id] = out
	else:
		push_warning("ButtonFrames: %s has no mesh named %s" % [frame_id, node_name])
	# Free the throwaway instance. The Mesh we kept a reference to survives; the
	# other fourteen (and their textures) go with the PackedScene, which trim_cache
	# drops as soon as the caller has finished asking.
	root.free()
	return out

# Rebuild one of the GLB's StandardMaterial3Ds as the idle shader, preserving every
# authored input exactly. `spec` is [amplitude, phase, drift].
static func _material_for(src: Material, spec: Array) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _idle_shader()
	var sm := src as StandardMaterial3D
	if sm != null:
		mat.resource_name = sm.resource_name
		mat.set_shader_parameter("albedo_tex", sm.albedo_texture)
		mat.set_shader_parameter("albedo_col", sm.albedo_color)
		mat.set_shader_parameter("metal", sm.metallic)
		mat.set_shader_parameter("rough", sm.roughness)
		if sm.emission_enabled:
			mat.set_shader_parameter("emis_tex", sm.emission_texture)
			mat.set_shader_parameter("emis_col", sm.emission)
			# A LINEAR multiply, deliberately — see the note at the top of the file.
			mat.set_shader_parameter("emis_energy", sm.emission_energy_multiplier)
		else:
			mat.set_shader_parameter("emis_col", Color(0, 0, 0, 1))
			mat.set_shader_parameter("emis_energy", 0.0)
	# Polished metal only: full strength at roughness 0, gone by 0.25. Every neon
	# body in the set sits at 0.26-0.34 and every accent strip is a dielectric, so
	# this lands on exactly the three chrome frames' bodies and the textured trims
	# that are authored as mirrors.
	if sm != null:
		mat.set_shader_parameter("sheen",
			SHEEN_MAX * sm.metallic * clampf(1.0 - sm.roughness / SHEEN_ROUGH_CUTOFF, 0.0, 1.0))
	mat.set_shader_parameter("cycle", CYCLE)
	mat.set_shader_parameter("breathe", float(spec[0]))
	mat.set_shader_parameter("phase", float(spec[1]))
	# Drift is pointless without something to drift: a slot with no emissive map is
	# a flat colour, and offsetting its UV would cost a fetch for no change at all.
	var has_emis_tex: bool = (src as StandardMaterial3D) != null \
		and (src as StandardMaterial3D).emission_texture != null
	mat.set_shader_parameter("drift", float(spec[2]) if has_emis_tex else 0.0)
	return mat

# A MeshInstance3D ready to be parented to a `Button_<Colour>` at the identity
# transform, or NULL for "default"/unknown. Every instance for a given frame shares
# one Mesh and one set of three ShaderMaterials, so the only per-button cost is the
# node itself.
static func make_frame_instance(frame_id: String) -> MeshInstance3D:
	var entry := build(frame_id)
	if entry.is_empty():
		return null
	var mi := MeshInstance3D.new()
	mi.name = INSTANCE_NAME
	mi.mesh = entry["mesh"]
	var mats: Array = entry["mats"]
	for i in mats.size():
		mi.set_surface_override_material(i, mats[i])
	# The board's lights cast no shadows and it has no GI, so neither costs anything
	# here — they are turned off so a cosmetic can never add a pass the stock bezel
	# did not have.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi

# True when this frame's idle actually moves — i.e. it is worth paying for a redraw.
# "default" and any frame authored with a flat amplitude and no drift answer false.
static func animates(frame_id: String) -> bool:
	if not is_cosmetic(frame_id):
		return false
	for spec: Array in FRAMES[frame_id].get("anim", []):
		if absf(float(spec[0])) > 0.001 or absf(float(spec[2])) > 0.001:
			return true
	return false

# Release every cached frame whose id is not in `keep`, and let go of the library
# scene itself. Gameplay calls this with just the equipped frame, so a session holds
# one cosmetic's mesh and textures and nothing else; the shop calls it as it closes,
# having legitimately needed all sixteen while it was open.
static func trim_cache(keep: Array) -> void:
	for id: String in _cache.keys():
		if not keep.has(id):
			_cache.erase(id)
	_lib = null
