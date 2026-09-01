extends RefCounted
class_name LumeWorlds

# The eight LUMEO worlds: charming, hand-built 2D scenes that the gameplay board
# stands in front of. Everything here is GLSL, authored in this project — no
# Blender, no .glb, no image assets.
#
# ---------------------------------------------------------------------------
# Why these are 2D and the other ten backgrounds are 3D
# ---------------------------------------------------------------------------
# BackgroundScenes' floors and worlds are geometry inside the board's own
# SubViewport, which sounds like the richer place to build — but that viewport
# CANNOT SEE THE SKY. Measured with tools/lume_frame.gd: every gameplay camera
# looks down 33.5 degrees through a ~25 degree vertical lens, so its top ray is
# still ~18 degrees BELOW the horizon and lands on the ground at z = -3.6 (Easy,
# 21:9) to -5.2 (Hard, 16:9). Nothing beyond that is in frame at all, and a prop
# standing at z = -4 may be 0.45 m tall before its head leaves the picture.
#
# That is exactly why the Themes1 imports are floors and the Themes2 worlds had
# to be raised onto an island. A sun, a Ferris wheel, a flock of birds or a
# button castle simply has nowhere to stand in there.
#
# BackgroundManager's canvas layer does not have that problem: it paints the
# WHOLE frame, behind a viewport that is transparent everywhere the board is not,
# so the board reads as standing in the scene and the scene keeps its sky. That
# is where the older illustrated themes (Dreamy Clouds, Coral Reef, Neon City)
# live, and these eight join them there — same catalog, same wallet, same equip.
#
# ---------------------------------------------------------------------------
# The shape of one world
# ---------------------------------------------------------------------------
# Each world is a pair of GLSL functions and nothing else:
#
#     vec3 lumeStatic(vec2 a)                    // everything that never moves
#     vec3 lumeDyn(vec3 col, vec2 a, float t)    // only what does
#     vec3 lumeHaze()                            // its own air, for the grade
#
# BackgroundManager wraps that pair three ways (W_STATIC / W_DYN / W_FULL below)
# to get the three shaders its node-theme path wants: a plate baked once, a light
# per-frame pass that samples the plate and draws the movers, and a free-running
# whole-scene shader for the fallback and the prewarm. Writing the scene ONCE and
# wrapping it is what keeps a world's static and animated halves from drifting
# apart — the older themes duplicate their scenery across three consts.
#
# ---------------------------------------------------------------------------
# Composition — the board is standing ON these, not in front of them
# ---------------------------------------------------------------------------
# The single rule, and the one this file was rebuilt around: each world is the
# SURFACE THE BOARD STANDS ON, drawn down the same axis the board is seen down.
# Not a backdrop behind it. A backdrop — sky at the top, a horizon, scenery
# standing up — makes the buttons read as pasted onto a poster, because the
# device is a thing on a table and its own perspective says so.
#
# The frame agrees: the gameplay cameras look down through a lens whose top ray
# is still ~18 degrees BELOW the horizon, so every pixel of every board at every
# aspect is ground. See the tabletop block in KIT for the projection, and
# tools/lume_frame.tscn for the measurement it is fitted to.
#
# What that leaves room for, and where:
#
#   * THE SURFACE fills the frame. Draw its pattern in tableUV() metres, never in
#     screen space — the compression toward the far edge IS the depth cue, and a
#     pattern drawn in screen space reads as wallpaper no matter how good it is.
#   * THINGS LYING ON IT are scattered in tabletop coordinates too (tablePoint)
#     and sized by tableScale, so the far ones crowd together and shrink on their
#     own. |u| has to stay under about 0.56 * w or a prop falls off the sides.
#   * THINGS HANGING OVERHEAD — fronds, vines, bunting, lamp strings, banners,
#     balloons — are between the camera and the ground, so they land in the TOP
#     band, which is where the old backdrop used to be. This is the only way
#     something tall can appear at all, and it is also how you really see a palm
#     from a towel or bunting from underneath.
#   * A SURFACE MAY END, and Rainbow Skyway is the one here that does — but only
#     on a rim curved hard enough to fall away through the SIDE edges of the
#     frame. Solve it against the frame rather than picking it: a rim that runs
#     level across the picture is a horizon by another name, and it costs this
#     whole file's premise. Anything past it belongs to a different world (there,
#     open sky) and needs its own value, usually darker, or the edge disappears.
#   * DRESSING THE GUTTERS is done in tabletop metres against the FRAME's own
#     edge, not at a fixed offset: the u that lands on the side of the picture at
#     depth w is aspect * 0.3153 * w (OCEAN's edgeU). A prop placed at a constant
#     u sits in the margin at 16:9 and walks in over the buttons at 21:9. This is
#     the tabletop form of the `aspect - k` rule below.
#   * THE MIDDLE is the board. lumeGrade hazes exactly that ellipse so the buttons
#     always have clean air around them.
#   * The LEVEL badge holds a.x 0.03..0.24 / a.y 0.13..0.36, the close button
#     a.x aspect-0.12 .. aspect / a.y 0.02..0.10, and "Your turn!" the bottom
#     centre. Nothing bright goes in any of the three.
#
# `a` is aspect-corrected UV: a = vec2(UV.x * aspect, UV.y), so a.y is always
# 0..1 top to bottom and a.x runs 0..aspect. Anchor left-hand furniture to a.x
# and right-hand furniture to `aspect - k`, never to a fraction of the width, or
# a world composed on 16:9 falls apart on a 21:9 phone.
#
# ---------------------------------------------------------------------------
# Cost
# ---------------------------------------------------------------------------
# The rule the older themes were rescued by (BACKGROUND_PERF_NOTES.md) applies
# here from the start: nothing expensive per pixel per frame. All the fbm, all
# the scenery SDFs and all the ground texture live in lumeStatic, which is baked
# once into a plate. lumeDyn samples that plate and draws only the movers, each
# behind a bounding-box guard with a derivative-free window so the guard cannot
# seam (see the win1/radWin note in background_manager). Dense dot fields —
# sparkles, fireflies, embers, stars — are not drawn here at all: they are real
# CPUParticles2D, added per world in theme_props.gd.

# ---------------------------------------------------------------------------
# The catalog
# ---------------------------------------------------------------------------
# Shop/persistence ids in shop order, cheapest first. FROZEN — these strings are
# what a saved wallet contains. The prices live in CoinsManager.THEMES and the
# display order the shop actually renders is CATEGORIES["items"] in
# shop_screen.gd; keep all three in this order.
const ORDER := ["lume_rainbow", "lume_ocean",
	"lume_candy", "lume_space", "lume_forest", "lume_volcano", "lume_arcade",
	"lume_kingdom"]

static func has_world(id: String) -> bool:
	return ORDER.has(id)

# ---------------------------------------------------------------------------
# The kit
# ---------------------------------------------------------------------------
# Shared vocabulary, prepended to every world. Assumes background_manager's _HEAD
# (noise + shapes + nature) is already in front of it.
const KIT := "
float sdRBox(vec2 p, vec2 b, float r) { return sdBox(p, max(b - vec2(r), vec2(0.0))) - r; }
float sdSeg(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a; vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0);
	return length(pa - ba * h) - r;
}
float sdRing(vec2 p, float r, float w) { return abs(length(p) - r) - w; }
// Smooth 0..1 ramp, saves a smoothstep(clamp(...)) everywhere.
float ss(float lo, float hi, float x) { return smoothstep(lo, hi, x); }

// ---- The hero motif: one LUMEO key cap, seen slightly from above. A dark
// bezel, a coloured dome lifted off it, the white inset ring the real buttons
// wear, and a specular sliver. This is what makes these worlds LUMEO's rather
// than a generic set of backdrops — it recurs as a sign, a cloud, a flower head,
// a planet, a Ferris-wheel cabin and, in Button Kingdom, as the architecture. ----
vec4 lumeCap(vec2 p, vec3 c, float lift) {
	vec4 acc = vec4(0.0);
	acc = _ov(acc, vec3(0.07, 0.07, 0.10), aafill(ellip(p, vec2(0.0, 0.13), vec2(1.0, 0.60), 0.0)));
	acc = _ov(acc, vec3(0.15, 0.15, 0.19), aaline(ellip(p, vec2(0.0, 0.13), vec2(1.0, 0.60), 0.0), 0.04) * 0.8);
	vec2 q = p + vec2(0.0, lift);
	float cd = ellip(q, vec2(0.0, 0.0), vec2(0.86, 0.52), 0.0);
	float ca = aafill(cd);
	vec3 body = mix(c * 0.66, c * 1.16, ss(0.45, -0.55, q.y));
	acc = _ov(acc, body, ca);
	acc = _ov(acc, vec3(0.95, 0.95, 0.97), aaline(ellip(q, vec2(0.0, 0.0), vec2(0.60, 0.34), 0.0), 0.055) * ca * 0.92);
	acc = _ov(acc, vec3(1.0), aafill(ellip(q, vec2(-0.26, -0.20), vec2(0.24, 0.10), -0.28)) * ca * 0.40);
	return acc;
}
vec3 placeCap(vec3 col, vec2 a, vec2 pos, float s, vec3 c, float lift, float glow) {
	vec2 p = (a - pos) / s;
	if (abs(p.x) > 1.55 || abs(p.y) > 1.25) return col;
	float win = win1(p.x, -1.48, 1.48, 0.14) * win1(p.y, -1.18, 1.18, 0.14);
	if (glow > 0.0) col += c * glow * ss(1.5, 0.3, length(p)) * win;
	vec4 b = lumeCap(p, c, lift);
	return mix(col, b.rgb, b.a * win);
}

// ---- The same motif flat-on: a coloured disc with the inset ring. Used for
// signs, badges, wheel cabins and anything that reads as a button head-on. ----
vec4 lumeDisc(vec2 p, vec3 c, float ringAmt) {
	vec4 acc = vec4(0.0);
	float d = sdCircle(p, 1.0);
	float da = aafill(d);
	acc = _ov(acc, mix(c * 1.10, c * 0.70, ss(-0.9, 0.9, p.y)), da);
	acc = _ov(acc, vec3(0.95, 0.95, 0.97), aaline(sdCircle(p, 0.62), 0.075) * da * ringAmt);
	acc = _ov(acc, vec3(1.0), aafill(ellip(p, vec2(-0.30, -0.34), vec2(0.30, 0.16), -0.30)) * da * 0.34);
	acc = _ov(acc, c * 0.45, aaline(d, 0.055) * da * 0.7);
	return acc;
}
vec3 placeDisc(vec3 col, vec2 a, vec2 pos, float s, vec3 c, float ringAmt, float glow) {
	vec2 p = (a - pos) / s;
	if (abs(p.x) > 1.4 || abs(p.y) > 1.4) return col;
	float win = radWin(length(p), 1.18, 1.36);
	if (glow > 0.0) col += c * glow * ss(1.6, 0.2, length(p)) * win;
	vec4 b = lumeDisc(p, c, ringAmt);
	return mix(col, b.rgb, b.a * win);
}

// ---- A soft contact shadow: what stops a prop from floating. ----
vec3 lumeShadow(vec3 col, vec2 a, vec2 c, vec2 e, float k) {
	float d = length((a - c) / e);
	return mix(col, col * 0.55, ss(1.0, 0.0, d) * k);
}

// ---- A pennant on a pole, waving from its root. `ph` is its own phase so a
// whole string of them ripples instead of flapping in lockstep. ----
vec3 lumeFlag(vec3 col, vec2 a, vec2 root, float s, vec3 c, float t, float ph) {
	vec2 p = (a - root) / s;
	if (p.x < -0.4 || p.x > 1.6 || p.y > 0.4 || p.y < -1.9) return col;
	float win = win1(p.x, -0.34, 1.54, 0.14) * win1(p.y, -1.84, 0.34, 0.14);
	col = mix(col, vec3(0.30, 0.24, 0.20), aafill(sdSeg(p, vec2(0.0, 0.0), vec2(0.0, -1.7), 0.05)) * win);
	vec2 q = p - vec2(0.0, -1.55);
	float wave = 0.16 * sin(q.x * 5.0 - t * 3.4 + ph);
	q.y -= wave * ss(0.0, 1.2, q.x);
	float fd = max(max(-q.x, q.x - 1.25), abs(q.y) - 0.30 * (1.0 - 0.55 * clamp(q.x / 1.25, 0.0, 1.0)));
	float fa = aafill(fd);
	col = mix(col, mix(c, c * 0.66, ss(-0.3, 0.35, q.y)), fa * win);
	col = mix(col, c * 1.3, aaline(fd, 0.035) * fa * win * 0.5);
	return col;
}

// ---------------------------------------------------------------------------
// The tabletop
// ---------------------------------------------------------------------------
// THE ONE THING THAT DECIDES HOW EVERY ONE OF THESE WORLDS IS COMPOSED.
//
// The board is a device standing on a surface, seen from above and behind at
// 33.5 degrees. It is NOT a thing standing in front of a backdrop, and a world
// built as a backdrop — sky at the top, horizon, scenery standing up — fights it:
// the buttons read as pasted onto a poster instead of sitting in a place.
//
// The frame agrees. Measured with tools/lume_frame.tscn, every gameplay camera
// looks down through a ~25 degree lens whose TOP ray is still ~18 degrees below
// the horizon, so the whole frame is GROUND on every board at every aspect. The
// horizon is not merely unimportant here, it is off screen: its vanishing row
// sits at v = -0.579, more than half a frame above the top edge.
//
// So each world is the SURFACE THE BOARD STANDS ON, drawn in that surface's own
// coordinates, and the only things allowed above it are things that hang: fronds
// and vines overhead, bunting, lamp strings, balloons — which are between the
// camera and the ground and therefore land in the top band exactly where a
// backdrop used to be.
const float HORIZON_V = -0.579;

// How much further away the tabletop is under screen row `y`: 1.0 at the bottom
// edge of the frame, ~2.7 at the top. Fitted to the three gameplay cameras (they
// see ground from about 5 m at the bottom edge to about 14 m at the top).
float persp(float y) { return 1.0 / max(y - HORIZON_V, 0.02) * (1.0 - HORIZON_V); }

// The tabletop's own coordinates for a screen point, in metres: x across, y away
// from the player. Feed a repeating pattern with this and it recedes correctly —
// a floor drawn in screen space instead reads as wallpaper, which is the whole
// mistake this block exists to prevent.
vec2 tableUV(vec2 a) {
	float k = persp(a.y);
	return vec2((a.x - aspect * 0.5) * k * 3.26, k * 5.17);
}

// How large something LYING ON the tabletop at row `y` should be drawn: 1.0 at
// the bottom edge, ~0.37 at the top. Anything scattered on the ground multiplies
// its size by this or it reads as flat.
float tableScale(float y) { return 1.0 / persp(y); }

// The screen row a tabletop distance `w` (metres away) lands on — the inverse of
// tableUV's second component, for placing something at a chosen depth.
float tableRow(float w) {
	return (1.0 - HORIZON_V) * 5.17 / max(w, 0.1) + HORIZON_V;
}

// The screen position and drawn size of something LYING at tabletop point (u, w).
// Scattering props in tabletop coordinates instead of in screen coordinates is
// what makes a scatter read as a scatter: the far ones crowd together and shrink
// on their own, exactly as the ground under them does.
vec2 tablePoint(vec2 uw) {
	float y = tableRow(uw.y);
	return vec2(aspect * 0.5 + uw.x / max(persp(y) * 3.26, 0.001), y);
}

// Distance haze: the far end of a tabletop is dimmer and cooler than the near
// end, and that gradient alone is most of what makes a flat fill read as a plane
// receding away from the player.
vec3 tableFar(vec3 col, vec2 a, vec3 far, float amt) {
	return mix(col, far, ss(1.05, -0.10, a.y) * amt);
}

