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
	// sin-free hash (Hoskins). sin() is among the slowest mobile-GPU ops and this
	// runs ~24x per fbm call x millions of px; the noise PATTERN shifts slightly,
	// the noise character/sharpness is identical.
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
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
	for (int i = 0; i < 4; i++) { v += a * gnoise(p); p = p * 2.0 + vec2(1.7, 9.2); a *= 0.5; }
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

# ---------------------------------------------------------------------------
# Detailed illustrated themes (mid-value static scenes + high-value animated
# scenes). These are full procedural shaders — recognisable drawn scenes built
# from SDF shapes + noise, not flat gradients. _SHAPES_GLSL gives every scene a
# shared toolbox of 2D primitives; _HEAD prepends the shader header + noise +
# shapes so each scene only has to declare its fragment().
# ---------------------------------------------------------------------------
const _SHAPES_GLSL := "
float sdCircle(vec2 p, float r) { return length(p) - r; }
float sdBox(vec2 p, vec2 b) { vec2 d = abs(p) - b; return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0); }
float sdTri(vec2 p, float r) {
	float k = 1.7320508;
	p.x = abs(p.x) - r;
	p.y = p.y + r / k;
	if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	p.x -= clamp(p.x, -2.0 * r, 0.0);
	return -length(p) * sign(p.y);
}
mat2 rot(float a) { float c = cos(a); float s = sin(a); return mat2(vec2(c, -s), vec2(s, c)); }
float hash11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float hash21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
// Crisp, resolution-independent fill/line from a signed distance (uses screen
// derivatives so edges stay a clean ~1px — sharp, never blurry).
float aafill(float d) { float w = max(fwidth(d), 0.00001); return clamp(0.5 - d / w, 0.0, 1.0); }
float aaline(float d, float hw) { float w = max(fwidth(d), 0.00001); return clamp((hw - abs(d)) / w + 0.5, 0.0, 1.0); }
// Analytic, derivative-FREE edge windows. A prop wrapped in a hard bounding-box `if`
// guard seams along that boundary: aafill/aaline use fwidth(), whose value is
// undefined where neighbouring fragments in the 2x2 quad took the guard's early
// return. Multiplying the prop's alpha by one of these windows — which reach 0 just
// INSIDE the (slightly enlarged) guard and are 1 across all visible prop content —
// forces that seam to zero without changing the look. win1 windows one axis over
// [lo, hi] with ramp width f; radWin windows a radius.
float win1(float x, float lo, float hi, float f) { return clamp(smoothstep(lo, lo + f, x) * (1.0 - smoothstep(hi - f, hi, x)), 0.0, 1.0); }
float radWin(float r, float inner, float outer) { return 1.0 - smoothstep(inner, outer, r); }
float sdStar5(vec2 p, float r, float rf) {
	vec2 k1 = vec2(0.809016994, -0.587785252);
	vec2 k2 = vec2(-k1.x, k1.y);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}
float sdHeart(vec2 p) {
	p.x = abs(p.x);
	if (p.y + p.x > 1.0)
		return sqrt(dot(p - vec2(0.25, 0.75), p - vec2(0.25, 0.75))) - 0.35355339;
	vec2 e = p - 0.5 * vec2(max(p.x + p.y, 0.0), max(p.x + p.y, 0.0));
	return sqrt(min(dot(p - vec2(0.0, 1.0), p - vec2(0.0, 1.0)), dot(e, e))) * sign(p.x - p.y);
}
"

# ---------------------------------------------------------------------------
# NATURE TOOLBOX — high-poly, detailed, reusable scene props shared by every
# illustrated scene: three bird species (pigeon / crow / pelican), randomised
# billowy clouds, and three tree species (pine / round broadleaf / poplar).
# Each is built from layered SDF primitives so the silhouettes read crisp at
# any size. The public `placeBird/placeCloud/placeTree` helpers wrap each prop
# with a cheap bounding-box early-out (so off-prop pixels cost nothing) and a
# `dark` knob to render the prop as a flat silhouette for dusk/night scenes.
# ---------------------------------------------------------------------------
const _NATURE_GLSL := "
float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }
// Convex wedge: base at q=0, apex at +x=L, half-width W at the base (-> 0 at apex).
float wedge(vec2 q, float L, float W) {
	float d1 = -q.x;
	float d2 = q.x - L;
	float d3 = abs(q.y) - W * (1.0 - clamp(q.x / L, 0.0, 1.0));
	return max(max(d1, d2), d3);
}
// Tilted ellipse, centre c, half-extents e, tilt ang. Returns <0 inside.
float ellip(vec2 q, vec2 c, vec2 e, float ang) {
	vec2 r = (q - c) * rot(ang);
	return length(r / e) - 1.0;
}
vec4 _ov(vec4 d, vec3 c, float a) { return vec4(mix(d.rgb, c, a), max(d.a, a)); }

// ---- Detailed side-profile birds, gliding, facing +x. kind 0 pigeon / 1 crow
// / 2 pelican; flap in [-1,1] raises the near wing. Drawn in unit-ish space. ----
vec4 birdProfile(vec2 p, float flap, int kind) {
	vec4 acc = vec4(0.0);
	vec3 backC = vec3(0.30, 0.35, 0.46);
	vec3 midC = vec3(0.44, 0.49, 0.59);
	vec3 bellyC = vec3(0.74, 0.78, 0.85);
	vec3 wingC = vec3(0.36, 0.41, 0.52);
	vec3 wingTip = vec3(0.20, 0.24, 0.34);
	vec3 beakC = vec3(0.86, 0.60, 0.42);
	vec3 rimC = vec3(0.95, 0.97, 1.0);
	vec2 bodyE = vec2(0.56, 0.34);
	vec2 headP = vec2(0.54, -0.16); float headR = 0.21;
	float beakL = 0.18, beakW = 0.075, beakBend = 0.10;
	float tailL = 0.46, tailW = 0.24;
	float wingL = 0.34, wingW = 0.14;
	float pouch = 0.0, throat = 1.0;
	if (kind == 1) {
		backC = vec3(0.03, 0.04, 0.06); midC = vec3(0.07, 0.08, 0.12); bellyC = vec3(0.13, 0.14, 0.20);
		wingC = vec3(0.05, 0.06, 0.10); wingTip = vec3(0.01, 0.02, 0.04); beakC = vec3(0.05, 0.05, 0.07);
		rimC = vec3(0.45, 0.55, 0.80);
		bodyE = vec2(0.60, 0.27); headP = vec2(0.54, -0.14); headR = 0.195;
		beakL = 0.28; beakW = 0.085; beakBend = 0.04; tailL = 0.66; tailW = 0.20; wingL = 0.40; wingW = 0.13; throat = 0.0;
	} else if (kind == 2) {
		backC = vec3(0.78, 0.80, 0.86); midC = vec3(0.90, 0.91, 0.95); bellyC = vec3(1.0, 1.0, 1.0);
		wingC = vec3(0.82, 0.85, 0.91); wingTip = vec3(0.14, 0.15, 0.21); beakC = vec3(0.98, 0.80, 0.42);
		rimC = vec3(1.0, 1.0, 1.0);
		bodyE = vec2(0.64, 0.38); headP = vec2(0.42, -0.18); headR = 0.20;
		beakL = 0.62; beakW = 0.10; beakBend = 0.06; tailL = 0.30; tailW = 0.26; wingL = 0.46; wingW = 0.17; throat = 0.0; pouch = 1.0;
	}
	float fa = 0.5 + 0.5 * flap;
	// soft ambient outline (slightly inflated dark silhouette) for separation
	{
		float body = ellip(p, vec2(0.0, 0.0), bodyE + 0.03, 0.0);
		float head = sdCircle(p - headP, headR + 0.03);
		acc = _ov(acc, mix(backC * 0.35, vec3(0.0), 0.3), aafill(min(body, head)) * 0.5);
	}
	// far wing (behind body), subtle, counter-sweeping with the flap for depth
	{
		float fsweep = 0.25 - 0.7 * flap;
		vec2 fdir = vec2(cos(fsweep), sin(fsweep));
		vec2 fc = vec2(-0.04, 0.06) + fdir * wingL * 0.9;
		acc = _ov(acc, wingC * 0.5, aafill(ellip(p, fc, vec2(wingL * 0.85, wingW * 0.8), fsweep)));
	}
	// tail: a splayed fan of individual tapered feathers rooted at the back of the
	// body. Each feather is its own narrow wedge fanned about the root, with the
	// centre feathers longest — reads as real plumage instead of one flat triangle,
	// and scales with the body (tailL/tailW vary per species).
	{
		vec2 root = vec2(-bodyE.x * 0.86, -0.02);
		for (int k = 0; k < 5; k++) {
			float fk = float(k) / 4.0 - 0.5;                   // -0.5 .. 0.5 across the fan
			vec2 q = (p - root) * rot(0.10 + fk * 0.52);       // splay each feather about the root
			float fl = tailL * (1.0 - 0.44 * abs(fk));         // centre feathers longest
			float d = wedge(vec2(q.x + fl, q.y), fl, tailW * 0.34);
			float ta = aafill(d);
			vec3 tc = mix(wingTip, wingC, clamp((q.x + fl) / fl, 0.0, 1.0));
			acc = _ov(acc, tc, ta);
			acc = _ov(acc, wingTip, aaline(q.y, 0.005) * ta * 0.5);   // central shaft
			acc = _ov(acc, rimC, aaline(d, 0.005) * ta * 0.3);        // crisp feather edge
		}
	}
	// body with a vertical light gradient + rim light along the back
	{
		float bd = ellip(p, vec2(0.0, 0.0), bodyE, 0.0);
		float ba = aafill(bd);
		float ly = clamp((p.y + bodyE.y) / (2.0 * bodyE.y), 0.0, 1.0);
		vec3 bc = mix(backC, midC, smoothstep(0.0, 0.5, ly));
		bc = mix(bc, bellyC, smoothstep(0.45, 1.0, ly));
		acc = _ov(acc, bc, ba);
		acc = _ov(acc, rimC, aaline(bd, 0.012) * step(p.y, -0.02) * ba * 0.5);
		acc = _ov(acc, vec3(0.30, 0.58, 0.50), aafill(ellip(p, vec2(0.30, -0.02), vec2(0.16, 0.12), 0.5)) * 0.5 * throat);
		acc = _ov(acc, vec3(0.55, 0.32, 0.52), aafill(ellip(p, vec2(0.34, 0.05), vec2(0.12, 0.09), 0.5)) * 0.4 * throat);
	}
	// neck bridge + shaded head
	{
		acc = _ov(acc, mix(midC, bellyC, 0.3), aafill(ellip(p, mix(vec2(0.2, -0.05), headP, 0.5), vec2(0.2, 0.18), 0.3)));
		float hd = sdCircle(p - headP, headR);
		float ha = aafill(hd);
		float hy = clamp((p.y - headP.y + headR) / (2.0 * headR), 0.0, 1.0);
		acc = _ov(acc, mix(backC, mix(midC, bellyC, 0.4), smoothstep(0.0, 1.0, hy)), ha);
		acc = _ov(acc, rimC, aaline(hd, 0.010) * step(p.y, headP.y) * ha * 0.5);
	}
	// beak: gently curved, with a top highlight (+ dark tip for pigeon/crow)
	{
		vec2 q = p - (headP + vec2(headR * 0.62, 0.0));
		q.y -= beakBend * (q.x / max(beakL, 0.001)) * (q.x / max(beakL, 0.001));
		float bd = wedge(q, beakL, beakW);
		acc = _ov(acc, beakC, aafill(bd));
		acc = _ov(acc, beakC * 1.2, aaline(q.y + beakW * 0.3, 0.006) * aafill(bd) * 0.5);
		if (kind != 2) acc = _ov(acc, beakC * 0.5, aafill(wedge(q - vec2(beakL * 0.55, 0.0), beakL * 0.45, beakW * 0.5)) * 0.7);
	}
	// pelican pouch slung under the lower mandible
	if (pouch > 0.5) {
		vec2 bb = headP + vec2(headR * 0.62, 0.0);
		float clip = step(bb.y - 0.02 + (p.x - bb.x) * 0.20, p.y);
		float pd = ellip(p, bb + vec2(beakL * 0.42, 0.14), vec2(beakL * 0.5, 0.13), -0.12);
		acc = _ov(acc, vec3(0.99, 0.72, 0.42), aafill(pd) * clip);
		acc = _ov(acc, vec3(1.0, 0.85, 0.55), aaline(pd, 0.008) * clip * 0.4);
	}
	// eye: lid ring, pupil, catchlight
	acc = _ov(acc, mix(beakC, vec3(0.10, 0.08, 0.06), 0.6), aafill(sdCircle(p - (headP + vec2(0.07, -0.03)), 0.04)));
	acc = _ov(acc, vec3(0.03, 0.02, 0.04), aafill(sdCircle(p - (headP + vec2(0.07, -0.03)), 0.028)));
	acc = _ov(acc, vec3(1.0), aafill(sdCircle(p - (headP + vec2(0.082, -0.042)), 0.010)));
	// near wing: small + bold, sweeping through a wide arc so the flap is obvious
	{
		vec2 sh = vec2(0.10, -0.07);
		float wsweep = -0.20 - 0.95 * flap;
		vec2 dir = vec2(cos(wsweep), sin(wsweep));
		vec2 wc = sh + dir * wingL * 0.9;
		float wd = ellip(p, wc, vec2(wingL, wingW), wsweep);
		float wa = aafill(wd);
		acc = _ov(acc, wingC, wa);
		vec2 r = (p - wc) * rot(wsweep);
		for (int k = 0; k < 3; k++) { float fk = float(k);
			acc = _ov(acc, wingTip, aaline(r.x - (-0.4 + fk * 0.4) * wingL, 0.008) * wa * 0.5);
		}
		acc = _ov(acc, wingTip, aafill(ellip(p, sh + dir * wingL * 1.7, vec2(wingL * 0.45, wingW * 0.8), wsweep)) * wa);
		acc = _ov(acc, rimC, aaline(wd, 0.008) * wa * 0.4);
	}
	return acc;
}
vec3 placeBird(vec3 col, vec2 a, vec2 pos, float s, float flap, int kind, float dark) {
	vec2 bp = (a - pos) / s;
	if (abs(bp.x) > 1.56 || abs(bp.y) > 1.34) return col;
	vec4 b = birdProfile(bp, flap, kind);
	float win = win1(bp.x, -1.50, 1.50, 0.18) * win1(bp.y, -1.28, 1.28, 0.18);
	return mix(col, mix(b.rgb, vec3(0.09, 0.06, 0.09), dark), b.a * win);
}
// One free-flying bird, fully randomised from `seed`: species (repeats are fine),
// horizontal speed, size (up to smax) and vertical lane (within [ylo, ylo+yspan]).
// It glides left -> right, then loops the long way round so there's an off-screen
// gap before it re-enters from the left (NOT an instant edge-to-edge wrap): the
// travel period is the screen span PLUS a random gap distance, and while the
// phase is in that extra stretch the bird sits past the right edge, unseen.
vec3 flyBird(vec3 col, vec2 a, float t, float seed, float ylo, float yspan, float smax, float dark) {
	float speed = 0.045 + 0.075 * hash11(seed * 1.7);          // random glide speed
	float size  = smax * (0.5 + 0.5 * hash11(seed * 2.3));     // random size, smax = max
	float yy    = ylo + yspan * hash11(seed * 3.1);            // random vertical lane
	float gap   = 0.4 + 1.8 * hash11(seed * 4.7);              // off-screen idle distance
	int kind    = int(floor(hash11(seed * 5.3) * 2.999));      // 0/1/2 species, repeats ok
	float span  = aspect + 0.6;                                // entry margin -> exit margin
	float x = -0.3 + mod(t * speed + seed * 11.7, span + gap); // > span => parked off-screen
	float bob  = yy + 0.018 * sin(t * (1.0 + hash11(seed * 8.1)) + seed);
	float flap = sin(t * (4.5 + 2.5 * hash11(seed * 6.1)) + seed * 3.0);
	return placeBird(col, a, vec2(x, bob), size, flap, kind, dark);
}

// ---- Billowy cumulus cloud: flat-ish base, randomised lumps on top. q is
// cloud-relative, s scales, seed randomises the shape. Returns <0 inside. ----
float cloudSDF(vec2 q, float s, float seed) {
	q /= s;
	float d = sdBox(q - vec2(0.0, 0.06), vec2(0.78, 0.12));
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float t = fi / 4.0 - 0.5;
		float r = 0.26 + 0.20 * hash11(seed + fi * 1.7);
		float bump = 0.10 + 0.18 * hash11(seed + fi * 3.3);
		vec2 c = vec2(t * 1.4, -0.02 - bump - 0.12 * (1.0 - abs(t) * 1.7));
		d = smin(d, sdCircle(q - c, r), 0.16);
	}
	return d * s;
}
vec3 placeCloud(vec3 base, vec2 a, vec2 pos, float s, float seed, vec3 lit, vec3 shade) {
	vec2 cp = (a - pos) / s;
	if (abs(cp.x) > 1.24 || abs(cp.y) > 0.90) return base;
	float win = win1(cp.x, -1.22, 1.22, 0.12) * win1(cp.y, -0.84, 0.84, 0.12);
	float d = cloudSDF(a - pos, s, seed);
	float cl = aafill(d) * win;
	float topness = clamp((pos.y - a.y) / (0.5 * s) + 0.5, 0.0, 1.0);
	vec3 cc = mix(shade, lit, smoothstep(0.0, 1.0, topness));
	base = mix(base, cc, cl);
	base = mix(base, lit, aaline(d, 0.004 * s) * step(a.y, pos.y) * 0.5 * win);
	return base;
}

// ---- Trees: trunk base at p=0, growing up (-y). kind 0 pine / 1 round broadleaf
// / 2 poplar; seed randomises lean, tier widths and canopy lumps. ----
vec4 treeAt(vec2 p, float s, int kind, float seed) {
	vec4 acc = vec4(0.0);
	p /= s;
	float lean = (hash11(seed * 1.7) - 0.5) * 0.14;
	p.x -= lean * max(0.0, -p.y);
	vec3 bark = vec3(0.34, 0.22, 0.13);
	vec3 barkD = vec3(0.20, 0.13, 0.08);
	float trunkH = (kind == 2) ? 1.55 : 1.05;
	// tapered, striated trunk
	{
		float tw = 0.06;
		vec2 q = p - vec2(0.0, -trunkH * 0.5);
		float taper = mix(1.4, 0.7, clamp((-p.y) / (trunkH + 0.5), 0.0, 1.0));
		float td = sdBox(q, vec2(tw * taper, trunkH * 0.5));
		float tA = aafill(td);
		vec3 tcol = mix(barkD, bark, 0.5 + 0.5 * sin(p.y * 40.0 + seed));
		acc = _ov(acc, tcol, tA);
		acc = _ov(acc, barkD, aaline(q.x - tw * 0.3, 0.008) * tA * 0.7);
		acc = _ov(acc, bark * 1.25, aaline(q.x + tw * 0.5, 0.008) * tA * 0.6);
	}
	if (kind == 0) {
		vec3 gD = vec3(0.05, 0.24, 0.12);
		vec3 gM = vec3(0.10, 0.40, 0.20);
		vec3 gL = vec3(0.22, 0.58, 0.30);
		for (int t = 0; t < 5; t++) { float ft = float(t);
			float ay = -2.35 + ft * 0.30;
			float hw = 0.38 + ft * 0.16 + 0.05 * hash11(seed + ft);
			float h = 0.7;
			vec2 r = p - vec2(0.0, ay);
			float edge = abs(r.x) - hw * clamp(r.y / h, 0.0, 1.0);
			edge += 0.04 * gnoise(vec2(r.x * 8.0, ay * 3.0 + seed)) - 0.02;
			float droop = r.y - h - 0.06 * sin(r.x * 18.0);
			float cd = max(max(-r.y, droop), edge);
			float ca = aafill(cd);
			float lit = smoothstep(0.3, -0.5, r.x) * smoothstep(h, 0.0, r.y);
			vec3 gc = mix(gD, gM, smoothstep(0.0, 0.7, r.y / h + 0.5));
			gc = mix(gc, gL, lit * 0.7);
			gc *= 0.85 + 0.3 * gnoise(vec2(r.x * 10.0, r.y * 10.0 + seed));
			acc = _ov(acc, gc, ca);
			acc = _ov(acc, gL, aaline(edge, 0.015) * ca * step(r.x, 0.0) * 0.4);
		}
	} else if (kind == 1) {
		vec3 gD = vec3(0.07, 0.30, 0.15);
		vec3 gL = vec3(0.26, 0.62, 0.32);
		vec2 ctr = vec2(0.0, -1.1);
		float blob = sdCircle(p - ctr, 0.5) - 0.06 * fbm((p - ctr) * 4.0 + seed);
		for (int i = 0; i < 8; i++) { float fi = float(i);
			float ang = fi / 8.0 * 6.2832 + seed;
			vec2 c = ctr + (0.36 + 0.12 * hash11(seed + fi)) * vec2(cos(ang), sin(ang)) * vec2(1.0, 0.82);
			blob = smin(blob, sdCircle(p - c, 0.26 + 0.12 * hash11(seed + fi * 1.3)), 0.16);
		}
		blob -= 0.04 * fbm(p * 6.0 + seed);
		float ba = aafill(blob);
		float lit = smoothstep(0.4, -0.6, p.x - ctr.x) * smoothstep(0.4, -0.6, p.y - ctr.y);
		float ao = smoothstep(-0.2, 0.6, p.y - ctr.y);
		vec3 gc = mix(gD, gL, lit);
		gc *= 1.0 - 0.35 * ao;
		gc *= 0.85 + 0.3 * fbm(p * 9.0 + seed);
		acc = _ov(acc, gc, ba);
		for (int i = 0; i < 5; i++) { float fi = float(i);
			vec2 c = ctr + vec2(-0.3 + 0.25 * hash11(seed + fi * 2.1), -0.3 - 0.22 * hash11(seed + fi * 3.7));
			acc = _ov(acc, gL * 1.1, aafill(sdCircle(p - c, 0.10 + 0.05 * hash11(seed + fi))) * ba * 0.5);
		}
	} else {
		vec3 gD = vec3(0.09, 0.34, 0.17);
		vec3 gL = vec3(0.26, 0.60, 0.32);
		vec2 ctr = vec2(0.0, -1.5);
		float d = ellip(p, ctr, vec2(0.40, 0.92), 0.0);
		for (int i = 0; i < 7; i++) { float fi = float(i);
			float yy = -0.65 - fi * 0.26;
			float side = (hash11(seed + fi * 1.9) - 0.5) * 0.6;
			d = smin(d, sdCircle(p - vec2(side, yy), 0.20 + 0.06 * hash11(seed + fi)), 0.13);
		}
		d -= 0.035 * fbm(p * 7.0 + seed);
		float da = aafill(d);
		float lit = smoothstep(0.4, -0.5, p.x - ctr.x);
		vec3 gc = mix(gD, gL, lit);
		gc *= 0.85 + 0.3 * fbm(p * 10.0 + seed);
		acc = _ov(acc, gc, da);
		acc = _ov(acc, gL, aaline(ellip(p, ctr + vec2(-0.1, 0.0), vec2(0.28, 0.8), 0.0), 0.05) * da * 0.4);
	}
	return acc;
}
vec3 placeTree(vec3 col, vec2 a, vec2 base, float s, int kind, float seed, float dark) {
	vec2 tp = (a - base) / s;
	if (tp.x < -1.5 || tp.x > 1.5 || tp.y > 0.30 || tp.y < -2.86) return col;
	vec4 t = treeAt(a - base, s, kind, seed);
	float win = win1(tp.x, -1.42, 1.42, 0.16) * win1(tp.y, -2.78, 0.24, 0.18);
	return mix(col, mix(t.rgb, vec3(0.03, 0.06, 0.10), dark), t.a * win);
}

// ---- Premium grass tuft: several curved, tapered, gradient blades ----
vec4 grassTuft(vec2 p, float seed) {
	vec4 acc = vec4(0.0);
	for (int i = 0; i < 7; i++) { float fi = float(i);
		float off = (hash11(seed + fi * 1.3) - 0.5) * 0.9;
		float h = 0.7 + 0.5 * hash11(seed + fi * 2.1);
		float bend = (hash11(seed + fi * 3.7) - 0.5) * 0.8;
		float wbl = 0.05 + 0.02 * hash11(seed + fi * 4.9);
		float t = clamp((-p.y) / h, 0.0, 1.0);
		float cx = off + bend * t * t;
		float d = abs(p.x - cx) - wbl * (1.0 - t);
		d = max(d, max(p.y, -p.y - h));
		float ga = aafill(d);
		vec3 gc = mix(vec3(0.10, 0.34, 0.14), vec3(0.42, 0.72, 0.30), t);
		acc = _ov(acc, gc, ga);
		acc = _ov(acc, vec3(0.55, 0.82, 0.40), aaline(p.x - cx + wbl * 0.3, 0.004) * ga * 0.4);
	}
	return acc;
}
vec3 placeGrass(vec3 col, vec2 a, vec2 base, float s, float seed) {
	vec2 gp = (a - base) / s;
	if (gp.x < -1.3 || gp.x > 1.3 || gp.y > 0.30 || gp.y < -1.54) return col;
	vec4 g = grassTuft(gp, seed);
	float win = win1(gp.x, -1.24, 1.24, 0.14) * win1(gp.y, -1.46, 0.26, 0.16);
	return mix(col, g.rgb, g.a * win);
}

