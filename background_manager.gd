extends Node

# Renders the user's equipped theme background as a single global full-screen
# layer beneath every other UI. Sits at CanvasLayer layer = -1, so the default
# ScreenCanvas (layer 1) draws over it. When the selected theme is "default"
# the layer is transparent and per-screen backgrounds show through unchanged;
# when it's a purchased theme, every screen checks `is_themed()` and skips
# building its own shader background, letting this global one take over.
#
# Also exposes `make_preview(theme_id, size)` so shop_screen.gd can render
# small previews of each theme tile without re-typing the shader code.

# Gradient (Perlin-style) value noise with quintic smoothing + domain warping.
# This is what gives the premium themes their smooth, organic, NON-pixelized look
# (the old value-noise versions read blocky). Shared verbatim by both shaders.
const _NOISE_GLSL := "
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453) * 2.0 - 1.0;
}
float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float b = dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.5 + 0.5;
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) { v += a * gnoise(p); p = p * 2.0 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}
"

const _SKYBOUND_SHADER := "
shader_type canvas_item;
uniform float aspect = 1.78;
" + _NOISE_GLSL + "
void fragment() {
	vec2 uv = UV;
	// rich, smoothly-banded sky gradient
	vec3 sky_top = vec3(0.21, 0.44, 0.80);
	vec3 sky_mid = vec3(0.42, 0.64, 0.92);
	vec3 sky_low = vec3(0.80, 0.87, 0.97);
	vec3 col = mix(sky_top, sky_mid, smoothstep(0.0, 0.55, uv.y));
	col = mix(col, sky_low, smoothstep(0.55, 1.0, uv.y));
	// warm sun bloom, upper-right
	vec2 sun = vec2(0.76, 0.20);
	float sd = distance(vec2(uv.x * aspect, uv.y), vec2(sun.x * aspect, sun.y));
	col += vec3(1.0, 0.93, 0.78) * smoothstep(0.55, 0.0, sd) * 0.45;
	// domain-warped clouds: warp the sample coords by another fbm so the shapes
	// are billowy and organic instead of a blocky lattice.
	vec2 q = vec2(uv.x * aspect, uv.y) * 2.2;
	vec2 warp = vec2(fbm(q + vec2(TIME * 0.020, 0.0)),
					 fbm(q + vec2(4.3, 1.7) - vec2(TIME * 0.015, 0.0)));
	float c1 = fbm(q + warp * 1.4 + vec2(TIME * 0.018, 0.0));
	float clouds = smoothstep(0.50, 0.92, c1);
	// soft self-shadowing gives the clouds volume
	float shade = smoothstep(0.45, 0.85, fbm(q * 1.6 + warp));
	vec3 cloud_col = mix(vec3(0.64, 0.71, 0.84), vec3(1.0, 1.0, 1.0), clouds);
	cloud_col = mix(cloud_col, cloud_col * 0.82, shade * 0.5);
	col = mix(col, cloud_col, clouds * 0.95);
	// gentle vignette so the frame settles
	vec2 p = (uv - vec2(0.5)) * vec2(aspect, 1.0);
	col *= mix(0.82, 1.0, smoothstep(1.2, 0.2, length(p)));
	COLOR = vec4(col, 1.0);
}
"