// ---- The grade. Two jobs, both about the buttons rather than the world: haze
// the ellipse the board occupies so it always has clean air around it, and
// vignette the frame so the LEVEL badge, the close button and the 'Your turn!'
// pill keep their contrast. Applied over the COMPOSITE, never baked. ----
vec3 lumeGrade(vec3 col, vec2 a, vec3 haze) {
	// Measured against real gameplay frames rather than guessed: at 0.52 the haze
	// swallowed Button Kingdom's whole keep, and at 0 the scenery competed with the
	// buttons for attention in the one part of the frame they own. 0.30 over a
	// tighter ellipse settles the air behind the board without erasing what is
	// standing in it.
	vec2 d = vec2((a.x - aspect * 0.5) * 0.62, a.y - 0.66);
	col = mix(col, haze, ss(0.50, 0.02, length(d)) * 0.24);
	vec2 p = vec2(a.x - aspect * 0.5, a.y - 0.48);
	col *= mix(0.76, 1.0, ss(1.18, 0.28, length(p)));
	return col;
}
"

# ---------------------------------------------------------------------------
# The three wrappers
# ---------------------------------------------------------------------------
# W_STATIC is what gets baked into the plate: the scene with nothing moving and
# no grade (the grade belongs over the composite, or the movers would sit on top
# of already-hazed air). W_DYN is the per-frame pass. W_FULL is the whole scene
# free-running, for the prewarm and for the frame or two before a plate lands.
const W_STATIC := "
void fragment() {
	vec2 a = vec2(UV.x * aspect, UV.y);
	COLOR = vec4(lumeStatic(a), 1.0);
}
"
const W_DYN := "
uniform sampler2D static_tex : filter_linear;
void fragment() {
	vec2 a = vec2(UV.x * aspect, UV.y);
	vec3 col = lumeDyn(texture(static_tex, UV).rgb, a, TIME);
	COLOR = vec4(lumeGrade(col, a, lumeHaze()), 1.0);
}
"
const W_FULL := "
void fragment() {
	vec2 a = vec2(UV.x * aspect, UV.y);
	vec3 col = lumeDyn(lumeStatic(a), a, TIME);
	COLOR = vec4(lumeGrade(col, a, lumeHaze()), 1.0);
}
"

const CANDY := "
vec3 lumeHaze() { return vec3(0.97, 0.84, 0.88); }

// A lollipop LYING on the surface: a swirled disc with its stick running away
// from the player. `spin` turns the swirl.
vec3 lollyFlat(vec3 col, vec2 a, vec2 c, float r, float ang, vec3 c1, vec3 c2, float spin) {
	vec2 d = vec2(cos(ang), sin(ang));
	// stick first, so the head sits on it
	{
		float sd = sdSeg(a, c + d * r * 0.7, c + d * r * 2.3, r * 0.115);
		float sa = aafill(sd);
		col = mix(col, vec3(0.98, 0.96, 0.93), sa);
		col = mix(col, vec3(0.86, 0.82, 0.78), aaline(sd + r * 0.09, r * 0.05) * sa * 0.7);
	}
	vec2 p = (a - c) / r;
	if (abs(p.x) > 1.35 || abs(p.y) > 1.35) return col;
	float win = radWin(length(p), 1.10, 1.30);
	// seen from above and a little in front, so the disc is an ellipse
	p.y /= 0.80;
	float dd = sdCircle(p, 1.0);
	float da = aafill(dd) * win;
	float sw = fract(atan(p.y, p.x) / 6.2832 + length(p) * 2.4 - spin);
	vec3 cc = mix(c1, c2, ss(0.46, 0.54, sw) * ss(0.98, 0.90, sw));
	col = mix(col, mix(cc * 1.10, cc * 0.72, ss(-1.0, 1.0, p.y)), da);
	col = mix(col, vec3(1.0), aafill(ellip(p, vec2(-0.32, -0.36), vec2(0.30, 0.17), -0.35)) * da * 0.55);
	col = mix(col, c1 * 0.50, aaline(dd, 0.05) * da * 0.8);
	return col;
}

// A gumdrop sitting on the surface: a sugared dome. `glow` lifts it as the
// sweetness runs past.
vec3 gumdropAt(vec3 col, vec2 a, vec2 c, float r, vec3 cc, float glow) {
	vec2 p = (a - c) / r;
	if (abs(p.x) > 1.6 || abs(p.y) > 1.7) return col;
	float win = win1(p.x, -1.5, 1.5, 0.14) * win1(p.y, -1.6, 1.6, 0.14);
	col += cc * glow * ss(1.7, 0.0, length(p)) * 0.22 * win;
	col = mix(col, col * 0.72, aafill(ellip(p, vec2(0.10, 0.42), vec2(1.0, 0.34), 0.0)) * 0.5 * win);
	float d = ellip(p, vec2(0.0, 0.0), vec2(0.88, 0.80), 0.0);
	float da = aafill(d) * win;
	col = mix(col, mix(cc * 1.22, cc * 0.62, ss(-0.85, 0.85, p.y)), da);
	col = mix(col, vec3(1.0), aafill(ellip(p, vec2(-0.28, -0.32), vec2(0.26, 0.19), -0.4)) * da * 0.55);
	col = mix(col, mix(cc, vec3(1.0), 0.55), aaline(d, 0.075) * da * 0.85);
	return col;
}

vec3 lumeStatic(vec2 a) {
	vec2 g = tableUV(a);
	// poured icing: two marbles over a rose base, in tabletop metres so the swirl
	// compresses into the distance. Pale pastels alone came out as one flat sheet
	// of near-white — the marbling has to be a real colour interval to read at all.
	float m1 = fbm(g * 0.30);
	float m2 = fbm(g * 0.17 + vec2(7.0, 2.0));
	vec3 col = mix(vec3(0.98, 0.74, 0.82), vec3(0.88, 0.46, 0.64), ss(0.38, 0.70, m1));
	col = mix(col, vec3(0.60, 0.87, 0.80), ss(0.44, 0.68, m2) * 0.70);
	col = mix(col, vec3(1.00, 0.93, 0.80), ss(0.58, 0.80, m1 * 0.6 + m2 * 0.6) * 0.60);
	// a quilted waffle pressed into the icing. A plain wash gives the eye nothing
	// to read the perspective off; a repeating unit in tabletop metres gives it
	// everything, because the compression toward the far edge IS the depth cue.
	{
		vec2 q = g * 0.62;
		vec2 f = abs(fract(q + 0.5) - 0.5);
		float seam = min(f.x, f.y);
		col *= 1.0 - 0.13 * ss(0.10, 0.0, seam);
		col += vec3(1.0, 0.97, 0.93) * ss(0.16, 0.05, seam) * ss(0.30, 0.12, max(f.x, f.y)) * 0.06;
		// and a diagonal sugar grain over the top of it
		col *= 0.985 + 0.030 * ss(0.45, 0.55, fract((q.x + q.y) * 3.0));
	}
	// a chocolate ribbon poured across the surface
	{
		float cx = 4.6 + 2.4 * sin(g.y * 0.26) + 0.8 * sin(g.y * 0.72);
		float d = abs(g.x - cx) - 0.95;
		col = mix(col, vec3(0.34, 0.19, 0.14), aafill(d));
		col = mix(col, vec3(0.52, 0.31, 0.22), aaline(d + 0.16, 0.09) * aafill(d) * 0.8);
		col = mix(col, vec3(0.68, 0.46, 0.32), aaline(d, 0.05) * 0.5);
	}
	// sprinkles, scattered on the tabletop and sized by how far off they are
	for (int i = 0; i < 30; i++) {
		float fi = float(i);
		float h1 = hash11(fi * 3.7);
		float h2 = hash11(fi * 5.3);
		float h3 = hash11(fi * 9.1);
		vec2 c = tablePoint(vec2((h1 - 0.5) * 15.0, 5.1 + h2 * 8.8));
		float r = 0.019 * tableScale(c.y);
		if (abs(a.x - c.x) > r * 2.0 || abs(a.y - c.y) > r * 2.0) continue;
		float win = win1(a.x, c.x - r * 1.9, c.x + r * 1.9, r * 0.4)
			* win1(a.y, c.y - r * 1.9, c.y + r * 1.9, r * 0.4);
		vec3 sc = vec3(0.98, 0.42, 0.48);
		if (h3 > 0.66) sc = vec3(0.42, 0.76, 0.95); else if (h3 > 0.33) sc = vec3(0.99, 0.84, 0.36);
		col = mix(col, sc, aafill(sdRBox((a - c) * rot(h3 * 3.0), vec2(r * 1.1, r * 0.34), r * 0.3)) * win);
	}
	// marshmallow pillows lying about
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float h1 = hash11(fi * 7.9);
		float h2 = hash11(fi * 4.1);
		vec2 c = tablePoint(vec2((h1 - 0.5) * 11.0, 5.4 + h2 * 8.0));
		float r = (0.052 + 0.024 * h2) * tableScale(c.y);
		if (abs(a.x - c.x) > r * 2.2 || abs(a.y - c.y) > r * 1.9) continue;
		float win = win1(a.x, c.x - r * 2.1, c.x + r * 2.1, r * 0.3)
			* win1(a.y, c.y - r * 1.8, c.y + r * 1.8, r * 0.3);
		vec3 mc = (h1 > 0.5) ? vec3(1.0, 0.97, 0.95) : vec3(1.0, 0.86, 0.90);
		col = mix(col, col * 0.80, aafill(ellip(a, c + vec2(r * 0.25, r * 0.55), vec2(r * 1.2, r * 0.40), 0.0)) * 0.5 * win);
		float d = sdRBox(a - c, vec2(r * 1.05, r * 0.72), r * 0.42);
		float da = aafill(d) * win;
		col = mix(col, mix(mc, mc * 0.80, ss(-r, r, a.y - c.y)), da);
		col = mix(col, vec3(1.0), aaline(d, r * 0.10) * da * ss(c.y, c.y - r, a.y) * 0.8);
	}
	col = tableFar(col, a, vec3(0.99, 0.85, 0.90), 0.38);
	return col;
}

vec3 lumeDyn(vec3 col, vec2 a, float t) {
	// three lollipops lying on the surface, each swirling at its own rate
	col = lollyFlat(col, a, tablePoint(vec2(-2.90, 6.10)), 0.150 * tableScale(tableRow(6.10)),
		-0.9, vec3(0.98, 0.30, 0.42), vec3(1.0, 0.97, 0.94), t * 0.055);
	col = lollyFlat(col, a, tablePoint(vec2(3.40, 7.60)), 0.128 * tableScale(tableRow(7.60)),
		-2.4, vec3(0.42, 0.76, 0.95), vec3(1.0, 0.97, 0.94), -t * 0.042);
	col = lollyFlat(col, a, tablePoint(vec2(-0.90, 11.20)), 0.110 * tableScale(tableRow(11.20)),
		-1.7, vec3(0.55, 0.85, 0.45), vec3(1.0, 0.97, 0.94), t * 0.070);
	// a row of gumdrops with a wave of sweetness running along it
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float h = hash11(fi * 4.3);
		vec2 c = tablePoint(vec2((fi - 2.5) * 2.4 + 1.1 * (h - 0.5), 6.2 + 4.4 * hash11(fi * 2.1)));
		float r = (0.050 + 0.020 * h) * tableScale(c.y);
		vec3 cc = vec3(0.98, 0.46, 0.52);
		if (h > 0.66) cc = vec3(0.52, 0.82, 0.94); else if (h > 0.33) cc = vec3(0.72, 0.92, 0.58);
		col = gumdropAt(col, a, c, r, cc, ss(0.55, 1.0, sin(t * 1.15 - fi * 0.85)));
	}
	// and a slow sugar bloom travelling out across the icing
	{
		float w = mod(t * 1.30, 12.0) + 4.4;
		vec2 g = tableUV(a);
		col += vec3(1.0, 0.94, 0.97) * ss(1.8, 0.0, abs(g.y - w)) * 0.13;
	}
	return col;
}
"

# ===========================================================================
# 04 — SPACE PETS
# ===========================================================================
# The board floats on a luminous nebula plane. Space has no up, so this is the
# one world where the tabletop needs no ground at all — it is a sheet of coloured
# gas going away from the player, with small worlds resting on it, a rocket
# skimming low across it, and a saucer holding station above with its beam
# pooling on the surface.
const SPACE := "
vec3 lumeHaze() { return vec3(0.13, 0.10, 0.28); }

// A world resting on the plane: a lit sphere whose surface bands scroll, so it
// turns without any geometry, plus the shadow it casts on the gas under it.
vec3 planetAt(vec3 col, vec2 a, vec2 c, float r, vec3 hi, vec3 lo, float spin, float ring, vec3 ringC) {
	vec2 p = (a - c) / r;
	float ext = ring > 0.5 ? 2.4 : 1.45;
	if (abs(p.x) > ext || abs(p.y) > ext) return col;
	float win = radWin(length(p), ext - 0.20, ext - 0.05);
	col = mix(col, col * 0.55, aafill(ellip(p, vec2(0.30, 0.85), vec2(1.15, 0.34), 0.0)) * 0.55 * win);
	if (ring > 0.5) {
		float rd = abs(ellip(p, vec2(0.0, 0.0), vec2(1.95, 0.52), -0.22)) - 0.18;
		col = mix(col, ringC * 0.70, aafill(rd) * win * step(p.y, 0.0) * 0.90);
	}
	float d = sdCircle(p, 1.0);
	float da = aafill(d) * win;
	// longitude as the arcsine of x: the bands crowd at the limb the way a real
	// sphere's do, which is the whole reason the scroll reads as spin
	float u = asin(clamp(p.x, -1.0, 1.0)) / 1.5708;
	float band = 0.5 + 0.5 * sin(p.y * 8.0 + 1.6 * sin(u * 3.0 + spin));
	vec3 sph = mix(lo, hi, band);
	sph = mix(sph, hi * 1.12, ss(0.55, 0.95, fract(u * 1.5 + spin * 0.16)) * 0.5);
	float lit = ss(1.5, -0.4, length(p - vec2(-0.38, -0.42)));
	col = mix(col, sph * mix(0.52, 1.16, lit), da);
	col = mix(col, hi * 1.5, aaline(d, 0.035) * da * ss(0.6, -0.9, p.x + p.y) * 0.55);
	if (ring > 0.5) {
		float rd = abs(ellip(p, vec2(0.0, 0.0), vec2(1.95, 0.52), -0.22)) - 0.18;
		col = mix(col, ringC, aafill(rd) * win * step(0.0, p.y) * 0.95);
		col = mix(col, ringC * 1.4, aaline(rd, 0.03) * win * step(0.0, p.y) * 0.5);
	}
	return col;
}

// A little rocket with a tapering flame, skimming low across the plane along +x.
vec3 rocketAt(vec3 col, vec2 a, vec2 c, float s, float t) {
	vec2 p = (a - c) / s;
	if (p.x < -3.2 || p.x > 1.6 || abs(p.y) > 1.6) return col;
	float win = win1(p.x, -3.1, 1.5, 0.16) * win1(p.y, -1.5, 1.5, 0.14);
	col = mix(col, col * 0.6, aafill(ellip(p, vec2(-0.3, 1.05), vec2(1.15, 0.22), 0.0)) * 0.5 * win);
	float fl = 0.9 + 0.25 * sin(t * 22.0);
	float fd = max(-p.x - 1.9 * fl, max(p.x + 0.72, abs(p.y) - 0.30 * (1.0 - (-p.x - 0.72) / (1.9 * fl))));
	col = mix(col, vec3(1.0, 0.52, 0.20), aafill(fd) * win * 0.9);
	col = mix(col, vec3(1.0, 0.92, 0.55), aafill(fd + 0.14) * win);
	col = mix(col, vec3(0.86, 0.26, 0.32), aafill(min(
		max(max(-p.x - 0.72, p.x + 0.10), abs(p.y - 0.52) - 0.30 + (p.x + 0.72) * 0.45),
		max(max(-p.x - 0.72, p.x + 0.10), abs(p.y + 0.52) - 0.30 + (p.x + 0.72) * 0.45))) * win);
	float bd = ellip(p, vec2(0.0, 0.0), vec2(0.98, 0.36), 0.0);
	float ba = aafill(bd) * win;
	col = mix(col, mix(vec3(0.99, 0.98, 0.99), vec3(0.62, 0.64, 0.76), ss(-0.36, 0.36, p.y)), ba);
	col = mix(col, vec3(0.86, 0.26, 0.32), aafill(max(bd, p.x - 0.34)) * win);
	col = mix(col, vec3(0.30, 0.72, 0.92), aafill(sdCircle(p - vec2(-0.18, -0.02), 0.20)) * win);
	col = mix(col, vec3(0.85, 0.96, 1.0), aafill(sdCircle(p - vec2(-0.22, -0.07), 0.09)) * win);
	return col;
}