// ---- Detailed mushroom: domed spotted cap, gills, shaded cream stem ----
vec4 mushroomShape(vec2 p, float seed, vec3 capCol) {
	vec4 acc = vec4(0.0);
	float capR = 0.5 + 0.1 * hash11(seed);
	// stem (slight bulge at the base)
	{
		float sy = -p.y;
		float sw = 0.16 * (1.0 + 0.5 * smoothstep(0.0, 0.15, sy) - 0.3 * smoothstep(0.0, 0.6, sy));
		float d = abs(p.x) - sw;
		d = max(d, max(p.y, -p.y - 0.62));
		float sa = aafill(d);
		vec3 sc = mix(vec3(0.78, 0.74, 0.62), vec3(0.95, 0.92, 0.82), smoothstep(0.0, -0.6, p.y));
		acc = _ov(acc, sc, sa);
		acc = _ov(acc, vec3(0.68, 0.64, 0.53), aaline(p.x - 0.05, 0.02) * sa * 0.5);
	}
	// gill ring just under the cap
	acc = _ov(acc, vec3(0.86, 0.80, 0.70), aafill(ellip(p, vec2(0.0, -0.5), vec2(capR * 0.9, 0.10), 0.0)) * step(p.y, -0.46));
	// domed cap (upper half) with shading + white spots + rim light
	{
		float cd = ellip(p, vec2(0.0, -0.6), vec2(capR, capR * 0.72), 0.0);
		float ca = aafill(cd) * step(p.y, -0.56);
		vec3 cc = mix(capCol * 0.7, capCol, smoothstep(-0.6 - capR * 0.7, -0.6, p.y));
		cc = mix(cc, capCol * 1.15, smoothstep(0.2, -0.3, p.x) * 0.5);
		acc = _ov(acc, cc, ca);
		for (int i = 0; i < 5; i++) { float fi = float(i);
			vec2 sp = vec2((-0.55 + 0.28 * fi) * capR + 0.05 * hash11(seed + fi), -0.62 - 0.10 * hash11(seed + fi * 2.0));
			acc = _ov(acc, vec3(0.98, 0.96, 0.90), aafill(sdCircle(p - sp, (0.06 + 0.03 * hash11(seed + fi)) * capR)) * ca * 0.95);
		}
		acc = _ov(acc, vec3(1.0, 0.95, 0.90), aaline(cd, 0.02) * step(p.y, -0.62) * ca * 0.4);
	}
	return acc;
}
vec3 placeMushroom(vec3 col, vec2 a, vec2 base, float s, float seed, float glow, vec3 glowCol) {
	vec2 mp = (a - base) / s;
	if (mp.x < -1.12 || mp.x > 1.12 || mp.y > 0.30 || mp.y < -1.72) return col;
	float win = win1(mp.x, -1.06, 1.06, 0.12) * win1(mp.y, -1.64, 0.26, 0.14);
	col = mix(col, col * 0.6, aafill(ellip(a, base + vec2(0.0, 0.02 * s), vec2(0.5 * s, 0.12 * s), 0.0)) * 0.4 * win);
	vec3 capCol = mix(vec3(0.86, 0.16, 0.14), glowCol, glow);
	if (glow > 0.5) col += glowCol * smoothstep(1.4, 0.0, length(mp)) * 0.25 * win;
	vec4 m = mushroomShape(mp, seed, capCol);
	return mix(col, m.rgb, m.a * win);
}
"

const _HEAD := "shader_type canvas_item;\nuniform float aspect = 1.78;\n" + _NOISE_GLSL + _SHAPES_GLSL + _NATURE_GLSL

# ---- MID-VALUE: detailed static scenes ----
# Composition rule: the Simon wheel covers the vertical middle of the screen, so
# every scene keeps its hero detail in the top band (y < 0.20) and bottom band
# (y > 0.70) and keeps the centre as open atmosphere. Edges are drawn crisp with
# aafill/aaline (no blur) for a high-end look.

const _RAINBOW_SHADER := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(0.46, 0.76, 0.99), vec3(0.85, 0.95, 1.0), uv.y);
	// sun + crisp rays, upper-left
	vec2 sp = vec2(0.15 * aspect, 0.11);
	float sd = distance(a, sp);
	float sang = atan(a.y - sp.y, a.x - sp.x);
	col += vec3(1.0, 0.92, 0.55) * smoothstep(0.34, 0.0, sd) * (0.28 + 0.14 * max(0.0, sin(sang * 16.0)));
	col = mix(col, vec3(1.0, 0.96, 0.62), aafill(sd - 0.070));
	// rainbow arc with crisp bands
	vec2 cc = vec2(0.5 * aspect, 1.36);
	float rd = distance(a, cc);
	float bw = 0.050;
	for (int i = 0; i < 7; i++) {
		float r0 = 0.56 + float(i) * bw;
		float ring = aafill(rd - (r0 + bw)) * aafill(r0 - rd);
		vec3 bc = vec3(0.93, 0.22, 0.24);
		if (i == 1) bc = vec3(0.98, 0.57, 0.18);
		if (i == 2) bc = vec3(0.99, 0.89, 0.26);
		if (i == 3) bc = vec3(0.32, 0.77, 0.36);
		if (i == 4) bc = vec3(0.24, 0.53, 0.92);
		if (i == 5) bc = vec3(0.36, 0.30, 0.72);
		if (i == 6) bc = vec3(0.62, 0.32, 0.74);
		col = mix(col, bc, ring * 0.92);
	}
	// billowy randomised clouds across the top band
	col = placeCloud(col, a, vec2(0.28 * aspect, 0.16), 0.22, 11.0, vec3(1.0), vec3(0.80, 0.85, 0.93));
	col = placeCloud(col, a, vec2(0.60 * aspect, 0.11), 0.15, 27.0, vec3(1.0), vec3(0.82, 0.87, 0.95));
	col = placeCloud(col, a, vec2(0.87 * aspect, 0.25), 0.19, 43.0, vec3(1.0), vec3(0.80, 0.85, 0.93));
	// a flock of birds gliding past: random species (repeats fine), speeds, sizes
	// and an off-screen gap before each loops back in from the left
	for (int i = 0; i < 5; i++) col = flyBird(col, a, TIME, float(i) * 7.3 + 1.0, 0.26, 0.12, 0.10, 0.0);
	// grassy hill + crisp flowers at the bottom
	float hill = 0.80 - 0.05 * sin(uv.x * 5.0);
	col = mix(col, mix(vec3(0.35, 0.70, 0.32), vec3(0.18, 0.48, 0.20), (uv.y - hill) / (1.0 - hill)), aafill(hill - uv.y));
	// a round broadleaf + a pine rooted on the hill
	col = placeTree(col, a, vec2(0.14 * aspect, 0.885), 0.15, 1, 4.0, 0.0);
	col = placeTree(col, a, vec2(0.86 * aspect, 0.895), 0.14, 0, 9.0, 0.0);
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		vec2 fp = vec2((0.06 + 0.11 * fi) * aspect, 0.86 + 0.06 * hash11(fi * 3.1));
		vec3 pc = vec3(hash11(fi * 1.3), hash11(fi * 2.9), hash11(fi * 5.7)) * 0.55 + 0.40;
		col = mix(col, vec3(0.16, 0.42, 0.18), aaline(a.x - fp.x, 0.004) * step(fp.y, a.y) * step(a.y, fp.y + 0.07));
		col = mix(col, pc, aafill(sdStar5(a - fp, 0.022, 0.45)));
		col = mix(col, vec3(1.0, 0.92, 0.35), aafill(distance(a, fp) - 0.007));
	}
	COLOR = vec4(col, 1.0);
}
"
# Rainbow static plate: the full scene MINUS the 5 flying birds (the only animated
# element). Birds are drawn as sprites over this plate.
const _RAINBOW_STATIC := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(0.46, 0.76, 0.99), vec3(0.85, 0.95, 1.0), uv.y);
	vec2 sp = vec2(0.15 * aspect, 0.11);
	float sd = distance(a, sp);
	float sang = atan(a.y - sp.y, a.x - sp.x);
	col += vec3(1.0, 0.92, 0.55) * smoothstep(0.34, 0.0, sd) * (0.28 + 0.14 * max(0.0, sin(sang * 16.0)));
	col = mix(col, vec3(1.0, 0.96, 0.62), aafill(sd - 0.070));
	vec2 cc = vec2(0.5 * aspect, 1.36);
	float rd = distance(a, cc);
	float bw = 0.050;
	for (int i = 0; i < 7; i++) {
		float r0 = 0.56 + float(i) * bw;
		float ring = aafill(rd - (r0 + bw)) * aafill(r0 - rd);
		vec3 bc = vec3(0.93, 0.22, 0.24);
		if (i == 1) bc = vec3(0.98, 0.57, 0.18);
		if (i == 2) bc = vec3(0.99, 0.89, 0.26);
		if (i == 3) bc = vec3(0.32, 0.77, 0.36);
		if (i == 4) bc = vec3(0.24, 0.53, 0.92);
		if (i == 5) bc = vec3(0.36, 0.30, 0.72);
		if (i == 6) bc = vec3(0.62, 0.32, 0.74);
		col = mix(col, bc, ring * 0.92);
	}
	col = placeCloud(col, a, vec2(0.28 * aspect, 0.16), 0.22, 11.0, vec3(1.0), vec3(0.80, 0.85, 0.93));
	col = placeCloud(col, a, vec2(0.60 * aspect, 0.11), 0.15, 27.0, vec3(1.0), vec3(0.82, 0.87, 0.95));
	col = placeCloud(col, a, vec2(0.87 * aspect, 0.25), 0.19, 43.0, vec3(1.0), vec3(0.80, 0.85, 0.93));
	float hill = 0.80 - 0.05 * sin(uv.x * 5.0);
	col = mix(col, mix(vec3(0.35, 0.70, 0.32), vec3(0.18, 0.48, 0.20), (uv.y - hill) / (1.0 - hill)), aafill(hill - uv.y));
	col = placeTree(col, a, vec2(0.14 * aspect, 0.885), 0.15, 1, 4.0, 0.0);
	col = placeTree(col, a, vec2(0.86 * aspect, 0.895), 0.14, 0, 9.0, 0.0);
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		vec2 fp = vec2((0.06 + 0.11 * fi) * aspect, 0.86 + 0.06 * hash11(fi * 3.1));
		vec3 pc = vec3(hash11(fi * 1.3), hash11(fi * 2.9), hash11(fi * 5.7)) * 0.55 + 0.40;
		col = mix(col, vec3(0.16, 0.42, 0.18), aaline(a.x - fp.x, 0.004) * step(fp.y, a.y) * step(a.y, fp.y + 0.07));
		col = mix(col, pc, aafill(sdStar5(a - fp, 0.022, 0.45)));
		col = mix(col, vec3(1.0, 0.92, 0.35), aafill(distance(a, fp) - 0.007));
	}
	COLOR = vec4(col, 1.0);
}
"

const _FOREST_SHADER := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(0.78, 0.88, 0.66), vec3(0.20, 0.42, 0.26), smoothstep(0.0, 1.0, uv.y));
	// crisp god-ray shafts
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float x0 = (0.12 + 0.18 * fi) * aspect;
		col += vec3(0.95, 0.98, 0.62) * smoothstep(0.05 + 0.02 * hash11(fi), 0.0, abs(a.x - (x0 + uv.y * 0.12))) * (1.0 - uv.y) * 0.16;
	}
	// distant misty treeline along the back, low on the horizon (no floating blobs)
	for (int i = 0; i < 8; i++) {
		float fi = float(i);
		float bx = (0.04 + 0.13 * fi) * aspect;
		col = placeTree(col, a, vec2(bx, 0.80 + 0.02 * hash11(fi * 4.1)), 0.10 + 0.03 * hash11(fi * 2.3), int(mod(fi, 2.0)), fi * 3.1 + 30.0, 0.45);
	}
	// ground band along the bottom (~1/8 of the screen): earthy soil capped with a
	// grassy crust, slightly uneven
	float groundY = 0.875;
	float gline = groundY + 0.012 * sin(uv.x * 7.0) + 0.006 * sin(uv.x * 19.0);
	float isG = aafill(gline - uv.y);
	vec3 soil = mix(vec3(0.34, 0.22, 0.12), vec3(0.19, 0.11, 0.06), smoothstep(gline, 1.0, uv.y));
	soil *= 0.9 + 0.2 * fbm(vec2(a.x * 10.0, uv.y * 10.0));
	soil = mix(soil, vec3(0.16, 0.42, 0.18), smoothstep(gline + 0.045, gline, uv.y));
	col = mix(col, soil, isG);
	// soft contact shadows where the big trees meet the ground
	col = mix(col, col * 0.7, aafill(ellip(a, vec2(0.13 * aspect, gline + 0.01), vec2(0.12, 0.018), 0.0)) * isG * 0.6);
	col = mix(col, col * 0.7, aafill(ellip(a, vec2(0.87 * aspect, gline + 0.01), vec2(0.12, 0.018), 0.0)) * isG * 0.6);
	// trees rooted ON the ground so their trunks rise from the surface
	col = placeTree(col, a, vec2(0.13 * aspect, gline + 0.012), 0.26, 0, 2.0, 0.0);
	col = placeTree(col, a, vec2(0.87 * aspect, gline + 0.016), 0.24, 1, 7.0, 0.0);
	col = placeTree(col, a, vec2(0.30 * aspect, gline + 0.004), 0.17, 2, 13.0, 0.0);
	col = placeTree(col, a, vec2(0.70 * aspect, gline + 0.004), 0.16, 0, 19.0, 0.0);
	// premium grass right across the whole ground
	for (int i = 0; i < 16; i++) {
		float fi = float(i);
		float gx = (0.02 + 0.063 * fi) * aspect + 0.02 * hash11(fi * 6.1);
		col = placeGrass(col, a, vec2(gx, gline + 0.012 + 0.01 * hash11(fi * 3.3)), 0.05 + 0.02 * hash11(fi * 2.9), fi * 1.3 + 5.0);
	}
	// many small spotted mushrooms nestled in the grass across the ground
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		float mx = (0.08 + 0.10 * fi) * aspect + 0.02 * hash11(fi * 5.3);
		float my = gline + 0.012 + 0.012 * hash11(fi * 3.1);
		col = placeGrass(col, a, vec2(mx - 0.025, my), 0.05 + 0.02 * hash11(fi * 1.7), fi * 2.3);
		col = placeMushroom(col, a, vec2(mx, my), 0.045 + 0.02 * hash11(fi * 2.7), fi * 1.9, 0.0, vec3(0.0));
		col = placeGrass(col, a, vec2(mx + 0.03, my), 0.05 + 0.02 * hash11(fi * 4.1), fi * 3.7 + 1.0);
	}
	// fireflies (sharp glints)
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		vec2 fp = vec2(hash11(fi * 3.1) * aspect, 0.18 + 0.62 * hash11(fi * 7.7));
		col += vec3(0.95, 0.95, 0.45) * aafill(distance(a, fp) - 0.0035);
		col += vec3(0.90, 0.90, 0.40) * smoothstep(0.020, 0.0, distance(a, fp)) * 0.30;
	}
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	col *= mix(0.72, 1.0, smoothstep(1.2, 0.25, length(p)));
	COLOR = vec4(col, 1.0);
}
"

const _DESERT_SHADER := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(1.0, 0.80, 0.45), vec3(0.99, 0.58, 0.40), uv.y * 0.7);
	col = mix(col, vec3(0.52, 0.26, 0.40), smoothstep(0.42, 0.62, uv.y));
	// big setting sun, upper-right, with banded slats
	vec2 sp = vec2(0.72 * aspect, 0.14);
	col += vec3(1.0, 0.72, 0.34) * smoothstep(0.40, 0.0, distance(a, sp)) * 0.30;
	float sun = aafill(distance(a, sp) - 0.085);
	col = mix(col, vec3(1.0, 0.88, 0.50), sun);
	col = mix(col, vec3(1.0, 0.62, 0.30), sun * aaline(mod(a.y - sp.y + 0.5, 0.05) - 0.025, 0.012) * step(0.0, a.y - sp.y + 0.02));
	// a flock near the top, dark against the sunset: random species, speeds, sizes
	// and an off-screen gap before each loops back in from the left
	for (int i = 0; i < 5; i++) col = flyBird(col, a, TIME, float(i) * 6.1 + 2.0, 0.18, 0.10, 0.090, 0.86);
	// layered mesas, crisp flat tops
	for (int L = 0; L < 2; L++) {
		float d = float(L);
		float top = 0.50 + d * 0.06;
		float blocky = top - 0.05 * step(0.5, fract(uv.x * (2.0 + d) + d * 0.3)) - 0.03 * step(0.5, fract(uv.x * (3.7 + d)));
		col = mix(col, mix(vec3(0.62, 0.30, 0.26), vec3(0.45, 0.20, 0.20), d), aafill(blocky - uv.y) * step(uv.y, 0.64));
	}
	// desert floor
	col = mix(col, mix(vec3(0.84, 0.48, 0.27), vec3(0.50, 0.27, 0.17), (uv.y - 0.62) / 0.38), aafill(0.62 - uv.y));
	// foreground saguaro cacti, crisp, framing the bottom
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float cx = (0.10 + 0.26 * fi) * aspect;
		float hh = 0.13 + 0.03 * hash11(fi);
		float body = sdBox(vec2(a.x - cx, a.y - 0.86), vec2(0.020, hh));
		float arm1 = min(sdBox(vec2(a.x - cx - 0.050, a.y - 0.80), vec2(0.035, 0.014)), sdBox(vec2(a.x - cx - 0.082, a.y - 0.76), vec2(0.014, 0.040)));
		float arm2 = min(sdBox(vec2(a.x - cx + 0.050, a.y - 0.84), vec2(0.035, 0.014)), sdBox(vec2(a.x - cx + 0.082, a.y - 0.80), vec2(0.014, 0.040)));
		float cac = min(body, min(arm1, arm2));
		col = mix(col, vec3(0.13, 0.34, 0.19), aafill(cac));
		col = mix(col, vec3(0.20, 0.46, 0.26), aaline(cac + 0.006, 0.004));
	}
	COLOR = vec4(col, 1.0);
}
"
# Desert: static plate (sky/sun/mesas/floor/cacti) minus the flock of birds.
const _DESERT_STATIC := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(1.0, 0.80, 0.45), vec3(0.99, 0.58, 0.40), uv.y * 0.7);
	col = mix(col, vec3(0.52, 0.26, 0.40), smoothstep(0.42, 0.62, uv.y));
	vec2 sp = vec2(0.72 * aspect, 0.14);
	col += vec3(1.0, 0.72, 0.34) * smoothstep(0.40, 0.0, distance(a, sp)) * 0.30;
	float sun = aafill(distance(a, sp) - 0.085);
	col = mix(col, vec3(1.0, 0.88, 0.50), sun);
	col = mix(col, vec3(1.0, 0.62, 0.30), sun * aaline(mod(a.y - sp.y + 0.5, 0.05) - 0.025, 0.012) * step(0.0, a.y - sp.y + 0.02));
	for (int L = 0; L < 2; L++) {
		float d = float(L);
		float top = 0.50 + d * 0.06;
		float blocky = top - 0.05 * step(0.5, fract(uv.x * (2.0 + d) + d * 0.3)) - 0.03 * step(0.5, fract(uv.x * (3.7 + d)));
		col = mix(col, mix(vec3(0.62, 0.30, 0.26), vec3(0.45, 0.20, 0.20), d), aafill(blocky - uv.y) * step(uv.y, 0.64));
	}
	col = mix(col, mix(vec3(0.84, 0.48, 0.27), vec3(0.50, 0.27, 0.17), (uv.y - 0.62) / 0.38), aafill(0.62 - uv.y));
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float cx = (0.10 + 0.26 * fi) * aspect;
		float hh = 0.13 + 0.03 * hash11(fi);
		float body = sdBox(vec2(a.x - cx, a.y - 0.86), vec2(0.020, hh));
		float arm1 = min(sdBox(vec2(a.x - cx - 0.050, a.y - 0.80), vec2(0.035, 0.014)), sdBox(vec2(a.x - cx - 0.082, a.y - 0.76), vec2(0.014, 0.040)));
		float arm2 = min(sdBox(vec2(a.x - cx + 0.050, a.y - 0.84), vec2(0.035, 0.014)), sdBox(vec2(a.x - cx + 0.082, a.y - 0.80), vec2(0.014, 0.040)));
		float cac = min(body, min(arm1, arm2));
		col = mix(col, vec3(0.13, 0.34, 0.19), aafill(cac));
		col = mix(col, vec3(0.20, 0.46, 0.26), aaline(cac + 0.006, 0.004));
	}
	COLOR = vec4(col, 1.0);
}
"
# Desert dynamic: sample plate, draw the gliding flock over it.
const _DESERT_DYN := _HEAD + "uniform sampler2D static_tex : filter_linear;
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = texture(static_tex, uv).rgb;
	for (int i = 0; i < 5; i++) col = flyBird(col, a, TIME, float(i) * 6.1 + 2.0, 0.18, 0.10, 0.090, 0.86);
	COLOR = vec4(col, 1.0);
}
"

const _SPEEDWAY_FUNCS := "
// Rear-view race car drawn in unit-ish space (y points DOWN). `body` is the paint
// colour. Built from rounded SDF boxes: shaded body, dark rear glass, glowing tail
// lights, plate, wheels and a soft contact shadow — reads crisp at any scale.
vec4 carRear(vec2 q, vec3 body) {
	vec4 acc = vec4(0.0);
	acc = _ov(acc, vec3(0.0), aafill(ellip(q, vec2(0.0, 0.50), vec2(0.66, 0.10), 0.0)) * 0.40);
	acc = _ov(acc, vec3(0.05, 0.05, 0.07), aafill(sdBox(q - vec2(-0.46, 0.34), vec2(0.10, 0.13)) - 0.02));
	acc = _ov(acc, vec3(0.05, 0.05, 0.07), aafill(sdBox(q - vec2( 0.46, 0.34), vec2(0.10, 0.13)) - 0.02));
	float bd = sdBox(q - vec2(0.0, 0.14), vec2(0.46, 0.30)) - 0.07;
	float ba = aafill(bd);
	vec3 bc = mix(body * 1.2, body * 0.6, clamp(q.y * 1.1 + 0.5, 0.0, 1.0));
	acc = _ov(acc, bc, ba);
	acc = _ov(acc, mix(body, vec3(1.0), 0.6), aaline(bd, 0.02) * step(q.y, -0.05) * ba * 0.7);
	float win = sdBox(q - vec2(0.0, -0.12), vec2(0.32, 0.15)) - 0.05;
	float wa = aafill(win);
	acc = _ov(acc, vec3(0.09, 0.12, 0.17), wa);
	acc = _ov(acc, vec3(0.45, 0.55, 0.65), aaline(win, 0.02) * step(q.y, -0.12) * wa * 0.7);
	acc = _ov(acc, vec3(1.0, 0.16, 0.10), aafill(sdBox(q - vec2(-0.33, 0.20), vec2(0.10, 0.05)) - 0.02));
	acc = _ov(acc, vec3(1.0, 0.16, 0.10), aafill(sdBox(q - vec2( 0.33, 0.20), vec2(0.10, 0.05)) - 0.02));
	acc = _ov(acc, vec3(1.0, 0.62, 0.50), aafill(sdBox(q - vec2(-0.33, 0.19), vec2(0.05, 0.02))));
	acc = _ov(acc, vec3(1.0, 0.62, 0.50), aafill(sdBox(q - vec2( 0.33, 0.19), vec2(0.05, 0.02))));
	acc = _ov(acc, vec3(0.88, 0.88, 0.78), aafill(sdBox(q - vec2(0.0, 0.27), vec2(0.11, 0.045))));
	return acc;
}
vec3 placeCar(vec3 col, vec2 a, vec2 c, float s, vec3 body, float fade) {
	vec2 q = (a - c) / s;
	if (abs(q.x) > 1.04 || abs(q.y) > 0.84) return col;
	vec4 cv = carRear(q, body);
	float win = win1(q.x, -0.98, 0.98, 0.10) * win1(q.y, -0.78, 0.78, 0.10);
	return mix(col, cv.rgb, cv.a * fade * win);
}
"
const _SPEEDWAY_SHADER := _HEAD + _SPEEDWAY_FUNCS + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	// sunset sky: dusky violet up high warming to a fiery glow toward the horizon
	vec3 col = mix(vec3(0.20, 0.11, 0.36), vec3(1.0, 0.60, 0.30), smoothstep(0.0, 0.27, uv.y));
	col = mix(col, vec3(1.0, 0.74, 0.40), smoothstep(0.15, 0.27, uv.y));
	// big setting sun in the upper sky, with a soft halo + banded slats
	vec2 sunp = vec2(0.62 * aspect, 0.125);
	float sdist = distance(a, sunp);
	col += vec3(1.0, 0.52, 0.24) * smoothstep(0.40, 0.0, sdist) * 0.5;
	float sundisk = aafill(sdist - 0.115);
	vec3 sunCol = mix(vec3(1.0, 0.93, 0.60), vec3(1.0, 0.60, 0.28), smoothstep(-0.115, 0.115, a.y - sunp.y));
	col = mix(col, sunCol, sundisk);
	col = mix(col, vec3(0.99, 0.52, 0.26), sundisk * step(0.0, a.y - sunp.y) * step(0.5, fract((a.y - sunp.y) * 26.0)) * 0.55);
	// a few thin sunset cloud streaks near the horizon
	for (int sc = 0; sc < 3; sc++) {
		float fsc = float(sc);
		float cy = 0.17 + 0.028 * fsc;
		col = mix(col, vec3(0.80, 0.36, 0.32), smoothstep(0.05, 0.0, abs(uv.y - cy)) * step(uv.y, 0.26) * 0.38 * (0.5 + 0.5 * sin(uv.x * 8.0 + fsc)));
	}
	// asphalt track in perspective, with kerbs
	if (uv.y >= 0.27) {
		float ty = (uv.y - 0.27) / 0.73;
		float halfw = mix(0.06, 0.62, ty);
		float cx = uv.x - 0.5;
		if (abs(cx) < halfw) {
			col = mix(vec3(0.24, 0.24, 0.27), vec3(0.12, 0.12, 0.14), ty);
			col = mix(col, vec3(0.95, 0.85, 0.20), step(abs(cx), 0.010 * mix(0.3, 1.0, ty)) * step(0.5, fract(uv.y * 14.0)));
			float kerb = step(halfw - 0.045, abs(cx)) * step(abs(cx), halfw - 0.014);
			col = mix(col, mix(vec3(0.90, 0.15, 0.15), vec3(0.95), step(0.5, fract(uv.y * 22.0))), kerb);
			col = mix(col, vec3(0.95), step(halfw - 0.014, abs(cx)));
		} else {
			col = mix(vec3(0.24, 0.48, 0.24), vec3(0.14, 0.32, 0.16), ty);
		}
	}
	// A stream of cars driving away down the track: each lane spawns a car every
	// once in a while (an off-screen gap, like the birds), the car recedes from the
	// near foreground up toward the vanishing point, shrinking with perspective and
	// fading out at the far end. Fresh colour + lane on every spawn.
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float speed = 0.05 + 0.05 * hash11(fi * 1.7);
		float gap = 0.6 + 1.4 * hash11(fi * 4.3);
		float raw = TIME * speed + hash11(fi * 9.1) * 3.0;
		float p = mod(raw, 1.0 + gap);
		if (p > 1.0) continue;                                   // parked off-track (the gap)
		float cyc = floor(raw / (1.0 + gap));                    // which car this lane is on
		float yy = mix(1.05, 0.305, p);                          // near (bottom) -> far (top)
		float ty = clamp((yy - 0.27) / 0.73, 0.0, 1.0);
		float halfw = mix(0.06, 0.62, ty);
		float lane = (fi - 1.0) * 0.46;                          // one car per fixed lane: L / centre / R (never collide)
		float cx = 0.5 + lane * halfw;
		float s = mix(0.016, 0.165, ty);
		float ci = hash11(fi * 2.9 + cyc * 1.7);
		vec3 body = vec3(0.90, 0.16, 0.16);                      // red
		if (ci > 0.16) body = vec3(0.13, 0.40, 0.92);            // blue
		if (ci > 0.33) body = vec3(0.96, 0.78, 0.12);            // yellow
		if (ci > 0.50) body = vec3(0.13, 0.62, 0.28);            // green
		if (ci > 0.66) body = vec3(0.96, 0.45, 0.10);            // orange
		if (ci > 0.83) body = vec3(0.92, 0.93, 0.97);            // white
		float fade = smoothstep(0.305, 0.345, yy) * smoothstep(1.05, 0.96, yy);
		col = placeCar(col, a, vec2(cx * aspect, yy), s, body, fade);
	}
	COLOR = vec4(col, 1.0);
}
"
# Speedway static plate: sunset sky + sun + cloud streaks + the perspective track
# with kerbs (all static — the only animated thing is the stream of cars).
const _SPEEDWAY_STATIC := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(0.20, 0.11, 0.36), vec3(1.0, 0.60, 0.30), smoothstep(0.0, 0.27, uv.y));
	col = mix(col, vec3(1.0, 0.74, 0.40), smoothstep(0.15, 0.27, uv.y));
	vec2 sunp = vec2(0.62 * aspect, 0.125);
	float sdist = distance(a, sunp);
	col += vec3(1.0, 0.52, 0.24) * smoothstep(0.40, 0.0, sdist) * 0.5;
	float sundisk = aafill(sdist - 0.115);
	vec3 sunCol = mix(vec3(1.0, 0.93, 0.60), vec3(1.0, 0.60, 0.28), smoothstep(-0.115, 0.115, a.y - sunp.y));
	col = mix(col, sunCol, sundisk);
	col = mix(col, vec3(0.99, 0.52, 0.26), sundisk * step(0.0, a.y - sunp.y) * step(0.5, fract((a.y - sunp.y) * 26.0)) * 0.55);
	for (int sc = 0; sc < 3; sc++) {
		float fsc = float(sc);
		float cy = 0.17 + 0.028 * fsc;
		col = mix(col, vec3(0.80, 0.36, 0.32), smoothstep(0.05, 0.0, abs(uv.y - cy)) * step(uv.y, 0.26) * 0.38 * (0.5 + 0.5 * sin(uv.x * 8.0 + fsc)));
	}
	if (uv.y >= 0.27) {
		float ty = (uv.y - 0.27) / 0.73;
		float halfw = mix(0.06, 0.62, ty);
		float cx = uv.x - 0.5;
		if (abs(cx) < halfw) {
			col = mix(vec3(0.24, 0.24, 0.27), vec3(0.12, 0.12, 0.14), ty);
			col = mix(col, vec3(0.95, 0.85, 0.20), step(abs(cx), 0.010 * mix(0.3, 1.0, ty)) * step(0.5, fract(uv.y * 14.0)));
			float kerb = step(halfw - 0.045, abs(cx)) * step(abs(cx), halfw - 0.014);
			col = mix(col, mix(vec3(0.90, 0.15, 0.15), vec3(0.95), step(0.5, fract(uv.y * 22.0))), kerb);
			col = mix(col, vec3(0.95), step(halfw - 0.014, abs(cx)));
		} else {
			col = mix(vec3(0.24, 0.48, 0.24), vec3(0.14, 0.32, 0.16), ty);
		}
	}
	COLOR = vec4(col, 1.0);
}
"
# Speedway dynamic: sample plate, draw the receding stream of cars over it.
const _SPEEDWAY_DYN := _HEAD + "uniform sampler2D static_tex : filter_linear;\n" + _SPEEDWAY_FUNCS + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = texture(static_tex, uv).rgb;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float speed = 0.05 + 0.05 * hash11(fi * 1.7);
		float gap = 0.6 + 1.4 * hash11(fi * 4.3);
		float raw = TIME * speed + hash11(fi * 9.1) * 3.0;
		float p = mod(raw, 1.0 + gap);
		if (p > 1.0) continue;
		float cyc = floor(raw / (1.0 + gap));
		float yy = mix(1.05, 0.305, p);
		float ty = clamp((yy - 0.27) / 0.73, 0.0, 1.0);
		float halfw = mix(0.06, 0.62, ty);
		float lane = (fi - 1.0) * 0.46;
		float cx = 0.5 + lane * halfw;
		float s = mix(0.016, 0.165, ty);
		float ci = hash11(fi * 2.9 + cyc * 1.7);
		vec3 body = vec3(0.90, 0.16, 0.16);
		if (ci > 0.16) body = vec3(0.13, 0.40, 0.92);
		if (ci > 0.33) body = vec3(0.96, 0.78, 0.12);
		if (ci > 0.50) body = vec3(0.13, 0.62, 0.28);
		if (ci > 0.66) body = vec3(0.96, 0.45, 0.10);
		if (ci > 0.83) body = vec3(0.92, 0.93, 0.97);
		float fade = smoothstep(0.305, 0.345, yy) * smoothstep(1.05, 0.96, yy);
		col = placeCar(col, a, vec2(cx * aspect, yy), s, body, fade);
	}
	COLOR = vec4(col, 1.0);
}
"

