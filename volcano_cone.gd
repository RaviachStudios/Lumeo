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

# Volcano cone shader: earth-brown soil rock on the slopes, with a molten, pooling
# crater floor at the top. Lava is confined to the crater bowl only — the front and
# sides of the cone read as plain brown mountainside with no lava running down them.
const SHADER_CODE := "
shader_type spatial;
render_mode cull_disabled;

uniform float rim_y = 0.30;
uniform float rim_r = 0.186;
// 0 at rest; pulsed toward 1 (then tweened back to 0) when the wheel erupts every 3
// rounds — the crater floods brighter and molten lava spills a little way down the slopes.
uniform float erupt = 0.0;
varying vec3 v_pos;

// sin-free hash (Hoskins). This runs 8x per gnoise x 5 octaves = 40x per fbm, on
// every pixel of the hub cone EVERY frame (the Volcano skin redraws the wheel
// viewport continuously). sin() is among the slowest mobile-GPU ops, so the old
// sin-based hash made the cone a per-frame bottleneck; this is pure arithmetic.
// The gradient vectors shift slightly, but the noise character/sharpness — and
// therefore the rock texture and crater look — is identical.
vec3 hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return -1.0 + 2.0 * fract((p.xxy + p.yxx) * p.zyx);
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
	// Radius from the cone axis — used to isolate the crater bowl at the top.
	float rad = length(vec2(v_pos.x, v_pos.z));

	// Earth-brown mountainside — the front/slopes are plain soil rock, no lava.
	float rock = fbm(v_pos * 9.0);
	vec3 rock_dark = vec3(0.150, 0.090, 0.050);
	vec3 rock_light = vec3(0.320, 0.200, 0.110);
	vec3 albedo = mix(rock_dark, rock_light, rock);

	// Molten pool filling the crater bowl (everything inside the rim radius) —
	// this is the ONLY lava, and it sits at the top of the cone. No streams run
	// down the slope, so the front of the mountain stays earth brown.
	float crater = smoothstep(rim_r * 1.0, rim_r * 0.55, rad);
	float bubble = 0.7 + 0.3 * sin(TIME * 2.2 + rock * 20.0);

	vec3 lava_col = vec3(1.00, 0.30, 0.04);
	vec3 hot_col = vec3(1.00, 0.78, 0.30);
	vec3 emission = mix(lava_col, hot_col, 0.6) * crater * bubble * 4.5;

	// --- ERUPTION (every 3 rounds): the crater floods and lava spills down the slopes ---
	if (erupt > 0.001) {
		// crater floor flares much brighter and boils harder while erupting
		emission += mix(lava_col, hot_col, 0.75) * crater * erupt * (0.6 + 0.4 * bubble) * 5.0;
		// molten channels running a little way DOWN the outer slope (outside the crater rim):
		// a few irregular streaks, strongest near the rim and thinning downslope.
		float ang = atan(v_pos.z, v_pos.x);
		float chan = 0.5 + 0.5 * sin(ang * 5.0 + fbm(v_pos * 6.0) * 4.0);
		float streak = smoothstep(0.5, 0.95, chan);
		float onSlope = smoothstep(rim_r * 1.02, rim_r * 1.14, rad);     // only below the crater lip
		float down = smoothstep(0.0, rim_y, v_pos.y);                    // 1 at the rim, fades toward the foot
		float slopeLava = streak * onSlope * down * erupt;
		float boil = 0.6 + 0.4 * sin(TIME * 3.0 + ang * 4.0);
		albedo = mix(albedo, vec3(0.32, 0.07, 0.02), clamp(slopeLava, 0.0, 1.0));
		emission += mix(lava_col, hot_col, 0.5) * slopeLava * boil * 5.0;
	}

	ALBEDO = albedo;
	EMISSION = emission;
	METALLIC = 0.0;
	ROUGHNESS = 0.9;
	SPECULAR = 0.05;
}
"