// A saucer holding station above the plane, its beam pooling on the surface.
vec3 ufoAt(vec3 col, vec2 a, vec2 c, float s, float t) {
	vec2 p = (a - c) / s;
	if (abs(p.x) > 2.4 || p.y < -1.2 || p.y > 4.2) return col;
	float win = win1(p.x, -2.3, 2.3, 0.16) * win1(p.y, -1.1, 4.1, 0.20);
	// the beam, and the ellipse of light it lays on the gas below
	{
		float bd = max(max(-p.y + 0.18, p.y - 3.2), abs(p.x) - 0.22 - p.y * 0.40);
		float pulse = 0.7 + 0.3 * sin(t * 2.2);
		col += vec3(0.45, 0.95, 0.72) * ss(0.22, -0.10, bd) * win * 0.18 * ss(3.2, 0.2, p.y) * pulse;
		col += vec3(0.40, 0.95, 0.70) * ss(1.0, 0.0, length((p - vec2(0.0, 3.15)) / vec2(1.6, 0.42))) * 0.30 * pulse * win;
	}
	float dd = ellip(p, vec2(0.0, 0.16), vec2(1.05, 0.30), 0.0);
	float da = aafill(dd) * win;
	col = mix(col, mix(vec3(0.80, 0.84, 0.92), vec3(0.30, 0.34, 0.46), ss(-0.14, 0.46, p.y)), da);
	col = mix(col, vec3(0.55, 0.98, 0.80), aaline(dd, 0.05) * da * 0.6);
	float hd = max(ellip(p, vec2(0.0, 0.10), vec2(0.50, 0.46), 0.0), p.y - 0.10);
	float ha = aafill(hd) * win;
	col = mix(col, vec3(0.52, 0.92, 0.86), ha * 0.85);
	col = mix(col, vec3(1.0), aafill(ellip(p, vec2(-0.16, -0.10), vec2(0.14, 0.09), -0.3)) * ha * 0.7);
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float glow = 0.4 + 0.6 * ss(0.4, 1.0, sin(t * 3.4 - fi * 1.2));
		col += vec3(1.0, 0.85, 0.42) * ss(0.28, 0.0, length(p - vec2((fi - 2.0) * 0.40, 0.30))) * glow * win * 0.55;
	}
	return col;
}

// A pet: a rounded blob with two big eyes and an antenna, bobbing along.
vec3 petAt(vec3 col, vec2 a, vec2 c, float s, vec3 body, float wob) {
	vec2 p = (a - c) / s;
	if (abs(p.x) > 1.5 || abs(p.y) > 1.8) return col;
	float win = win1(p.x, -1.42, 1.42, 0.14) * win1(p.y, -1.72, 1.72, 0.14);
	col = mix(col, body * 0.7, aafill(sdSeg(p, vec2(0.10, -0.72), vec2(0.26 + 0.10 * wob, -1.32), 0.055)) * win);
	col += body * ss(0.16, 0.0, length(p - vec2(0.26 + 0.10 * wob, -1.36))) * 0.9 * win;
	float d = ellip(p, vec2(0.0, 0.0), vec2(0.78, 0.86), 0.06 * wob);
	float da = aafill(d) * win;
	col = mix(col, mix(body * 1.18, body * 0.58, ss(-0.8, 0.9, p.y)), da);
	col = mix(col, body * 1.6, aaline(d, 0.05) * da * ss(0.5, -0.8, p.y) * 0.6);
	col = mix(col, vec3(0.99, 1.0, 1.0), aafill(min(sdCircle(p - vec2(-0.27, -0.12), 0.25), sdCircle(p - vec2(0.29, -0.12), 0.22))) * win);
	col = mix(col, vec3(0.06, 0.05, 0.12), aafill(min(sdCircle(p - vec2(-0.23 + 0.05 * wob, -0.09), 0.12), sdCircle(p - vec2(0.33 + 0.05 * wob, -0.09), 0.11))) * win);
	col = mix(col, vec3(1.0), aafill(min(sdCircle(p - vec2(-0.27 + 0.05 * wob, -0.14), 0.045), sdCircle(p - vec2(0.29 + 0.05 * wob, -0.14), 0.04))) * win);
	return col;
}

vec3 lumeStatic(vec2 a) {
	vec2 g = tableUV(a);
	vec3 col = mix(vec3(0.055, 0.040, 0.135), vec3(0.020, 0.016, 0.070), ss(1.05, 0.0, a.y));
	// the gas: two coloured sheets lying in the plane, so they run away from the
	// player instead of hanging behind the board like a curtain
	{
		vec2 q = g * 0.20;
		float n = fbm(q + vec2(fbm(q * 1.7), fbm(q * 1.7 + 3.1)) * 1.2);
		col += vec3(0.60, 0.17, 0.66) * ss(0.42, 0.68, n) * 0.60;
		float n2 = fbm(g * 0.28 + vec2(9.0, 2.0));
		col += vec3(0.10, 0.44, 0.72) * ss(0.44, 0.70, n2) * 0.55;
		col += vec3(0.95, 0.55, 0.85) * ss(0.62, 0.84, n) * 0.30;
	}
	// stars lying in the plane: scattered in tabletop coordinates, so they crowd
	// together toward the far edge exactly as a receding field should
	for (int i = 0; i < 90; i++) {
		float fi = float(i);
		vec2 c = tablePoint(vec2((hash11(fi * 1.37) - 0.5) * 34.0, 5.2 + hash11(fi * 2.71) * 13.0));
		float r = (0.0016 + 0.0032 * hash11(fi * 4.11)) * tableScale(c.y);
		if (abs(a.x - c.x) > r * 5.0 || abs(a.y - c.y) > r * 5.0) continue;
		float b = 0.45 + 0.55 * hash11(fi * 5.53);
		col += mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.88, 0.72), hash11(fi * 6.7)) * b
			* ss(r * 3.4, 0.0, distance(a, c));
	}
	// a scatter of rocks resting on the plane
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		vec2 c = tablePoint(vec2((hash11(fi * 21.3) - 0.5) * 20.0, 5.6 + hash11(fi * 11.7) * 8.0));
		float r = (0.012 + 0.010 * hash11(fi * 5.1)) * tableScale(c.y);
		if (abs(a.x - c.x) > r * 3.0 || abs(a.y - c.y) > r * 3.0) continue;
		float win = win1(a.x, c.x - r * 2.8, c.x + r * 2.8, r * 0.4) * win1(a.y, c.y - r * 2.8, c.y + r * 2.8, r * 0.4);
		float d = sdCircle((a - c) / vec2(1.0, 0.78), r);
		for (int j = 0; j < 4; j++) {
			float fj = float(j);
			d = smin(d, sdCircle(a - c - r * 0.7 * vec2(cos(fj * 1.9 + fi), sin(fj * 1.9 + fi) * 0.78), r * 0.5), r * 0.4);
		}
		float da = aafill(d) * win;
		col = mix(col, col * 0.5, aafill(ellip(a, c + vec2(r * 0.5, r * 0.9), vec2(r * 1.4, r * 0.4), 0.0)) * 0.5 * win);
		col = mix(col, mix(vec3(0.34, 0.30, 0.40), vec3(0.13, 0.11, 0.19), ss(-r, r, a.y - c.y)), da);
		col = mix(col, vec3(0.60, 0.54, 0.68), aaline(d, r * 0.09) * ss(c.y, c.y - r, a.y) * da * 0.8);
	}
	return col;
}

vec3 lumeDyn(vec3 col, vec2 a, float t) {
	// the gas giant, resting on the plane near the player and cut by the left edge
	col = planetAt(col, a, tablePoint(vec2(-3.60, 5.45)), 0.210 * tableScale(tableRow(5.45)),
		vec3(0.98, 0.74, 0.46), vec3(0.72, 0.36, 0.30), t * 0.055, 1.0, vec3(0.96, 0.86, 0.70));
	// two small worlds further out
	col = planetAt(col, a, tablePoint(vec2(-4.20, 11.80)), 0.085 * tableScale(tableRow(11.80)),
		vec3(0.55, 0.86, 0.92), vec3(0.16, 0.40, 0.62), -t * 0.10, 0.0, vec3(0.0));
	col = planetAt(col, a, tablePoint(vec2(6.60, 9.40)), 0.105 * tableScale(tableRow(9.40)),
		vec3(0.72, 0.94, 0.60), vec3(0.22, 0.48, 0.36), t * 0.085, 0.0, vec3(0.0));
	// a rocket skimming across the far half of the plane
	{
		float lane = tableRow(12.4);
		float x = -0.7 + mod(t * 0.115, aspect + 4.0);
		col = rocketAt(col, a, vec2(x, lane + 0.012 * sin(t * 0.9)), 0.040 * tableScale(lane), t);
	}
	// the saucer, holding station over the mid-distance
	{
		float lane = tableRow(8.6);
		col = ufoAt(col, a, vec2(aspect * 0.700 + 0.05 * sin(t * 0.31), lane - 0.115 + 0.014 * sin(t * 0.77)),
			0.052 * tableScale(lane), t);
	}
	// and three pets, drifting just above the surface
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float w = 6.0 + fi * 2.6;
		float lane = tableRow(w);
		float sc = tableScale(lane);
		col = petAt(col, a, vec2(mod(0.4 + fi * 1.5 + t * (0.030 - fi * 0.005), aspect + 0.9) - 0.45,
			lane - 0.055 * sc + 0.022 * sc * sin(t * (0.62 + fi * 0.2) + fi * 2.0)),
			(0.046 - fi * 0.004) * sc,
			(i == 0) ? vec3(0.42, 0.92, 0.72) : ((i == 1) ? vec3(0.96, 0.62, 0.86) : vec3(0.98, 0.86, 0.42)),
			sin(t * (1.5 - fi * 0.2) + fi));
	}
	return col;
}
"

# ===========================================================================
# 05 — MAGICAL FOREST
# ===========================================================================
# The forest floor, with the canopy overhead rather than in front. Moss, roots,
# glowing mushrooms and flowers on the ground; vines and leaf clusters hanging
# into the top of the frame; and the whole surface read by the pools of light
# that come down through the leaves, which move.
const FOREST := "
vec3 lumeHaze() { return vec3(0.20, 0.36, 0.29); }

// A glowing flower growing out of the moss: a ring of petals round a lit heart.
vec3 flowerAt(vec3 col, vec2 a, vec2 c, float r, vec3 cc, float pulse) {
	vec2 p = (a - c) / r;
	if (abs(p.x) > 1.8 || abs(p.y) > 1.8) return col;
	float win = radWin(length(p), 1.55, 1.75);
	col += cc * ss(1.7, 0.0, length(p)) * (0.14 + 0.20 * pulse) * win;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float ang = fi / 6.0 * 6.2832 + 0.3;
		vec2 pc = 0.62 * vec2(cos(ang), sin(ang) * 0.72);
		col = mix(col, mix(cc * 0.75, mix(cc, vec3(1.0), 0.35), 0.4 + 0.6 * pulse),
			aafill(ellip(p, pc, vec2(0.44, 0.30), ang)) * win);
	}
	col = mix(col, mix(vec3(1.0, 0.98, 0.86), cc, 0.25), aafill(ellip(p, vec2(0.0, 0.0), vec2(0.34, 0.26), 0.0)) * win);
	col += vec3(1.0, 0.96, 0.80) * ss(0.55, 0.0, length(p * vec2(1.0, 1.3))) * (0.22 + 0.32 * pulse) * win;
	return col;
}

// A mushroom growing out of the moss, seen from above and in front: a domed cap
// with a lit rim, a spotted top and a short stem showing at its base.
vec3 shroomAt(vec3 col, vec2 a, vec2 c, float r, vec3 cc, float seed, float glow) {
	vec2 p = (a - c) / r;
	if (abs(p.x) > 1.7 || abs(p.y) > 1.7) return col;
	float win = radWin(length(p), 1.45, 1.65);
	col += cc * ss(1.8, 0.2, length(p)) * glow * 0.22 * win;
	col = mix(col, col * 0.66, aafill(ellip(p, vec2(0.10, 0.60), vec2(1.05, 0.34), 0.0)) * 0.55 * win);
	col = mix(col, vec3(0.92, 0.89, 0.79), aafill(sdRBox(p - vec2(0.0, 0.42), vec2(0.20, 0.34), 0.12)) * win);
	float d = ellip(p, vec2(0.0, 0.0), vec2(0.95, 0.70), 0.0);
	float da = aafill(d) * win;
	col = mix(col, mix(cc * 1.20, cc * 0.60, ss(-0.7, 0.7, p.y)), da);
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 sp = vec2((-0.50 + 0.34 * fi) + 0.12 * hash11(seed + fi), -0.14 - 0.26 * hash11(seed + fi * 2.0));
		col = mix(col, vec3(0.99, 0.97, 0.92), aafill(ellip(p, sp, vec2(0.16, 0.11), 0.0)) * da * 0.95);
	}
	col = mix(col, mix(cc, vec3(1.0), 0.6), aaline(d, 0.075) * da * ss(0.5, -0.8, p.y) * 0.9);
	return col;
}

// Something behind the big root, having a look: two lit eyes and round ears,
// easing out and slipping back.
vec3 watcherAt(vec3 col, vec2 a, vec2 pivot, float s, float lean, vec3 c) {
	if (lean <= 0.001) return col;
	vec2 p = (a - pivot) / s;
	p.x -= lean * 1.1;
	if (abs(p.x) > 1.6 || abs(p.y) > 1.6) return col;
	float win = win1(p.x, -1.5, 1.5, 0.14) * win1(p.y, -1.5, 1.5, 0.14) * ss(-0.05, 0.12, p.x);
	col = mix(col, c * 0.75, aafill(min(sdCircle(p - vec2(0.34, -0.78), 0.30), sdCircle(p - vec2(0.98, -0.72), 0.26))) * win);
	float d = ellip(p, vec2(0.62, 0.0), vec2(0.82, 0.74), 0.0);
	float da = aafill(d) * win;
	col = mix(col, mix(c * 1.15, c * 0.55, ss(-0.7, 0.8, p.y)), da);
	col = mix(col, c * 1.7, aaline(d, 0.05) * da * 0.5);
	col = mix(col, vec3(1.0, 0.99, 0.90), aafill(min(sdCircle(p - vec2(0.34, -0.16), 0.24), sdCircle(p - vec2(0.94, -0.16), 0.22))) * win);
	col = mix(col, vec3(0.06, 0.07, 0.06), aafill(min(sdCircle(p - vec2(0.38, -0.14), 0.11), sdCircle(p - vec2(0.98, -0.14), 0.10))) * win);
	col += vec3(0.70, 1.0, 0.72) * ss(0.5, 0.0, min(length(p - vec2(0.34, -0.16)), length(p - vec2(0.94, -0.16)))) * 0.20 * win;
	return col;
}

