# Shared 3D volcano cone — the SINGLE source of truth for the "lava cone" look worn
# by BOTH the Volcano skin's wheel hub (simon_wheel.gd) and the four framing volcanos
# in its gameplay background (background_manager.gd). Keeping one mesh builder + one
# shader here is what guarantees the background cones are EXACTLY the central hub, not
# a lookalike that could drift out of sync when either is tweaked.
#
# The cone is built in LOCAL units with its foot at y = 0 and the crater bowl opening
# upward, so a caller can drop it anywhere and scale the MeshInstance3D uniformly. The
# shader reads object-space VERTEX (v_pos), so uniform scaling never distorts the lava
# pattern — pass the UNSCALED rim_y / rim_r to material() to match the mesh.
# Consumers preload this (const VolcanoCone = preload(...)) rather than relying on a
# global class_name, so there's no script load-order dependency.
extends RefCounted

# Hub proportions (wheel local units; the hub's HUB_R baseline is 0.30). These are the
# exact values simon_wheel derives for its centre cone, hoisted here as the shared spec.
const BASE_R := 0.354         # HUB_R * 1.18  — cone foot radius
const RIM_R := 0.186          # HUB_R * 0.62  — crater outer rim radius (cone top)
const H := 0.30               # cone rise above the foot
const CRATER_R := 0.12        # HUB_R * 0.40  — crater floor (lava pool) radius
const CRATER_DROP := 0.10     # how deep the crater recesses below the rim

static var _shader: Shader

# Low, wide volcano cone with a recessed lava crater; foot at y = 0. A ring of quads
# sweeps the outer slope (foot -> crater rim), drops a short inner wall to a small
# crater floor (the lava pool), then caps the floor. Verbatim of the wheel hub's
# _volcano_mesh, parameterised so both callers share one builder.
static func build_mesh(base_r := BASE_R, rim_r := RIM_R, h := H,
		crater_r := CRATER_R, crater_drop := CRATER_DROP, steps := 64) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim_y := h
	var floor_y := h - crater_drop
	for j in steps:
		var a0: float = TAU * float(j) / steps
		var a1: float = TAU * float(j + 1) / steps
		# outer slope: foot (base radius, y=0) up to the crater rim
		var s00 := Vector3(cos(a0) * base_r, 0.0, sin(a0) * base_r)
		var s10 := Vector3(cos(a1) * base_r, 0.0, sin(a1) * base_r)
		var s11 := Vector3(cos(a1) * rim_r, rim_y, sin(a1) * rim_r)
		var s01 := Vector3(cos(a0) * rim_r, rim_y, sin(a0) * rim_r)
		var ns := (s10 - s00).cross(s01 - s00).normalized()
		if ns.y < 0.0:
			ns = -ns
		_quad(st, s00, s10, s11, s01, ns)
		# inner crater wall: rim down to the crater floor (faces inward/up)
		var w11 := Vector3(cos(a1) * crater_r, floor_y, sin(a1) * crater_r)
		var w01 := Vector3(cos(a0) * crater_r, floor_y, sin(a0) * crater_r)
		var nw := (s11 - s01).cross(w01 - s01).normalized()
		if nw.y < 0.0:
			nw = -nw
		_quad(st, s01, s11, w11, w01, nw)
		# crater floor (lava pool), facing straight up
		var c := Vector3(0.0, floor_y, 0.0)
		_quad(st, w01, w11, c, c, Vector3.UP)
	return st.commit()

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)
	for v in [a, c, d]:
		st.set_normal(n)
		st.add_vertex(v)

# The lava-cone shader, compiled once and shared by every cone (hub + background).
static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader

# Fresh ShaderMaterial on the shared shader. Pass the UNSCALED rim height / radius that
# the mesh was built with (defaults match build_mesh) so the lava bands line up.
static func material(rim_y := H, rim_r := RIM_R) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.set_shader_parameter("rim_y", rim_y)
	m.set_shader_parameter("rim_r", rim_r)
	return m

# Volcano cone shader: dark basalt rock with bright lava rivulets that flow DOWNHILL
# from the crater, and a molten, pooling crater floor. The lava channels are vertical
# ridged-noise veins whose sampling Y scrolls with TIME so the hot rock appears to
# creep down the slope; emission is strongest at the top and fades downward.
const SHADER_CODE := "
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