const _REEF_FUNCS := "
// Branching/lumpy reef coral, base at q=0 growing up (-y). seed randomises the
// fingers; tint is the coral colour, lighter toward the tips with bright polyps.
vec4 coralClump(vec2 q, float seed, vec3 tint) {
	vec4 acc = vec4(0.0);
	float d = 1000.0;
	for (int k = 0; k < 6; k++) {
		float fk = float(k);
		float bx = (hash11(seed + fk * 1.3) - 0.5) * 0.18;
		float bh = 0.09 + 0.07 * hash11(seed + fk * 2.1);
		float lean = (hash11(seed + fk * 3.7) - 0.5) * 0.12;
		vec2 p2 = q - vec2(bx, 0.0);
		float t = clamp(-p2.y / bh, 0.0, 1.0);
		float cx = lean * t * t;
		float w = 0.020 * (1.0 - 0.45 * t);
		float fd = abs(p2.x - cx) - w;
		fd = max(fd, max(p2.y, -p2.y - bh));
		fd = min(fd, distance(p2, vec2(cx, -bh)) - w);          // rounded tip knob
		d = min(d, fd);
	}
	float ca = aafill(d);
	vec3 cc = mix(tint * 0.55, tint * 1.2, smoothstep(0.02, -0.16, q.y));
	cc *= 0.85 + 0.3 * hash21(floor(q * 90.0));                  // speckled polyp texture
	acc = _ov(acc, cc, ca);
	acc = _ov(acc, tint + vec3(0.25), aaline(d, 0.006) * step(q.y, -0.02) * ca * 0.5);
	return acc;
}
// Translucent pulsing jellyfish: glowing bell + wavy trailing tentacles. q is
// jelly-relative (y DOWN, tentacles hang at +y); t drives the pulse + sway.
vec4 jelly(vec2 q, float t, vec3 tint) {
	vec4 acc = vec4(0.0);
	float pulse = 0.86 + 0.14 * sin(t * 2.2);
	vec2 e = vec2(0.5 * pulse, 0.40 / pulse);
	float bell = ellip(q, vec2(0.0, 0.0), e, 0.0);
	float rim = 0.08 + 0.04 * sin(q.x * 16.0);                  // scalloped lower rim
	float bd = max(bell, q.y - rim);
	float ba = aafill(bd);
	vec3 bc = mix(tint * 1.3, tint * 0.55, clamp(q.y / 0.40 + 0.5, 0.0, 1.0));
	acc = _ov(acc, bc, ba * 0.72);
	acc = _ov(acc, vec3(1.0), aaline(bd, 0.012) * step(q.y, -0.02) * ba * 0.6);
	acc = _ov(acc, tint + vec3(0.25), aafill(ellip(q, vec2(0.0, -0.06), e * 0.45, 0.0)) * 0.45);
	for (int k = 0; k < 6; k++) {
		float fk = float(k) / 5.0 - 0.5;
		float ty = q.y - rim;
		float wav = fk * e.x * 1.5 + 0.05 * sin(q.y * 11.0 + t * 3.0 + fk * 6.0) * smoothstep(0.0, 0.5, ty);
		float td = abs(q.x - wav) - 0.011 * (1.0 - clamp(ty / 0.85, 0.0, 1.0));
		td = max(td, max(-ty, ty - 0.85));
		acc = _ov(acc, mix(tint, vec3(1.0), 0.35), aafill(td) * 0.55);
	}
	return acc;
}
vec3 placeJelly(vec3 col, vec2 a, vec2 c, float s, float t, vec3 tint) {
	vec2 q = (a - c) / s;
	if (abs(q.x) > 1.04 || q.y < -0.70 || q.y > 1.20) return col;
	float win = win1(q.x, -0.98, 0.98, 0.10) * win1(q.y, -0.66, 1.16, 0.10);
	col += tint * smoothstep(0.65, 0.0, length(q * vec2(1.0, 0.55))) * 0.12 * win;
	vec4 j = jelly(q, t, tint);
	return mix(col, j.rgb, j.a * win);
}
"
const _REEF_SHADER := _HEAD + _REEF_FUNCS + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	vec3 col = mix(vec3(0.16, 0.55, 0.72), vec3(0.02, 0.13, 0.30), uv.y);
	// drifting, shimmering light shafts from the surface
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float x0 = (0.10 + 0.20 * fi) * aspect + 0.07 * sin(t * 0.3 + fi * 1.7);
		float lean = uv.y * 0.16 + 0.04 * sin(t * 0.45 + fi * 2.0);
		col += vec3(0.50, 0.85, 0.92) * smoothstep(0.05, 0.0, abs(a.x - (x0 + lean))) * (1.0 - uv.y) * (0.16 + 0.06 * sin(t * 0.8 + fi));
	}
	// swaying tapered seaweed rooted on the floor at the sides
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float side = step(3.5, fi);
		float basex = (mix(0.05, 0.95, side) + (mod(fi, 4.0) - 1.5) * 0.045) * aspect;
		float rootY = 0.86;
		float h = 0.22 + 0.08 * hash11(fi * 2.3);
		float tt = clamp((rootY - uv.y) / h, 0.0, 1.0);
		float sway = (0.03 + 0.06 * tt) * sin(t * 1.2 + fi * 1.7 + tt * 3.0);
		float w = 0.014 * (1.0 - 0.7 * tt);
		float d = abs(a.x - (basex + sway)) - w;
		d = max(d, max(uv.y - rootY, rootY - h - uv.y));
		vec3 wc = mix(vec3(0.08, 0.40, 0.20), vec3(0.22, 0.64, 0.30), tt);
		col = mix(col, wc, aafill(d));
	}
	// sandy floor with gently shifting caustic dapples
	float floorY = 0.82 + 0.02 * sin(uv.x * 9.0) + 0.015 * sin(uv.x * 23.0);
	float isFloor = aafill(floorY - uv.y);
	col = mix(col, mix(vec3(0.92, 0.84, 0.60), vec3(0.74, 0.62, 0.42), (uv.y - floorY) / 0.18), isFloor);
	col += vec3(0.18, 0.26, 0.22) * smoothstep(0.6, 0.95, fbm(vec2(a.x * 5.0 + t * 0.2, uv.y * 5.0 - t * 0.1))) * isFloor * 0.5;
	// detailed coral clumps rooted on the floor
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float cx = (0.10 + 0.20 * fi) * aspect;
		vec3 ccol = vec3(0.97, 0.36, 0.52);
		if (int(mod(fi, 3.0)) == 1) ccol = vec3(0.99, 0.60, 0.18);
		if (int(mod(fi, 3.0)) == 2) ccol = vec3(0.58, 0.42, 0.95);
		col = mix(col, col * 0.7, aafill(ellip(a, vec2(cx, 0.865), vec2(0.07, 0.014), 0.0)) * 0.4);
		vec4 cor = coralClump(a - vec2(cx, 0.86), fi * 4.7 + 1.0, ccol);
		col = mix(col, cor.rgb, cor.a);
	}
	// starfish on the sand
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		col = mix(col, vec3(1.0, 0.60, 0.25), aafill(sdStar5((a - vec2(mix(0.25, 0.75, fi) * aspect, 0.90)) * rot(0.3), 0.030, 0.5)));
	}
	// fish swimming across the top and floor bands at random speeds/directions
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float dir = (hash11(fi * 7.0) < 0.5) ? -1.0 : 1.0;
		float speed = 0.04 + 0.07 * hash11(fi * 2.3);
		float span = aspect + 0.30;
		float baseY = mix(0.13, 0.74, step(3.5, fi)) + 0.06 * hash11(fi * 5.1);
		float yy = baseY + 0.02 * sin(t * 0.8 + fi * 2.0);
		float prog = mod(t * speed + hash11(fi * 3.1) * span, span) - 0.15;
		float xx = (dir > 0.0) ? prog : (span - 0.30 - prog);
		vec2 q = a - vec2(xx, yy);
		q.x *= dir;
		float wig = 0.007 * sin(t * 8.0 + fi * 3.0);
		q.y += wig * smoothstep(0.0, 0.05, -q.x);               // tail-led body wiggle
		vec3 fc = vec3(0.99, 0.72, 0.20);
		if (int(mod(fi, 2.0)) == 0) fc = vec3(0.30, 0.72, 0.99);
		if (int(mod(fi, 3.0)) == 2) fc = vec3(0.95, 0.35, 0.45);
		float body = aafill(length(q * vec2(0.7, 1.7)) - 0.028);
		float tail = aafill(sdTri(vec2(q.x + 0.030 + wig, q.y) * rot(1.57), 0.018));
		col = mix(col, fc, max(body, tail));
		col = mix(col, fc * 0.65, aaline(q.y, 0.0018) * step(abs(q.x), 0.020) * body);
		// eye at the FRONT of the face (+q.x is the head; the tail trails at -q.x)
		col = mix(col, vec3(1.0), aafill(distance(q, vec2(0.020, -0.004)) - 0.007) * body);
		col = mix(col, vec3(0.05), aafill(distance(q, vec2(0.022, -0.004)) - 0.004) * body);
	}
	// drifting jellyfish across the top band (translucent, above the wheel)
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float jx = (0.13 + 0.25 * fi) * aspect + 0.05 * sin(t * 0.25 + fi * 2.3);
		float jy = 0.12 + 0.13 * hash11(fi * 4.1) + 0.05 * sin(t * 0.4 + fi * 1.7);
		float js = 0.06 + 0.025 * hash11(fi * 6.7);
		vec3 tint = vec3(0.95, 0.55, 0.85);
		if (int(mod(fi, 3.0)) == 1) tint = vec3(0.55, 0.80, 0.98);
		if (int(mod(fi, 3.0)) == 2) tint = vec3(0.98, 0.72, 0.45);
		col = placeJelly(col, a, vec2(jx, jy), js, t + fi * 1.3, tint);
	}
	// rising bubbles (sharp rings) streaming upward
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		vec2 bp = vec2(hash11(fi * 3.7) * aspect + 0.01 * sin(t + fi), fract(hash11(fi * 1.9) - t * (0.05 + 0.05 * hash11(fi))));
		col = mix(col, col + vec3(0.30, 0.40, 0.40), aaline(distance(a, bp) - 0.008, 0.0015));
	}
	COLOR = vec4(col, 1.0);
}
"
# Reef static plate: water gradient + sandy floor (caustics frozen) + coral clumps
# + starfish. The shafts, seaweed, fish and jellyfish animate; bubbles are particles.
const _REEF_STATIC := _HEAD + _REEF_FUNCS + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(0.16, 0.55, 0.72), vec3(0.02, 0.13, 0.30), uv.y);
	float floorY = 0.82 + 0.02 * sin(uv.x * 9.0) + 0.015 * sin(uv.x * 23.0);
	float isFloor = aafill(floorY - uv.y);
	col = mix(col, mix(vec3(0.92, 0.84, 0.60), vec3(0.74, 0.62, 0.42), (uv.y - floorY) / 0.18), isFloor);
	col += vec3(0.18, 0.26, 0.22) * smoothstep(0.6, 0.95, fbm(vec2(a.x * 5.0, uv.y * 5.0))) * isFloor * 0.5;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float cx = (0.10 + 0.20 * fi) * aspect;
		vec3 ccol = vec3(0.97, 0.36, 0.52);
		if (int(mod(fi, 3.0)) == 1) ccol = vec3(0.99, 0.60, 0.18);
		if (int(mod(fi, 3.0)) == 2) ccol = vec3(0.58, 0.42, 0.95);
		col = mix(col, col * 0.7, aafill(ellip(a, vec2(cx, 0.865), vec2(0.07, 0.014), 0.0)) * 0.4);
		vec4 cor = coralClump(a - vec2(cx, 0.86), fi * 4.7 + 1.0, ccol);
		col = mix(col, cor.rgb, cor.a);
	}
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		col = mix(col, vec3(1.0, 0.60, 0.25), aafill(sdStar5((a - vec2(mix(0.25, 0.75, fi) * aspect, 0.90)) * rot(0.3), 0.030, 0.5)));
	}
	COLOR = vec4(col, 1.0);
}
"
# Reef dynamic: sample plate, draw the shimmering light shafts, swaying seaweed,
# darting fish (bounded) and drifting jellyfish over it.
const _REEF_DYN := _HEAD + _REEF_FUNCS + "uniform sampler2D static_tex : filter_linear;
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	vec3 col = texture(static_tex, uv).rgb;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float x0 = (0.10 + 0.20 * fi) * aspect + 0.07 * sin(t * 0.3 + fi * 1.7);
		float lean = uv.y * 0.16 + 0.04 * sin(t * 0.45 + fi * 2.0);
		col += vec3(0.50, 0.85, 0.92) * smoothstep(0.05, 0.0, abs(a.x - (x0 + lean))) * (1.0 - uv.y) * (0.16 + 0.06 * sin(t * 0.8 + fi));
	}
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float side = step(3.5, fi);
		float basex = (mix(0.05, 0.95, side) + (mod(fi, 4.0) - 1.5) * 0.045) * aspect;
		float rootY = 0.86;
		float h = 0.22 + 0.08 * hash11(fi * 2.3);
		float tt = clamp((rootY - uv.y) / h, 0.0, 1.0);
		float sway = (0.03 + 0.06 * tt) * sin(t * 1.2 + fi * 1.7 + tt * 3.0);
		float w = 0.014 * (1.0 - 0.7 * tt);
		float d = abs(a.x - (basex + sway)) - w;
		d = max(d, max(uv.y - rootY, rootY - h - uv.y));
		vec3 wc = mix(vec3(0.08, 0.40, 0.20), vec3(0.22, 0.64, 0.30), tt);
		col = mix(col, wc, aafill(d));
	}
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float dir = (hash11(fi * 7.0) < 0.5) ? -1.0 : 1.0;
		float speed = 0.04 + 0.07 * hash11(fi * 2.3);
		float span = aspect + 0.30;
		float baseY = mix(0.13, 0.74, step(3.5, fi)) + 0.06 * hash11(fi * 5.1);
		float yy = baseY + 0.02 * sin(t * 0.8 + fi * 2.0);
		float prog = mod(t * speed + hash11(fi * 3.1) * span, span) - 0.15;
		float xx = (dir > 0.0) ? prog : (span - 0.30 - prog);
		vec2 q = a - vec2(xx, yy);
		q.x *= dir;
		float wig = 0.007 * sin(t * 8.0 + fi * 3.0);
		q.y += wig * smoothstep(0.0, 0.05, -q.x);
		if (abs(q.x) < 0.11 && abs(q.y) < 0.075) {
			vec3 col0 = col;
			vec3 fc = vec3(0.99, 0.72, 0.20);
			if (int(mod(fi, 2.0)) == 0) fc = vec3(0.30, 0.72, 0.99);
			if (int(mod(fi, 3.0)) == 2) fc = vec3(0.95, 0.35, 0.45);
			float body = aafill(length(q * vec2(0.7, 1.7)) - 0.028);
			float tail = aafill(sdTri(vec2(q.x + 0.030 + wig, q.y) * rot(1.57), 0.018));
			col = mix(col, fc, max(body, tail));
			col = mix(col, fc * 0.65, aaline(q.y, 0.0018) * step(abs(q.x), 0.020) * body);
			col = mix(col, vec3(1.0), aafill(distance(q, vec2(0.020, -0.004)) - 0.007) * body);
			col = mix(col, vec3(0.05), aafill(distance(q, vec2(0.022, -0.004)) - 0.004) * body);
			col = mix(col0, col, win1(q.x, -0.095, 0.095, 0.018) * win1(q.y, -0.065, 0.065, 0.012));
		}
	}
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float jx = (0.13 + 0.25 * fi) * aspect + 0.05 * sin(t * 0.25 + fi * 2.3);
		float jy = 0.12 + 0.13 * hash11(fi * 4.1) + 0.05 * sin(t * 0.4 + fi * 1.7);
		float js = 0.06 + 0.025 * hash11(fi * 6.7);
		vec3 tint = vec3(0.95, 0.55, 0.85);
		if (int(mod(fi, 3.0)) == 1) tint = vec3(0.55, 0.80, 0.98);
		if (int(mod(fi, 3.0)) == 2) tint = vec3(0.98, 0.72, 0.45);
		col = placeJelly(col, a, vec2(jx, jy), js, t + fi * 1.3, tint);
	}
	COLOR = vec4(col, 1.0);
}
"