// A cluster of leaves hanging into the frame from the canopy overhead.
vec3 leafSpray(vec3 col, vec2 a, vec2 origin, float s, float a0, float sway, vec3 c1, vec3 c2) {
	vec2 rel = (a - origin) / s;
	if (dot(rel, rel) > 2.60) return col;
	float win = radWin(length(rel), 1.38, 1.60);
	// the twig
	col = mix(col, vec3(0.24, 0.17, 0.12),
		aafill(sdSeg(rel, vec2(0.0, 0.0), vec2(cos(a0), sin(a0)) * 1.25 + vec2(0.0, 0.06 * sway), 0.045)) * win);
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		float h = hash11(a0 * 17.0 + fi * 3.1);
		float u = 0.16 + fi * 0.135;
		float side = (mod(fi, 2.0) < 0.5) ? 1.0 : -1.0;
		vec2 c = vec2(cos(a0), sin(a0)) * u * 1.25 + vec2(0.0, 0.06 * sway * u);
		vec2 q = rel - c;
		if (dot(q, q) > 0.13) continue;
		float ang = a0 + side * (0.85 + 0.25 * h) + sway * 0.10;
		float d = ellip(q, vec2(cos(ang), sin(ang)) * 0.15, vec2(0.175, 0.088), ang);
		float da = aafill(d) * win;
		vec3 lc = mix(c1, c2, h);
		col = mix(col, lc, da);
		col = mix(col, lc * 1.4, aaline(d, 0.022) * da * 0.5);
	}
	return col;
}

vec3 lumeStatic(vec2 a) {
	vec2 g = tableUV(a);
	// moss, with bare earth showing through where it thins
	float n = fbm(g * 0.42);
	vec3 col = mix(vec3(0.14, 0.32, 0.19), vec3(0.24, 0.46, 0.24), ss(0.34, 0.70, n));
	col = mix(col, vec3(0.26, 0.20, 0.14), ss(0.66, 0.86, fbm(g * 0.27 + 4.0)) * 0.6);
	col *= 0.95 + 0.10 * hash21(floor(g * 48.0));
	col *= 0.93 + 0.14 * fbm(g * 3.1);
	// fallen leaves
	for (int i = 0; i < 18; i++) {
		float fi = float(i);
		float h = hash11(fi * 5.9);
		vec2 c = tablePoint(vec2((hash11(fi * 2.7) - 0.5) * 18.0, 5.1 + hash11(fi * 8.3) * 9.5));
		float r = 0.014 * tableScale(c.y);
		if (abs(a.x - c.x) > r * 3.0 || abs(a.y - c.y) > r * 2.4) continue;
		float win = win1(a.x, c.x - r * 2.8, c.x + r * 2.8, r * 0.4) * win1(a.y, c.y - r * 2.2, c.y + r * 2.2, r * 0.4);
		vec3 lc = mix(vec3(0.52, 0.38, 0.16), vec3(0.30, 0.42, 0.18), h);
		col = mix(col, lc, aafill(ellip(a, c, vec2(r * 1.6, r * 0.75), h * 3.0)) * win);
	}
	// roots running over the floor toward the player
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float base = (fi - 1.0) * 6.4 + 1.2;
		float cx = base + 1.5 * sin(g.y * 0.30 + fi * 2.0);
		float d = abs(g.x - cx) - (0.30 + 0.12 * sin(g.y * 1.1 + fi));
		float da = aafill(d);
		col = mix(col, mix(vec3(0.34, 0.24, 0.16), vec3(0.20, 0.14, 0.10), ss(-0.3, 0.3, g.x - cx)), da);
		col = mix(col, vec3(0.46, 0.35, 0.24), aaline(d + 0.10, 0.05) * da * 0.7);
		col = mix(col, vec3(0.16, 0.30, 0.18), aaline(d, 0.06) * 0.55);
	}
	// stones
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float h = hash11(fi * 6.7);
		vec2 c = tablePoint(vec2((hash11(fi * 3.1) - 0.5) * 17.0, 5.4 + hash11(fi * 9.1) * 8.4));
		float r = (0.016 + 0.020 * h) * tableScale(c.y);
		if (abs(a.x - c.x) > r * 3.0 || abs(a.y - c.y) > r * 2.6) continue;
		float win = win1(a.x, c.x - r * 2.8, c.x + r * 2.8, r * 0.4) * win1(a.y, c.y - r * 2.4, c.y + r * 2.4, r * 0.4);
		float d = ellip(a, c, vec2(r * 1.5, r * 0.9), h * 2.0);
		col = mix(col, col * 0.6, aafill(ellip(a, c + vec2(r * 0.4, r * 0.6), vec2(r * 1.7, r * 0.55), 0.0)) * 0.5 * win);
		col = mix(col, mix(vec3(0.32, 0.36, 0.33), vec3(0.15, 0.19, 0.19), ss(-r, r, a.y - c.y)), aafill(d) * win);
		col = mix(col, vec3(0.36, 0.58, 0.34), aaline(d, r * 0.10) * ss(c.y, c.y - r, a.y) * win * 0.7);
	}
	col = tableFar(col, a, vec3(0.10, 0.22, 0.20), 0.55);
	return col;
}

vec3 lumeDyn(vec3 col, vec2 a, float t) {
	vec2 g = tableUV(a);
	// pools of light coming down through the canopy and sliding as it moves
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 c = vec2(-3.4 + fi * 4.2 + 0.9 * sin(t * 0.21 + fi * 2.0), 6.4 + fi * 2.9 + 0.7 * sin(t * 0.17 + fi));
		float d = length((g - c) / vec2(2.6, 2.0));
		col += vec3(0.72, 0.95, 0.58) * ss(1.0, 0.0, d) * (0.10 + 0.05 * sin(t * 0.4 + fi * 1.7));
	}
	// mushrooms and flowers growing out of the moss
	col = shroomAt(col, a, tablePoint(vec2(-2.70, 6.10)), 0.070 * tableScale(tableRow(6.10)), vec3(0.35, 0.82, 0.94), 3.0, 0.8 + 0.2 * sin(t * 1.1));
	col = shroomAt(col, a, tablePoint(vec2(-3.90, 8.40)), 0.050 * tableScale(tableRow(8.40)), vec3(0.58, 0.60, 0.98), 9.0, 0.8 + 0.2 * sin(t * 0.9 + 2.0));
	col = shroomAt(col, a, tablePoint(vec2(3.10, 6.70)), 0.075 * tableScale(tableRow(6.70)), vec3(0.62, 0.94, 0.72), 17.0, 0.8 + 0.2 * sin(t * 1.3 + 4.0));
	col = shroomAt(col, a, tablePoint(vec2(4.60, 9.60)), 0.050 * tableScale(tableRow(9.60)), vec3(0.98, 0.62, 0.86), 23.0, 0.8 + 0.2 * sin(t * 1.0 + 1.0));
	col = flowerAt(col, a, tablePoint(vec2(-2.40, 5.50)), 0.048 * tableScale(tableRow(5.50)), vec3(0.42, 0.88, 0.98), 0.5 + 0.5 * sin(t * 1.1));
	col = flowerAt(col, a, tablePoint(vec2(-4.60, 10.30)), 0.036 * tableScale(tableRow(10.30)), vec3(0.86, 0.56, 0.98), 0.5 + 0.5 * sin(t * 0.9 + 2.0));
	col = flowerAt(col, a, tablePoint(vec2(2.60, 5.80)), 0.046 * tableScale(tableRow(5.80)), vec3(0.98, 0.72, 0.46), 0.5 + 0.5 * sin(t * 1.3 + 4.0));
	col = flowerAt(col, a, tablePoint(vec2(5.40, 12.20)), 0.032 * tableScale(tableRow(12.20)), vec3(0.52, 0.98, 0.72), 0.5 + 0.5 * sin(t * 0.8 + 1.0));
	// something behind the left-hand root, having a look every nine seconds
	{
		vec2 c = tablePoint(vec2(-3.10, 7.40));
		float ph = fract(t / 9.0);
		col = watcherAt(col, a, c, 0.058 * tableScale(c.y), ss(0.0, 0.10, ph) * ss(0.34, 0.24, ph), vec3(0.46, 0.38, 0.56));
	}
	// the canopy hanging into the frame, breathing
	col = leafSpray(col, a, vec2(-0.08, -0.10), 0.42, 0.72, sin(t * 0.62), vec3(0.10, 0.30, 0.16), vec3(0.34, 0.62, 0.28));
	col = leafSpray(col, a, vec2(0.30, -0.16), 0.30, 1.05, sin(t * 0.71 + 0.6), vec3(0.13, 0.36, 0.19), vec3(0.42, 0.70, 0.30));
	col = leafSpray(col, a, vec2(aspect + 0.06, -0.14), 0.38, 2.44, sin(t * 0.48 + 2.0), vec3(0.09, 0.28, 0.15), vec3(0.30, 0.56, 0.26));
	col = leafSpray(col, a, vec2(aspect - 0.34, -0.20), 0.28, 2.10, sin(t * 0.58 + 3.1), vec3(0.13, 0.34, 0.18), vec3(0.38, 0.66, 0.30));
	col = leafSpray(col, a, vec2(aspect * 0.52, -0.22), 0.30, 1.42, sin(t * 0.55 + 1.0), vec3(0.12, 0.33, 0.18), vec3(0.36, 0.64, 0.30));
	return col;
}
"

const VOLCANO := "
vec3 lumeHaze() { return vec3(0.40, 0.20, 0.24); }

// A lava blob: a molten drop with two eyes and a grin, squashing as it lands.
vec3 blobAt(vec3 col, vec2 a, vec2 c, float s, float squash, float smile) {
	vec2 p = (a - c) / s;
	if (abs(p.x) > 1.7 || abs(p.y) > 1.7) return col;
	float win = radWin(length(p), 1.45, 1.65);
	col += vec3(1.0, 0.48, 0.12) * ss(1.9, 0.2, length(p)) * 0.35 * win;
	float d = ellip(p, vec2(0.0, 0.0), vec2(0.86 + squash * 0.30, 0.86 - squash * 0.30), 0.0);
	float da = aafill(d) * win;
	col = mix(col, mix(vec3(1.0, 0.86, 0.42), vec3(0.96, 0.32, 0.10), ss(-0.8, 0.9, p.y)), da);
	col = mix(col, vec3(1.0, 0.98, 0.82), aaline(d, 0.06) * da * ss(0.5, -0.8, p.y) * 0.75);
	col = mix(col, vec3(0.20, 0.07, 0.06), aafill(min(sdCircle(p - vec2(-0.28, -0.18), 0.135), sdCircle(p - vec2(0.28, -0.18), 0.135))) * win);
	col = mix(col, vec3(1.0), aafill(min(sdCircle(p - vec2(-0.31, -0.22), 0.050), sdCircle(p - vec2(0.31, -0.22), 0.050))) * win);
	col = mix(col, vec3(0.20, 0.07, 0.06), aaline(sdCircle(p - vec2(0.0, 0.05 - smile * 0.55), 0.42 + smile * 0.30), 0.035)
		* step(0.20, p.y) * win);
	return col;
}

vec3 lumeStatic(vec2 a) {
	vec2 g = tableUV(a);
	// cooled basalt: plates of crust with the heat still showing between them
	float n = fbm(g * 0.46);
	vec3 col = mix(vec3(0.105, 0.078, 0.105), vec3(0.048, 0.036, 0.054), ss(0.36, 0.70, n));
	col *= 0.90 + 0.20 * hash21(floor(g * 40.0));
	col *= 0.92 + 0.14 * fbm(g * 3.2);
	// the crazing between the plates, lit from underneath
	{
		float f = fbm(g * 0.85 + 7.0);
		col += vec3(1.0, 0.34, 0.08) * ss(0.009, 0.0, abs(f - 0.5)) * 0.42;
		float f2 = fbm(g * 2.1 + 3.0);
		col += vec3(1.0, 0.42, 0.10) * ss(0.006, 0.0, abs(f2 - 0.5)) * 0.16;
	}
	// glowing stones scattered over it
	for (int i = 0; i < 13; i++) {
		float fi = float(i);
		float h = hash11(fi * 5.9);
		vec2 c = tablePoint(vec2((hash11(fi * 2.3) - 0.5) * 17.0, 5.1 + hash11(fi * 7.1) * 9.4));
		float r = (0.013 + 0.017 * h) * tableScale(c.y);
		if (abs(a.x - c.x) > r * 3.4 || abs(a.y - c.y) > r * 3.0) continue;
		float win = win1(a.x, c.x - r * 3.2, c.x + r * 3.2, r * 0.4) * win1(a.y, c.y - r * 2.8, c.y + r * 2.8, r * 0.4);
		float d = ellip(a, c, vec2(r * 1.4, r * 0.85), h * 2.0);
		if (h > 0.5) col += vec3(1.0, 0.44, 0.10) * ss(r * 3.0, 0.0, distance(a, c)) * 0.30 * win;
		col = mix(col, mix(vec3(0.26, 0.19, 0.21), vec3(0.11, 0.08, 0.10), ss(-r, r, a.y - c.y)), aafill(d) * win);
		if (h > 0.5) col = mix(col, vec3(1.0, 0.66, 0.24), aaline(d, r * 0.11) * ss(c.y, c.y - r, a.y) * win * 0.8);
	}
	// the far end of the plain is hot, which is where all the light comes from
	col = tableFar(col, a, vec3(0.22, 0.11, 0.15), 0.40);
	col += vec3(1.0, 0.42, 0.14) * ss(0.62, 0.0, a.y + 0.22) * 0.09;
	return col;
}

vec3 lumeDyn(vec3 col, vec2 a, float t) {
	vec2 g = tableUV(a);
	// three lava runs crossing the plain, each drifting at its own rate. The
	// crust is what makes it read as molten rock: dark plates riding the flow,
	// with the hot seams between them carried along together.
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float base = (fi - 1.0) * 4.6 + 0.8;
		float w = 0.20 + fi * 0.06;
		float cx = base + 1.6 * sin(g.y * 0.26 + fi * 2.1) + 0.5 * sin(g.y * 0.7 - fi);
		float dy = abs(g.x - cx);
		if (dy > w * 3.0) continue;
		float win = 1.0 - ss(w * 2.2, w * 2.9, dy);
		col = mix(col, vec3(0.085, 0.058, 0.078), ss(w * 2.0, w * 1.05, dy) * win);
		float body = ss(w, w * 0.86, dy);
		vec2 q = vec2((g.x - cx) / w * 1.4, g.y * 0.85 - t * (0.55 + fi * 0.12));
		float plate = fbm(q);
		float seam = ss(0.038, 0.0, abs(plate - 0.5));
		float edge = ss(0.55, 1.0, dy / w);
		float heat = clamp(seam * 0.85 + edge * 0.55, 0.0, 1.0);
		vec3 rock = mix(vec3(0.16, 0.09, 0.10), vec3(0.30, 0.16, 0.14), ss(0.35, 0.62, plate));
		vec3 hot = mix(vec3(0.92, 0.30, 0.04), vec3(1.00, 0.74, 0.30), ss(0.50, 1.0, heat));
		col = mix(col, mix(rock, hot, ss(0.26, 0.72, heat)), body * win);
		col += vec3(1.0, 0.40, 0.09) * ss(w * 2.8, w * 0.6, dy) * 0.10 * win;
	}
	// two blobs bouncing along the middle run, out of step with each other
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float w = 6.4 + fi * 2.8;
		float lane = tableRow(w);
		float sc = tableScale(lane);
		float span = aspect + 0.9;
		float x = -0.45 + mod(t * (0.085 + fi * 0.035) + fi * 2.7, span + 1.1);
		float hop = abs(sin(t * (2.6 + fi * 0.7) + fi * 1.3));
		float sz = (0.046 - fi * 0.008) * sc;
		col = lumeShadow(col, a, vec2(x, lane + sz * 0.35), vec2(sz * 1.5, sz * 0.35), 0.5 * (1.0 - hop * 0.6));
		col = blobAt(col, a, vec2(x, lane - sz * 0.55 - hop * sz * 1.9), sz, ss(0.30, 0.0, hop) * 0.35, 0.30 + 0.30 * hop);
	}
	// smoke puffs drifting up off the hot ground, out toward the far edge
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float ph = fract(t * 0.10 + fi * 0.33);
		vec2 c = vec2(aspect * (0.16 + 0.34 * fi) + 0.05 * sin(t * 0.6 + fi), 0.34 - ph * 0.30);
		float r = 0.016 + ph * 0.052;
		float k = (1.0 - ph) * ss(0.0, 0.12, ph);
		if (abs(a.x - c.x) > r * 2.6 || abs(a.y - c.y) > r * 2.6) continue;
		float d = sdCircle(a - c, r);
		for (int j = 0; j < 3; j++) {
			float fj = float(j);
			d = smin(d, sdCircle(a - c - r * 0.85 * vec2(cos(fj * 2.1 + fi), sin(fj * 2.1 + fi)), r * 0.60), r * 0.5);
		}
		col = mix(col, vec3(0.46, 0.34, 0.38), ss(0.008, -0.004, d) * k * 0.50);
	}
	// and the far end breathing, as whatever is out there flares
	col += vec3(1.0, 0.42, 0.14) * ss(0.62, 0.0, a.y + 0.22) * (0.02 + 0.02 * sin(t * 0.7));
	return col;
}
"

