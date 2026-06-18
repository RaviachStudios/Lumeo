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

const _SKYBOUND_SHADER := "
shader_type canvas_item;
uniform float aspect = 1.78;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.0; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 uv = UV;
	vec3 sky_top = vec3(0.36, 0.63, 0.96);
	vec3 sky_bot = vec3(0.20, 0.45, 0.86);
	vec3 col = mix(sky_top, sky_bot, uv.y);
	// soft white horizon haze
	col = mix(col, vec3(0.95, 0.97, 1.0), smoothstep(0.55, 1.0, uv.y) * 0.18);
	// two cloud layers, slowly drifting at different speeds
	vec2 p1 = vec2(uv.x * aspect, uv.y) * 2.6 + vec2(TIME * 0.020, 0.0);
	float c1 = fbm(p1);
	float clouds1 = smoothstep(0.48, 0.78, c1);
	vec2 p2 = vec2(uv.x * aspect, uv.y) * 5.4 + vec2(TIME * 0.045, -0.05);
	float c2 = fbm(p2);
	float clouds2 = smoothstep(0.55, 0.85, c2) * 0.6;
	// soft shadow on the underside of clouds
	vec3 cloud_col = mix(vec3(0.82, 0.88, 0.98), vec3(1.0), uv.y * 0.6 + 0.4);
	col = mix(col, cloud_col, clamp(clouds1 + clouds2, 0.0, 1.0) * 0.92);
	// gentle top-of-frame highlight, sun-ish
	col += vec3(1.0, 0.96, 0.85) * smoothstep(0.55, 0.0, distance(uv, vec2(0.78, 0.18))) * 0.25;
	COLOR = vec4(col, 1.0);
}
"

const _INFERNO_SHADER := "
shader_type canvas_item;
uniform float aspect = 1.78;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.0; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 uv = UV;
	// near-black void
	vec3 col = vec3(0.012, 0.005, 0.020);
	// fire rises from the bottom — sample noise with a downward-moving offset
	vec2 p = vec2(uv.x * aspect * 2.2, (1.0 - uv.y) * 2.6);
	p.y -= TIME * 0.55;
	float n = fbm(p);
	n += fbm(p * 2.0) * 0.45;
	float heat = pow(clamp(1.0 - uv.y, 0.0, 1.0), 1.4);
	float flame = clamp(n * heat * 1.55 - 0.20, 0.0, 1.0);
	// color ladder: deep purple base -> magenta -> red -> orange -> yellow core
	vec3 c1 = vec3(0.10, 0.02, 0.18);
	vec3 c2 = vec3(0.60, 0.10, 0.40);
	vec3 c3 = vec3(0.95, 0.22, 0.12);
	vec3 c4 = vec3(1.00, 0.62, 0.10);
	vec3 c5 = vec3(1.00, 0.95, 0.55);
	vec3 fc = c1;
	fc = mix(fc, c2, smoothstep(0.05, 0.30, flame));
	fc = mix(fc, c3, smoothstep(0.25, 0.55, flame));
	fc = mix(fc, c4, smoothstep(0.50, 0.78, flame));
	fc = mix(fc, c5, smoothstep(0.78, 0.96, flame));
	col = mix(col, fc, smoothstep(0.0, 0.28, flame));
	// glowing embers — small high-frequency hot spots, biased to the bottom half
	float emb = fbm(p * 5.5 + vec2(0.0, TIME * 0.9));
	col += vec3(1.0, 0.62, 0.20) * smoothstep(0.84, 0.97, emb) * heat * 0.85;
	// a soft top-edge vignette so the fire sits in a darker frame
	col *= mix(0.55, 1.0, smoothstep(0.0, 0.45, 1.0 - uv.y));
	COLOR = vec4(col, 1.0);
}
"

const _SHADERS := {
	"skybound": _SKYBOUND_SHADER,
	"inferno": _INFERNO_SHADER,
}

var _layer: CanvasLayer
var _bg: ColorRect
var _mat: ShaderMaterial
var _cache: Dictionary = {}     # theme_id -> Shader

func _ready() -> void:
	_build_layer()
	CoinsManager.themes_changed.connect(_on_themes_changed)
	get_tree().root.size_changed.connect(_fit_to_viewport)
	_apply_theme()

# Whether a non-default theme is currently equipped. Screens read this in
# their _ready() to decide whether to skip their own per-screen background.
func is_themed() -> bool:
	return CoinsManager.selected_theme != CoinsManager.DEFAULT_THEME

# Build a small ColorRect rendering the theme at the requested size, for use
# as a preview tile in the shop. For "default", returns a dark fallback rect.
func make_preview(theme_id: String, size: Vector2) -> Control:
	var rect := ColorRect.new()
	rect.custom_minimum_size = size
	rect.size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if theme_id == CoinsManager.DEFAULT_THEME or not _SHADERS.has(theme_id):
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
	sh.code = _SHADERS[theme_id]
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
	if t == CoinsManager.DEFAULT_THEME or not _SHADERS.has(t):
		_bg.material = null
		_bg.color = Color(0, 0, 0, 0)                       # fully transparent
		return
	_mat.shader = _get_shader(t)
	_bg.material = _mat
	_bg.color = Color(1, 1, 1, 1)                           # opaque so shader fills
	_fit_to_viewport()