const _KITTY_SHADER := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	vec3 col = mix(vec3(1.0, 0.82, 0.89), vec3(1.0, 0.64, 0.79), uv.y);
	// soft candy stripes
	col = mix(col, col * 1.04, aaline(fract(a.x * 10.0) - 0.5, 0.18) * 0.3);
	// LOTS of hearts drifting up across the whole screen, each fading in and out
	for (int i = 0; i < 18; i++) {
		float fi = float(i);
		float speed = 0.02 + 0.05 * hash11(fi * 2.9);
		float yy = fract(hash11(fi * 3.1) - t * speed);
		vec2 hp = vec2(hash11(fi * 1.7) * aspect + 0.02 * sin(t * 0.7 + fi), yy);
		float sz = 16.0 + 14.0 * hash11(fi * 5.3);
		float fade = 0.30 + 0.70 * (0.5 + 0.5 * sin(t * 1.6 + fi * 2.0));
		vec3 hc = mix(vec3(1.0, 0.33, 0.54), vec3(1.0, 0.86, 0.92), hash11(fi));
		col = mix(col, hc, aafill(sdHeart((a - hp) * vec2(1.0, -1.0) * sz)) * fade);
	}
	// paw prints along the bottom
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		vec2 pp = vec2((0.12 + 0.18 * fi) * aspect, 0.93);
		col = mix(col, vec3(1.0, 0.60, 0.74), aafill(distance(a, pp) - 0.018));
		for (int k = 0; k < 4; k++) {
			float fk = float(k);
			col = mix(col, vec3(1.0, 0.60, 0.74), aafill(distance(a, pp + 0.026 * vec2(cos(fk * 1.4 - 0.7), -abs(sin(fk * 1.4 - 0.7)) * 0.8 - 0.4)) - 0.008));
		}
	}
	// ---- adorable Neko Pop kitty, tucked into the TOP-LEFT (clear of the wheel) ----
	vec2 c = vec2(0.175 * aspect, 0.150);
	vec2 q = a - c;
	float R = 0.090;
	// the LEFT eye (the cat's own left = screen right, +x) winks on a slow cycle
	float winkOpen = smoothstep(0.06, 0.14, fract(t * 0.22 + 0.45));   // 0 = winked shut, 1 = open
	// soft drop shadow
	col = mix(col, col * 0.86, aafill(length((q - vec2(0.008, 0.010)) * vec2(1.0, 0.96)) - (R + 0.004)) * 0.30);
	// ears (white) + head, drawn as one white silhouette. Ears are ROUNDED (rounded
	// triangle base + a rounded tip lobe) so they read as soft fur, not flat wedges.
	float earL = aafill(sdTri((q - vec2(-0.072, -0.082)) * rot(0.34), 0.038) - 0.013);
	earL = max(earL, aafill(sdCircle((q - vec2(-0.082, -0.116)) * vec2(1.0, 0.85), 0.018)));
	float earR = aafill(sdTri((q - vec2( 0.072, -0.082)) * rot(-0.34), 0.038) - 0.013);
	earR = max(earR, aafill(sdCircle((q - vec2( 0.082, -0.116)) * vec2(1.0, 0.85), 0.018)));
	float head = aafill(length(q * vec2(1.0, 0.96)) - R);
	col = mix(col, vec3(1.0), max(head, max(earL, earR)));
	// gentle fur shading toward the bottom
	col = mix(col, vec3(0.97, 0.90, 0.95), aafill(length(q * vec2(1.0, 0.96)) - R) * smoothstep(-0.08, 0.10, q.y) * 0.35);
	// inner pink ears (rounded, nested inside the soft ear)
	col = mix(col, vec3(0.98, 0.55, 0.66), aafill(sdTri((q - vec2(-0.072, -0.070)) * rot(0.34), 0.018) - 0.008));
	col = mix(col, vec3(0.98, 0.55, 0.66), aafill(sdTri((q - vec2( 0.072, -0.070)) * rot(-0.34), 0.018) - 0.008));
	// crisp outline
	col = mix(col, vec3(0.86, 0.45, 0.60), aaline(length(q * vec2(1.0, 0.96)) - R, 0.0022) * head);
	// blush cheeks
	col = mix(col, vec3(1.0, 0.62, 0.72), aafill(distance(q, vec2(-0.062, 0.030)) - 0.019) * head * 0.85);
	col = mix(col, vec3(1.0, 0.62, 0.72), aafill(distance(q, vec2( 0.062, 0.030)) - 0.019) * head * 0.85);
	// big glossy eyes — the right-screen eye (cat's LEFT) winks; the other stays open
	float eyL = 0.030;                              // viewer-left eye: always open
	float eyR = mix(0.004, 0.030, winkOpen);        // cat's left eye: squashes shut on the wink
	col = mix(col, vec3(0.17, 0.10, 0.17), aafill(length((q - vec2(-0.040, 0.006)) / vec2(0.021, eyL)) - 1.0) * head);
	col = mix(col, vec3(0.17, 0.10, 0.17), aafill(length((q - vec2( 0.040, 0.006)) / vec2(0.021, eyR)) - 1.0) * head);
	// when winked shut, draw a happy upward eyelash curve on the cat's left eye
	col = mix(col, vec3(0.40, 0.22, 0.30), aaline(distance(q - vec2(0.040, 0.012), vec2(0.0)) - 0.018, 0.0018) * step(q.y, 0.012) * step(0.024, q.x) * step(q.x, 0.056) * head * (1.0 - winkOpen));
	col = mix(col, vec3(1.0), aafill(distance(q, vec2(-0.034, -0.004)) - 0.006) * head);
	col = mix(col, vec3(1.0), aafill(distance(q, vec2( 0.046, -0.004)) - 0.006) * head * winkOpen);
	col = mix(col, vec3(1.0), aafill(distance(q, vec2(-0.046, 0.012)) - 0.003) * head);
	// little heart nose
	col = mix(col, vec3(0.98, 0.40, 0.52), aafill(sdHeart((q - vec2(0.0, 0.030)) * vec2(1.0, -1.0) * 70.0)) * head);
	// :3 mouth (two tiny arcs under the nose)
	col = mix(col, vec3(0.70, 0.34, 0.45), aaline(distance(q - vec2(-0.012, 0.044), vec2(0.0)) - 0.013, 0.0017) * step(0.044, q.y) * step(q.y, 0.060) * head);
	col = mix(col, vec3(0.70, 0.34, 0.45), aaline(distance(q - vec2( 0.012, 0.044), vec2(0.0)) - 0.013, 0.0017) * step(0.044, q.y) * step(q.y, 0.060) * head);
	// whiskers (three per side, fanned)
	for (int s = -1; s <= 1; s += 2) {
		float fs = float(s);
		for (int w = 0; w < 3; w++) {
			float fw = float(w) - 1.0;
			vec2 wc = vec2(fs * 0.112, 0.024 + fw * 0.016);
			float wd = aafill(sdBox((q - wc) * rot(fs * (-fw) * 0.22), vec2(0.034, 0.0014)));
			col = mix(col, vec3(0.62, 0.46, 0.52), wd * 0.85);
		}
	}
	// kawaii bow on the right ear
	vec2 bw = q - vec2(0.082, -0.108);
	float bowL = aafill(sdTri((bw + vec2(0.020, 0.0)) * rot(-1.5708), 0.026));
	float bowR = aafill(sdTri((bw - vec2(0.020, 0.0)) * rot(1.5708), 0.026));
	col = mix(col, vec3(1.0, 0.30, 0.50), max(bowL, bowR));
	col = mix(col, vec3(1.0, 0.62, 0.74), (aafill(sdTri((bw + vec2(0.020, -0.006)) * rot(-1.5708), 0.012)) + aafill(sdTri((bw - vec2(0.020, -0.006)) * rot(1.5708), 0.012))) * 0.6);
	col = mix(col, vec3(0.85, 0.18, 0.40), aafill(distance(bw, vec2(0.0)) - 0.011));
	// twinkling 4-point sparkles orbiting the kitty
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		vec2 spp = c + 0.17 * vec2(cos(fi * 1.05 + 0.3), sin(fi * 1.05 + 0.3));
		float tw = 0.5 + 0.5 * sin(t * 4.0 + fi * 1.7);
		vec2 d = a - spp;
		col += vec3(1.0, 1.0, 0.92) * (aaline(d.x, 0.0016) * step(abs(d.y), 0.011) + aaline(d.y, 0.0016) * step(abs(d.x), 0.011)) * tw * 0.9;
	}
	COLOR = vec4(col, 1.0);
}
"
# Kitty static plate: candy-pink gradient + stripes + paw prints. The drifting
# hearts are particles; the winking kitty + orbiting sparkles animate.
const _KITTY_STATIC := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(1.0, 0.82, 0.89), vec3(1.0, 0.64, 0.79), uv.y);
	col = mix(col, col * 1.04, aaline(fract(a.x * 10.0) - 0.5, 0.18) * 0.3);
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		vec2 pp = vec2((0.12 + 0.18 * fi) * aspect, 0.93);
		col = mix(col, vec3(1.0, 0.60, 0.74), aafill(distance(a, pp) - 0.018));
		for (int k = 0; k < 4; k++) {
			float fk = float(k);
			col = mix(col, vec3(1.0, 0.60, 0.74), aafill(distance(a, pp + 0.026 * vec2(cos(fk * 1.4 - 0.7), -abs(sin(fk * 1.4 - 0.7)) * 0.8 - 0.4)) - 0.008));
		}
	}
	COLOR = vec4(col, 1.0);
}
"
# Kitty dynamic: sample plate, draw the Neko Pop kitty (bounded to its corner so
# its many SDF ops only cost there) with its slow wink, plus orbiting sparkles.
const _KITTY_DYN := _HEAD + "uniform sampler2D static_tex : filter_linear;
uniform float eye_l = 1.0;   // viewer-left eye openness (0 = happy-closed)
uniform float eye_r = 1.0;   // viewer-right eye openness (the one that winks)
uniform float smile = 0.0;   // extra grin 0..1, driven by the gesture controller
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	vec3 col = texture(static_tex, uv).rgb;
	vec2 c = vec2(0.175 * aspect, 0.150);
	vec2 q = a - c;
	if (abs(q.x) < 0.185 && abs(q.y) < 0.185) {
		vec3 col0 = col;
		float R = 0.090;
		col = mix(col, col * 0.86, aafill(length((q - vec2(0.008, 0.010)) * vec2(1.0, 0.96)) - (R + 0.004)) * 0.30);
		float earL = aafill(sdTri((q - vec2(-0.072, -0.082)) * rot(0.34), 0.038) - 0.013);
		earL = max(earL, aafill(sdCircle((q - vec2(-0.082, -0.116)) * vec2(1.0, 0.85), 0.018)));
		float earR = aafill(sdTri((q - vec2( 0.072, -0.082)) * rot(-0.34), 0.038) - 0.013);
		earR = max(earR, aafill(sdCircle((q - vec2( 0.082, -0.116)) * vec2(1.0, 0.85), 0.018)));
		float head = aafill(length(q * vec2(1.0, 0.96)) - R);
		col = mix(col, vec3(1.0), max(head, max(earL, earR)));
		col = mix(col, vec3(0.97, 0.90, 0.95), aafill(length(q * vec2(1.0, 0.96)) - R) * smoothstep(-0.08, 0.10, q.y) * 0.35);
		col = mix(col, vec3(0.98, 0.55, 0.66), aafill(sdTri((q - vec2(-0.072, -0.070)) * rot(0.34), 0.018) - 0.008));
		col = mix(col, vec3(0.98, 0.55, 0.66), aafill(sdTri((q - vec2( 0.072, -0.070)) * rot(-0.34), 0.018) - 0.008));
		col = mix(col, vec3(0.86, 0.45, 0.60), aaline(length(q * vec2(1.0, 0.96)) - R, 0.0022) * head);
		col = mix(col, vec3(1.0, 0.62, 0.72), aafill(distance(q, vec2(-0.062, 0.030)) - 0.019) * head * 0.85);
		col = mix(col, vec3(1.0, 0.62, 0.72), aafill(distance(q, vec2( 0.062, 0.030)) - 0.019) * head * 0.85);
		float eyLh = mix(0.004, 0.030, eye_l);      // viewer-left eye height
		float eyRh = mix(0.004, 0.030, eye_r);      // viewer-right eye height (winks)
		col = mix(col, vec3(0.17, 0.10, 0.17), aafill(length((q - vec2(-0.040, 0.006)) / vec2(0.021, eyLh)) - 1.0) * head);
		col = mix(col, vec3(0.17, 0.10, 0.17), aafill(length((q - vec2( 0.040, 0.006)) / vec2(0.021, eyRh)) - 1.0) * head);
		col = mix(col, vec3(0.40, 0.22, 0.30), aaline(distance(q - vec2(-0.040, 0.012), vec2(0.0)) - 0.018, 0.0018) * step(q.y, 0.012) * step(-0.056, q.x) * step(q.x, -0.024) * head * (1.0 - eye_l));
		col = mix(col, vec3(0.40, 0.22, 0.30), aaline(distance(q - vec2( 0.040, 0.012), vec2(0.0)) - 0.018, 0.0018) * step(q.y, 0.012) * step(0.024, q.x) * step(q.x, 0.056) * head * (1.0 - eye_r));
		col = mix(col, vec3(1.0), aafill(distance(q, vec2(-0.034, -0.004)) - 0.006) * head * eye_l);
		col = mix(col, vec3(1.0), aafill(distance(q, vec2( 0.046, -0.004)) - 0.006) * head * eye_r);
		col = mix(col, vec3(1.0), aafill(distance(q, vec2(-0.046, 0.012)) - 0.003) * head * eye_l);
		col = mix(col, vec3(0.98, 0.40, 0.52), aafill(sdHeart((q - vec2(0.0, 0.030)) * vec2(1.0, -1.0) * 70.0)) * head);
		col = mix(col, vec3(0.70, 0.34, 0.45), aaline(distance(q - vec2(-0.012, 0.044), vec2(0.0)) - 0.013, 0.0017) * step(0.044, q.y) * step(q.y, 0.060) * head);
		col = mix(col, vec3(0.70, 0.34, 0.45), aaline(distance(q - vec2( 0.012, 0.044), vec2(0.0)) - 0.013, 0.0017) * step(0.044, q.y) * step(q.y, 0.060) * head);
		col = mix(col, vec3(0.72, 0.33, 0.44), aaline(distance(q - vec2(0.0, 0.028), vec2(0.0)) - 0.032, 0.0020) * step(0.052, q.y) * step(q.y, 0.070) * head * smile);
		for (int s = -1; s <= 1; s += 2) {
			float fs = float(s);
			for (int w = 0; w < 3; w++) {
				float fw = float(w) - 1.0;
				vec2 wc = vec2(fs * 0.112, 0.024 + fw * 0.016);
				float wd = aafill(sdBox((q - wc) * rot(fs * (-fw) * 0.22), vec2(0.034, 0.0014)));
				col = mix(col, vec3(0.62, 0.46, 0.52), wd * 0.85);
			}
		}
		vec2 bw = q - vec2(0.082, -0.108);
		float bowL = aafill(sdTri((bw + vec2(0.020, 0.0)) * rot(-1.5708), 0.026));
		float bowR = aafill(sdTri((bw - vec2(0.020, 0.0)) * rot(1.5708), 0.026));
		col = mix(col, vec3(1.0, 0.30, 0.50), max(bowL, bowR));
		col = mix(col, vec3(1.0, 0.62, 0.74), (aafill(sdTri((bw + vec2(0.020, -0.006)) * rot(-1.5708), 0.012)) + aafill(sdTri((bw - vec2(0.020, -0.006)) * rot(1.5708), 0.012))) * 0.6);
		col = mix(col, vec3(0.85, 0.18, 0.40), aafill(distance(bw, vec2(0.0)) - 0.011));
		col = mix(col0, col, win1(q.x, -0.18, 0.18, 0.02) * win1(q.y, -0.18, 0.18, 0.02));
	}
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		vec2 spp = c + 0.17 * vec2(cos(fi * 1.05 + 0.3), sin(fi * 1.05 + 0.3));
		float tw = 0.5 + 0.5 * sin(t * 4.0 + fi * 1.7);
		vec2 d = a - spp;
		col += vec3(1.0, 1.0, 0.92) * (aaline(d.x, 0.0016) * step(abs(d.y), 0.011) + aaline(d.y, 0.0016) * step(abs(d.x), 0.011)) * tw * 0.9;
	}
	COLOR = vec4(col, 1.0);
}
"

const _COSMOS_SHADER := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	vec3 col = mix(vec3(0.03, 0.02, 0.10), vec3(0.08, 0.03, 0.18), uv.y);
	// nebula clouds biased to the top and bottom bands
	col += vec3(0.45, 0.18, 0.60) * smoothstep(0.55, 0.95, fbm(a * 2.6 + 1.0)) * 0.45 * smoothstep(0.45, 0.0, abs(uv.y - 0.13));
	col += vec3(0.15, 0.35, 0.70) * smoothstep(0.50, 0.95, fbm(a * 2.2 + 7.0)) * 0.40 * smoothstep(0.45, 0.0, abs(uv.y - 0.88));
	// crisp star field, each star twinkling on its own cycle; brightest sparkle
	for (int i = 0; i < 30; i++) {
		float fi = float(i);
		vec2 sp = vec2(hash11(fi * 1.3) * aspect, hash11(fi * 2.7));
		float br = hash11(fi * 3.9);
		float tw = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * (1.4 + 2.2 * hash11(fi * 5.1)) + fi * 3.3));
		col += vec3(1.0) * aafill(distance(a, sp) - 0.0018 * (0.5 + br)) * (0.35 + 0.65 * br) * tw;
		if (br > 0.80) {
			float spk = tw * (0.6 + 0.4 * sin(t * 2.5 + fi));
			col += vec3(0.80, 0.90, 1.0) * aaline(a.y - sp.y, 0.0015) * step(abs(a.x - sp.x), 0.012) * spk;
			col += vec3(0.80, 0.90, 1.0) * aaline(a.x - sp.x, 0.0015) * step(abs(a.y - sp.y), 0.012) * spk;
		}
	}
	// ringed planet, top-right — the ring SPINS (bright segments sweep around it)
	vec2 pc = vec2(0.74 * aspect, 0.16);
	vec2 q = a - pc;
	float ringline = aaline(length(q * vec2(1.0, 3.2)) - 0.17, 0.013);
	float rang = atan(q.y * 3.2, q.x);
	float spin = 0.5 + 0.5 * sin(rang * 6.0 - t * 1.4);                 // segments rotate -> spin
	vec3 ringCol = vec3(0.92, 0.82, 0.62) * (0.55 + 0.6 * spin);
	col = mix(col, ringCol, ringline);
	float pl = aafill(length(q) - 0.105);
	vec3 pcol = mix(vec3(0.96, 0.72, 0.42), vec3(0.62, 0.34, 0.22), clamp(q.y / 0.105 * 0.5 + 0.5, 0.0, 1.0));
	pcol = mix(pcol, pcol * 0.85, step(0.5, fract(q.y * 26.0)));
	col = mix(col, pcol, pl);
	col = mix(col, ringCol, ringline * step(0.0, q.y));                 // front arc of the ring
	// Mars — detailed red planet, top-left (dusty mottle, polar cap, lit limb)
	vec2 mq = a - vec2(0.17 * aspect, 0.12);
	float mr = 0.058;
	float marsA = aafill(length(mq) - mr);
	vec3 mcol = mix(vec3(0.78, 0.34, 0.18), vec3(0.55, 0.22, 0.12), fbm(mq * 16.0 + 2.0));
	mcol = mix(mcol, vec3(0.88, 0.52, 0.32), smoothstep(0.5, 0.82, fbm(mq * 26.0 - 1.0)) * 0.6);   // highlands
	mcol = mix(mcol, vec3(0.92, 0.94, 0.98), smoothstep(0.62, 0.92, -mq.y / mr) * 0.85);            // north polar cap
	mcol *= mix(0.26, 1.15, smoothstep(-0.35, 0.6, dot(normalize(mq + 0.0008), normalize(vec2(-0.6, -0.6)))));
	col += vec3(0.70, 0.34, 0.18) * smoothstep(mr + 0.024, mr, length(mq)) * 0.30;                  // thin atmosphere
	col = mix(col, mcol, marsA);
	// Earth — bottom-right, SPINNING on its axis so the continents scroll past, with
	// drifting clouds, a lit day side fading into night, and an atmospheric rim glow
	vec2 ec = vec2(0.80 * aspect, 0.84);
	vec2 eq = a - ec;
	float er = 0.078;
	float ea = aafill(length(eq) - er);
	float spinx = eq.x + t * 0.05;                                       // surface rotates on the axis
	vec3 ecol = mix(vec3(0.10, 0.40, 0.64), vec3(0.06, 0.24, 0.48), clamp(eq.y / er * 0.5 + 0.5, 0.0, 1.0));
	float land = fbm(vec2(spinx, eq.y) * 15.0 + 3.0);
	ecol = mix(ecol, vec3(0.18, 0.50, 0.26), smoothstep(0.54, 0.68, land));
	ecol = mix(ecol, vec3(0.34, 0.60, 0.34), smoothstep(0.66, 0.82, land) * 0.7);
	ecol = mix(ecol, vec3(0.88, 0.92, 0.98), smoothstep(0.74, 0.96, fbm(vec2(eq.x + t * 0.03, eq.y) * 11.0 - 1.0)) * 0.5);
	float lightd = dot(normalize(eq + vec2(0.0008, 0.0008)), normalize(vec2(-0.6, -0.7)));
	ecol *= mix(0.20, 1.18, smoothstep(-0.35, 0.6, lightd));
	col += vec3(0.30, 0.52, 0.72) * smoothstep(er + 0.032, er, length(eq)) * 0.5;
	col = mix(col, ecol, ea);
	// the Moon orbiting Earth (replaces the old bottom-left crescent)
	float moonAng = t * 0.55;
	vec2 moonPos = ec + vec2(cos(moonAng) * 0.165, sin(moonAng) * 0.072);   // elliptical (perspective) orbit
	vec2 mnq = a - moonPos;
	float mnr = 0.019;
	vec3 mnc = vec3(0.80, 0.80, 0.84) * (0.72 + 0.4 * fbm(mnq * 40.0));
	mnc = mix(mnc, mnc * 0.6, smoothstep(0.35, 0.7, fbm(mnq * 70.0)));      // dark maria
	mnc *= mix(0.30, 1.1, smoothstep(-0.3, 0.6, dot(normalize(mnq + 0.0006), normalize(vec2(-0.6, -0.7)))));
	col = mix(col, mnc, aafill(length(mnq) - mnr));
	// a shooting star streaking through every once in a while on a random path
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float period = 6.0 + 4.0 * hash11(fi * 2.1);
		float phase = (t + fi * 11.0) / period;
		float seed = floor(phase);
		float ph = fract(phase);
		vec2 ssp = vec2(hash11(seed + fi * 1.3) * aspect, 0.05 + 0.30 * hash11(seed + fi * 2.7));
		float ang = 3.14159 * (0.16 + 0.68 * hash11(seed + fi * 3.9));
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 head = ssp + dir * ph * (aspect * 1.2);
		vec2 d = a - head;
		float along = dot(d, -dir);
		float perp = dot(d, vec2(-dir.y, dir.x));
		float trail = smoothstep(0.22, 0.0, along) * step(0.0, along) * smoothstep(0.008, 0.0, abs(perp));
		float vis = smoothstep(0.0, 0.04, ph) * smoothstep(0.60, 0.40, ph);
		col += vec3(0.85, 0.95, 1.0) * trail * vis * 0.9;
		col += vec3(1.0) * smoothstep(0.012, 0.0, length(d)) * vis;
	}
	COLOR = vec4(col, 1.0);
}
"
# Cosmos static plate: space gradient + nebula + Mars (all static). The starfield,
# spinning ringed planet, spinning Earth, orbiting Moon and shooting stars animate.
const _COSMOS_STATIC := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(0.03, 0.02, 0.10), vec3(0.08, 0.03, 0.18), uv.y);
	col += vec3(0.45, 0.18, 0.60) * smoothstep(0.55, 0.95, fbm(a * 2.6 + 1.0)) * 0.45 * smoothstep(0.45, 0.0, abs(uv.y - 0.13));
	col += vec3(0.15, 0.35, 0.70) * smoothstep(0.50, 0.95, fbm(a * 2.2 + 7.0)) * 0.40 * smoothstep(0.45, 0.0, abs(uv.y - 0.88));
	vec2 mq = a - vec2(0.17 * aspect, 0.12);
	float mr = 0.058;
	float marsA = aafill(length(mq) - mr);
	vec3 mcol = mix(vec3(0.78, 0.34, 0.18), vec3(0.55, 0.22, 0.12), fbm(mq * 16.0 + 2.0));
	mcol = mix(mcol, vec3(0.88, 0.52, 0.32), smoothstep(0.5, 0.82, fbm(mq * 26.0 - 1.0)) * 0.6);
	mcol = mix(mcol, vec3(0.92, 0.94, 0.98), smoothstep(0.62, 0.92, -mq.y / mr) * 0.85);
	mcol *= mix(0.26, 1.15, smoothstep(-0.35, 0.6, dot(normalize(mq + 0.0008), normalize(vec2(-0.6, -0.6)))));
	col += vec3(0.70, 0.34, 0.18) * smoothstep(mr + 0.024, mr, length(mq)) * 0.30;
	col = mix(col, mcol, marsA);
	COLOR = vec4(col, 1.0);
}
"
# Cosmos dynamic: sample plate, then the spinning ringed planet, spinning Earth +
# orbiting Moon, and shooting stars — each planet bounded so it only costs where it
# actually is. (The starfield is particles.)
const _COSMOS_DYN := _HEAD + "uniform sampler2D static_tex : filter_linear;
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	vec3 col = texture(static_tex, uv).rgb;
	vec2 pc = vec2(0.74 * aspect, 0.16);
	vec2 q = a - pc;
	if (abs(q.x) < 0.24 && abs(q.y) < 0.11) {
		vec3 col0 = col;
		float ringline = aaline(length(q * vec2(1.0, 3.2)) - 0.17, 0.013);
		float rang = atan(q.y * 3.2, q.x);
		float spin = 0.5 + 0.5 * sin(rang * 6.0 - t * 1.4);
		vec3 ringCol = vec3(0.92, 0.82, 0.62) * (0.55 + 0.6 * spin);
		col = mix(col, ringCol, ringline);
		float pl = aafill(length(q) - 0.105);
		vec3 pcol = mix(vec3(0.96, 0.72, 0.42), vec3(0.62, 0.34, 0.22), clamp(q.y / 0.105 * 0.5 + 0.5, 0.0, 1.0));
		pcol = mix(pcol, pcol * 0.85, step(0.5, fract(q.y * 26.0)));
		col = mix(col, pcol, pl);
		col = mix(col, ringCol, ringline * step(0.0, q.y));
		col = mix(col0, col, win1(q.x, -0.23, 0.23, 0.02) * win1(q.y, -0.105, 0.105, 0.018));
	}
	vec2 ec = vec2(0.80 * aspect, 0.84);
	vec2 eq = a - ec;
	if (abs(eq.x) < 0.15 && abs(eq.y) < 0.15) {
		vec3 col0 = col;
		float er = 0.078;
		float ea = aafill(length(eq) - er);
		float spinx = eq.x + t * 0.05;
		vec3 ecol = mix(vec3(0.10, 0.40, 0.64), vec3(0.06, 0.24, 0.48), clamp(eq.y / er * 0.5 + 0.5, 0.0, 1.0));
		float land = fbm(vec2(spinx, eq.y) * 15.0 + 3.0);
		ecol = mix(ecol, vec3(0.18, 0.50, 0.26), smoothstep(0.54, 0.68, land));
		ecol = mix(ecol, vec3(0.34, 0.60, 0.34), smoothstep(0.66, 0.82, land) * 0.7);
		ecol = mix(ecol, vec3(0.88, 0.92, 0.98), smoothstep(0.74, 0.96, fbm(vec2(eq.x + t * 0.03, eq.y) * 11.0 - 1.0)) * 0.5);
		float lightd = dot(normalize(eq + vec2(0.0008, 0.0008)), normalize(vec2(-0.6, -0.7)));
		ecol *= mix(0.20, 1.18, smoothstep(-0.35, 0.6, lightd));
		col += vec3(0.30, 0.52, 0.72) * smoothstep(er + 0.032, er, length(eq)) * 0.5;
		col = mix(col, ecol, ea);
		col = mix(col0, col, win1(eq.x, -0.14, 0.14, 0.02) * win1(eq.y, -0.14, 0.14, 0.02));
	}
	float moonAng = t * 0.55;
	vec2 moonPos = ec + vec2(cos(moonAng) * 0.165, sin(moonAng) * 0.072);
	vec2 mnq = a - moonPos;
	if (abs(mnq.x) < 0.055 && abs(mnq.y) < 0.055) {
		vec3 col0 = col;
		float mnr = 0.019;
		vec3 mnc = vec3(0.80, 0.80, 0.84) * (0.72 + 0.4 * fbm(mnq * 40.0));
		mnc = mix(mnc, mnc * 0.6, smoothstep(0.35, 0.7, fbm(mnq * 70.0)));
		mnc *= mix(0.30, 1.1, smoothstep(-0.3, 0.6, dot(normalize(mnq + 0.0006), normalize(vec2(-0.6, -0.7)))));
		col = mix(col, mnc, aafill(length(mnq) - mnr));
		col = mix(col0, col, win1(mnq.x, -0.05, 0.05, 0.01) * win1(mnq.y, -0.05, 0.05, 0.01));
	}
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float period = 6.0 + 4.0 * hash11(fi * 2.1);
		float phase = (t + fi * 11.0) / period;
		float seed = floor(phase);
		float ph = fract(phase);
		vec2 ssp = vec2(hash11(seed + fi * 1.3) * aspect, 0.05 + 0.30 * hash11(seed + fi * 2.7));
		float ang = 3.14159 * (0.16 + 0.68 * hash11(seed + fi * 3.9));
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 head = ssp + dir * ph * (aspect * 1.2);
		vec2 d = a - head;
		float along = dot(d, -dir);
		float perp = dot(d, vec2(-dir.y, dir.x));
		float trail = smoothstep(0.22, 0.0, along) * step(0.0, along) * smoothstep(0.008, 0.0, abs(perp));
		float vis = smoothstep(0.0, 0.04, ph) * smoothstep(0.60, 0.40, ph);
		col += vec3(0.85, 0.95, 1.0) * trail * vis * 0.9;
		col += vec3(1.0) * smoothstep(0.012, 0.0, length(d)) * vis;
	}
	COLOR = vec4(col, 1.0);
}
"