# ===========================================================================
# 07 — ARCADE NIGHT
# ===========================================================================
# The floor of an arcade at night: the classic dark carpet with its neon
# confetti, the machines all off frame around the player, and everything you can
# actually see of them — the coloured light they throw down, the pools under each
# one, the sweep of a sign turning overhead — landing on the carpet.
const ARCADE := "
vec3 lumeHaze() { return vec3(0.16, 0.10, 0.30); }

// The colour a cabinet at bearing `u` throws down the carpet: a long soft wedge
// widening as it comes toward the player. Six of these ARE the room.
vec3 spill(vec3 col, vec2 g, float u0, float w0, vec3 c, float k) {
	float d = abs(g.x - u0 * (g.y / 12.0));
	float wide = w0 * (0.35 + 0.75 * (g.y / 12.0));
	return col + c * ss(wide, 0.0, d) * ss(4.6, 12.4, g.y) * k;
}

vec3 lumeStatic(vec2 a) {
	vec2 g = tableUV(a);
	vec3 col = vec3(0.055, 0.035, 0.115);
	// the carpet: a black ground with neon confetti scattered on it, drawn in
	// tabletop metres so the pattern crowds together toward the far end
	{
		vec2 q = g * 1.35;
		vec2 cell = floor(q);
		vec2 f = fract(q) - 0.5;
		for (int j = 0; j < 3; j++) {
			float fj = float(j);
			vec2 cc = cell + fj * 7.0;
			float h1 = hash21(cc + fj * 7.0);
			float h2 = hash21(cc + fj * 13.0 + 3.0);
			float h3 = hash21(cc + fj * 29.0 + 9.0);
			// Kept INSIDE its own cell: a jitter wide enough to cross the wall
			// leaves each piece cut in half along it, and the cut lines read as a
			// grid drawn over the carpet.
			vec2 jp = f - (vec2(h1, h2) - 0.5) * 0.44;
			vec3 cc2 = vec3(0.95, 0.24, 0.42);
			if (h3 > 0.75) cc2 = vec3(0.32, 0.92, 0.66);
			else if (h3 > 0.50) cc2 = vec3(0.30, 0.62, 0.98);
			else if (h3 > 0.25) cc2 = vec3(0.99, 0.78, 0.24);
			float sz = 0.055 + 0.045 * h1;
			float d = (h2 > 0.5)
				? sdRBox(jp * rot(h1 * 3.0), vec2(sz * 1.7, sz * 0.45), sz * 0.4)
				: sdCircle(jp, sz);
			col = mix(col, cc2 * 0.85, aafill(d) * 0.9);
		}
		// and the woven grain under it
		col *= 0.90 + 0.16 * hash21(floor(g * 34.0));
	}
	// the light the machines throw down onto it
	col = spill(col, g, -3.2, 1.5, vec3(0.95, 0.20, 0.40), 0.26);
	col = spill(col, g, -1.1, 1.3, vec3(0.28, 0.70, 0.99), 0.24);
	col = spill(col, g, 0.9, 1.4, vec3(0.32, 0.94, 0.62), 0.22);
	col = spill(col, g, 2.9, 1.5, vec3(0.99, 0.74, 0.24), 0.24);
	col = spill(col, g, 4.8, 1.3, vec3(0.68, 0.40, 0.98), 0.22);
	// tokens dropped on the carpet
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		float h = hash11(fi * 6.3);
		vec2 c = tablePoint(vec2((hash11(fi * 2.9) - 0.5) * 15.0, 5.2 + hash11(fi * 4.7) * 8.4));
		float r = 0.011 * tableScale(c.y);
		if (abs(a.x - c.x) > r * 3.0 || abs(a.y - c.y) > r * 3.0) continue;
		float win = win1(a.x, c.x - r * 2.8, c.x + r * 2.8, r * 0.4) * win1(a.y, c.y - r * 2.8, c.y + r * 2.8, r * 0.4);
		float d = ellip(a, c, vec2(r, r * 0.62), 0.0);
		col += vec3(1.0, 0.82, 0.34) * ss(r * 2.6, 0.0, distance(a, c)) * 0.22 * win;
		col = mix(col, mix(vec3(0.99, 0.82, 0.36), vec3(0.72, 0.52, 0.16), ss(-r, r, a.y - c.y)), aafill(d) * win);
		col = mix(col, vec3(1.0, 0.95, 0.72), aaline(d, r * 0.16) * win * 0.7);
	}
	col = tableFar(col, a, vec3(0.13, 0.07, 0.24), 0.45);
	return col;
}

vec3 lumeDyn(vec3 col, vec2 a, float t) {
	vec2 g = tableUV(a);
	// The machines are off frame, so what changes on screen when their screens
	// change is the COLOUR of the light each one lays down. Every cabinet holds a
	// game for a few seconds and then switches, on its own clock.
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float h = hash11(fi * 3.9);
		float step0 = floor(t / (3.4 + h * 2.6) + fi * 1.7);
		float k = hash11(step0 * 7.3 + fi * 11.0);
		vec3 c = vec3(0.95, 0.20, 0.40);
		if (k > 0.75) c = vec3(0.32, 0.94, 0.62);
		else if (k > 0.50) c = vec3(0.30, 0.62, 0.98);
		else if (k > 0.25) c = vec3(0.99, 0.74, 0.24);
		// a flicker, so a screen reads as a screen and not as a lamp
		float fl = 0.80 + 0.20 * sin(t * 11.0 + fi * 2.0) * ss(0.4, 1.0, hash11(step0 + fi));
		col = spill(col, g, -3.2 + fi * 2.0, 1.4, c, 0.30 * fl);
	}
	// a sign turning overhead, sweeping its light across the carpet
	{
		float sw = mod(t * 0.24, 2.4) - 1.2;
		float d = abs(g.x - sw * (2.2 + g.y * 0.55));
		col += vec3(0.42, 0.30, 0.90) * ss(2.4 + g.y * 0.18, 0.0, d) * 0.16;
	}
	// pixels drifting low over the carpet, and the glints they strike off it
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float h = hash11(fi * 8.1);
		float w = 6.0 + fi * 2.2;
		float lane = tableRow(w);
		float sc = tableScale(lane);
		float x = mod(0.3 + fi * 0.9 + t * (0.055 + 0.03 * h), aspect + 0.5) - 0.25;
		float y = lane - 0.055 * sc + 0.020 * sc * sin(t * (1.1 + h) + fi * 2.0);
		vec2 p = (a - vec2(x, y)) / (0.020 * sc);
		if (abs(p.x) > 2.2 || abs(p.y) > 2.2) continue;
		float win = win1(p.x, -2.1, 2.1, 0.2) * win1(p.y, -2.1, 2.1, 0.2);
		vec3 c = vec3(0.95, 0.24, 0.42);
		if (h > 0.66) c = vec3(0.32, 0.92, 0.66); else if (h > 0.33) c = vec3(0.30, 0.62, 0.98);
		col += c * ss(1.9, 0.0, length(p)) * 0.30 * win;
		col = mix(col, mix(c, vec3(1.0), 0.35), aafill(sdRBox(p, vec2(0.55), 0.16)) * win);
	}
	return col;
}
"

# ===========================================================================
# 08 — BUTTON KINGDOM
# ===========================================================================
# The courtyard. Every piece of it is a button: the flagstones carry cap-shaped
# inlays, the great seal in the middle of the floor is the five of them, the
# banners hanging over the frame wear them, and the citizens crossing the yard
# ARE them. Nothing here is decorated with buttons — it is built of them, which
# is the difference between a motif and a world.
const KINGDOM := "
vec3 lumeHaze() { return vec3(0.86, 0.74, 0.58); }

// A citizen: a cap with two legs and two eyes, walking. `ph` drives the stride,
// and the whole body bobs with it.
vec3 citizenAt(vec3 col, vec2 a, vec2 foot, float s, vec3 c, float ph, float face) {
	vec2 p = (a - foot) / s;
	if (abs(p.x) > 1.7 || p.y > 0.55 || p.y < -2.3) return col;
	float win = win1(p.x, -1.6, 1.6, 0.14) * win1(p.y, -2.2, 0.48, 0.14);
	col = mix(col, col * 0.62, aafill(ellip(p, vec2(0.10, 0.10), vec2(0.85, 0.24), 0.0)) * 0.55 * win);
	float bob = 0.09 * abs(sin(ph));
	p.y += bob;
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float sw = sin(ph + fi * 3.1416) * 0.34;
		col = mix(col, c * 0.45, aafill(sdSeg(p, vec2((fi - 0.5) * 0.34, -0.72), vec2((fi - 0.5) * 0.34 + sw, -0.05), 0.10)) * win);
		col = mix(col, c * 0.32, aafill(ellip(p, vec2((fi - 0.5) * 0.34 + sw * 1.15, -0.02), vec2(0.19, 0.085), 0.0)) * win);
	}
	float d = sdCircle(p - vec2(0.0, -1.30), 0.62);
	float da = aafill(d) * win;
	col = mix(col, mix(c * 1.18, c * 0.60, ss(-1.9, -0.7, p.y)), da);
	col = mix(col, vec3(0.96, 0.96, 0.98), aaline(sdCircle(p - vec2(0.0, -1.30), 0.40), 0.065) * da * 0.85);
	col = mix(col, c * 0.42, aaline(d, 0.045) * da * 0.8);
	col = mix(col, vec3(1.0, 1.0, 0.99), aafill(min(sdCircle(p - vec2(-0.20 + face * 0.05, -1.42), 0.145),
		sdCircle(p - vec2(0.20 + face * 0.05, -1.42), 0.145))) * win);
	col = mix(col, vec3(0.09, 0.07, 0.11), aafill(min(sdCircle(p - vec2(-0.18 + face * 0.10, -1.42), 0.070),
		sdCircle(p - vec2(0.22 + face * 0.10, -1.42), 0.070))) * win);
	col = mix(col, vec3(0.20, 0.10, 0.12), aaline(sdCircle(p - vec2(face * 0.05, -1.02), 0.24), 0.026) * step(p.y, -1.16) * win * 0.9);
	return col;
}

// A banner hanging into the frame from a pole above it, with a cap on its face.
vec3 bannerAt(vec3 col, vec2 a, float x, float len, float wdt, vec3 c, vec3 cap, float t, float ph) {
	float wave = 0.020 * sin(a.y * 22.0 - t * 2.0 + ph);
	vec2 p = a - vec2(x + wave, 0.0);
	if (abs(p.x) > wdt * 1.9 || p.y > len + 0.06) return col;
	float win = win1(p.x, -wdt * 1.8, wdt * 1.8, wdt * 0.25) * win1(p.y, -0.4, len + 0.05, 0.03);
	// the cloth, pointed at the bottom
	float d = max(abs(p.x) - wdt, max(-p.y - 0.02, p.y - len + abs(p.x) * 0.9));
	float da = aafill(d) * win;
	col = mix(col, mix(c * 1.12, c * 0.62, ss(-wdt, wdt, p.x - wave * 6.0)), da);
	col = mix(col, c * 1.4, aaline(d, wdt * 0.10) * da * 0.5);
	// the gold hem and the cap on its face
	col = mix(col, vec3(0.95, 0.80, 0.36), aaline(p.y - len * 0.86 + abs(p.x) * 0.9, wdt * 0.09) * da);
	col = placeDisc(col, a, vec2(x + wave * 1.4, len * 0.46), wdt * 0.52, cap, 1.0, 0.05);
	return col;
}

vec3 lumeStatic(vec2 a) {
	vec2 g = tableUV(a);
	// flagstones, laid in tabletop metres so the courses crowd with distance
	vec2 q = g * 0.62;
	vec2 cell = floor(q + vec2(0.5 * floor(q.y), 0.0));
	vec2 f = fract(q + vec2(0.5 * floor(q.y), 0.0)) - 0.5;
	float h = hash21(cell);
	vec3 stone = mix(vec3(0.78, 0.71, 0.60), vec3(0.62, 0.55, 0.46), h);
	stone *= 0.95 + 0.10 * hash21(floor(g * 30.0));
	float seam = min(0.5 - abs(f.x), 0.5 - abs(f.y));
	vec3 col = stone;
	col *= 1.0 - 0.42 * ss(0.075, 0.0, seam);
	col += vec3(1.0, 0.95, 0.86) * ss(0.13, 0.055, seam) * 0.10;
	// a cap inlaid into every fourth flagstone
	if (h > 0.72) {
		vec3 cc = vec3(0.92, 0.34, 0.40);
		float k = hash21(cell + 31.0);
		if (k > 0.75) cc = vec3(0.66, 0.44, 0.94);
		else if (k > 0.50) cc = vec3(0.34, 0.66, 0.95);
		else if (k > 0.25) cc = vec3(0.42, 0.78, 0.52);
		col = mix(col, cc * 0.80, aafill(sdCircle(f, 0.26)) * 0.7);
		col = mix(col, vec3(0.95, 0.93, 0.88), aaline(sdCircle(f, 0.16), 0.035) * 0.7);
	}
	// the carpet running away from the player toward the keep
	{
		float d = abs(g.x - 0.5) - 1.55;
		float da = aafill(d);
		col = mix(col, mix(vec3(0.72, 0.17, 0.22), vec3(0.54, 0.11, 0.16), ss(-1.5, 1.5, g.x - 0.5)), da);
		col = mix(col, vec3(0.95, 0.80, 0.36), aaline(abs(g.x - 0.5) - 1.34, 0.075) * da);
		col = mix(col, vec3(0.86, 0.26, 0.30), ss(0.10, 0.0, abs(fract(g.y * 0.85) - 0.5)) * da * 0.4);
		// a woven diamond down the length of it
		{
			vec2 w = vec2((g.x - 0.5) * 0.9, g.y * 0.55);
			float dia = abs(fract(w.x + w.y) - 0.5) + abs(fract(w.x - w.y) - 0.5);
			col = mix(col, vec3(0.84, 0.30, 0.34), ss(0.62, 0.44, dia) * da * 0.45);
		}
		col = mix(col, vec3(0.95, 0.80, 0.36), aaline(d, 0.055) * 0.8);
	}
	col = tableFar(col, a, vec3(0.95, 0.80, 0.58), 0.46);
	// the light coming down the yard from whatever is out there
	col += vec3(1.0, 0.80, 0.44) * ss(0.90, 0.0, a.y + 0.16) * 0.20;
	return col;
}