const _INFERNO_SHADER := "
shader_type canvas_item;
uniform float aspect = 1.78;
" + _NOISE_GLSL + "
void fragment() {
	vec2 uv = UV;
	// near-black void
	vec3 col = vec3(0.015, 0.006, 0.022);
	// fire rises from the bottom — sample warped noise scrolling upward so the
	// flames are smooth, licking tongues rather than a noisy blocky field.
	vec2 q = vec2(uv.x * aspect * 1.8, (1.0 - uv.y) * 2.4);
	vec2 warp = vec2(fbm(q * 1.3 + vec2(0.0, TIME * 0.50)),
					 fbm(q * 1.3 + vec2(3.1, TIME * 0.40)));
	float n = fbm(q + warp * 1.5 + vec2(0.0, TIME * 0.60));
	float heat = pow(clamp(1.0 - uv.y, 0.0, 1.0), 1.3);
	float flame = clamp(n * heat * 1.7 - 0.18, 0.0, 1.0);
	// color ladder: deep purple base -> magenta -> red -> orange -> yellow core
	vec3 c1 = vec3(0.12, 0.02, 0.20);
	vec3 c2 = vec3(0.62, 0.09, 0.36);
	vec3 c3 = vec3(0.96, 0.24, 0.10);
	vec3 c4 = vec3(1.00, 0.62, 0.12);
	vec3 c5 = vec3(1.00, 0.94, 0.62);
	vec3 fc = c1;
	fc = mix(fc, c2, smoothstep(0.04, 0.32, flame));
	fc = mix(fc, c3, smoothstep(0.26, 0.56, flame));
	fc = mix(fc, c4, smoothstep(0.52, 0.80, flame));
	fc = mix(fc, c5, smoothstep(0.80, 0.97, flame));
	col = mix(col, fc, smoothstep(0.0, 0.26, flame));
	// glowing embers — small high-frequency hot spots, biased to the bottom half
	float emb = fbm(q * 3.0 + vec2(0.0, TIME * 1.10));
	col += vec3(1.0, 0.60, 0.20) * smoothstep(0.82, 0.98, emb) * heat * 0.70;
	// a soft top-edge vignette so the fire sits in a darker frame
	col *= mix(0.50, 1.0, smoothstep(0.0, 0.50, 1.0 - uv.y));
	vec2 p = (uv - vec2(0.5)) * vec2(aspect, 1.0);
	col *= mix(0.70, 1.0, smoothstep(1.2, 0.25, length(p)));
	COLOR = vec4(col, 1.0);
}
"

# Basic static-gradient themes (150 coins each). Each entry drives the shared
# elegant-gradient shader built in _gradient_shader: a smooth vertical gradient +
# a soft off-centre glow + a gentle vignette. Keys map to ids in CoinsManager.THEMES.
#   top/bot  vertical gradient endpoints
#   glow     colour of the soft radial glow, placed at (gx, gy) in UV space
#   gs       glow strength
const _GRADIENTS := {
	"midnight": {"top": Color(0.05, 0.09, 0.19), "bot": Color(0.01, 0.02, 0.06),
		"glow": Color(0.10, 0.22, 0.48), "gx": 0.5, "gy": 0.30, "gs": 0.55},
	"indigo":   {"top": Color(0.12, 0.07, 0.24), "bot": Color(0.03, 0.02, 0.09),
		"glow": Color(0.36, 0.20, 0.58), "gx": 0.5, "gy": 0.34, "gs": 0.55},
	"sunset":   {"top": Color(0.13, 0.06, 0.20), "bot": Color(0.42, 0.16, 0.13),
		"glow": Color(0.97, 0.50, 0.22), "gx": 0.5, "gy": 0.92, "gs": 0.40},
	"forest":   {"top": Color(0.03, 0.12, 0.10), "bot": Color(0.01, 0.04, 0.04),
		"glow": Color(0.10, 0.38, 0.27), "gx": 0.5, "gy": 0.32, "gs": 0.50},
	"crimson":  {"top": Color(0.18, 0.04, 0.07), "bot": Color(0.05, 0.01, 0.03),
		"glow": Color(0.58, 0.11, 0.20), "gx": 0.5, "gy": 0.30, "gs": 0.45},
	"slate":    {"top": Color(0.15, 0.17, 0.21), "bot": Color(0.05, 0.06, 0.09),
		"glow": Color(0.26, 0.32, 0.40), "gx": 0.5, "gy": 0.30, "gs": 0.50},
}

const _SHADERS := {
	"skybound": _SKYBOUND_SHADER,
	"inferno": _INFERNO_SHADER,
}

# Whether a theme id is renderable by this manager (animated shader OR gradient).
func _has_theme(theme_id: String) -> bool:
	return _SHADERS.has(theme_id) or _GRADIENTS.has(theme_id)