const _NEON_SHADER := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	vec3 col = mix(vec3(0.06, 0.03, 0.16), vec3(0.18, 0.05, 0.24), uv.y * 0.6);
	// moon + halo, top-left
	vec2 mp = vec2(0.18 * aspect, 0.12);
	col += vec3(0.60, 0.45, 0.70) * smoothstep(0.22, 0.0, distance(a, mp)) * 0.25;
	col = mix(col, vec3(0.96, 0.92, 0.82), aafill(distance(a, mp) - 0.055));
	// stars
	for (int i = 0; i < 14; i++) {
		float fi = float(i);
		col += vec3(0.90) * aafill(distance(a, vec2(hash11(fi * 1.1) * aspect, hash11(fi * 2.2) * 0.40)) - 0.0016) * 0.8;
	}
	// an airplane crossing the night sky every once in a while, with a vapour trail
	// that fades out behind it. Re-rolls direction, altitude each pass; off-screen
	// gaps between passes come for free from the cross-screen travel.
	float plnPeriod = 13.0;
	float plnPh = fract(t / plnPeriod);
	float plnSeed = floor(t / plnPeriod);
	float pdir = (hash11(plnSeed * 1.7) < 0.5) ? 1.0 : -1.0;
	float py = 0.10 + 0.16 * hash11(plnSeed * 2.3);
	float px = mix(-0.2, aspect + 0.2, (pdir > 0.0) ? plnPh : (1.0 - plnPh));
	vec2 pq = a - vec2(px, py + 0.008 * sin(t * 0.6));
	pq.x *= pdir;                                            // face travel direction
	// vapour trail streams from the TAIL only (behind the plane), tapering as it fades
	float behind = -pq.x - 0.027;                            // distance behind the tail
	col += vec3(0.85, 0.90, 1.0) * smoothstep(0.34, 0.0, behind) * step(0.0, behind) * smoothstep(0.0035 + behind * 0.02, 0.0, abs(pq.y)) * 0.40;
	float pbody = ellip(pq, vec2(0.0, 0.0), vec2(0.032, 0.0065), 0.0);
	float pwing = sdBox(pq - vec2(-0.002, 0.0), vec2(0.010, 0.026));
	float ptail = sdBox(pq - vec2(-0.027, 0.0), vec2(0.006, 0.013));
	float plane = min(pbody, min(pwing, ptail));
	float pa2 = aafill(plane);
	col = mix(col, vec3(0.82, 0.86, 0.96), pa2);
	col = mix(col, vec3(0.45, 0.55, 0.78), aaline(plane, 0.0015) * pa2);
	float nav = 0.5 + 0.5 * sin(t * 8.0);
	col += vec3(1.0, 0.25, 0.25) * aafill(distance(pq, vec2(0.0,  0.026)) - 0.004) * nav;
	col += vec3(0.30, 1.0, 0.35) * aafill(distance(pq, vec2(0.0, -0.026)) - 0.004) * (1.0 - nav);
	// skyline silhouette — towers stand on the BOTTOM edge of the screen (no reflection)
	float horizon = 1.0;
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		float bx = fi / 10.0 * aspect;
		float bw = aspect / 10.0 * 0.94;
		float edge = abs(fi / 9.0 - 0.5) * 2.0;
		float bh = 0.30 + 0.42 * pow(edge, 1.4) + 0.05 * hash11(fi * 3.3);
		float top = horizon - bh;
		if (a.x > bx && a.x < bx + bw && uv.y > top && uv.y < horizon) {
			vec3 bcol = mix(vec3(0.08, 0.07, 0.18), vec3(0.14, 0.09, 0.26), hash11(fi));
			vec2 cell = floor(vec2((a.x - bx) * 26.0, (uv.y - top) * 40.0));
			float lit = step(0.45, hash21(cell + fi));
			// windows wink: each lit window blinks off every once in a while on its
			// own slow random schedule (floor() steps an irregular on/off sequence)
			lit *= step(0.22, fract(hash21(cell + fi) * 7.31 + floor(t * (0.18 + 0.5 * hash21(cell + fi * 1.9))) * 0.61803));
			vec2 w = fract(vec2((a.x - bx) * 26.0, (uv.y - top) * 40.0)) - 0.5;
			vec3 wc = mix(vec3(0.95, 0.85, 0.40), vec3(0.30, 0.85, 0.98), hash11(fi * 7.0));
			col = mix(bcol, wc, aafill(max(abs(w.x) - 0.30, abs(w.y) - 0.32)) * lit);
			col = mix(col, mix(vec3(1.0, 0.20, 0.60), vec3(0.20, 0.90, 1.0), hash11(fi * 2.1)), aaline(uv.y - top, 0.004));
		}
	}
	// neon billboard on a rooftop in the bottom band
	vec2 np = vec2(0.80 * aspect, 0.73);
	col = mix(col, vec3(0.05, 0.02, 0.10), aafill(sdBox(a - np, vec2(0.05, 0.04))));
	col = mix(col, vec3(1.0, 0.25, 0.60), aaline(sdBox(a - np, vec2(0.05, 0.04)), 0.004));
	col = mix(col, vec3(0.20, 0.95, 1.0), aafill(sdStar5((a - np) * rot(0.2), 0.022, 0.5)));
	COLOR = vec4(col, 1.0);
}
"
# Neon static plate: gradient + moon + halo + city skyline (windows frozen lit) +
# the rooftop billboard. The starfield is particles; the airplane animates.
const _NEON_STATIC := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(0.06, 0.03, 0.16), vec3(0.18, 0.05, 0.24), uv.y * 0.6);
	vec2 mp = vec2(0.18 * aspect, 0.12);
	col += vec3(0.60, 0.45, 0.70) * smoothstep(0.22, 0.0, distance(a, mp)) * 0.25;
	col = mix(col, vec3(0.96, 0.92, 0.82), aafill(distance(a, mp) - 0.055));
	float horizon = 1.0;
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		float bx = fi / 10.0 * aspect;
		float bw = aspect / 10.0 * 0.94;
		float edge = abs(fi / 9.0 - 0.5) * 2.0;
		float bh = 0.30 + 0.42 * pow(edge, 1.4) + 0.05 * hash11(fi * 3.3);
		float top = horizon - bh;
		if (a.x > bx && a.x < bx + bw && uv.y > top && uv.y < horizon) {
			vec3 bcol = mix(vec3(0.08, 0.07, 0.18), vec3(0.14, 0.09, 0.26), hash11(fi));
			vec2 cell = floor(vec2((a.x - bx) * 26.0, (uv.y - top) * 40.0));
			float lit = step(0.45, hash21(cell + fi));
			lit *= step(0.22, fract(hash21(cell + fi) * 7.31));
			vec2 w = fract(vec2((a.x - bx) * 26.0, (uv.y - top) * 40.0)) - 0.5;
			vec3 wc = mix(vec3(0.95, 0.85, 0.40), vec3(0.30, 0.85, 0.98), hash11(fi * 7.0));
			col = mix(bcol, wc, aafill(max(abs(w.x) - 0.30, abs(w.y) - 0.32)) * lit);
			col = mix(col, mix(vec3(1.0, 0.20, 0.60), vec3(0.20, 0.90, 1.0), hash11(fi * 2.1)), aaline(uv.y - top, 0.004));
		}
	}
	vec2 np = vec2(0.80 * aspect, 0.73);
	col = mix(col, vec3(0.05, 0.02, 0.10), aafill(sdBox(a - np, vec2(0.05, 0.04))));
	col = mix(col, vec3(1.0, 0.25, 0.60), aaline(sdBox(a - np, vec2(0.05, 0.04)), 0.004));
	col = mix(col, vec3(0.20, 0.95, 1.0), aafill(sdStar5((a - np) * rot(0.2), 0.022, 0.5)));
	COLOR = vec4(col, 1.0);
}
"
# Neon dynamic: sample plate, draw the crossing airplane + vapour trail + blinking
# nav lights, bounded to a thin band so it's nearly free elsewhere.
const _NEON_DYN := _HEAD + "uniform sampler2D static_tex : filter_linear;
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	vec3 col = texture(static_tex, uv).rgb;
	float plnPeriod = 13.0;
	float plnPh = fract(t / plnPeriod);
	float plnSeed = floor(t / plnPeriod);
	float pdir = (hash11(plnSeed * 1.7) < 0.5) ? 1.0 : -1.0;
	float py = 0.10 + 0.16 * hash11(plnSeed * 2.3);
	float px = mix(-0.2, aspect + 0.2, (pdir > 0.0) ? plnPh : (1.0 - plnPh));
	vec2 pq = a - vec2(px, py + 0.008 * sin(t * 0.6));
	pq.x *= pdir;
	if (abs(pq.y) < 0.075) {
		vec3 col0 = col;
		float behind = -pq.x - 0.027;
		col += vec3(0.85, 0.90, 1.0) * smoothstep(0.34, 0.0, behind) * step(0.0, behind) * smoothstep(0.0035 + behind * 0.02, 0.0, abs(pq.y)) * 0.40;
		float pbody = ellip(pq, vec2(0.0, 0.0), vec2(0.032, 0.0065), 0.0);
		float pwing = sdBox(pq - vec2(-0.002, 0.0), vec2(0.010, 0.026));
		float ptail = sdBox(pq - vec2(-0.027, 0.0), vec2(0.006, 0.013));
		float plane = min(pbody, min(pwing, ptail));
		float pa2 = aafill(plane);
		col = mix(col, vec3(0.82, 0.86, 0.96), pa2);
		col = mix(col, vec3(0.45, 0.55, 0.78), aaline(plane, 0.0015) * pa2);
		float nav = 0.5 + 0.5 * sin(t * 8.0);
		col += vec3(1.0, 0.25, 0.25) * aafill(distance(pq, vec2(0.0, 0.026)) - 0.004) * nav;
		col += vec3(0.30, 1.0, 0.35) * aafill(distance(pq, vec2(0.0, -0.026)) - 0.004) * (1.0 - nav);
		col = mix(col0, col, win1(pq.y, -0.07, 0.07, 0.015));
	}
	COLOR = vec4(col, 1.0);
}
"

# ---- HIGH-VALUE: detailed animated scenes ----

const _CLOUDS_SHADER := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(0.30, 0.56, 0.86), vec3(0.78, 0.88, 0.98), smoothstep(0.0, 1.0, uv.y));
	// sun with slowly turning rays, top-right
	vec2 sp = vec2(0.80 * aspect, 0.12);
	float sang = atan(a.y - sp.y, a.x - sp.x);
	col += vec3(1.0, 0.95, 0.70) * smoothstep(0.40, 0.0, distance(a, sp)) * (0.30 + 0.12 * max(0.0, sin(sang * 14.0 + TIME * 0.5)));
	col = mix(col, vec3(1.0, 0.97, 0.75), aafill(distance(a, sp) - 0.060));
	// layered drifting clouds
	for (int L = 0; L < 4; L++) {
		float d = float(L);
		vec2 cq = a * (1.5 + d * 0.7) + vec2(TIME * (0.02 + d * 0.012), -d * 2.0);
		vec2 warp = vec2(fbm(cq + vec2(TIME * 0.02, 0.0)), fbm(cq + vec2(3.0, 1.0)));
		float c = fbm(cq + warp * 1.3);
		float clouds = smoothstep(0.55, 0.78, c);
		col = mix(col, mix(vec3(0.82, 0.86, 0.95), vec3(1.0), clouds), clouds * (0.85 - d * 0.12));
	}
	// defined billowy clouds drifting across the top, randomly shaped
	col = placeCloud(col, a, vec2(fract(0.10 + TIME * 0.012) * (aspect + 0.5) - 0.25, 0.20), 0.20, 5.0, vec3(1.0), vec3(0.80, 0.85, 0.95));
	col = placeCloud(col, a, vec2(fract(0.52 + TIME * 0.008) * (aspect + 0.5) - 0.25, 0.12), 0.15, 23.0, vec3(1.0), vec3(0.82, 0.87, 0.96));
	col = placeCloud(col, a, vec2(fract(0.80 + TIME * 0.010) * (aspect + 0.5) - 0.25, 0.27), 0.17, 41.0, vec3(1.0), vec3(0.80, 0.85, 0.95));
	// hot-air balloon drifting across the top
	float bx = fract(TIME * 0.02 + 0.1) * (aspect + 0.2) - 0.1;
	vec2 bq = a - vec2(bx, 0.16 + 0.01 * sin(TIME * 0.6));
	float balloon = aafill(length(bq * vec2(1.0, 1.15)) - 0.06);
	col = mix(col, vec3(0.95, 0.30, 0.30), balloon * step(0.5, fract((bq.x) * 18.0 + 0.0)));
	col = mix(col, vec3(0.98, 0.85, 0.25), balloon * step(fract((bq.x) * 18.0), 0.5));
	col = mix(col, vec3(0.45, 0.30, 0.18), aafill(sdBox(bq - vec2(0.0, 0.075), vec2(0.016, 0.012))));
	col = mix(col, vec3(0.30, 0.22, 0.14), aaline(abs(bq.x) - 0.04 * (bq.y - 0.06), 0.002) * step(0.0, bq.y) * step(bq.y, 0.065));
	// a flock gliding past, wings flapping: random species (repeats fine), speeds,
	// sizes and an off-screen gap before each loops back in from the left
	for (int i = 0; i < 5; i++) col = flyBird(col, a, TIME, float(i) * 5.7 + 3.0, 0.26, 0.14, 0.082, 0.32);
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	col *= mix(0.85, 1.0, smoothstep(1.2, 0.2, length(p)));
	COLOR = vec4(col, 1.0);
}
"
# Clouds static plate: sky + sun + the 4 soft layered fbm cloud sheets, FROZEN
# (their slow drift is removed). Baking these once removes ~12 fbm calls/pixel/frame
# — the dominant cost. The defined clouds, balloon and birds still drift in the dyn.
const _CLOUDS_STATIC := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(0.30, 0.56, 0.86), vec3(0.78, 0.88, 0.98), smoothstep(0.0, 1.0, uv.y));
	vec2 sp = vec2(0.80 * aspect, 0.12);
	float sang = atan(a.y - sp.y, a.x - sp.x);
	col += vec3(1.0, 0.95, 0.70) * smoothstep(0.40, 0.0, distance(a, sp)) * (0.30 + 0.12 * max(0.0, sin(sang * 14.0)));
	col = mix(col, vec3(1.0, 0.97, 0.75), aafill(distance(a, sp) - 0.060));
	for (int L = 0; L < 4; L++) {
		float d = float(L);
		vec2 cq = a * (1.5 + d * 0.7) + vec2(0.0, -d * 2.0);
		vec2 warp = vec2(fbm(cq), fbm(cq + vec2(3.0, 1.0)));
		float c = fbm(cq + warp * 1.3);
		float clouds = smoothstep(0.55, 0.78, c);
		col = mix(col, mix(vec3(0.82, 0.86, 0.95), vec3(1.0), clouds), clouds * (0.85 - d * 0.12));
	}
	COLOR = vec4(col, 1.0);
}
"
# Clouds dynamic: sample plate, draw the defined drifting clouds, the hot-air
# balloon and the flock, then the vignette (applied to the whole composite, as in
# the original).
const _CLOUDS_DYN := _HEAD + "uniform sampler2D static_tex : filter_linear;
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = texture(static_tex, uv).rgb;
	col = placeCloud(col, a, vec2(fract(0.10 + TIME * 0.012) * (aspect + 0.5) - 0.25, 0.20), 0.20, 5.0, vec3(1.0), vec3(0.80, 0.85, 0.95));
	col = placeCloud(col, a, vec2(fract(0.52 + TIME * 0.008) * (aspect + 0.5) - 0.25, 0.12), 0.15, 23.0, vec3(1.0), vec3(0.82, 0.87, 0.96));
	col = placeCloud(col, a, vec2(fract(0.80 + TIME * 0.010) * (aspect + 0.5) - 0.25, 0.27), 0.17, 41.0, vec3(1.0), vec3(0.80, 0.85, 0.95));
	float bx = fract(TIME * 0.02 + 0.1) * (aspect + 0.2) - 0.1;
	vec2 bq = a - vec2(bx, 0.16 + 0.01 * sin(TIME * 0.6));
	float balloon = aafill(length(bq * vec2(1.0, 1.15)) - 0.06);
	col = mix(col, vec3(0.95, 0.30, 0.30), balloon * step(0.5, fract((bq.x) * 18.0 + 0.0)));
	col = mix(col, vec3(0.98, 0.85, 0.25), balloon * step(fract((bq.x) * 18.0), 0.5));
	col = mix(col, vec3(0.45, 0.30, 0.18), aafill(sdBox(bq - vec2(0.0, 0.075), vec2(0.016, 0.012))));
	col = mix(col, vec3(0.30, 0.22, 0.14), aaline(abs(bq.x) - 0.04 * (bq.y - 0.06), 0.002) * step(0.0, bq.y) * step(bq.y, 0.065));
	for (int i = 0; i < 5; i++) col = flyBird(col, a, TIME, float(i) * 5.7 + 3.0, 0.26, 0.14, 0.082, 0.32);
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	col *= mix(0.85, 1.0, smoothstep(1.2, 0.2, length(p)));
	COLOR = vec4(col, 1.0);
}
"

const _AURORA_SHADER := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	// brighter, glowier night sky with a soft high-altitude airglow
	vec3 col = mix(vec3(0.03, 0.05, 0.14), vec3(0.05, 0.08, 0.20), uv.y);
	col += vec3(0.06, 0.12, 0.18) * smoothstep(0.85, 0.0, uv.y) * 0.6;
	// twinkling stars, up high
	for (int i = 0; i < 40; i++) {
		float fi = float(i);
		vec2 sp = vec2(hash11(fi * 1.7) * aspect, hash11(fi * 2.9) * 0.55);
		float tw = 0.4 + 0.6 * (0.5 + 0.5 * sin(t * (1.5 + 2.0 * hash11(fi * 4.1)) + fi * 3.0));
		col += vec3(0.90, 0.95, 1.0) * aafill(distance(a, sp) - 0.0016) * (0.4 + 0.6 * hash11(fi * 5.0)) * tw;
	}
	// periodic shooting stars on random paths (replaces the old fixed white streak)
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float period = 5.0 + 3.0 * hash11(fi * 2.1);
		float phase = (t + fi * 9.0) / period;
		float seed = floor(phase);
		float ph = fract(phase);
		vec2 sp = vec2(hash11(seed + fi * 1.3) * aspect, 0.03 + 0.22 * hash11(seed + fi * 2.7));
		float ang = 3.14159 * (0.16 + 0.68 * hash11(seed + fi * 3.9));
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 head = sp + dir * ph * (aspect * 1.2);
		vec2 d = a - head;
		float along = dot(d, -dir);
		float perp = dot(d, vec2(-dir.y, dir.x));
		float trail = smoothstep(0.22, 0.0, along) * step(0.0, along) * smoothstep(0.008, 0.0, abs(perp));
		float vis = smoothstep(0.0, 0.04, ph) * smoothstep(0.60, 0.40, ph);
		col += vec3(0.85, 0.95, 1.0) * trail * vis * 0.9;
		col += vec3(1.0) * smoothstep(0.012, 0.0, length(d)) * vis;
	}
	// flowing, luminous aurora curtains (brighter + more colourful, with light rays)
	for (int L = 0; L < 5; L++) {
		float d = float(L);
		float wave = 0.20 + d * 0.06 + 0.09 * sin(a.x * 3.0 + t * 0.6 + d * 1.3) + 0.04 * sin(a.x * 7.0 - t * 0.4);
		float band = smoothstep(0.12, 0.0, abs(uv.y - wave));
		float curtain = fbm(vec2(a.x * 4.0 - t * 0.2, uv.y * 3.0 + d));
		vec3 ac = mix(vec3(0.15, 1.0, 0.55), vec3(0.35, 0.60, 1.0), d / 4.0);
		if (L == 4) ac = vec3(0.85, 0.35, 0.95);
		col += ac * band * (0.5 + 0.6 * curtain) * smoothstep(wave, wave - 0.26, uv.y) * 0.95;
		col += ac * band * smoothstep(0.60, 0.95, fbm(vec2(a.x * 16.0, t * 0.1 + d))) * 0.5 * smoothstep(wave, wave - 0.30, uv.y);
	}
	// ===== tall, detailed snow-capped mountain ranges (back -> front) =====
	for (int L = 0; L < 3; L++) {
		float fL = float(L);
		float f = 1.1 + fL * 0.7;
		float ph = fL * 3.7;
		float crest = 0.52 + fL * 0.09;
		float amp = 0.17 - fL * 0.015;
		float peaks = abs(fract(uv.x * f + ph) - 0.5) * 2.0;
		peaks = 0.55 * peaks + 0.45 * abs(fract(uv.x * f * 2.1 + ph * 1.3) - 0.5) * 2.0;
		peaks += 0.10 * (fbm(vec2(uv.x * 12.0, fL)) - 0.5);          // jagged roughness
		float top = crest - amp * peaks;
		float mMask = aafill(top - uv.y);                           // body below the ridge
		vec3 mcol = mix(vec3(0.17, 0.21, 0.35), vec3(0.02, 0.03, 0.09), fL * 0.5);
		mcol *= 0.8 + 0.4 * fbm(vec2(uv.x * 10.0 + fL, uv.y * 10.0)); // rocky mottle + facets
		// snow blankets the slopes well below the ridge (not just a thin crest line),
		// with a soft uneven snowline + light texture so it still reads as deep snow
		float snowline = top + 0.20 + 0.06 * fbm(vec2(uv.x * 8.0, fL));
		float snow = smoothstep(snowline, top + 0.004, uv.y);
		snow *= 0.86 + 0.14 * fbm(vec2(uv.x * 26.0, fL));
		mcol = mix(mcol, vec3(0.88, 0.93, 1.0), snow);
		col = mix(col, mcol, mMask);
	}
	// small conifers dotted across the snowy slopes of the front range
	col = placeTree(col, a, vec2(0.13 * aspect, 0.70), 0.045, 0, 3.0, 0.55);
	col = placeTree(col, a, vec2(0.25 * aspect, 0.73), 0.040, 0, 8.0, 0.55);
	col = placeTree(col, a, vec2(0.37 * aspect, 0.71), 0.048, 0, 14.0, 0.55);
	col = placeTree(col, a, vec2(0.50 * aspect, 0.735), 0.040, 0, 19.0, 0.55);
	col = placeTree(col, a, vec2(0.63 * aspect, 0.715), 0.046, 0, 23.0, 0.55);
	col = placeTree(col, a, vec2(0.76 * aspect, 0.74), 0.040, 0, 27.0, 0.55);
	col = placeTree(col, a, vec2(0.88 * aspect, 0.72), 0.046, 0, 31.0, 0.55);
	COLOR = vec4(col, 1.0);
}
"
# Aurora static plate: night sky + airglow + snow-capped mountain ranges + conifers
# (all static). The starfield, shooting stars and flowing aurora curtains animate.
const _AURORA_STATIC := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(0.03, 0.05, 0.14), vec3(0.05, 0.08, 0.20), uv.y);
	col += vec3(0.06, 0.12, 0.18) * smoothstep(0.85, 0.0, uv.y) * 0.6;
	for (int L = 0; L < 3; L++) {
		float fL = float(L);
		float f = 1.1 + fL * 0.7;
		float ph = fL * 3.7;
		float crest = 0.52 + fL * 0.09;
		float amp = 0.17 - fL * 0.015;
		float peaks = abs(fract(uv.x * f + ph) - 0.5) * 2.0;
		peaks = 0.55 * peaks + 0.45 * abs(fract(uv.x * f * 2.1 + ph * 1.3) - 0.5) * 2.0;
		peaks += 0.10 * (fbm(vec2(uv.x * 12.0, fL)) - 0.5);
		float top = crest - amp * peaks;
		float mMask = aafill(top - uv.y);
		vec3 mcol = mix(vec3(0.17, 0.21, 0.35), vec3(0.02, 0.03, 0.09), fL * 0.5);
		mcol *= 0.8 + 0.4 * fbm(vec2(uv.x * 10.0 + fL, uv.y * 10.0));
		float snowline = top + 0.20 + 0.06 * fbm(vec2(uv.x * 8.0, fL));
		float snow = smoothstep(snowline, top + 0.004, uv.y);
		snow *= 0.86 + 0.14 * fbm(vec2(uv.x * 26.0, fL));
		mcol = mix(mcol, vec3(0.88, 0.93, 1.0), snow);
		col = mix(col, mcol, mMask);
	}
	col = placeTree(col, a, vec2(0.13 * aspect, 0.70), 0.045, 0, 3.0, 0.55);
	col = placeTree(col, a, vec2(0.25 * aspect, 0.73), 0.040, 0, 8.0, 0.55);
	col = placeTree(col, a, vec2(0.37 * aspect, 0.71), 0.048, 0, 14.0, 0.55);
	col = placeTree(col, a, vec2(0.50 * aspect, 0.735), 0.040, 0, 19.0, 0.55);
	col = placeTree(col, a, vec2(0.63 * aspect, 0.715), 0.046, 0, 23.0, 0.55);
	col = placeTree(col, a, vec2(0.76 * aspect, 0.74), 0.040, 0, 27.0, 0.55);
	col = placeTree(col, a, vec2(0.88 * aspect, 0.72), 0.046, 0, 31.0, 0.55);
	COLOR = vec4(col, 1.0);
}
"
# Aurora dynamic: sample plate, draw the flowing luminous aurora curtains (clipped
# to the sky above the ridgeline so they sit behind the mountains) + shooting stars.
const _AURORA_DYN := _HEAD + "uniform sampler2D static_tex : filter_linear;
// cheap 2-octave noise for the soft aurora curtains (the full 4-octave fbm was the
// theme's lag — ~10 fbm/pixel across the upper half every frame).
float anoise(vec2 p) { return 0.62 * gnoise(p) + 0.38 * gnoise(p * 2.3 + 5.0); }
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	vec3 col = texture(static_tex, uv).rgb;
	if (uv.y < 0.52) {
		for (int L = 0; L < 5; L++) {
			float d = float(L);
			float wave = 0.20 + d * 0.06 + 0.09 * sin(a.x * 3.0 + t * 0.6 + d * 1.3) + 0.04 * sin(a.x * 7.0 - t * 0.4);
			float band = smoothstep(0.12, 0.0, abs(uv.y - wave));
			if (band < 0.004) continue;                     // skip the noise outside this curtain's band
			vec3 ac = mix(vec3(0.15, 1.0, 0.55), vec3(0.35, 0.60, 1.0), d / 4.0);
			if (L == 4) ac = vec3(0.85, 0.35, 0.95);
			float curtain = anoise(vec2(a.x * 4.0 - t * 0.2, uv.y * 3.0 + d));
			col += ac * band * (0.5 + 0.6 * curtain) * smoothstep(wave, wave - 0.26, uv.y) * 0.95;
			float shimmer = smoothstep(0.60, 0.95, gnoise(vec2(a.x * 16.0, t * 0.1 + d)));
			col += ac * band * shimmer * 0.5 * smoothstep(wave, wave - 0.30, uv.y);
		}
	}
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float period = 5.0 + 3.0 * hash11(fi * 2.1);
		float phase = (t + fi * 9.0) / period;
		float seed = floor(phase);
		float ph = fract(phase);
		vec2 sp = vec2(hash11(seed + fi * 1.3) * aspect, 0.03 + 0.22 * hash11(seed + fi * 2.7));
		float ang = 3.14159 * (0.16 + 0.68 * hash11(seed + fi * 3.9));
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 head = sp + dir * ph * (aspect * 1.2);
		vec2 d = a - head;
		float along = dot(d, -dir);
		float perp = dot(d, vec2(-dir.y, dir.x));
		float trail = smoothstep(0.22, 0.0, along) * step(0.0, along) * smoothstep(0.008, 0.0, abs(perp));
		float vis = smoothstep(0.0, 0.04, ph) * smoothstep(0.60, 0.40, ph);
		col += vec3(0.85, 0.95, 1.0) * trail * vis * 0.9;
		col += vec3(1.0) * smoothstep(0.012, 0.0, length(d)) * vis;
	}
	COLOR = vec4(col, 1.0);
}
"