vec3 lumeDyn(vec3 col, vec2 a, float t) {
	vec2 g = tableUV(a);
	// THE GREAT SEAL: the five caps set into the courtyard floor, lighting in turn
	// and then all together — the one moment in these ten worlds where the scenery
	// plays the game.
	{
		float cycle = fract(t / 6.0);
		for (int i = 0; i < 5; i++) {
			float fi = float(i);
			float ang = -1.5708 + fi * 1.2566;
			vec2 uw = vec2(0.5, 9.6) + vec2(cos(ang), sin(ang) * 0.62) * 2.35;
			vec2 c = tablePoint(uw);
			float r = 0.048 * tableScale(c.y);
			vec3 cc = vec3(0.95, 0.30, 0.36);
			if (i == 1) cc = vec3(0.99, 0.79, 0.24);
			else if (i == 2) cc = vec3(0.28, 0.80, 0.55);
			else if (i == 3) cc = vec3(0.32, 0.64, 0.96);
			else if (i == 4) cc = vec3(0.68, 0.44, 0.96);
			float lit = ss(0.06, 0.0, abs(cycle - 0.06 - fi * 0.09)) * 0.9
				+ ss(0.10, 0.0, abs(cycle - 0.74)) * 1.0;
			col = placeDisc(col, a, c, r, cc, 1.0, 0.06 + 0.55 * lit);
		}
		// the ring the five sit in, measured in the SAME tabletop metres the caps
		// are placed by — in screen units it lands somewhere else entirely
		float rd = abs(length((g - vec2(0.5, 9.6)) / vec2(1.0, 0.62)) - 2.35) - 0.16;
		col = mix(col, vec3(0.95, 0.82, 0.42), ss(0.06, -0.04, rd) * 0.55);
	}
	// torchlight pools along both sides of the yard, breathing out of step
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float side = (mod(fi, 2.0) < 0.5) ? -1.0 : 1.0;
		vec2 uw = vec2(0.5 + side * 3.6, 6.4 + floor(fi * 0.5) * 4.2);
		float d = length((g - uw) / vec2(2.1, 2.6));
		col += vec3(1.0, 0.70, 0.34) * ss(1.0, 0.0, d) * (0.16 + 0.05 * sin(t * 3.1 + fi * 1.7));
	}
	// banners hanging over the yard from a rail above the frame
	col = bannerAt(col, a, aspect * 0.115, 0.30, 0.052, vec3(0.34, 0.64, 0.94), vec3(0.99, 0.79, 0.24), t, 0.0);
	col = bannerAt(col, a, aspect * 0.385, 0.24, 0.044, vec3(0.90, 0.36, 0.42), vec3(0.28, 0.80, 0.55), t, 1.4);
	col = bannerAt(col, a, aspect * 0.640, 0.26, 0.046, vec3(0.44, 0.76, 0.52), vec3(0.32, 0.64, 0.96), t, 2.8);
	col = bannerAt(col, a, aspect * 0.885, 0.32, 0.054, vec3(0.66, 0.44, 0.94), vec3(0.95, 0.30, 0.36), t, 4.2);
	// buttons floating over the courtyard, bobbing on their own beats
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float h = hash11(fi * 6.1);
		vec3 cc = vec3(0.95, 0.30, 0.36);
		if (i == 1) cc = vec3(0.99, 0.79, 0.24);
		else if (i == 2) cc = vec3(0.28, 0.80, 0.55);
		else if (i == 3) cc = vec3(0.32, 0.64, 0.96);
		float x = mod(0.35 + fi * 0.86 + t * (0.010 + 0.008 * h), aspect + 0.6) - 0.3;
		float y = 0.055 + 0.115 * h + 0.016 * sin(t * (0.8 + 0.5 * h) + fi * 1.7);
		col = placeDisc(col, a, vec2(x, y), 0.024 + 0.010 * h, cc, 1.0, 0.10 + 0.09 * sin(t * 1.9 + fi));
	}
	// and the citizens, crossing the yard. Each turns round at the ends of its own
	// beat rather than looping, so the courtyard is never a conveyor.
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float h = hash11(fi * 9.3);
		float w = 6.1 + fi * 2.3;
		float lane = tableRow(w);
		float sc = tableScale(lane);
		float per = 17.0 + h * 9.0;
		float tri = abs(fract(t / per + fi * 0.31) * 2.0 - 1.0);
		float lim = 0.50 * w;
		float x = tablePoint(vec2(mix(-lim, lim, ss(0.05, 0.95, tri)), w)).x;
		float go = ss(0.02, 0.10, tri) * ss(0.98, 0.90, tri);
		vec3 cc = vec3(0.99, 0.79, 0.24);
		if (i == 1) cc = vec3(0.32, 0.64, 0.96);
		else if (i == 2) cc = vec3(0.68, 0.44, 0.96);
		col = citizenAt(col, a, vec2(x, lane), 0.062 * sc, cc, t * 5.0 * go, (tri < 0.5) ? 1.0 : -1.0);
	}
	return col;
}
"

# ===========================================================================
# 01 — RAINBOW SKYWAY
# ===========================================================================
# A cloudstone terrace floating in open sky, and the whole trick of it is where
# the terrace ENDS. Its far rim is an arc that peaks just under the top edge of
# the frame and falls away into the two upper corners, so the only sky in shot is
# a pair of corner wedges and no straight line crosses the picture anywhere. A
# rim drawn level would be a horizon, and a horizon is what turns a background
# back into a poster with the buttons stuck on it.
#
# THE RAINBOW IS ON THE TERRACE, not in the air over it, and the birds are
# standing on it rather than flying above it. Both were built the other way first
# — a bow arching across the sky and four birds gliding through the top band — and
# both had the same thing wrong with them: they lived in the strip of frame the
# board does not reach, so they belonged to a different picture from the buttons.
# Put on the surface, the bow is a circle in TABLETOP metres that the buttons
# stand on and the birds are props with contact shadows, and everything in the
# frame is in one place again. That is the same rule as the tabletop itself, one
# level further in: it is not enough for the GROUND to be the ground if everything
# alive is still hanging in the sky above it.
#
# Its five bands are the five LUMEO key colours in the order a rainbow puts them,
# which is what makes it this game's rainbow.
const RAINBOW := "
vec3 lumeHaze() { return vec3(0.91, 0.92, 0.99); }

// ---- How much TERRACE there is at a point: 1 at the player's feet, 0 out past
// the bow. NOT an edge — a dissolve, and that is the whole of this block.
//
// This shipped twice as a real rim: an ellipse solved against the frame, with a
// lit lip, a shaded thickness and a bounce off the cloud sea below. Both times the
// top of the picture came out as a line across the sky, because that is what a rim
// IS however carefully it is drawn. What is wanted beyond the rainbow is sky, so
// the stone simply gets further away until there is none of it left, over about
// two and a half metres of tabletop — roughly a.y 0.24 down to 0.07 in the middle
// of the frame. There is no boundary anywhere for the eye to catch on.
//
// Keyed on DEPTH plus a little of |across|, not on a closed shape. An ellipse
// dissolves its sides far sooner than its middle (the frame's corners sit close to
// the curve while its centre is metres inside it), which ate the left and right
// thirds of the floor; the |g.x| term is just enough to pull the far corners in
// first and keep a hint of an island without ever drawing one.
float deckAmt(vec2 g) { return ss(12.6, 10.0, g.y + 0.10 * abs(g.x)); }

// The tabletop u that lands on the frame's own EDGE at depth w — the same helper
// Deep Ocean dresses its gutters with, and for the same reason: a prop pinned to a
// constant u sits in the margin at 16:9 and walks in over the buttons at 21:9.
float edgeU(float w) { return aspect * 0.3153 * w; }

// ---- The five LUMEO key colours in the order a rainbow puts them. Every band of
// colour in this world — the arch and the wash it lays on the floor — is read off
// this one ramp, which is what makes it this game's rainbow and not a generic
// spectrum.
//
// It is also the ONLY place the LUMEO motif appears here, deliberately. Every
// other world carries a key cap as an object, and this one was built with two of
// them adrift in the corners; but the corners are the only sky in the frame and
// they are also where the LEVEL badge and the close button live, so a cap out
// there reads as a stray coin crowding the HUD at every size that is visible at
// all. A rainbow made of the five button colours is a stronger claim on the game
// than a trinket in the margin. ----
vec3 lumeBow(float x01) {
	float x = clamp(x01, 0.0, 1.0) * 4.0;
	vec3 c = mix(vec3(0.99, 0.36, 0.40), vec3(1.0, 0.80, 0.30), ss(0.0, 1.0, x));
	c = mix(c, vec3(0.38, 0.86, 0.58), ss(1.0, 2.0, x));
	c = mix(c, vec3(0.38, 0.72, 0.99), ss(2.0, 3.0, x));
	c = mix(c, vec3(0.74, 0.50, 0.99), ss(3.0, 4.0, x));
	return c;
}

// ---- The bow, and the whole of what makes this world work: it is a circle in
// TABLETOP METRES, so what the frame gets is that circle IN PERSPECTIVE — an arch
// lying ON the terrace that the buttons stand on, not a band hung in the air
// behind them. Centre and radius are solved against the frame: the crown lands at
// a.y 0.299 and the two feet run off the side edges at 0.628 (16:9) / 0.891
// (21:9), so it sweeps the side gutters and passes under the board. It sits that
// far forward on purpose: further back its far edge runs into the rim vapour and
// the thickest of the distance haze, which is where its red half went.
//
// Only the FAR half of the circle is ever in shot, which is why one circle gives
// an arch and not a closed ring: at every depth the frame reaches, the near half's
// |u| is already wider than the picture.
const vec2 BOW_C = vec2(0.0, 5.20);
const float BOW_R = 4.10;
const float BOW_HW = 0.62;      // half the band's width across all five colours, in metres

// Signed distance across the band in metres — negative on the near side of the
// arc, positive on the far side. It doubles as the position along the colour ramp,
// so one length() buys the band, its colour and its spill.
float bowD(vec2 g) { return length(g - BOW_C) - BOW_R; }
vec3 bowCol(float d) { return lumeBow(clamp(0.5 - d / (2.0 * BOW_HW), 0.0, 1.0)); }

// ---- A bird flying LOW ACROSS the terrace: in at the right, out at the left.
// It flies on a tabletop lane at a fixed DEPTH, so its size comes from how far
// away it is, and its shadow tracks the stone underneath it. That shadow is the
// whole reason it reads as a bird in this place rather than one gliding over the
// top of the picture, which is what the first pass drew and what made it belong
// to a different scene from the buttons.
//
// The shared toolbox's placeBird only ever faces +x. These fly the other way, so
// this is that same wrapper with the profile mirrored. ----
vec3 placeBirdDir(vec3 col, vec2 a, vec2 pos, float s, float flap, int kind, float dark, float dir) {
	vec2 bp = (a - pos) / s;
	bp.x *= dir;
	if (abs(bp.x) > 1.56 || abs(bp.y) > 1.34) return col;
	vec4 b = birdProfile(bp, flap, kind);
	float win = win1(bp.x, -1.50, 1.50, 0.18) * win1(bp.y, -1.28, 1.28, 0.18);
	return mix(col, mix(b.rgb, vec3(0.09, 0.06, 0.09), dark), b.a * win);
}

// Same traverse as Deep Ocean's fish, and for the same reasons: the limit is a
// multiple of edgeU(w) so one `cross` is one screen speed at every depth, and
// per - cross is the gap it spends off frame so a row of them is not a conveyor.
vec3 birdCross(vec3 col, vec2 a, float t, float w, float per, float cross, float ph,
		int kind, float sz) {
	float u01 = fract(t / per + ph) * per / cross;
	if (u01 > 1.0) return col;
	float lim = edgeU(w) * 1.22;
	vec2 pt = tablePoint(vec2(mix(lim, -lim, u01), w));
	float s = sz * tableScale(pt.y);
	// how high it is flying, which is also how far its shadow trails behind it
	float rise = s * (1.30 + 0.24 * sin(t * 0.85 + ph * 9.0));
	col = lumeShadow(col, a, pt + vec2(s * 0.22, s * 0.08), vec2(s * 1.00, s * 0.26), 0.48);
	return placeBirdDir(col, a, pt - vec2(0.0, rise), s,
		sin(t * 6.2 + ph * 5.0), kind, 0.34, -1.0);
}

// ---- The sky. Plain: a gradient, the sun's warmth off the upper right, and
// nothing else in it. There was a cloud SEA here — billowing fbm tops each with a
// lit lip — which is what the terrace was floating OVER back when it had an edge
// to float over. With the edge gone it was just texture stacked under the horizon
// that is no longer there. The only clouds left are the three drifting through it
// in lumeDyn, which is what sky actually has in it. ----
vec3 skyBeyond(vec2 a) {
	vec3 col = mix(vec3(0.60, 0.78, 0.99), vec3(0.84, 0.91, 1.0), ss(-0.06, 0.30, a.y));
	col += vec3(1.0, 0.86, 0.58) * ss(1.30, 0.0, distance(a, vec2(aspect * 0.95, -0.14))) * 0.12;
	return col;
}

// ---- The terrace surface: pale cloudstone laid in small flagstones, drawn in
// tabletop metres so the joints crowd together into the distance on their own and
// stop being drawn at all before they get fine enough to shimmer. ----
vec3 deckAt(vec2 a, vec2 g) {
	// Warm stone, not white. The terrace was near-white through several passes and
	// every colour laid on it came out pastel: a 0.3 mix toward a saturated red over
	// something that bright is pink. The floor has to have somewhere to go.
	vec3 col = mix(vec3(0.97, 0.93, 0.86), vec3(0.58, 0.68, 0.89), ss(4.2, 11.6, g.y));
	// Laid in a BROKEN BOND — every other course offset half a stone. A square grid
	// recedes just as correctly and still reads as graph paper, because the eye
	// picks up the continuous cross-joints running away from it; staggering them is
	// the whole difference between a paved terrace and a pattern.
	vec2 P = vec2(0.66, 0.44);
	float course = floor(g.y / P.y);
	vec2 gg = vec2(g.x + mod(course, 2.0) * P.x * 0.5, g.y);
	vec2 f = (fract(gg / P) - 0.5) * P;
	float td = sdRBox(f, P * 0.5 - vec2(0.030), 0.09);
	float fade = ss(12.5, 4.6, g.y);
	// every stone a shade of its own, so the floor is a laid surface and not a fill
	col *= mix(1.0, 0.966 + 0.058 * hash21(floor(gg / P)), fade);
	col = mix(col * 0.862, col, mix(1.0, ss(-0.038, 0.008, td), fade));
	// a chalky bevel just inside each joint — what gives the stone thickness at the
	// near end of the frame, where the joints are widest
	col = mix(col, col * 1.085, ss(-0.018, -0.058, td) * ss(-0.108, -0.058, td) * fade);
	col *= 0.988 + 0.024 * fbm(g * 3.4);
	// sunlight from off the upper right
	col += vec3(1.0, 0.88, 0.60) * ss(1.40, 0.0, distance(a, vec2(aspect * 0.95, -0.14))) * 0.115;
	// Distance haze, pulled hard toward the SKY's own colour rather than to a
	// generic pale blue. The far stone has to arrive at the sky it is dissolving
	// into, or the dissolve has a value step left in it to give itself away.
	col = tableFar(col, a, vec3(0.73, 0.85, 0.99), 0.58);
	// THE BOW GOES ON LAST — after the rim vapour and after the distance haze, and
	// that ordering is not tidiness. Painted before them it lost its entire red
	// half: the vapour band and the haze both land exactly where the arch's far
	// edge does, and between them they took a saturated red to grey. It is light
	// lying on the stone, so it is the one thing on this floor the air in front of
	// it does not get to flatten — only soften, at half the rate (`far`).
	//
	// MIXED rather than replaced, so the joints, the bevels and the grain all still
	// read through it. The moment it hides the stone the surface stops being one.
	float bd = bowD(g);
	float far = 1.0 - 0.28 * ss(1.05, -0.10, a.y);
	col = mix(col, bowCol(bd), radWin(abs(bd), BOW_HW * 0.80, BOW_HW * 1.14) * 0.97 * far);
	// and the light it spills onto the stone either side — the SAME ramp run five
	// times as wide, so the spectrum keeps going out across the floor instead of
	// clamping to violet on one side and red on the other and flattening both.
	// This is where most of the colour in this world actually is.
	col = mix(col, lumeBow(clamp(0.5 - bd / (2.0 * BOW_HW * 5.0), 0.0, 1.0)),
		radWin(abs(bd), BOW_HW * 1.08, BOW_HW * 5.20) * 0.44 * far);
	return col;
}

vec3 lumeStatic(vec2 a) {
	vec2 g = tableUV(a);
	float on = deckAmt(g);
	vec3 col = skyBeyond(a);
	if (on > 0.003) col = mix(col, deckAt(a, g), on);
	return col;
}