# Build the GLSL for an elegant static-gradient theme from a _GRADIENTS entry.
func _gradient_shader(def: Dictionary) -> String:
	var top: Color = def["top"]
	var bot: Color = def["bot"]
	var glow: Color = def["glow"]
	return "shader_type canvas_item;\n" + \
		"uniform float aspect = 1.78;\n" + \
		"void fragment() {\n" + \
		"	vec2 uv = UV;\n" + \
		"	vec3 top = vec3(%.4f, %.4f, %.4f);\n" % [top.r, top.g, top.b] + \
		"	vec3 bot = vec3(%.4f, %.4f, %.4f);\n" % [bot.r, bot.g, bot.b] + \
		"	vec3 glow = vec3(%.4f, %.4f, %.4f);\n" % [glow.r, glow.g, glow.b] + \
		"	vec3 col = mix(top, bot, smoothstep(0.0, 1.0, uv.y));\n" + \
		"	vec2 g = vec2((uv.x - %.3f) * aspect, uv.y - %.3f);\n" % [float(def["gx"]), float(def["gy"])] + \
		"	col += glow * smoothstep(0.85, 0.0, length(g)) * %.3f;\n" % [float(def["gs"])] + \
		"	vec2 p = (uv - vec2(0.5)) * vec2(aspect, 1.0);\n" + \
		"	col *= mix(0.66, 1.0, smoothstep(1.15, 0.2, length(p)));\n" + \
		"	COLOR = vec4(col, 1.0);\n" + \
		"}\n"

var _layer: CanvasLayer
var _bg: ColorRect
var _mat: ShaderMaterial
var _cache: Dictionary = {}     # theme_id -> Shader
# Themes are only painted on the gameplay screen now (every other screen wears
# its own bespoke background). GameManager flips this on/off as it swaps screens,
# BEFORE the incoming screen builds, so is_themed() is already correct in _ready().
var _active := false

func _ready() -> void:
	_build_layer()
	CoinsManager.themes_changed.connect(_on_themes_changed)
	get_tree().root.size_changed.connect(_fit_to_viewport)
	_apply_theme()

# Called by GameManager on every screen swap: true only for the gameplay screen.
func set_active(on: bool) -> void:
	if _active == on:
		return
	_active = on
	_apply_theme()

# Whether a non-default theme is currently equipped AND should be painted on the
# current screen. Screens read this in their _ready() to decide whether to skip
# their own per-screen background. Only true on the gameplay screen.
func is_themed() -> bool:
	return _active and CoinsManager.selected_theme != CoinsManager.DEFAULT_THEME

# Build a small ColorRect rendering the theme at the requested size, for use
# as a preview tile in the shop. For "default", returns a dark fallback rect.
func make_preview(theme_id: String, size: Vector2) -> Control:
	var rect := ColorRect.new()
	rect.custom_minimum_size = size
	rect.size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if theme_id == CoinsManager.DEFAULT_THEME or not _has_theme(theme_id):
		# Stock look: subtle dark gradient (no shader) so default still feels
		# distinct from "empty slot".
		rect.color = Color(0.10, 0.14, 0.28)
		return rect
	rect.color = Color(1, 1, 1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = _get_shader(theme_id)
	mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))
	rect.material = mat
	return rect

func _get_shader(theme_id: String) -> Shader:
	if _cache.has(theme_id):
		return _cache[theme_id]
	var sh := Shader.new()
	if _SHADERS.has(theme_id):
		sh.code = _SHADERS[theme_id]
	else:
		sh.code = _gradient_shader(_GRADIENTS[theme_id])
	_cache[theme_id] = sh
	return sh

func _build_layer() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = -1                                       # below ScreenCanvas (layer 1)
	add_child(_layer)
	_bg = ColorRect.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.color = Color(0, 0, 0, 0)
	_layer.add_child(_bg)
	_mat = ShaderMaterial.new()
	_fit_to_viewport()

func _fit_to_viewport() -> void:
	var sz := get_viewport().get_visible_rect().size
	if _bg:
		_bg.position = Vector2.ZERO
		_bg.size = sz
	if _mat:
		_mat.set_shader_parameter("aspect", sz.x / maxf(1.0, sz.y))

func _on_themes_changed() -> void:
	_apply_theme()

func _apply_theme() -> void:
	var t: String = CoinsManager.selected_theme
	if not _active or t == CoinsManager.DEFAULT_THEME or not _has_theme(t):
		_bg.material = null
		_bg.color = Color(0, 0, 0, 0)                       # fully transparent
		return
	_mat.shader = _get_shader(t)
	_bg.material = _mat
	_bg.color = Color(1, 1, 1, 1)                           # opaque so shader fills
	_fit_to_viewport()