const _FAIRIES_SHADER := _HEAD + "
// A little winged fairy sprite: glowing body + head and two pairs of translucent
// iridescent wings that flap. q is fairy-relative (head up = -y); tint colours the
// wings. Kept small — reads as a sprite, with an additive aura added by placeFairy.
vec4 fairyFig(vec2 q, float flap, vec3 tint) {
	vec4 acc = vec4(0.0);
	float fl = 0.18 + 0.18 * flap;
	for (int si = 0; si < 2; si++) {
		float s = (si == 0) ? -1.0 : 1.0;
		vec2 sh = vec2(s * 0.04, -0.05);
		float uw = ellip(q, sh + vec2(s * 0.20, -0.10), vec2(0.20, 0.11), s * fl);
		acc = _ov(acc, mix(tint, vec3(1.0), 0.55), aafill(uw) * 0.45);
		acc = _ov(acc, vec3(1.0), aaline(uw, 0.006) * 0.4);
		float lw = ellip(q, sh + vec2(s * 0.15, 0.08), vec2(0.13, 0.085), -s * fl * 0.5);
		acc = _ov(acc, mix(tint, vec3(0.75, 0.9, 1.0), 0.5), aafill(lw) * 0.45);
	}
	acc = _ov(acc, vec3(1.0, 0.96, 0.88), aafill(ellip(q, vec2(0.0, 0.02), vec2(0.055, 0.15), 0.0)));
	acc = _ov(acc, vec3(1.0, 0.92, 0.82), aafill(sdCircle(q - vec2(0.0, -0.19), 0.065)));
	acc = _ov(acc, vec3(1.0, 0.85, 0.6), aafill(sdCircle(q - vec2(0.0, -0.20), 0.090)) * 0.3);
	return acc;
}
vec3 placeFairy(vec3 col, vec2 a, vec2 c, float s, float flap, vec3 tint) {
	vec2 q = (a - c) / s;
	if (abs(q.x) > 0.74 || abs(q.y) > 0.64) return col;
	float win = win1(q.x, -0.68, 0.68, 0.10) * win1(q.y, -0.58, 0.58, 0.10);
	col += tint * smoothstep(0.55, 0.0, length(q)) * 0.30 * win;
	vec4 f = fairyFig(q, flap, tint);
	return mix(col, f.rgb, f.a * win);
}
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(0.18, 0.05, 0.22), vec3(0.30, 0.08, 0.32), uv.y);
	// magical bokeh
	col += vec3(0.50, 0.20, 0.50) * smoothstep(0.55, 0.92, fbm(a * 3.0 + vec2(0.0, TIME * 0.05))) * 0.28;
	float t = TIME;
	// a big glowing GREEN star presiding over the top-left, slowly turning + twinkling
	vec2 gsp = vec2(0.16 * aspect, 0.14);
	vec2 gsq = a - gsp;
	float gtw = 0.7 + 0.3 * sin(t * 2.4);
	float gstar = sdStar5(gsq * rot(t * 0.25), 0.052, 0.42);
	col += vec3(0.20, 1.0, 0.45) * smoothstep(0.17, 0.0, length(gsq)) * 0.45 * gtw;        // soft green halo
	col += vec3(0.45, 1.0, 0.55) * smoothstep(0.025, 0.0, gstar) * 0.7;                     // inner bloom
	col = mix(col, vec3(0.78, 1.0, 0.82), aafill(gstar));                                   // bright star body
	col = mix(col, vec3(0.16, 0.82, 0.34), aaline(gstar, 0.0035));                          // crisp green edge
	col += vec3(0.40, 0.30, 0.10) * aafill(gstar) * smoothstep(0.0, 0.05, gsq.y);           // faint inner facet shading
	col += vec3(0.5, 1.0, 0.6) * (aaline(gsq.x, 0.0016) * (1.0 - smoothstep(0.055, 0.075, abs(gsq.y))) + aaline(gsq.y, 0.0016) * (1.0 - smoothstep(0.055, 0.075, abs(gsq.x)))) * gtw * 0.55; // sparkle rays
	// periodic magical shooting stars on random paths, blue or flame-coloured; each
	// re-rolls its start point, angle and colour every cycle so they never repeat
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float period = 3.0 + 2.5 * hash11(fi * 2.1);
		float phase = (t + fi * 7.3) / period;
		float seed = floor(phase);
		float ph = fract(phase);
		vec2 sp = vec2(hash11(seed + fi * 1.3) * aspect, 0.04 + 0.30 * hash11(seed + fi * 2.7));
		float ang = 3.14159 * (0.18 + 0.64 * hash11(seed + fi * 3.9));
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 head = sp + dir * ph * (aspect * 1.25);
		vec2 d = a - head;
		float along = dot(d, -dir);
		float perp = dot(d, vec2(-dir.y, dir.x));
		float trail = smoothstep(0.20, 0.0, along) * step(0.0, along) * smoothstep(0.009, 0.0, abs(perp));
		float vis = smoothstep(0.0, 0.04, ph) * smoothstep(0.62, 0.40, ph);
		vec3 sc = (hash11(seed + fi * 5.1) < 0.5) ? vec3(0.40, 0.70, 1.0) : vec3(1.0, 0.52, 0.18);
		col += sc * trail * vis * 0.9;
		col += sc * smoothstep(0.013, 0.0, length(d)) * vis;
	}
	// floating sparkle dust + glowing fireflies drifting through the glade
	for (int i = 0; i < 30; i++) {
		float fi = float(i);
		vec2 dp = vec2(fract(hash11(fi * 1.3) + t * 0.01 * (0.5 + hash11(fi))) * aspect,
					   fract(hash11(fi * 2.7) - t * 0.02 * (0.5 + hash11(fi * 3.0))));
		float tw = 0.5 + 0.5 * sin(t * 3.0 + fi * 2.0);
		col += vec3(1.0, 0.70, 0.90) * aafill(distance(a, dp) - 0.0035) * tw;
	}
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float yband = mix(0.16, 0.80, step(2.5, fi));
		vec2 fp = vec2((0.15 + 0.7 * hash11(fi * 5.0)) * aspect + 0.12 * sin(t * 0.5 + fi * 2.0),
					   yband + 0.06 * cos(t * 0.4 + fi));
		col += vec3(1.0, 0.85, 0.55) * smoothstep(0.05, 0.0, distance(a, fp)) * (0.5 + 0.5 * sin(t * 5.0 + fi * 3.0));
		col += vec3(0.95, 0.90, 0.50) * aafill(distance(a, fp) - 0.0035);
	}
	// real winged fairies fluttering above the glade (biased to the top/side bands)
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float yband = mix(0.16, 0.36, step(1.5, fi));
		vec2 fp = vec2((0.18 + 0.64 * hash11(fi * 4.3)) * aspect + 0.14 * sin(t * 0.4 + fi * 2.2),
					   yband + 0.05 * cos(t * 0.55 + fi * 1.7));
		float flap = sin(t * 9.0 + fi * 3.0);
		vec3 tint = vec3(0.75, 0.85, 1.0);
		if (int(mod(fi, 3.0)) == 1) tint = vec3(1.0, 0.70, 0.90);
		if (int(mod(fi, 3.0)) == 2) tint = vec3(0.70, 1.0, 0.80);
		col = placeFairy(col, a, fp, 0.075, flap, tint);
	}
	// enchanted mossy ground band with glowing mushrooms in the grass
	float gline = 0.875 + 0.012 * sin(uv.x * 6.0) + 0.006 * sin(uv.x * 17.0);
	float isG = aafill(gline - uv.y);
	vec3 soil = mix(vec3(0.16, 0.10, 0.20), vec3(0.07, 0.04, 0.11), smoothstep(gline, 1.0, uv.y));
	soil = mix(soil, vec3(0.12, 0.30, 0.20), smoothstep(gline + 0.04, gline, uv.y));
	col = mix(col, soil, isG);
	for (int i = 0; i < 14; i++) {
		float fi = float(i);
		col = placeGrass(col, a, vec2((0.03 + 0.072 * fi) * aspect, gline + 0.012 + 0.008 * hash11(fi * 3.3)), 0.05, fi * 1.7 + 5.0);
	}
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float mx = (0.10 + 0.16 * fi) * aspect;
		float my = gline + 0.012 + 0.01 * hash11(fi * 3.1);
		col = placeGrass(col, a, vec2(mx - 0.02, my), 0.05, fi * 2.1 + 3.0);
		col = placeMushroom(col, a, vec2(mx, my), 0.05, fi * 1.7, 1.0, vec3(0.40, 0.85, 0.80));
		col = placeGrass(col, a, vec2(mx + 0.025, my), 0.05, fi * 3.3 + 7.0);
	}
	COLOR = vec4(col, 1.0);
}
"

# --- Fairies, split into a baked static plate + a cheap live props pass --------
# The static plate is everything that doesn't visibly move (sky, the very-slow
# bokeh frozen, mossy ground, grass, glowing mushrooms). It's baked to a texture
# ONCE; per-frame cost is then ~zero for these (no fbm / ground / grass SDF).
const _FAIRIES_STATIC := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(0.18, 0.05, 0.22), vec3(0.30, 0.08, 0.32), uv.y);
	col += vec3(0.50, 0.20, 0.50) * smoothstep(0.55, 0.92, fbm(a * 3.0)) * 0.28;   // bokeh, frozen
	float gline = 0.875 + 0.012 * sin(uv.x * 6.0) + 0.006 * sin(uv.x * 17.0);
	float isG = aafill(gline - uv.y);
	vec3 soil = mix(vec3(0.16, 0.10, 0.20), vec3(0.07, 0.04, 0.11), smoothstep(gline, 1.0, uv.y));
	soil = mix(soil, vec3(0.12, 0.30, 0.20), smoothstep(gline + 0.04, gline, uv.y));
	col = mix(col, soil, isG);
	for (int i = 0; i < 14; i++) {
		float fi = float(i);
		col = placeGrass(col, a, vec2((0.03 + 0.072 * fi) * aspect, gline + 0.012 + 0.008 * hash11(fi * 3.3)), 0.05, fi * 1.7 + 5.0);
	}
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float mx = (0.10 + 0.16 * fi) * aspect;
		float my = gline + 0.012 + 0.01 * hash11(fi * 3.1);
		col = placeGrass(col, a, vec2(mx - 0.02, my), 0.05, fi * 2.1 + 3.0);
		col = placeMushroom(col, a, vec2(mx, my), 0.05, fi * 1.7, 1.0, vec3(0.40, 0.85, 0.80));
		col = placeGrass(col, a, vec2(mx + 0.025, my), 0.05, fi * 3.3 + 7.0);
	}
	COLOR = vec4(col, 1.0);
}
"
# The live pass: sample the baked plate, then run ONLY the moving props on top.
# fairyFig/placeFairy are defined here (they live in the original Fairies shader,
# not in _HEAD). mix(col, base, isG) at the end restores the ground over any
# bottom sparkles, exactly as the original draw order did.
const _FAIRIES_DYN := _HEAD + "
uniform sampler2D static_tex : filter_linear;
vec4 fairyFig(vec2 q, float flap, vec3 tint) {
	vec4 acc = vec4(0.0);
	float fl = 0.18 + 0.18 * flap;
	for (int si = 0; si < 2; si++) {
		float s = (si == 0) ? -1.0 : 1.0;
		vec2 sh = vec2(s * 0.04, -0.05);
		float uw = ellip(q, sh + vec2(s * 0.20, -0.10), vec2(0.20, 0.11), s * fl);
		acc = _ov(acc, mix(tint, vec3(1.0), 0.55), aafill(uw) * 0.45);
		acc = _ov(acc, vec3(1.0), aaline(uw, 0.006) * 0.4);
		float lw = ellip(q, sh + vec2(s * 0.15, 0.08), vec2(0.13, 0.085), -s * fl * 0.5);
		acc = _ov(acc, mix(tint, vec3(0.75, 0.9, 1.0), 0.5), aafill(lw) * 0.45);
	}
	acc = _ov(acc, vec3(1.0, 0.96, 0.88), aafill(ellip(q, vec2(0.0, 0.02), vec2(0.055, 0.15), 0.0)));
	acc = _ov(acc, vec3(1.0, 0.92, 0.82), aafill(sdCircle(q - vec2(0.0, -0.19), 0.065)));
	acc = _ov(acc, vec3(1.0, 0.85, 0.6), aafill(sdCircle(q - vec2(0.0, -0.20), 0.090)) * 0.3);
	return acc;
}
vec3 placeFairy(vec3 col, vec2 a, vec2 c, float s, float flap, vec3 tint) {
	vec2 q = (a - c) / s;
	if (abs(q.x) > 0.74 || abs(q.y) > 0.64) return col;
	float win = win1(q.x, -0.68, 0.68, 0.10) * win1(q.y, -0.58, 0.58, 0.10);
	col += tint * smoothstep(0.55, 0.0, length(q)) * 0.30 * win;
	vec4 f = fairyFig(q, flap, tint);
	return mix(col, f.rgb, f.a * win);
}
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 base = texture(static_tex, uv).rgb;
	vec3 col = base;
	float t = TIME;
	vec2 gsp = vec2(0.16 * aspect, 0.14);
	vec2 gsq = a - gsp;
	float gtw = 0.7 + 0.3 * sin(t * 2.4);
	float gstar = sdStar5(gsq * rot(t * 0.25), 0.052, 0.42);
	col += vec3(0.20, 1.0, 0.45) * smoothstep(0.17, 0.0, length(gsq)) * 0.45 * gtw;
	col += vec3(0.45, 1.0, 0.55) * smoothstep(0.025, 0.0, gstar) * 0.7;
	col = mix(col, vec3(0.78, 1.0, 0.82), aafill(gstar));
	col = mix(col, vec3(0.16, 0.82, 0.34), aaline(gstar, 0.0035));
	col += vec3(0.40, 0.30, 0.10) * aafill(gstar) * smoothstep(0.0, 0.05, gsq.y);
	col += vec3(0.5, 1.0, 0.6) * (aaline(gsq.x, 0.0016) * (1.0 - smoothstep(0.055, 0.075, abs(gsq.y))) + aaline(gsq.y, 0.0016) * (1.0 - smoothstep(0.055, 0.075, abs(gsq.x)))) * gtw * 0.55;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float period = 3.0 + 2.5 * hash11(fi * 2.1);
		float phase = (t + fi * 7.3) / period;
		float seed = floor(phase);
		float ph = fract(phase);
		vec2 sp = vec2(hash11(seed + fi * 1.3) * aspect, 0.04 + 0.30 * hash11(seed + fi * 2.7));
		float ang = 3.14159 * (0.18 + 0.64 * hash11(seed + fi * 3.9));
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 head = sp + dir * ph * (aspect * 1.25);
		vec2 d = a - head;
		float along = dot(d, -dir);
		float perp = dot(d, vec2(-dir.y, dir.x));
		float trail = smoothstep(0.20, 0.0, along) * step(0.0, along) * smoothstep(0.009, 0.0, abs(perp));
		float vis = smoothstep(0.0, 0.04, ph) * smoothstep(0.62, 0.40, ph);
		vec3 sc = (hash11(seed + fi * 5.1) < 0.5) ? vec3(0.40, 0.70, 1.0) : vec3(1.0, 0.52, 0.18);
		col += sc * trail * vis * 0.9;
		col += sc * smoothstep(0.013, 0.0, length(d)) * vis;
	}
	// NOTE: the 30 sparkle-dust + 5 firefly dots used to be per-pixel loops here.
	// They were the heaviest part of this pass (35 iterations of trig + fwidth over
	// every screen pixel). They are now drawn as real CPUParticles2D nodes on top of
	// this layer (see _spawn_fairies_props), so the GPU only touches the few pixels
	// each dot covers instead of all ~2.5M every frame.
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float yband = mix(0.16, 0.36, step(1.5, fi));
		vec2 fp = vec2((0.18 + 0.64 * hash11(fi * 4.3)) * aspect + 0.14 * sin(t * 0.4 + fi * 2.2),
					   yband + 0.05 * cos(t * 0.55 + fi * 1.7));
		float flap = sin(t * 9.0 + fi * 3.0);
		vec3 tint = vec3(0.75, 0.85, 1.0);
		if (int(mod(fi, 3.0)) == 1) tint = vec3(1.0, 0.70, 0.90);
		if (int(mod(fi, 3.0)) == 2) tint = vec3(0.70, 1.0, 0.80);
		col = placeFairy(col, a, fp, 0.075, flap, tint);
	}
	float gline = 0.875 + 0.012 * sin(uv.x * 6.0) + 0.006 * sin(uv.x * 17.0);
	float isG = aafill(gline - uv.y);
	COLOR = vec4(mix(col, base, isG), 1.0);
}
"

const _DEEPSPACE_FUNCS := "
// Irregular, lumpy asteroid silhouette radius (harmonic sum) — high-poly look.
float astRadius(float ang, float seed) {
	return 1.0 + 0.16 * sin(ang * 3.0 + seed) + 0.11 * sin(ang * 5.0 + seed * 2.0)
		+ 0.07 * sin(ang * 8.0 - seed) + 0.05 * sin(ang * 13.0 + seed * 3.0);
}
// Detailed cratered asteroid in unit space, lit from upper-left, with a shadowed
// terminator, mottled rock, several rimmed craters and a crisp lit edge.
vec4 asteroidShape(vec2 q, float seed) {
	vec4 acc = vec4(0.0);
	float ang = atan(q.y, q.x);
	float d = length(q) - astRadius(ang, seed);
	float ca = aafill(d);
	vec2 L = normalize(vec2(-0.6, -0.7));
	float lit = clamp(0.5 + 0.6 * dot(normalize(q + 0.0008), L), 0.0, 1.0);
	vec3 base = mix(vec3(0.16, 0.14, 0.13), vec3(0.52, 0.49, 0.45), lit);
	base *= 0.82 + 0.32 * fbm(q * 3.0 + seed);
	acc = _ov(acc, base, ca);
	for (int k = 0; k < 5; k++) {
		float fk = float(k);
		vec2 cc = vec2(cos(fk * 2.3 + seed), sin(fk * 1.7 + seed * 1.3)) * (0.25 + 0.5 * hash11(seed + fk));
		float cr = 0.10 + 0.12 * hash11(seed + fk * 2.1);
		float cd = length(q - cc) - cr;
		acc = _ov(acc, base * 0.5, aafill(cd) * ca * 0.85);
		acc = _ov(acc, mix(base, vec3(1.0), 0.35), aaline(cd, 0.016) * ca * (0.4 + 0.4 * lit));
	}
	acc = _ov(acc, vec3(0.78, 0.74, 0.68), aaline(d, 0.02) * ca * lit * 0.5);
	return acc;
}
vec3 placeAsteroid(vec3 col, vec2 a, vec2 c, float s, float seed, float ang) {
	vec2 q = (a - c) / s * rot(ang);
	if (length(q) > 1.62) return col;
	vec4 ast = asteroidShape(q, seed);
	return mix(col, ast.rgb, ast.a * radWin(length(q), 1.48, 1.60));
}
// Sleek delta-wing fighter facing +x: fuselage, delta wings, glowing cockpit.
vec4 shipShape(vec2 q, vec3 hull) {
	vec4 acc = vec4(0.0);
	float wf = 0.03, wb = -0.052, wspan = 0.045;
	float wy = wspan * clamp((wf - q.x) / (wf - wb), 0.0, 1.0);
	float wing = max(abs(q.y) - wy, max(q.x - wf, wb - q.x));
	float fus = ellip(q, vec2(0.0, 0.0), vec2(0.072, 0.016), 0.0);
	float hull_d = min(fus, wing);
	float ha = aafill(hull_d);
	vec3 hc = mix(hull * 1.25, hull * 0.55, clamp(q.y / 0.018 * 0.5 + 0.5, 0.0, 1.0));
	acc = _ov(acc, hc, ha);
	acc = _ov(acc, hull * 0.5, aaline(q.y, 0.0015) * ha * 0.5);
	acc = _ov(acc, vec3(0.45, 0.85, 1.0), aafill(ellip(q, vec2(0.028, 0.0), vec2(0.016, 0.010), 0.0)));
	acc = _ov(acc, vec3(0.85, 0.96, 1.0), aafill(ellip(q, vec2(0.033, -0.003), vec2(0.006, 0.004), 0.0)) * 0.8);
	acc = _ov(acc, mix(hull, vec3(1.0), 0.6), aaline(hull_d, 0.0015) * ha * step(q.y, 0.0) * 0.5);
	return acc;
}
// ---- Detailed spiral galaxy: inclined disc, two sweeping arms with dust + star
// dapple, a bright bulge and a hot core. Slowly winds about its axis. ----
vec3 galaxyAt(vec3 col, vec2 a, vec2 c, float s, float seed, float tilt, vec3 tint, float t) {
	vec2 q = (a - c) * rot(tilt);
	q.y /= 0.45;                                              // inclined disc (seen at an angle)
	float r = length(q) / s;
	if (r > 1.7) return col;
	float ang = atan(q.y, q.x);
	float arm = 0.5 + 0.5 * sin(2.0 * ang + r * 7.0 - t * 0.25 + seed);   // two trailing arms
	float arms = smoothstep(0.35, 0.95, arm) * smoothstep(1.5, 0.18, r);
	arms *= 0.55 + 0.45 * fbm(q * 6.0 / s + seed);                        // clumpy dust + clusters
	float disc = smoothstep(1.5, 0.0, r);
	col += tint * arms * 0.6;
	col += tint * disc * 0.16;
	col += mix(tint, vec3(1.0, 0.96, 0.86), 0.7) * smoothstep(0.20, 0.0, r) * 0.9;   // bulge
	col += vec3(1.0) * smoothstep(0.05, 0.0, r);                                     // core
	return col;
}
// ---- Detailed ring space station: a slowly rotating habitat ring with window
// lights, four spokes to a glowing central hub, and blinking docking beacons. ----
vec4 stationShape(vec2 q, float t) {
	vec4 acc = vec4(0.0);
	float ringR = 0.62;
	float ring = abs(length(q) - ringR) - 0.075;
	float ra = aafill(ring);
	float ang = atan(q.y, q.x);
	vec3 metal = mix(vec3(0.28, 0.32, 0.40), vec3(0.62, 0.68, 0.80), 0.5 + 0.5 * sin(ang * 3.0 + 0.6));
	acc = _ov(acc, metal, ra);
	float win = step(0.55, fract(ang * 7.0 / 3.14159 + t * 0.12));               // lit windows rotate
	acc = _ov(acc, vec3(1.0, 0.9, 0.55), aafill(abs(length(q) - ringR) - 0.026) * win);
	acc = _ov(acc, vec3(0.85, 0.95, 1.0), aaline(ring, 0.008) * ra * 0.5);
	for (int k = 0; k < 4; k++) {
		float sa = float(k) * 1.5708 + t * 0.08;
		vec2 dir = vec2(cos(sa), sin(sa));
		float along = dot(q, dir);
		float perp = dot(q, vec2(-dir.y, dir.x));
		float spoke = max(abs(perp) - 0.028, max(along - ringR, 0.12 - along));
		acc = _ov(acc, vec3(0.5, 0.55, 0.65), aafill(spoke));
		acc = _ov(acc, vec3(0.7, 0.78, 0.9), aaline(abs(perp) - 0.028, 0.005) * aafill(max(along - ringR, 0.12 - along)) * 0.6);
	}
	float hub = length(q) - 0.17;
	acc = _ov(acc, vec3(0.55, 0.60, 0.72), aafill(hub));
	acc = _ov(acc, vec3(0.9, 0.95, 1.0), aaline(hub, 0.006) * 0.7);
	acc = _ov(acc, vec3(0.45, 0.85, 1.0), aafill(length(q) - 0.075));            // glowing core
	acc = _ov(acc, vec3(1.0, 0.30, 0.22), aafill(length(q - vec2(0.0, -ringR)) - 0.022) * (0.5 + 0.5 * sin(t * 4.0)));    // docking beacons
	acc = _ov(acc, vec3(0.32, 1.0, 0.42), aafill(length(q - vec2(0.0,  ringR)) - 0.022) * (0.5 + 0.5 * sin(t * 4.0 + 3.14159)));
	return acc;
}
vec3 placeStation(vec3 col, vec2 a, vec2 c, float s, float t) {
	vec2 q = (a - c) / s;
	q.y /= 0.52;                                              // viewed at a tilt
	if (length(q) > 1.42) return col;
	float win = radWin(length(q), 1.28, 1.40);
	col += vec3(0.30, 0.50, 0.80) * smoothstep(1.1, 0.0, length(q)) * 0.14 * win;
	vec4 st = stationShape(q, t);
	return mix(col, st.rgb, st.a * win);
}
"
const _DEEPSPACE_SHADER := _HEAD + _DEEPSPACE_FUNCS + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	vec3 col = mix(vec3(0.02, 0.01, 0.07), vec3(0.05, 0.02, 0.12), uv.y);
	// drifting nebula
	col += vec3(0.30, 0.15, 0.50) * smoothstep(0.55, 0.95, fbm(a * 2.2 + vec2(t * 0.01, t * 0.005))) * 0.40;
	col += vec3(0.10, 0.30, 0.60) * smoothstep(0.50, 0.95, fbm(a * 1.8 - vec2(t * 0.008, 0.0))) * 0.28;
	// twinkling stars
	for (int i = 0; i < 50; i++) {
		float fi = float(i);
		float tw = 0.5 + 0.5 * sin(t * 2.0 + fi * 3.0);
		col += vec3(1.0) * aafill(distance(a, vec2(hash11(fi * 1.3) * aspect, hash11(fi * 2.7))) - 0.0016) * (0.4 + 0.6 * tw);
	}
	// detailed spiral galaxies replace the old planets — one in each corner band
	col = galaxyAt(col, a, vec2(0.17 * aspect, 0.13), 0.10, 1.0, 0.5, vec3(0.62, 0.58, 0.98), t);   // top-left, violet-blue
	col = galaxyAt(col, a, vec2(0.81 * aspect, 0.15), 0.11, 5.0, -0.7, vec3(0.98, 0.74, 0.50), t);  // top-right, warm gold
	col = galaxyAt(col, a, vec2(0.86 * aspect, 0.82), 0.085, 9.0, 1.3, vec3(0.45, 0.92, 0.86), t);  // bottom-right, teal
	// a super-detailed ring SPACE STATION, bottom-left
	col = placeStation(col, a, vec2(0.19 * aspect, 0.83), 0.075, t);
	// high-poly cratered asteroids tumbling across the field
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float ax = fract(hash11(fi * 4.1) + t * 0.02 * (0.5 + hash11(fi))) * (aspect + 0.2) - 0.1;
		float ay = mix(0.10, 0.88, hash11(fi * 6.7));
		float s = 0.034 + 0.028 * hash11(fi * 2.1);
		col = placeAsteroid(col, a, vec2(ax, ay), s, fi * 5.7 + 1.0, t * (0.2 + 0.3 * hash11(fi * 3.3)) + fi);
	}
	// a small fleet of fighters; those flying in the negative direction fire laser
	// bolts forward every once in a while (dogfight). Kept to the top/bottom bands.
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float dir = (hash11(fi * 3.3) < 0.5) ? 1.0 : -1.0;
		float speed = 0.04 + 0.05 * hash11(fi * 1.9);
		float span = aspect + 0.5;
		float prog = mod(t * speed + hash11(fi * 7.1) * span, span) - 0.25;
		float sx = (dir > 0.0) ? prog : (span - 0.5 - prog);
		float sy = mix(0.10, 0.26, hash11(fi * 5.7)) + step(2.5, fi) * 0.60;
		sy += 0.012 * sin(t * 0.6 + fi);
		vec3 hull = vec3(0.62, 0.66, 0.74);
		if (int(mod(fi, 3.0)) == 1) hull = vec3(0.74, 0.60, 0.55);
		if (int(mod(fi, 3.0)) == 2) hull = vec3(0.55, 0.64, 0.72);
		vec2 sq = a - vec2(sx, sy);
		sq.x *= dir;
		// engine glow streams from the TAIL only (behind the ship), not along its path
		float ebehind = -sq.x - 0.05;
		col += vec3(0.30, 0.70, 1.0) * smoothstep(0.12, 0.0, ebehind) * step(0.0, ebehind) * smoothstep(0.006, 0.0, abs(sq.y)) * (0.5 + 0.4 * sin(t * 20.0 + fi));
		vec4 sh = shipShape(sq, hull);
		col = mix(col, sh.rgb, sh.a);
		col += vec3(0.5, 0.85, 1.0) * aafill(distance(sq, vec2(-0.055, 0.0)) - 0.010) * 1.1;
		if (dir < 0.0) {                                              // firing run (negative direction)
			// fire only occasionally, on a slow per-ship random cadence (not a constant stream)
			float fireRate = 0.16 + 0.18 * hash11(fi * 2.7);
			float fph = t * fireRate + hash11(fi * 6.3) * 5.0;
			float shot = floor(fph);
			float fc = fract(fph);
			if (fc < 0.32 && hash11(shot * 1.7 + fi * 3.1) < 0.55) {  // brief bolt, and not every cycle
				float boltX = sx - 0.05 - (fc / 0.32) * 0.7;          // bolt streaks forward (-x)
				vec2 bq = a - vec2(boltX, sy);
				vec3 lcol = (hash11(fi * 9.1 + shot) < 0.5) ? vec3(1.0, 0.28, 0.22) : vec3(0.40, 1.0, 0.34);
				col += lcol * smoothstep(0.016, 0.0, length(bq * vec2(0.45, 1.7))) * 1.4;
				col += lcol * smoothstep(0.045, 0.0, length(bq)) * 0.30;
			}
		}
	}
	COLOR = vec4(col, 1.0);
}
"
# Deep Space static plate: just the background gradient + nebula (the nebula's
# TIME drift is removed so it's frozen). Stars become particles; galaxies,
# station, asteroids and fighters become sprites over this plate.
const _DEEPSPACE_STATIC := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = mix(vec3(0.02, 0.01, 0.07), vec3(0.05, 0.02, 0.12), uv.y);
	col += vec3(0.30, 0.15, 0.50) * smoothstep(0.55, 0.95, fbm(a * 2.2)) * 0.40;
	col += vec3(0.10, 0.30, 0.60) * smoothstep(0.50, 0.95, fbm(a * 1.8)) * 0.28;
	COLOR = vec4(col, 1.0);
}
"