vec3 lumeDyn(vec3 col, vec2 a, float t) {
	vec2 g = tableUV(a);
	float dk = deckAmt(g);
	// two cloud shadows crossing the terrace at different speeds and depths. This
	// is the whole of the light moving on this floor, and it is what stops a baked
	// plate reading as a photograph.
	{
		float x = mod(g.x + 8.0 - t * 0.52, 30.0) - 15.0;
		col *= 1.0 - 0.115 * ss(3.1, 0.0, abs(x)) * ss(4.2, 0.0, abs(g.y - 6.8)) * dk;
	}
	{
		float x = mod(g.x - 5.0 + t * 0.33, 24.0) - 12.0;
		col *= 1.0 - 0.080 * ss(1.9, 0.0, abs(x)) * ss(2.8, 0.0, abs(g.y - 9.6)) * dk;
	}
	// and the bow breathing under them, so the colour on the floor is never quite
	// still either
	{
		float bd = bowD(g);
		col += bowCol(bd) * radWin(abs(bd), BOW_HW * 0.60, BOW_HW * 2.60) * dk
			* (0.036 + 0.030 * sin(t * 0.31));
	}
	float sky = 1.0 - dk;
	if (sky > 0.02) {
		// wisps drifting over the drop. They are the only clouds here that move, so
		// they are the only ones not in the plate — a cloud drawn in both halves
		// leaves a frozen ghost of the plate copy everywhere the live one has been.
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float h = hash11(fi * 4.1 + 2.0);
			float x = mix(-0.30, aspect + 0.30, fract(t / (46.0 + h * 28.0) + fi * 0.37));
			vec3 was = col;
			col = placeCloud(col, a, vec2(x, 0.058 + 0.072 * h), 0.052 + 0.030 * h,
				fi * 13.7 + 4.0, vec3(1.0, 0.99, 0.97), vec3(0.74, 0.81, 0.96));
			col = mix(was, col, sky);
		}
	}
	// The birds, ON the terrace — pottering about on the stone with the board rather
	// than gliding over the top of the frame. Their lanes are tabletop DEPTHS, so
	// each one is sized and placed by the surface it is standing on; the two near
	// ones land low in the frame, below the buttons, and the two further back cross
	// the gutters at mid height.
	// The birds, flying RIGHT TO LEFT low over the terrace: in at one edge, out at
	// the other, each on its own tabletop lane. Same 11.5-15.5 s crossings the fish
	// in Deep Ocean use, so the two worlds move at one pace.
	col = birdCross(col, a, t, 5.90, 20.0, 14.5, 0.00, 0, 0.055);
	col = birdCross(col, a, t, 7.10, 18.0, 12.5, 0.44, 2, 0.048);
	col = birdCross(col, a, t, 8.60, 22.0, 15.5, 0.71, 1, 0.042);
	col = birdCross(col, a, t, 9.40, 17.0, 11.5, 0.27, 0, 0.038);
	return col;
}
"
# ===========================================================================
# 02 — DEEP OCEAN
# ===========================================================================
# The sea floor, with the water overhead rather than in front. The whole frame is
# rippled sand going away from the player; the rocks, the coral heads and the sea
# fans are scattered ON it in tabletop metres, each with the contact shadow that
# stops it floating; and the two things that are not on the floor - the kelp
# hanging in from a holdfast off the top edge, and the shafts of surface light
# coming down through the water - are overhead, which is the only reason they may
# occupy the top band.
#
# The depth is carried by four layers that all agree with each other: the caustic
# net, drawn in tabletop metres so its cells crowd into the distance with the sand;
# the props, sized by tableScale; the blue the floor loses itself in at the far
# end; and the fish, which swim on lanes at fixed DEPTHS rather than across the
# screen. Every one of those would read as wallpaper drawn in screen space.
#
# EVERY FISH IS LOW OVER THE SAND and casts a shadow onto it. There were two up in
# the water column at first, crossing the top band, and they were the only things
# in the picture not obviously in the same place as the board — a fish with no
# shadow reads as a sticker at whatever height the eye guesses, and the guess is
# always 'in front of the buttons'. The gap between a fish and its shadow is the
# only thing that says otherwise.
const OCEAN := "
vec3 lumeHaze() { return vec3(0.15, 0.46, 0.62); }

// The tabletop u that lands on the frame's own EDGE at depth w. Dressing the
// gutters means anchoring to this rather than to a fixed metre offset - it is the
// tabletop form of the header's rule about anchoring furniture to `aspect - k`,
// and it is what keeps the coral in the margins at 21:9 as well as at 16:9
// instead of walking in over the buttons.
float edgeU(float w) { return aspect * 0.3153 * w; }

// ---- A lump of rock, seen from above and a little in front. ----
vec3 rockAt(vec3 col, vec2 a, vec2 c, float r, float tone, float seed) {
	vec2 p = (a - c) / r;
	if (abs(p.x) > 1.9 || abs(p.y) > 1.5) return col;
	float win = win1(p.x, -1.80, 1.80, 0.16) * win1(p.y, -1.40, 1.40, 0.16);
	col = mix(col, col * 0.60, aafill(ellip(p, vec2(0.30, 0.48), vec2(1.30, 0.42), 0.0)) * 0.55 * win);
	float h = hash11(seed * 3.7);
	float d = ellip(p, vec2(0.0, 0.05), vec2(1.0, 0.60), 0.0);
	d = smin(d, ellip(p, vec2(-0.44 - 0.14 * h, 0.18), vec2(0.52, 0.38), 0.0), 0.34);
	d = smin(d, ellip(p, vec2(0.46 + 0.12 * h, 0.12), vec2(0.44, 0.34), 0.0), 0.34);
	float da = aafill(d) * win;
	vec3 base = mix(vec3(0.46, 0.53, 0.53), vec3(0.23, 0.33, 0.41), tone);
	col = mix(col, mix(base * 1.24, base * 0.64, ss(-0.66, 0.60, p.y)), da);
	col = mix(col, base * 1.50, aaline(ellip(p, vec2(-0.08, -0.14), vec2(0.70, 0.32), 0.0), 0.085) * da * 0.40);
	return col;
}

// ---- Branching coral: a few tapered arms fanning up from a foot, each with a
// bud on the end. Rigid, so it belongs in the plate. ----
vec3 coralAt(vec3 col, vec2 a, vec2 base, float s, vec3 c, float seed) {
	vec2 p = (a - base) / s;
	if (abs(p.x) > 1.35 || p.y > 0.40 || p.y < -1.85) return col;
	float win = win1(p.x, -1.26, 1.26, 0.15) * win1(p.y, -1.76, 0.32, 0.15);
	col = mix(col, col * 0.62, aafill(ellip(p, vec2(0.14, 0.13), vec2(0.90, 0.24), 0.0)) * 0.55 * win);
	float d = 9.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float h = hash11(seed * 3.1 + fi * 2.7);
		float ang = (fi * 0.25 - 0.5) * 1.55 + (h - 0.5) * 0.34;
		vec2 tip = vec2(sin(ang) * (0.78 + 0.34 * h), -cos(ang) * (1.02 + 0.55 * h));
		d = min(d, sdSeg(p, vec2(0.0, 0.06), tip * 0.55, 0.125));
		d = min(d, sdSeg(p, tip * 0.55, tip, 0.080));
		d = min(d, sdCircle(p - tip, 0.105));
	}
	float da = aafill(d) * win;
	col = mix(col, mix(c * 1.18, c * 0.52, ss(-1.55, 0.20, p.y)), da);
	col = mix(col, c * 1.45, aaline(d, 0.038) * da * 0.45);
	return col;
}

// ---- A sea fan: a flat blade of coral standing edge-on to the player, with the
// lattice showing through it. ----
vec3 fanAt(vec3 col, vec2 a, vec2 base, float s, vec3 c, float seed) {
	vec2 p = (a - base) / s;
	if (abs(p.x) > 1.25 || p.y > 0.35 || p.y < -1.70) return col;
	float win = win1(p.x, -1.16, 1.16, 0.14) * win1(p.y, -1.62, 0.28, 0.14);
	col = mix(col, col * 0.64, aafill(ellip(p, vec2(0.10, 0.10), vec2(0.72, 0.20), 0.0)) * 0.50 * win);
	float d = ellip(p, vec2(0.0, -0.86), vec2(0.92, 0.80), 0.0);
	d = max(d, -ellip(p, vec2(0.0, 0.36), vec2(0.66, 0.92), 0.0));
	float da = aafill(d) * win;
	col = mix(col, mix(c * 1.14, c * 0.56, ss(-1.6, 0.1, p.y)), da * 0.92);
	// the lattice: ribs radiating from the foot, cut back through the blade
	float ph = atan(p.x, -p.y + 0.06);
	col = mix(col, c * 0.60, ss(0.055, 0.0, abs(fract(ph * 3.2) - 0.5) - 0.30) * da * 0.55);
	col = mix(col, c * 1.42, aaline(d, 0.045) * da * 0.55);
	col = mix(col, c * 0.44, aafill(sdSeg(p, vec2(0.0, 0.10), vec2(0.0, -0.32), 0.075)) * win);
	return col;
}

// ---- A starfish lying flat on the sand. ----
vec3 starAt(vec3 col, vec2 a, vec2 c, float r, vec3 col1, float turn) {
	vec2 p = (a - c) / r;
	if (abs(p.x) > 1.5 || abs(p.y) > 1.2) return col;
	float win = radWin(length(p / vec2(1.0, 0.80)), 1.24, 1.44);
	vec2 q = p * rot(turn);
	q.y /= 0.72;
	float d = sdStar5(q, 1.0, 0.42) * 0.72;
	float da = aafill(d) * win;
	col = mix(col, col * 0.66, aafill(sdStar5((q - vec2(0.10, 0.22)) * 0.98, 1.0, 0.42) * 0.72) * 0.40 * win);
	col = mix(col, mix(col1 * 1.12, col1 * 0.70, ss(-0.9, 0.9, p.y)), da);
	col = mix(col, col1 * 0.72, ss(0.055, 0.0, abs(length(q) - 0.34)) * da * 0.6);
	return col;
}

// ---- A little fish, facing +x. kind 0 plain / 1 barred / 2 deep-bodied. ----
vec4 fishProfile(vec2 p, vec3 c, float tail, int kind) {
	vec4 acc = vec4(0.0);
	vec2 be = (kind == 2) ? vec2(0.50, 0.42) : vec2(0.62, 0.29);
	// the tail, hinged at the back of the body so the whole fan swings
	{
		float sa = tail * 0.40;
		float cs = cos(sa); float sn = sin(sa);
		vec2 q = p - vec2(-be.x * 0.80, 0.0);
		q = vec2(q.x * cs - q.y * sn, q.x * sn + q.y * cs);
		float d = max(max(q.x - 0.05, -0.54 - q.x), abs(q.y) + q.x * 0.74 - 0.09);
		d = max(d, 0.31 - length(vec2(q.x + 0.74, q.y * 0.86)));
		acc = _ov(acc, c * 0.58, aafill(d));
	}
	acc = _ov(acc, c * 0.72, aafill(ellip(p, vec2(-0.04, -be.y * 0.98), vec2(0.30, 0.20), 0.34)));
	acc = _ov(acc, c * 0.66, aafill(ellip(p, vec2(-0.08, be.y * 0.88), vec2(0.19, 0.12), -0.34)));
	float bd = ellip(p, vec2(0.0, 0.0), be, 0.0);
	float ba = aafill(bd);
	acc = _ov(acc, mix(c * 1.16, c * 0.62, ss(-be.y, be.y, p.y)), ba);
	acc = _ov(acc, vec3(1.0, 0.98, 0.93), aafill(ellip(p, vec2(0.02, be.y * 0.50), vec2(be.x * 0.74, be.y * 0.44), 0.0)) * ba * 0.50);
	if (kind == 1) {
		for (int i = 0; i < 2; i++)
			acc = _ov(acc, c * 0.44, aafill(sdBox(p - vec2(-0.14 + float(i) * 0.30, 0.0), vec2(0.055, be.y))) * ba * 0.85);
	} else if (kind == 2) {
		acc = _ov(acc, vec3(0.99, 0.92, 0.42), aafill(sdBox(p - vec2(0.10, 0.0), vec2(0.075, be.y))) * ba * 0.85);
	}
	acc = _ov(acc, c * 0.86, aafill(ellip(p, vec2(0.12, 0.11), vec2(0.21, 0.105), 0.44)) * ba);
	acc = _ov(acc, c * 0.40, aaline(bd, 0.035) * ba * 0.7);
	acc = _ov(acc, vec3(1.0), aafill(sdCircle(p - vec2(be.x * 0.55, -0.07), 0.105)) * ba);
	acc = _ov(acc, vec3(0.05, 0.07, 0.12), aafill(sdCircle(p - vec2(be.x * 0.59, -0.07), 0.052)) * ba);
	return acc;
}
vec3 placeFish(vec3 col, vec2 a, vec2 pos, float s, vec3 c, float tail, int kind, float dir) {
	vec2 p = (a - pos) / s;
	p.x *= dir;
	if (abs(p.x) > 1.35 || abs(p.y) > 0.95) return col;
	float win = win1(p.x, -1.28, 1.28, 0.14) * win1(p.y, -0.88, 0.88, 0.14);
	vec4 b = fishProfile(p, c, tail, kind);
	return mix(col, b.rgb, b.a * win);
}
// A fish CROSSING the frame: in at the right, out at the left, at a steady pace.
// It swims on a tabletop lane at a fixed DEPTH, so its size and its speed come
// from the water it is in rather than from a guess, and it swims JUST OVER THE
// SAND with a shadow on it — that gap between fish and shadow is the only thing
// that says it is in the scene rather than a sticker at whatever height the eye
// picks, and the eye always picks 'in front of the buttons'.
//
// The screen speed is the SAME on every lane, and that is not a coincidence: the
// travel limit is a multiple of edgeU(w), which grows with depth exactly as fast
// as the metres-per-pixel does. Set `cross` once and the whole shoal moves at one
// pace however deep each fish is.
//
// `cross` is how long the traverse takes and `per` is the whole cycle, so
// per - cross is the time it spends off frame before it comes round again.
// Without that gap the same fish re-enters at the right the instant it leaves at
// the left, and a row of them reads as a conveyor.
vec3 fishCross(vec3 col, vec2 a, float t, float w, float per, float cross, float ph,
		vec3 c, int kind, float sz) {
	float u01 = fract(t / per + ph) * per / cross;
	if (u01 > 1.0) return col;              // parked off frame, in the gap
	float lim = edgeU(w) * 1.22;            // starts and ends clear of both edges
	vec2 pt = tablePoint(vec2(mix(lim, -lim, u01), w));
	float s = sz * tableScale(pt.y);
	pt.y -= s * 0.10 * sin(t * 0.62 + ph * 11.0);
	col = lumeShadow(col, a, pt + vec2(s * 0.18, s * 0.10), vec2(s * 1.15, s * 0.30), 0.60);
	return placeFish(col, a, pt - vec2(0.0, s * 0.62), s, c,
		sin(t * 9.0 + ph * 7.0), kind, -1.0);
}