# Deep Space dynamic pass: sample the baked plate, then draw ONLY the hero props
# (galaxies, station, asteroids, fighters) over it. The 50-star loop and the two
# nebula fbm calls — the always-on per-pixel costs — are gone (stars are
# particles, nebula is in the plate). The fighter draw is wrapped in a tight
# bounding box so shipShape isn't evaluated over empty space.
const _DEEPSPACE_DYN := _HEAD + "uniform sampler2D static_tex : filter_linear;\n" + _DEEPSPACE_FUNCS + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	vec3 col = texture(static_tex, uv).rgb;
	col = galaxyAt(col, a, vec2(0.17 * aspect, 0.13), 0.10, 1.0, 0.5, vec3(0.62, 0.58, 0.98), t);
	col = galaxyAt(col, a, vec2(0.81 * aspect, 0.15), 0.11, 5.0, -0.7, vec3(0.98, 0.74, 0.50), t);
	col = galaxyAt(col, a, vec2(0.86 * aspect, 0.82), 0.085, 9.0, 1.3, vec3(0.45, 0.92, 0.86), t);
	col = placeStation(col, a, vec2(0.19 * aspect, 0.83), 0.075, t);
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float ax = fract(hash11(fi * 4.1) + t * 0.02 * (0.5 + hash11(fi))) * (aspect + 0.2) - 0.1;
		float ay = mix(0.10, 0.88, hash11(fi * 6.7));
		float s = 0.034 + 0.028 * hash11(fi * 2.1);
		col = placeAsteroid(col, a, vec2(ax, ay), s, fi * 5.7 + 1.0, t * (0.2 + 0.3 * hash11(fi * 3.3)) + fi);
	}
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float dir = (hash11(fi * 3.3) < 0.5) ? 1.0 : -1.0;
		float speed = 0.04 + 0.05 * hash11(fi * 1.9);
		float span = aspect + 0.5;
		float prog = mod(t * speed + hash11(fi * 7.1) * span, span) - 0.25;
		float sx = (dir > 0.0) ? prog : (span - 0.5 - prog);
		float sy = mix(0.10, 0.26, hash11(fi * 5.7)) + step(2.5, fi) * 0.60;
		sy += 0.012 * sin(t * 0.6 + fi);
		vec2 sq = a - vec2(sx, sy);
		sq.x *= dir;
		if (abs(sq.x) < 0.26 && abs(sq.y) < 0.10) {
			float win = win1(sq.x, -0.24, 0.24, 0.04) * win1(sq.y, -0.09, 0.09, 0.025);
			float ebehind = -sq.x - 0.05;
			col += vec3(0.30, 0.70, 1.0) * smoothstep(0.12, 0.0, ebehind) * step(0.0, ebehind) * smoothstep(0.006, 0.0, abs(sq.y)) * (0.5 + 0.4 * sin(t * 20.0 + fi)) * win;
			vec3 hull = vec3(0.62, 0.66, 0.74);
			if (int(mod(fi, 3.0)) == 1) hull = vec3(0.74, 0.60, 0.55);
			if (int(mod(fi, 3.0)) == 2) hull = vec3(0.55, 0.64, 0.72);
			vec4 sh = shipShape(sq, hull);
			col = mix(col, sh.rgb, sh.a * win);
			col += vec3(0.5, 0.85, 1.0) * aafill(distance(sq, vec2(-0.055, 0.0)) - 0.010) * 1.1 * win;
		}
		if (dir < 0.0) {
			float fireRate = 0.16 + 0.18 * hash11(fi * 2.7);
			float fph = t * fireRate + hash11(fi * 6.3) * 5.0;
			float shot = floor(fph);
			float fc = fract(fph);
			if (fc < 0.32 && hash11(shot * 1.7 + fi * 3.1) < 0.55) {
				float boltX = sx - 0.05 - (fc / 0.32) * 0.7;
				vec2 bq = a - vec2(boltX, sy);
				vec3 lcol = (hash11(fi * 9.1 + shot) < 0.5) ? vec3(1.0, 0.28, 0.22) : vec3(0.40, 1.0, 0.34);
				col += lcol * smoothstep(0.016, 0.0, length(bq * vec2(0.45, 1.7))) * 1.4;
				col += lcol * smoothstep(0.045, 0.0, length(bq)) * 0.30;
			}
		}
	}
	COLOR = vec4(col, 1.0);
}
"

# Rainbow dynamic pass: sample the baked plate, then draw ONLY the 5 gliding birds
# (the scene's only animated element).
const _RAINBOW_DYN := _HEAD + "uniform sampler2D static_tex : filter_linear;
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	vec3 col = texture(static_tex, uv).rgb;
	for (int i = 0; i < 5; i++) col = flyBird(col, a, TIME, float(i) * 7.3 + 1.0, 0.26, 0.12, 0.10, 0.0);
	COLOR = vec4(col, 1.0);
}
"

# ---------------------------------------------------------------------------
# SKIN BACKGROUNDS — bespoke animated scenes that belong to a complete wheel
# SKIN (not a purchasable theme). When a skin is equipped on the gameplay
# screen and the player hasn't equipped a separate paid theme, the skin paints
# its own world here. Keyed by the skin id in CoinsManager.SIMON_SKINS.
#
# VOLCANO ("inferno"): a high-end, level-reactive volcanic plain, in the same
# baked-plate + light-dyn style as the other animated themes. FOUR 3D-looking
# volcanoes sit one in each corner (seen from front-above so each summit reads as
# an elliptical caldera), rising from a clean dark-grey volcanic plain. The wheel
# covers the centre, so the corners carry the detail.
#
# It reacts to gameplay: every level completion makes all four volcanoes ERUPT
# (crater flare + molten fountain + ash/spark plume). Eruption strength escalates
# with the level (mid / heavy / big) — see theme_props.gd's on_level_complete.
# The eruptions are driven by a per-volcano `erupt` vec4 uniform pushed each frame
# by the props node (like the kitty's eye uniforms), NOT a free-running shader
# cycle, so the scene is calm between levels and bursts to life on success.
#
# Split for perf: the whole frozen scene (plain + the four volcano bodies with
# their baked crater lava-pool glow) bakes into the static plate; the dyn
# only samples that plate, flickers the already-baked hot pixels (cheap, no fbm),
# and draws the four eruptions (each box-guarded to its corner). Embers + ash are
# CPUParticles2D. So no full-screen fbm/SDF runs per frame.
# ---------------------------------------------------------------------------
# Shared toolbox for all three volcano shaders (plate / dyn / preview).
const _VOLCANO_FUNCS := "
float vridge(vec2 p) { return abs(fbm(p) - 0.5) * 2.0; }

// One 3D-looking volcano, unit space q = (a - center)/s, seen from front-above so
// the summit reads as an elliptical caldera. Lit from the upper-left. Frozen (no
// TIME) so it bakes into the plate; the hot lava pool is left deliberately bright
// red/orange so the dyn pass can flicker it for free.
vec4 volcanoBody(vec2 q, float seed) {
	vec4 acc = vec4(0.0);
	float topY = -0.70, botY = 1.08;
	float ty = clamp((q.y - topY) / (botY - topY), 0.0, 1.0);        // 0 summit .. 1 base
	float lean = (hash11(seed * 1.3) - 0.5) * 0.12;                  // gentle asymmetry
	float axis = q.x - lean * (1.0 - ty);                            // offset from the ridge line
	float hw = mix(0.26, 1.0, pow(ty, 0.80));                        // concave-up flanks
	float rough = 0.05 * fbm(vec2(q.y * 3.2 + seed, seed)) - 0.025;  // eroded edge
	float edge = abs(axis) - (hw + rough);
	float cone = max(edge, max(topY - q.y, q.y - botY));
	float ca = aafill(cone);
	float nx = clamp(axis / max(hw, 0.001), -1.0, 1.0);             // approx surface normal.x
	// rock shading — light from the upper-left, shaped by the (cone) normal
	float lit = clamp(0.52 - 0.60 * nx + (1.0 - ty) * 0.10, 0.0, 1.0);
	vec3 body = mix(vec3(0.075, 0.068, 0.085), vec3(0.37, 0.35, 0.39), lit);
	body *= 0.80 + 0.34 * fbm(q * 7.0 + seed) + 0.13 * fbm(q * 17.0 - seed * 2.0);   // 2-octave rock
	float gully = 0.5 + 0.5 * sin(nx * 9.0 + seed * 3.0 + fbm(q * 5.0) * 2.0);       // radial strata / gullies
	body *= 0.88 + 0.18 * gully * smoothstep(0.0, 0.35, ty);
	body *= mix(1.06, 0.58, smoothstep(0.10, 1.0, ty));                              // ambient occlusion to the base
	body += vec3(0.5, 0.22, 0.06) * smoothstep(0.42, 0.0, ty) * (0.35 + 0.25 * lit); // crater light on the upper cone
	acc = _ov(acc, body, ca);
	acc = _ov(acc, vec3(0.85, 0.78, 0.72), aaline(edge, 0.012) * step(axis, 0.0) * ca * 0.55);  // rim light (lit edge)
	acc = _ov(acc, vec3(0.03, 0.025, 0.035), aaline(edge, 0.010) * step(0.0, axis) * ca * 0.5); // core shadow (dark edge)
	// summit caldera, seen from front-above: rocky rim band, shaded bowl, lava pool
	vec2 cc = vec2(lean * 0.4, topY);
	float rimOut = ellip(q, cc, vec2(0.40, 0.15), 0.0);
	float rimIn  = ellip(q, cc + vec2(0.0, 0.012), vec2(0.30, 0.105), 0.0);
	float rimBand = aafill(rimOut) * (1.0 - aafill(rimIn));
	acc = _ov(acc, mix(vec3(0.13, 0.12, 0.14), vec3(0.46, 0.42, 0.44), smoothstep(0.10, -0.16, q.y - topY)), rimBand);
	float bowl = aafill(rimIn);
	acc = _ov(acc, mix(vec3(0.02, 0.015, 0.02), vec3(0.11, 0.06, 0.05), smoothstep(-0.10, 0.10, q.y - topY)), bowl);
	vec2 pc = cc + vec2(0.0, 0.03);
	float poolA = aafill(ellip(q, pc, vec2(0.22, 0.07), 0.0)) * bowl;
	float hotc = smoothstep(0.9, 0.0, length((q - pc) / vec2(0.22, 0.07)));          // bright molten centre
	acc = _ov(acc, mix(vec3(0.95, 0.28, 0.04), vec3(1.0, 0.92, 0.55), hotc), poolA);
	acc = _ov(acc, vec3(1.0, 0.55, 0.15), aaline(rimIn, 0.010) * bowl * step(topY, q.y) * 0.55);  // glowing near lip
	return acc;
}
vec3 placeVolcano(vec3 col, vec2 a, vec2 c, float s, float seed) {
	vec2 q = (a - c) / s;
	if (q.x < -1.4 || q.x > 1.4 || q.y < -1.3 || q.y > 1.3) return col;
	col = mix(col, col * 0.5, aafill(ellip(a, c + vec2(0.0, s * 1.0), vec2(s * 1.05, s * 0.14), 0.0)) * 0.55);   // contact shadow
	col += vec3(1.0, 0.45, 0.13) * smoothstep(0.55, 0.0, length((q - vec2(0.0, -0.70)) / vec2(0.9, 0.7))) * 0.10;  // resting summit glow
	vec4 v = volcanoBody(q, seed);
	float win = win1(q.x, -1.34, 1.34, 0.12) * win1(q.y, -1.24, 1.24, 0.12);
	return mix(col, v.rgb, v.a * win);
}
// The full FROZEN scene: hazy horizon, a clean dark-grey volcanic plain, and the
// four (smaller) corner volcanoes. No ground lava. Shared by the plate + preview.
vec3 volcanoScene(vec2 a, vec2 uv) {
	vec3 col = mix(vec3(0.15, 0.08, 0.075), vec3(0.135, 0.125, 0.145), smoothstep(0.0, 0.20, uv.y));  // hazy horizon -> grey plain
	col = mix(col, vec3(0.045, 0.042, 0.052), smoothstep(0.20, 1.0, uv.y));                            // near ground darker
	col += vec3(0.28, 0.10, 0.03) * smoothstep(0.26, 0.0, abs(uv.y - 0.16)) * 0.15;                    // faint distant haze (not lava)
	float grd = smoothstep(0.14, 0.28, uv.y);
	col *= 1.0 - 0.14 * grd * fbm(vec2(a.x * 7.0, uv.y * 7.0));                                        // rocky mottle
	col += vec3(0.04) * grd * vridge(vec2(a.x * 11.0, uv.y * 11.0)) * 0.35;                            // subtle grey facets
	col = placeVolcano(col, a, vec2(0.12 * aspect, 0.26), 0.12, 3.0);                                  // top-left (distant)
	col = placeVolcano(col, a, vec2(0.88 * aspect, 0.24), 0.12, 8.0);                                  // top-right (distant)
	col = placeVolcano(col, a, vec2(0.13 * aspect, 0.80), 0.17, 15.0);                                 // bottom-left (near)
	col = placeVolcano(col, a, vec2(0.87 * aspect, 0.78), 0.17, 22.0);                                 // bottom-right (near)
	return col;
}
// One eruption over a crater apex, driven by activity e (0 dormant .. ~3 big).
// Fully derivative-free (smoothstep/length only) so it is seam-safe over its box
// guard. Crater glow always shows a little; fountain + plume grow with e.
vec3 eruptAt(vec3 col, vec2 a, vec2 apex, float s, float e, float t, float seed) {
	float dx = a.x - apex.x;
	float up = apex.y - a.y;                                    // > 0 above the crater
	float maxH = s * (0.55 + 1.7 * e);
	if (up < -0.06 * s || up > maxH + 0.16 || abs(dx) > s * (0.95 + 0.55 * e)) return col;
	float cg = smoothstep(0.13 * s, 0.0, length(vec2(dx, up * 1.5)));                 // crater glow
	col += vec3(1.0, 0.52, 0.18) * cg * (0.28 + 1.2 * e) * (0.85 + 0.15 * sin(t * 6.0 + seed));
	if (up <= 0.0 || e < 0.03) return col;
	// molten fountain — a noisy glowing column thrown up from the crater
	float fw = s * (0.11 + 0.05 * e);
	float fn = gnoise(vec2(dx * 34.0 / s, up * 22.0 / s - t * 5.0));
	float fmask = smoothstep(fw * (0.5 + 0.6 * fn), 0.0, abs(dx)) * smoothstep(maxH * 0.72, 0.0, up);
	col = mix(col, mix(vec3(1.0, 0.55, 0.12), vec3(1.0, 0.95, 0.60), smoothstep(0.0, maxH * 0.45, up)), clamp(fmask * (0.4 + 0.9 * e), 0.0, 1.0));
	// ash + spark plume, rising and drifting overhead
	float drift = 0.06 * s * sin(up * 8.0 / s + t * 0.7 + seed) + dx * 0.22;
	float pw = s * (0.24 + 0.20 * e);
	float pn = gnoise(vec2(dx * 6.0 / s - t * 0.2, up * 5.0 / s - t * 0.6));
	float pmask = smoothstep(pw, 0.0, abs(dx - drift)) * smoothstep(0.0, 0.06, up) * smoothstep(maxH + 0.13, 0.0, up);
	col = mix(col, mix(vec3(0.09, 0.06, 0.07), vec3(0.28, 0.12, 0.07), smoothstep(0.2, 0.9, pn)), pmask * clamp(0.35 + 0.7 * e, 0.0, 1.0) * smoothstep(0.15, 0.85, pn) * 0.85);
	col += vec3(1.0, 0.50, 0.12) * pmask * e * smoothstep(0.76, 0.98, pn) * 1.5;      // glowing lava bombs / sparks
	return col;
}
"
# Volcano preview / live-fallback shader: the frozen scene + free-running auto
# eruptions (the shop preview has no gameplay events to drive the uniform).
const _VOLCANO_SHADER := _HEAD + _VOLCANO_FUNCS + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	vec3 col = volcanoScene(a, uv);
	float e0 = smoothstep(0.0, 0.10, fract(t * 0.13 + 0.00)) * smoothstep(0.70, 0.20, fract(t * 0.13 + 0.00)) * 2.0;
	float e1 = smoothstep(0.0, 0.10, fract(t * 0.11 + 0.50)) * smoothstep(0.70, 0.20, fract(t * 0.11 + 0.50)) * 2.0;
	float e2 = smoothstep(0.0, 0.10, fract(t * 0.09 + 0.25)) * smoothstep(0.70, 0.20, fract(t * 0.09 + 0.25)) * 2.4;
	float e3 = smoothstep(0.0, 0.10, fract(t * 0.10 + 0.75)) * smoothstep(0.70, 0.20, fract(t * 0.10 + 0.75)) * 2.4;
	col = eruptAt(col, a, vec2(0.12 * aspect, 0.26 - 0.70 * 0.12), 0.12, e0 + 0.12, t, 1.0);
	col = eruptAt(col, a, vec2(0.88 * aspect, 0.24 - 0.70 * 0.12), 0.12, e1 + 0.12, t, 2.0);
	col = eruptAt(col, a, vec2(0.13 * aspect, 0.80 - 0.70 * 0.17), 0.17, e2 + 0.12, t, 3.0);
	col = eruptAt(col, a, vec2(0.87 * aspect, 0.78 - 0.70 * 0.17), 0.17, e3 + 0.12, t, 4.0);
	col = mix(col, col * vec3(1.06, 0.9, 0.84), 0.12);
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	col *= mix(0.5, 1.0, smoothstep(1.3, 0.25, length(p)));
	COLOR = vec4(col, 1.0);
}
"
# Volcano static plate: the whole frozen scene (dark-grey plain + the four corner
# volcanoes with their detailed rock shading and baked crater lava-pool glow). The
# volcano SDFs + ground mottle fbm are the cost; frozen into the plate they cost
# nothing per frame. Eruptions animate in the dyn; embers/ash are particles.
# Grade + vignette are applied in the dyn (over the whole composite).
const _VOLCANO_STATIC := _HEAD + _VOLCANO_FUNCS + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	COLOR = vec4(volcanoScene(a, uv), 1.0);
}
"
# Volcano dynamic: sample the plate, flicker the baked hot (lava) pixels for a
# living glow (cheap — keys off the plate colour, no fbm), then draw the four
# corner eruptions driven by the per-volcano `erupt` uniform (each box-guarded to
# its corner inside eruptAt), then grade + vignette the whole composite.
const _VOLCANO_DYN := _HEAD + "uniform sampler2D static_tex : filter_linear;\nuniform vec4 erupt = vec4(0.0);\n" + _VOLCANO_FUNCS + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	vec3 col = texture(static_tex, uv).rgb;
	// living lava — flicker the baked hot (red-dominant) pixels; no fbm, ~free
	float hot = smoothstep(0.16, 0.5, col.r - col.b) * smoothstep(0.05, 0.35, col.r);
	float flick = sin(t * 3.1 + a.x * 20.0 + a.y * 15.0) * (0.5 + 0.5 * sin(t * 1.6 + a.x * 4.0));
	col += col * hot * flick * 0.35;
	// four corner eruptions (apex = center + (0, -0.80 * s)), from the uniform
	col = eruptAt(col, a, vec2(0.12 * aspect, 0.26 - 0.70 * 0.12), 0.12, erupt.x, t, 1.0);
	col = eruptAt(col, a, vec2(0.88 * aspect, 0.24 - 0.70 * 0.12), 0.12, erupt.y, t, 2.0);
	col = eruptAt(col, a, vec2(0.13 * aspect, 0.80 - 0.70 * 0.17), 0.17, erupt.z, t, 3.0);
	col = eruptAt(col, a, vec2(0.87 * aspect, 0.78 - 0.70 * 0.17), 0.17, erupt.w, t, 4.0);
	col = mix(col, col * vec3(1.06, 0.9, 0.84), 0.12);
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	col *= mix(0.5, 1.0, smoothstep(1.3, 0.25, length(p)));
	COLOR = vec4(col, 1.0);
}
"

# Skin id -> bespoke background shader. Painted on the gameplay screen when the
# matching complete skin is equipped and no paid theme is overriding it.
const _SKIN_SHADERS := {
	"inferno": _VOLCANO_SHADER,
}

# Basic static-gradient themes (80 coins each). Each entry drives the shared
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
	"crimson":  {"top": Color(0.18, 0.04, 0.07), "bot": Color(0.05, 0.01, 0.03),
		"glow": Color(0.58, 0.11, 0.20), "gx": 0.5, "gy": 0.30, "gs": 0.45},
	"slate":    {"top": Color(0.15, 0.17, 0.21), "bot": Color(0.05, 0.06, 0.09),
		"glow": Color(0.26, 0.32, 0.40), "gx": 0.5, "gy": 0.30, "gs": 0.50},
}