// ---- Sea grass, swaying. Animated, so it lives in lumeDyn and NOWHERE else: a
// blade drawn in both halves leaves a frozen ghost of the plate copy behind it. ----
vec3 weedAt(vec3 col, vec2 a, vec2 base, float s, vec3 c, float t, float ph) {
	vec2 p = (a - base) / s;
	if (abs(p.x) > 1.15 || p.y > 0.30 || p.y < -2.05) return col;
	float win = win1(p.x, -1.06, 1.06, 0.14) * win1(p.y, -1.96, 0.22, 0.14);
	float d = 9.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float h = hash11(ph * 7.0 + fi * 3.3);
		float L = 1.20 + 0.62 * h;
		float bend = (fi - 1.0) * 0.30 + 0.26 * sin(t * 0.80 + ph + fi * 0.9);
		// No per-segment early-out here, unlike the kelp: a tuft is drawn at about
		// 0.04 of the frame, so 0.16 of its own space is FOUR PIXELS, and a guard
		// that tight seams — aafill()'s fwidth is undefined across it and the
		// skipped side keeps a stray alpha. Nine sdSeg inside a box this small is
		// cheaper than the margin it would take to make the guard safe.
		for (int k = 0; k < 3; k++) {
			float u0 = float(k) * 0.3333;
			float u1 = u0 + 0.3333;
			vec2 A = vec2(bend * u0 * u0 * 1.7, -L * u0);
			vec2 B = vec2(bend * u1 * u1 * 1.7, -L * u1);
			d = min(d, sdSeg(p, A, B, 0.090 * (1.0 - u1 * 0.72)));
		}
	}
	float da = aafill(d) * win;
	col = mix(col, mix(c * 1.22, c * 0.48, ss(-1.55, 0.10, p.y)), da);
	return col;
}

// ---- Kelp hanging into the frame from a holdfast off the top edge. The plant is
// taller than the camera, so what is in shot is the middle of it drifting between
// the camera and the floor - the same licence the palms in Button Beach have, and
// the only way something tall can appear in a frame that is entirely ground. ----
vec3 kelpAt(vec3 col, vec2 a, vec2 origin, float s, float lean, float sway, vec3 c1, vec3 c2) {
	vec2 p = (a - origin) / s;
	if (abs(p.x) > 1.30 || p.y < -0.22 || p.y > 2.35) return col;
	float win = win1(p.x, -1.22, 1.22, 0.14) * win1(p.y, -0.16, 2.26, 0.14);
	float d = 9.0;
	for (int k = 0; k < 4; k++) {
		float u0 = float(k) * 0.25;
		float u1 = u0 + 0.25;
		vec2 A = vec2((lean + sway) * u0 * u0, 2.16 * u0);
		vec2 B = vec2((lean + sway) * u1 * u1, 2.16 * u1);
		if (p.y > B.y + 0.20 || p.y < A.y - 0.20) continue;
		d = min(d, sdSeg(p, A, B, 0.040 * (1.0 - u1 * 0.45)));
	}
	// the blades: long, narrow and tapered, in pairs down the stipe
	for (int k = 0; k < 7; k++) {
		float fk = float(k);
		float u = 0.10 + fk * 0.135;
		vec2 A = vec2((lean + sway) * u * u, 2.16 * u);
		if (abs(p.y - A.y) > 0.62) continue;
		float side = (mod(fk, 2.0) < 0.5) ? -1.0 : 1.0;
		float L = 0.62 - fk * 0.045;
		vec2 M = A + vec2(side * L * 0.55, 0.20 + 0.07 * sin(sway * 2.2 + fk));
		vec2 B = M + vec2(side * L * 0.50, 0.30 + 0.10 * sin(sway * 2.6 + fk * 1.7));
		d = min(d, sdSeg(p, A, M, 0.062));
		d = min(d, sdSeg(p, M, B, 0.034));
	}
	float da = aafill(d) * win;
	// shaded along its own length and never quite opaque, so it reads as a plant
	// hanging in water rather than as a green cut-out over the picture
	vec3 kc = mix(c1, c2, clamp(p.y * 0.46, 0.0, 1.0));
	kc = mix(kc * 0.72, kc * 1.16, ss(-0.55, 0.55, p.x - (lean + sway) * p.y * p.y * 0.22));
	col = mix(col, kc, da * 0.86);
	return col;
}

// ---- The caustic net. Four gratings folded into ridges: cheap, and drawn in
// TABLETOP metres so its cells stretch and crowd into the distance exactly as the
// sand does. Drawn in screen space it is the single fastest way to make a floor
// read as wallpaper.
//
// The CELL SIZE is the whole of whether this reads as caustics or as swirls: at a
// wavelength of metres the ridges come out as broad soft swooshes lying over the
// picture. 6.0 puts a cell at about a metre, which is a net at the player's feet
// and a fine sparkle out by the far edge. ----
float caustic(vec2 g, float t) {
	// A slow warp before the gratings. Four straight gratings on their own tile into
	// a lattice of identical rosettes that the eye picks up immediately; two sines
	// of warp is the whole of what buys them their irregularity.
	// The time rates are all about half what they first were. At the old speed the
	// net was travelling far enough in three seconds to be the loudest thing in the
	// frame, and the fish — the things that are supposed to read as alive — were
	// swimming inside a moving floor. Water undulates; it does not race.
	vec2 q = g + 0.30 * vec2(sin(g.y * 1.7 + t * 0.12), sin(g.x * 1.5 - t * 0.10));
	float v = sin(q.x * 7.9 + t * 0.30) + sin(q.y * 8.6 - t * 0.24)
		+ sin((q.x + q.y) * 5.4 + t * 0.20) + sin((q.x - q.y) * 5.0 - t * 0.16);
	v = 1.0 - abs(v * 0.27);
	v = clamp(v, 0.0, 1.0);
	v *= v; v *= v;
	return v;
}

// ---- A shaft of surface light coming down through the water. All of them lean
// the same way because they all come from the same sun, and each widens as it
// falls and is gone well before the bottom of the frame, so nothing bright lands
// where the 'Your turn!' pill sits. Returns its own strength through `hit`, so the
// caustics can brighten where a shaft actually lands instead of everywhere. ----
vec3 rayAt(vec3 col, vec2 a, float x0, float wdt, float amt, inout float hit) {
	float w = wdt * (0.55 + 0.85 * a.y);
	float x = a.x - x0 - a.y * 0.26;
	if (abs(x) > w * 2.0) return col;
	float f = radWin(abs(x), w * 0.25, w * 2.0) * ss(0.86, 0.00, a.y);
	hit += f;
	return col + vec3(0.52, 0.88, 1.0) * f * amt;
}

vec3 lumeStatic(vec2 a) {
	vec2 g = tableUV(a);
	// The sand, going from lit and almost warm at the player's feet to the blue it
	// loses itself in at the far end. Two stages, because one straight mix from tan
	// to navy runs through a dead grey in the middle of the frame.
	vec3 col = mix(vec3(0.78, 0.82, 0.72), vec3(0.24, 0.64, 0.72), ss(5.0, 9.2, g.y));
	col = mix(col, vec3(0.05, 0.28, 0.54), ss(9.0, 15.5, g.y));
	// dunes and ripples, in tabletop metres
	col *= 0.96 + 0.075 * fbm(g * 0.42);
	float rip = sin(g.y * 3.1 + 1.5 * fbm(g * 0.55) * 4.0 + 0.5 * sin(g.x * 0.8));
	col *= 1.0 + 0.075 * rip * ss(15.0, 5.0, g.y);
	col *= 0.975 + 0.05 * hash21(floor(g * 40.0));
	// pebbles and shells, scattered in tabletop coordinates and drawn at the size
	// distance gives them
	for (int i = 0; i < 14; i++) {
		float fi = float(i);
		float h1 = hash11(fi * 5.7);
		float h2 = hash11(fi * 2.9);
		vec2 c = tablePoint(vec2((h1 - 0.5) * 17.0, 5.2 + h2 * 8.4));
		float r = (0.0060 + 0.0055 * hash11(fi * 8.3)) * tableScale(c.y);
		if (abs(a.x - c.x) > r * 3.2 || abs(a.y - c.y) > r * 2.6) continue;
		float win = win1(a.x, c.x - r * 3.0, c.x + r * 3.0, r * 0.6)
			* win1(a.y, c.y - r * 2.4, c.y + r * 2.4, r * 0.6);
		vec3 sc = mix(vec3(0.92, 0.90, 0.84), vec3(0.58, 0.66, 0.66), h2);
		col = mix(col, col * 0.72, aafill(ellip(a, c + vec2(r * 0.6, r * 0.4), vec2(r * 1.8, r * 0.7), 0.0)) * 0.5 * win);
		col = mix(col, sc, aafill(ellip(a, c, vec2(r * 1.5, r * 0.9), 0.5 * h1)) * win);
	}
	// The furniture, all of it anchored to the frame's own edge so it dresses the
	// gutters and stays out from under the buttons at every aspect.
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float h = hash11(fi * 4.3 + 1.0);
		float w = 5.6 + fi * 1.55;
		float side = (mod(fi, 2.0) < 0.5) ? -1.0 : 1.0;
		vec2 c = tablePoint(vec2(side * edgeU(w) * (0.80 + 0.13 * h), w));
		col = rockAt(col, a, c, (0.030 + 0.016 * h) * tableScale(c.y), h, fi * 2.1);
	}
	col = coralAt(col, a, tablePoint(vec2(-edgeU(6.9) * 0.90, 6.9)), 0.052 * tableScale(tableRow(6.9)), vec3(0.98, 0.44, 0.56), 1.0);
	col = coralAt(col, a, tablePoint(vec2(edgeU(7.6) * 0.86, 7.6)), 0.048 * tableScale(tableRow(7.6)), vec3(1.0, 0.62, 0.28), 2.0);
	col = coralAt(col, a, tablePoint(vec2(-edgeU(10.4) * 0.88, 10.4)), 0.040 * tableScale(tableRow(10.4)), vec3(0.72, 0.48, 0.98), 3.0);
	col = coralAt(col, a, tablePoint(vec2(edgeU(11.6) * 0.84, 11.6)), 0.038 * tableScale(tableRow(11.6)), vec3(0.99, 0.82, 0.34), 4.0);
	col = fanAt(col, a, tablePoint(vec2(-edgeU(8.4) * 0.80, 8.4)), 0.060 * tableScale(tableRow(8.4)), vec3(0.96, 0.40, 0.44), 5.0);
	col = fanAt(col, a, tablePoint(vec2(edgeU(9.1) * 0.82, 9.1)), 0.054 * tableScale(tableRow(9.1)), vec3(0.44, 0.80, 0.90), 6.0);
	// Two boulders far out, almost lost in the water column. They are what gives the
	// floor a BEYOND: props on the same surface at a depth where the haze has nearly
	// taken them, rather than a ridge drawn across the top, which would be a horizon.
	// (The frame runs out at about 14 m — tableRow goes negative past it — so
	// 'far' here means 12 to 13, not the 20 the eye wants to ask for.)
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float w = 12.4 + fi * 1.1;
		vec2 c = tablePoint(vec2((fi < 0.5 ? -1.0 : 1.0) * edgeU(w) * 0.42, w));
		col = rockAt(col, a, c, 0.052 * tableScale(c.y), 0.95, fi * 6.7 + 3.0);
	}
	// Button coral: three heads of it, wearing the bezel, the dome and the inset
	// ring. This is the LUMEO motif growing on the sea floor rather than sitting on
	// top of it, which is why it is coral and not a sign.
	col = placeCap(col, a, tablePoint(vec2(-edgeU(6.0) * 0.93, 6.0)), 0.036 * tableScale(tableRow(6.0)), vec3(0.34, 0.82, 0.58), 0.10, 0.0);
	col = placeCap(col, a, tablePoint(vec2(edgeU(6.4) * 0.91, 6.4)), 0.033 * tableScale(tableRow(6.4)), vec3(0.98, 0.36, 0.42), 0.10, 0.0);
	col = placeCap(col, a, tablePoint(vec2(edgeU(9.8) * 0.94, 9.8)), 0.026 * tableScale(tableRow(9.8)), vec3(0.36, 0.68, 0.98), 0.10, 0.0);
	col = starAt(col, a, tablePoint(vec2(-edgeU(5.7) * 0.72, 5.7)), 0.030 * tableScale(tableRow(5.7)), vec3(1.0, 0.60, 0.34), 0.4);
	col = starAt(col, a, tablePoint(vec2(edgeU(8.3) * 0.74, 8.3)), 0.022 * tableScale(tableRow(8.3)), vec3(0.99, 0.46, 0.62), -0.9);
	// the water column itself: everything far goes blue and loses its contrast
	col = tableFar(col, a, vec3(0.06, 0.30, 0.52), 0.52);
	return col;
}

vec3 lumeDyn(vec3 col, vec2 a, float t) {
	vec2 g = tableUV(a);
	// Three shafts of surface light, all leaning the same way because they all come
	// from the same sun. Drawn before the caustics so the net can be brightened
	// where a shaft actually lands, which is what ties the two together instead of
	// leaving them as two unrelated effects over one floor.
	float hit = 0.0;
	col = rayAt(col, a, aspect * 0.17 + 0.045 * sin(t * 0.17), 0.125, 0.20, hit);
	col = rayAt(col, a, aspect * 0.52 + 0.035 * sin(t * 0.13 + 2.0), 0.085, 0.13, hit);
	col = rayAt(col, a, aspect * 0.88 + 0.050 * sin(t * 0.11 + 4.0), 0.140, 0.18, hit);
	// The net on the sand. Strong at the player's feet, gone by the far end — which
	// is both what water does and what keeps the cells from turning into a
	// shimmering moire once they compress past a pixel. Evaluated ONCE: the bright
	// filaments and the shade between them are the same number.
	float near = ss(13.5, 4.4, g.y);
	float cs = caustic(g, t);
	col += vec3(0.46, 0.90, 0.98) * cs * near * (0.165 + 0.22 * clamp(hit, 0.0, 1.0));
	col *= 1.0 - 0.055 * near * (1.0 - cs);
	// sea grass, out in the gutters where the coral is
	col = weedAt(col, a, tablePoint(vec2(-edgeU(6.2) * 0.86, 6.2)), 0.052 * tableScale(tableRow(6.2)), vec3(0.30, 0.74, 0.50), t, 0.0);
	col = weedAt(col, a, tablePoint(vec2(edgeU(6.7) * 0.88, 6.7)), 0.048 * tableScale(tableRow(6.7)), vec3(0.26, 0.68, 0.58), t, 1.7);
	col = weedAt(col, a, tablePoint(vec2(-edgeU(9.6) * 0.90, 9.6)), 0.038 * tableScale(tableRow(9.6)), vec3(0.24, 0.64, 0.48), t, 3.4);
	col = weedAt(col, a, tablePoint(vec2(edgeU(10.8) * 0.86, 10.8)), 0.033 * tableScale(tableRow(10.8)), vec3(0.32, 0.72, 0.46), t, 5.1);
	// The fish, all of them low over the sand and all swimming RIGHT TO LEFT: in at
	// one edge, out at the other. The crossings are 11.5-15.5 s over about 1560 px,
	// so roughly 110 px a second — plainly moving at a glance, and not so quick that
	// anything darts across the board mid-sequence.
	col = fishCross(col, a, t, 5.60, 19.0, 14.0, 0.24, vec3(0.90, 0.46, 0.94), 0, 0.050);
	col = fishCross(col, a, t, 6.30, 21.0, 15.5, 0.61, vec3(0.42, 0.78, 0.99), 2, 0.046);
	col = fishCross(col, a, t, 7.40, 17.0, 12.5, 0.08, vec3(0.99, 0.62, 0.24), 1, 0.038);
	col = fishCross(col, a, t, 9.00, 16.0, 11.5, 0.45, vec3(0.99, 0.86, 0.36), 0, 0.032);
	// and a pair swimming together — SAME period and crossing, phases a hair apart,
	// which is the only thing keeping them a pair rather than two lone fish
	col = fishCross(col, a, t, 8.10, 23.0, 13.5, 0.79, vec3(0.99, 0.52, 0.36), 1, 0.030);
	col = fishCross(col, a, t, 8.35, 23.0, 13.5, 0.82, vec3(0.99, 0.52, 0.36), 1, 0.024);
	// and the kelp overhead, hanging into the two top corners
	col = kelpAt(col, a, vec2(0.045, -0.40), 0.34, 0.34, 0.14 * sin(t * 0.44), vec3(0.06, 0.24, 0.26), vec3(0.16, 0.44, 0.34));
	col = kelpAt(col, a, vec2(aspect - 0.035, -0.36), 0.31, -0.38, 0.13 * sin(t * 0.37 + 2.2), vec3(0.05, 0.21, 0.25), vec3(0.14, 0.40, 0.36));
	return col;
}
"