const _SHADERS := {
	"skybound": _SKYBOUND_SHADER,
	"inferno": _INFERNO_SHADER,
	# Mid-value illustrated static scenes.
	"rainbow": _RAINBOW_SHADER,
	"forest": _FOREST_SHADER,
	"desert": _DESERT_SHADER,
	"speedway": _SPEEDWAY_SHADER,
	"reef": _REEF_SHADER,
	"kitty": _KITTY_SHADER,
	"cosmos": _COSMOS_SHADER,
	"neon": _NEON_SHADER,
	# High-value animated scenes.
	"clouds": _CLOUDS_SHADER,
	"aurora": _AURORA_SHADER,
	"fairies": _FAIRIES_SHADER,
	"deepspace": _DEEPSPACE_SHADER,
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
var _bg: ColorRect               # live shader layer (animated themes)
var _mat: ShaderMaterial
var _static_rect: TextureRect    # baked still-image layer (fully-static themes)
var _cache: Dictionary = {}     # theme_id -> Shader

# Themes whose shader contains NO TIME term — they render the exact same pixels
# every frame, so the per-frame procedural recompute is pure waste. These are
# baked once to a texture and shown as a still image (~zero per-frame GPU), which
# looks pixel-for-pixel identical to the live shader. Add a key here once you've
# confirmed (grep) its shader + every helper it calls is TIME-free.
const _STATIC_BAKE := {
	"forest": true,
}

# Animated themes split into a baked static plate + a cheap live "props" shader
# that samples that plate. The live shader skips the heavy static work (fbm,
# ground, grass/mushroom SDFs) entirely, so per-frame cost drops a lot while the
# animation stays pixel-identical. Maps theme key -> [static_plate_code, dyn_code].
# Themes rendered as a baked static PLATE + node-based moving props (particles +
# sprites) on top, so NO full-screen shader runs per frame. The dense per-pixel
# dot loops (sparkles/stars) were the perf killer; node props draw only where each
# element actually is. Maps theme key -> static plate shader code. The moving
# props for each key are built in theme_props.gd (ThemeProps).
const _NODE_PLATE := {
	"fairies": _FAIRIES_STATIC,
	"rainbow": _RAINBOW_STATIC,
	"deepspace": _DEEPSPACE_STATIC,
	"desert": _DESERT_STATIC,
	"speedway": _SPEEDWAY_STATIC,
	"cosmos": _COSMOS_STATIC,
	"neon": _NEON_STATIC,
	"aurora": _AURORA_STATIC,
	"kitty": _KITTY_STATIC,
	"reef": _REEF_STATIC,
	"clouds": _CLOUDS_STATIC,
	"skin:inferno": _VOLCANO_STATIC,
}
const _NODE_DYN := {
	"fairies": _FAIRIES_DYN,
	"rainbow": _RAINBOW_DYN,
	"deepspace": _DEEPSPACE_DYN,
	"desert": _DESERT_DYN,
	"speedway": _SPEEDWAY_DYN,
	"cosmos": _COSMOS_DYN,
	"neon": _NEON_DYN,
	"aurora": _AURORA_DYN,
	"kitty": _KITTY_DYN,
	"reef": _REEF_DYN,
	"clouds": _CLOUDS_DYN,
	"skin:inferno": _VOLCANO_DYN,
}

# Trivial full-screen blit: paint a baked plate texture across the _bg ColorRect
# (UV 0..1 over the rect = the whole screen). This is the same display path Stage
# 1 used successfully, so it fills correctly with no zoom/crop.
const _BLIT_SHADER := "shader_type canvas_item;\nuniform sampler2D plate_tex : filter_linear;\nvoid fragment() { COLOR = texture(plate_tex, UV); }"

# Bake state for the currently-shown static theme. We hold only the active baked
# texture (not a cache of all themes) to bound memory on GL/Mali devices. A
# generation counter guards against a theme-switch landing mid-bake.
var _bake_gen := 0
# Plate cache: baked static-plate textures kept in RAM (NOT flash), keyed by theme
# key. Pre-baked at startup + on equip so entering gameplay is instant. Bounded to
# the equipped theme (+ whatever is currently displayed) so memory stays ~1-2 plates.
var _plate_cache: Dictionary = {}   # key -> ImageTexture
var _baking: Dictionary = {}        # key -> true while a bake is in flight (dedup)
# Active display state.
var _node_key := ""                 # node theme currently shown ("" = none)
var _node_plate: ImageTexture
var _props_node: Node2D
var _props_key := ""                # theme the current _props_node was built for
# Themes are only painted on the gameplay screen now (every other screen wears
# its own bespoke background). GameManager flips this on/off as it swaps screens,
# BEFORE the incoming screen builds, so is_themed() is already correct in _ready().
var _active := false

# DEBUG: set false to hide the on-screen FPS readout before shipping. While true
# it shows live FPS in the top-left on every screen, so we can compare the cost of
# each theme (default vs baked-static Forest vs hybrid Fairies) with real numbers.
const DEBUG_FPS := false
var _fps_label: Label
var _render_mode := "none"        # FULL | HYBRID | BAKED | none — which path is live

# Deep Space's dynamic shader, built once at startup with every prop's random
# constants baked in as literals (so no per-pixel hash11) and every prop box-guarded
# (so galaxyAt/shipShape/placeAsteroid only run where the prop is). See _build_deepspace_dyn.
var _deepspace_dyn_code := ""

# sin-free hash matching the shaders' hash11, used to bake prop constants.
static func _fr(x: float) -> float:
	return x - floor(x)

static func _h11(p: float) -> float:
	p = _fr(p * 0.1031)
	p *= p + 33.33
	p *= p + p
	return _fr(p)

func _ready() -> void:
	_build_layer()
	_deepspace_dyn_code = _build_deepspace_dyn()             # bake prop constants once
	CoinsManager.themes_changed.connect(_on_themes_changed)
	CoinsManager.simon_changed.connect(_on_themes_changed)   # equipping a skin can change the bg
	get_tree().root.size_changed.connect(_fit_to_viewport)
	_apply_theme()
	_prebake_equipped()                                     # warm the cache during the loading screen
	if DEBUG_FPS:
		_build_fps_overlay()
	set_process(DEBUG_FPS)

func _build_fps_overlay() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 128                                          # above everything
	add_child(cl)
	_fps_label = Label.new()
	_fps_label.position = Vector2(12, 8)
	_fps_label.add_theme_color_override("font_color", Color(0, 1, 0))
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_fps_label.add_theme_constant_override("outline_size", 6)
	_fps_label.add_theme_font_size_override("font_size", 28)
	cl.add_child(_fps_label)

func _process(_dt: float) -> void:
	if _fps_label:
		var key := _node_key
		if key.is_empty():
			key = _resolved_bg_key()
		if key.is_empty():
			key = "default"
		# Show the actual render path so we can tell if the hybrid actually engaged
		# (HYBRID) or got stuck on the expensive FULL shader.
		_fps_label.text = "%d FPS  [%s/%s]" % [Engine.get_frames_per_second(), key, _render_mode]

# Called by GameManager on every screen swap: true only for the gameplay screen.
func set_active(on: bool) -> void:
	if _active == on:
		return
	_active = on
	_apply_theme()

# Whether BackgroundManager is painting a full-screen background on the current
# screen (a paid theme OR an equipped skin's bespoke background). Screens read
# this in their _ready() to decide whether to skip their own per-screen
# background. Only ever true on the gameplay screen (set_active gates it).
func is_themed() -> bool:
	return not _resolved_bg_key().is_empty()

# Resolve which background should paint on the current screen, as a cache key
# ("" = none, so per-screen backgrounds show through). A complete skin wins
# everything while it's on: equipping a skin is a "wear this whole look" choice
# that overrides both the per-part wheel colours AND any paid theme's background
# with the skin's own bespoke world (e.g. Volcano). Equipping a theme drops the
# skin (CoinsManager.select_theme flips simon_mode back to manual), at which point
# this falls through to the selected theme. Skin keys are namespaced "skin:<id>"
# so they never collide with theme ids — e.g. the "inferno" theme vs. the
# "inferno" Volcano skin.
func _resolved_bg_key() -> String:
	return _equipped_bg_key() if _active else ""

# The equipped background key regardless of whether gameplay is active — used to
# pre-bake the plate off-gameplay (loading screen / shop) so it's ready in time.
func _equipped_bg_key() -> String:
	if not CoinsManager.is_simon_manual():
		var skin: String = CoinsManager.selected_skin
		if _SKIN_SHADERS.has(skin):
			return "skin:" + skin
	var t: String = CoinsManager.selected_theme
	if t != CoinsManager.DEFAULT_THEME and _has_theme(t):
		return t
	return ""

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

# Build a small ColorRect rendering an equipped-skin's bespoke background at the
# requested size, for use behind the wheel preview in the SPECIAL SKINS shop tab.
# Returns a deep-void fallback rect for skins that ship no background.
func make_skin_preview(skin_id: String, size: Vector2) -> Control:
	var rect := ColorRect.new()
	rect.custom_minimum_size = size
	rect.size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _SKIN_SHADERS.has(skin_id):
		rect.color = Color(0.018, 0.008, 0.025)
		return rect
	rect.color = Color(1, 1, 1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = _get_shader("skin:" + skin_id)
	mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))
	rect.material = mat
	return rect

func _get_shader(key: String) -> Shader:
	if _cache.has(key):
		return _cache[key]
	var sh := Shader.new()
	if key.begins_with("skin:"):
		sh.code = _SKIN_SHADERS[key.substr(5)]
	elif _SHADERS.has(key):
		sh.code = _SHADERS[key]
	else:
		sh.code = _gradient_shader(_GRADIENTS[key])
	_cache[key] = sh
	return sh

func _build_layer() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = -1                                       # below ScreenCanvas (layer 1)
	add_child(_layer)
	_bg = ColorRect.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.color = Color(0, 0, 0, 0)
	_layer.add_child(_bg)
	# Still-image layer for baked static themes. Sits in the same spot as _bg;
	# only one of the two is ever visible at a time.
	_static_rect = TextureRect.new()
	_static_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_static_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_static_rect.visible = false
	_layer.add_child(_static_rect)
	_mat = ShaderMaterial.new()
	_fit_to_viewport()

func _fit_to_viewport() -> void:
	var sz := get_viewport().get_visible_rect().size
	if _bg:
		_bg.position = Vector2.ZERO
		_bg.size = sz
	if _static_rect:
		_static_rect.position = Vector2.ZERO
		_static_rect.size = sz
	if _mat:
		_mat.set_shader_parameter("aspect", sz.x / maxf(1.0, sz.y))
	# Baked plates are tied to the resolution they were rendered at; on a real size
	# change (rare — orientation is landscape-locked) drop the cache and re-apply.
	if _node_plate and Vector2(_node_plate.get_size()) != _native_px():
		_plate_cache.clear()
		_node_key = ""
		_node_plate = null
		_apply_theme()
		_prebake_equipped()

func _on_themes_changed() -> void:
	_apply_theme()
	# Keep the cache bounded to the equipped (+ currently displayed) theme, then
	# pre-bake the newly equipped one so it's ready before gameplay.
	_evict_plates_except([_equipped_bg_key(), _node_key])
	_prebake_equipped()

func _apply_theme() -> void:
	var key := _resolved_bg_key()
	if key.is_empty():
		_node_key = ""
		_node_plate = null
		_clear_props()
		_show_live(null)
		_static_rect.visible = false
		return
	# Fully-static themes (e.g. forest): show the baked plate. Cached -> instant.
	if _STATIC_BAKE.has(key):
		_node_key = ""
		_node_plate = null
		_clear_props()
		if _plate_cache.has(key):
			_show_plate_blit(_plate_cache[key])
			_render_mode = "BAKED"
		else:
			_show_live(key)                                # paint live until the bake lands
			_ensure_plate(key)
		return
	# Node themes: baked plate + LIGHT hero-prop shader + particle dots. Cached ->
	# instant (no full-screen shader, no bake hitch on gameplay entry).
	if _NODE_PLATE.has(key):
		if _plate_cache.has(key):
			_node_plate = _plate_cache[key]
			_node_key = key
			_show_node_dyn(key, _node_plate)
			_render_mode = "NODES"
			_ensure_props(key)
		else:
			_node_key = ""
			_node_plate = null
			_clear_props()
			_show_live(key)                                # full shader until the plate lands
			_ensure_plate(key)
		return
	# Other animated themes (skybound/inferno/skins): live full-screen shader.
	_node_key = ""
	_node_plate = null
	_clear_props()
	_static_rect.visible = false
	_show_live(key)

# Point the live ColorRect at a theme's shader (or clear it when key is null).
func _show_live(key: Variant) -> void:
	if key == null:
		_bg.material = null
		_bg.color = Color(0, 0, 0, 0)                       # fully transparent
		if _render_mode != "BAKED" and _render_mode != "NODES":
			_render_mode = "none"
		return
	_mat.shader = _get_shader(key)
	_bg.material = _mat
	_bg.color = Color(1, 1, 1, 1)                           # opaque so shader fills
	_render_mode = "FULL"
	_fit_to_viewport()

# Paint a baked plate texture across the full-screen _bg ColorRect (no TextureRect
# scaling quirks — UV 0..1 maps the texture across the whole screen). Used by both
# fully-static themes and node themes.
func _show_plate_blit(tex: Texture2D) -> void:
	_static_rect.visible = false
	_mat.shader = _compiled("blit", _BLIT_SHADER)
	_mat.set_shader_parameter("plate_tex", tex)
	_bg.material = _mat
	_bg.color = Color(1, 1, 1, 1)
	_bg.position = Vector2.ZERO
	_bg.size = get_viewport().get_visible_rect().size

# The real framebuffer pixel size, so a baked texture matches the live shader's
# native sharpness (the shader currently renders at window resolution under the
# canvas_items stretch mode, not the 1280x720 design size).
func _native_px() -> Vector2:
	var w := DisplayServer.window_get_size()
	if w.x > 0 and w.y > 0:
		return Vector2(w)
	return get_viewport().get_visible_rect().size

# Compile (and cache) a shader from raw code under an explicit cache key. Used
# for the split static/dynamic variants that aren't in the _SHADERS dict.
func _compiled(cache_key: String, code: String) -> Shader:
	if _cache.has(cache_key):
		return _cache[cache_key]
	var sh := Shader.new()
	sh.code = code
	_cache[cache_key] = sh
	return sh

# The plate shader for a theme: node themes bake their static-plate variant;
# static-bake themes (forest) bake their full shader. Returns null otherwise.
func _plate_shader_for(key: String) -> Shader:
	if _NODE_PLATE.has(key):
		return _compiled("plate:" + key, _NODE_PLATE[key])
	if _STATIC_BAKE.has(key):
		return _get_shader(key)
	return null

# Render a plate shader once into an offscreen SubViewport at native size and
# return the image as a texture. UPDATE_ONCE + no MSAA, freed right after the read,
# so it never enters the continuous-redraw path that OOM-crashed the wheel on GL/Mali.
func _render_plate(shader: Shader) -> ImageTexture:
	var px := Vector2i(_native_px())
	px.x = maxi(2, px.x)
	px.y = maxi(2, px.y)
	var vp := SubViewport.new()
	vp.size = px
	vp.transparent_bg = false
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.disable_3d = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(px)
	rect.color = Color(1, 1, 1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("aspect", float(px.x) / maxf(1.0, float(px.y)))
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return ImageTexture.create_from_image(img)

# Bake `key`'s plate into the RAM cache if not already there (dedup via _baking).
# Safe to call off-gameplay (pre-bake). After it lands, if this theme is the one
# waiting to be shown, re-apply so the display swaps from the live shader to the
# cheap cached plate; and pre-warm its dynamic shader so the first gameplay frame
# has no compile hitch.
func _ensure_plate(key: String) -> void:
	if _plate_cache.has(key) or _baking.get(key, false):
		return
	var sh := _plate_shader_for(key)
	if sh == null:
		return
	_baking[key] = true
	var tex: ImageTexture = await _render_plate(sh)
	_baking.erase(key)
	if tex == null:
		return
	_plate_cache[key] = tex
	if _NODE_PLATE.has(key):
		_prewarm_dyn(key, tex)
	# If gameplay is already waiting on this theme, show it now.
	if _active and _resolved_bg_key() == key and _node_key != key:
		_apply_theme()

# Build (or reuse) the ThemeProps particle tree for `key`.
func _ensure_props(key: String) -> void:
	if is_instance_valid(_props_node) and _props_key == key:
		return
	_clear_props()
	var props_script: Script = load("res://theme_props.gd")
	if props_script == null:
		return
	var props: Node2D = props_script.new()
	_props_node = props
	_props_key = key
	_layer.add_child(props)                                 # particle dots, drawn over the dyn shader
	props.call("setup", key, get_viewport().get_visible_rect().size, self)

# Compile + render a node theme's dynamic shader once (tiny throwaway viewport) so
# gl_compatibility compiles it now, not on the first gameplay frame.
func _prewarm_dyn(key: String, plate: Texture2D) -> void:
	if not _NODE_DYN.has(key):
		return
	var code: String = _deepspace_dyn_code if (key == "deepspace" and not _deepspace_dyn_code.is_empty()) else _NODE_DYN[key]
	var vp := SubViewport.new()
	vp.size = Vector2i(16, 16)
	vp.transparent_bg = false
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(16, 16)
	rect.color = Color(1, 1, 1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = _compiled("dyn:" + key, code)
	mat.set_shader_parameter("static_tex", plate)
	mat.set_shader_parameter("aspect", 1.78)
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	vp.queue_free()

# Pre-bake the equipped theme's plate into the cache (no-op for skins/default).
func _prebake_equipped() -> void:
	var eq := _equipped_bg_key()
	if _NODE_PLATE.has(eq) or _STATIC_BAKE.has(eq):
		_ensure_plate(eq)

# Drop cached plates whose keys aren't in `keep`, to bound RAM to ~1-2 plates.
func _evict_plates_except(keep: Array) -> void:
	for k in _plate_cache.keys():
		if not keep.has(k):
			_plate_cache.erase(k)

# Drive the _bg ColorRect with a node theme's dynamic shader: it samples the baked
# plate and draws the hero props on top (pixel-exact size, smooth animation). No
# per-pixel scene recompute — the heavy static work is baked into the plate.
func _show_node_dyn(key: String, plate: Texture2D) -> void:
	_static_rect.visible = false
	# Deep Space uses the startup-baked, box-guarded variant; others use their const.
	var code: String = _deepspace_dyn_code if (key == "deepspace" and not _deepspace_dyn_code.is_empty()) else _NODE_DYN[key]
	_mat.shader = _compiled("dyn:" + key, code)
	_mat.set_shader_parameter("static_tex", plate)
	_bg.material = _mat
	_bg.color = Color(1, 1, 1, 1)
	_bg.position = Vector2.ZERO
	var sz := get_viewport().get_visible_rect().size
	_bg.size = sz
	_mat.set_shader_parameter("aspect", sz.x / maxf(1.0, sz.y))
	if key == "kitty":
		set_kitty_eyes(1.0, 1.0, 0.0)                       # start with eyes open
	elif key == "skin:inferno":
		_mat.set_shader_parameter("erupt", Vector4.ZERO)    # start dormant

# Drive the kitty's expression (called every frame by its ThemeProps gesture
# controller). Harmless if the current shader isn't the kitty (ignored uniforms).
func set_kitty_eyes(l: float, r: float, smile_amt: float) -> void:
	if _mat:
		_mat.set_shader_parameter("eye_l", l)
		_mat.set_shader_parameter("eye_r", r)
		_mat.set_shader_parameter("smile", smile_amt)

# Drive the volcano's four per-crater eruption activities (called every frame by
# its ThemeProps controller). Harmless if the current shader isn't the volcano.
func set_volcano_erupt(a0: float, a1: float, a2: float, a3: float) -> void:
	if _mat:
		_mat.set_shader_parameter("erupt", Vector4(a0, a1, a2, a3))

# Called by game.gd when the player completes a level. Forwarded to the active
# theme's props node so it can react (only the kitty does, for now).
func notify_level_complete(level: int) -> void:
	if is_instance_valid(_props_node) and _props_node.has_method("on_level_complete"):
		_props_node.on_level_complete(level)

# Build Deep Space's dynamic shader with each moving prop's random constants baked
# in as GLSL literals (no per-pixel hash11) and every prop wrapped in a cheap
# bounding-box guard (so galaxyAt / placeAsteroid / shipShape — which use cos/sin/
# fbm — only run for the few pixels the prop covers). Galaxies + the station are at
# fixed positions; asteroids + fighters get their hash-derived constants inlined.
func _build_deepspace_dyn() -> String:
	var f := "uniform sampler2D static_tex : filter_linear;\n"
	f += "void fragment() {\n"
	f += "\tvec2 uv = UV;\n\tvec2 a = vec2(uv.x * aspect, uv.y);\n\tfloat t = TIME;\n"
	f += "\tvec3 col = texture(static_tex, uv).rgb;\n"
	# fixed galaxies (box-guarded; symmetric box >= 1.8 * size covers the rotated disc)
	f += "\tif (abs(a.x - 0.17 * aspect) < 0.19 && abs(a.y - 0.13) < 0.19) col = galaxyAt(col, a, vec2(0.17 * aspect, 0.13), 0.10, 1.0, 0.5, vec3(0.62, 0.58, 0.98), t);\n"
	f += "\tif (abs(a.x - 0.81 * aspect) < 0.21 && abs(a.y - 0.15) < 0.21) col = galaxyAt(col, a, vec2(0.81 * aspect, 0.15), 0.11, 5.0, -0.7, vec3(0.98, 0.74, 0.50), t);\n"
	f += "\tif (abs(a.x - 0.86 * aspect) < 0.16 && abs(a.y - 0.82) < 0.16) col = galaxyAt(col, a, vec2(0.86 * aspect, 0.82), 0.085, 9.0, 1.3, vec3(0.45, 0.92, 0.86), t);\n"
	# fixed station
	f += "\tif (abs(a.x - 0.19 * aspect) < 0.13 && abs(a.y - 0.83) < 0.09) col = placeStation(col, a, vec2(0.19 * aspect, 0.83), 0.075, t);\n"
	# asteroids — drift + tumble, constants baked
	for i in 4:
		var fi := float(i)
		var drift_off := _h11(fi * 4.1)
		var drift_spd := 0.02 * (0.5 + _h11(fi))
		var ay := lerpf(0.10, 0.88, _h11(fi * 6.7))
		var size := 0.034 + 0.028 * _h11(fi * 2.1)
		var ang_spd := 0.2 + 0.3 * _h11(fi * 3.3)
		var seed := fi * 5.7 + 1.0
		var box := size * 1.7
		f += "\t{ float ax = fract(%f + t * %f) * (aspect + 0.2) - 0.1; if (abs(a.x - ax) < %f && abs(a.y - %f) < %f) col = placeAsteroid(col, a, vec2(ax, %f), %f, %f, t * %f + %f); }\n" % [drift_off, drift_spd, box, ay, box, ay, size, seed, ang_spd, fi]
	# fighters — fly across, engine glow, occasional laser; constants baked
	var hulls := ["vec3(0.62, 0.66, 0.74)", "vec3(0.74, 0.60, 0.55)", "vec3(0.55, 0.64, 0.72)"]
	for i in 5:
		var fi := float(i)
		var dir := 1.0 if _h11(fi * 3.3) < 0.5 else -1.0
		var speed := 0.04 + 0.05 * _h11(fi * 1.9)
		var off := _h11(fi * 7.1)
		var base_y := lerpf(0.10, 0.26, _h11(fi * 5.7)) + (0.60 if fi >= 2.5 else 0.0)
		var hull: String = hulls[i % 3]
		var sx_expr := "prog" if dir > 0.0 else "(span - 0.5 - prog)"
		f += "\t{ float span = aspect + 0.5; float prog = mod(t * %f + %f * span, span) - 0.25; float sx = %s; float sy = %f + 0.012 * sin(t * 0.6 + %f); vec2 sq = a - vec2(sx, sy); sq.x *= %f;\n" % [speed, off, sx_expr, base_y, fi, dir]
		f += "\t\tif (abs(sq.x) < 0.26 && abs(sq.y) < 0.10) { float win = win1(sq.x, -0.24, 0.24, 0.04) * win1(sq.y, -0.09, 0.09, 0.025); float ebehind = -sq.x - 0.05; col += vec3(0.30, 0.70, 1.0) * smoothstep(0.12, 0.0, ebehind) * step(0.0, ebehind) * smoothstep(0.006, 0.0, abs(sq.y)) * (0.5 + 0.4 * sin(t * 20.0 + %f)) * win; vec4 sh = shipShape(sq, %s); col = mix(col, sh.rgb, sh.a * win); col += vec3(0.5, 0.85, 1.0) * aafill(distance(sq, vec2(-0.055, 0.0)) - 0.010) * 1.1 * win; }\n" % [fi, hull]
		if dir < 0.0:
			var fire_rate := 0.16 + 0.18 * _h11(fi * 2.7)
			var fire_off := _h11(fi * 6.3) * 5.0
			f += "\t\t{ float fph = t * %f + %f; float shot = floor(fph); float fc = fract(fph); if (fc < 0.32 && hash11(shot * 1.7 + %f) < 0.55) { float boltX = sx - 0.05 - (fc / 0.32) * 0.7; vec2 bq = a - vec2(boltX, sy); vec3 lcol = (hash11(%f + shot) < 0.5) ? vec3(1.0, 0.28, 0.22) : vec3(0.40, 1.0, 0.34); col += lcol * smoothstep(0.016, 0.0, length(bq * vec2(0.45, 1.7))) * 1.4; col += lcol * smoothstep(0.045, 0.0, length(bq)) * 0.30; } }\n" % [fire_rate, fire_off, fi * 3.1, fi * 9.1]
		f += "\t}\n"
	f += "\tCOLOR = vec4(col, 1.0);\n}\n"
	return _HEAD + _DEEPSPACE_FUNCS + f

# Public: the shared shader prelude (shader_type + noise/shape/nature helpers) so
# ThemeProps can compose prop-baking shaders that reuse the exact same SDF art.
func shader_head() -> String:
	return _HEAD

# Public: batch-bake a set of prop sprite shaders to transparent textures in ONE
# frame (each `body` is wrapped with _HEAD). Returns ImageTextures in the same
# order, or [] if a newer theme switch superseded the bake. Used by ThemeProps.
func bake_sprites(bodies: Array, px: Vector2i) -> Array:
	var gen := _bake_gen
	px.x = maxi(2, px.x)
	px.y = maxi(2, px.y)
	var vps: Array = []
	for body in bodies:
		var vp := SubViewport.new()
		vp.size = px
		vp.transparent_bg = true
		vp.msaa_2d = Viewport.MSAA_DISABLED
		vp.disable_3d = true
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var rect := ColorRect.new()
		rect.size = Vector2(px)
		rect.color = Color(1, 1, 1, 1)
		var m := ShaderMaterial.new()
		m.shader = _compiled_uncached(_HEAD + String(body))
		rect.material = m
		vp.add_child(rect)
		add_child(vp)
		vps.append(vp)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out: Array = []
	for vp in vps:
		out.append(ImageTexture.create_from_image(vp.get_texture().get_image()))
		vp.queue_free()
	if gen != _bake_gen:
		return []
	return out

# One-off shader compile that is NOT cached (sprite-bake shaders are transient).
func _compiled_uncached(code: String) -> Shader:
	var sh := Shader.new()
	sh.code = code
	return sh

func _clear_props() -> void:
	if is_instance_valid(_props_node):
		_props_node.queue_free()
	_props_node = null
	_props_key = ""
