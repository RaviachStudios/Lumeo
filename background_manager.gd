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
float hash11(float n) { return fract(sin(n) * 43758.5453); }
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
// Crisp, resolution-independent fill/line from a signed distance (uses screen
// derivatives so edges stay a clean ~1px — sharp, never blurry).
float aafill(float d) { float w = max(fwidth(d), 0.00001); return clamp(0.5 - d / w, 0.0, 1.0); }
float aaline(float d, float hw) { float w = max(fwidth(d), 0.00001); return clamp((hw - abs(d)) / w + 0.5, 0.0, 1.0); }
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
	if (abs(bp.x) > 1.4 || abs(bp.y) > 1.2) return col;
	vec4 b = birdProfile(bp, flap, kind);
	return mix(col, mix(b.rgb, vec3(0.09, 0.06, 0.09), dark), b.a);
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
	if (abs((a.x - pos.x) / s) > 1.1 || abs((a.y - pos.y) / s) > 0.75) return base;
	float d = cloudSDF(a - pos, s, seed);
	float cl = aafill(d);
	float topness = clamp((pos.y - a.y) / (0.5 * s) + 0.5, 0.0, 1.0);
	vec3 cc = mix(shade, lit, smoothstep(0.0, 1.0, topness));
	base = mix(base, cc, cl);
	base = mix(base, lit, aaline(d, 0.004 * s) * step(a.y, pos.y) * 0.5);
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
	if (tp.x < -1.4 || tp.x > 1.4 || tp.y > 0.2 || tp.y < -2.7) return col;
	vec4 t = treeAt(a - base, s, kind, seed);
	return mix(col, mix(t.rgb, vec3(0.03, 0.06, 0.10), dark), t.a);
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
	if (gp.x < -1.2 || gp.x > 1.2 || gp.y > 0.2 || gp.y < -1.4) return col;
	vec4 g = grassTuft(gp, seed);
	return mix(col, g.rgb, g.a);
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
	if (mp.x < -1.0 || mp.x > 1.0 || mp.y > 0.2 || mp.y < -1.6) return col;
	col = mix(col, col * 0.6, aafill(ellip(a, base + vec2(0.0, 0.02 * s), vec2(0.5 * s, 0.12 * s), 0.0)) * 0.4);
	vec3 capCol = mix(vec3(0.86, 0.16, 0.14), glowCol, glow);
	if (glow > 0.5) col += glowCol * smoothstep(1.4, 0.0, length(mp)) * 0.25;
	vec4 m = mushroomShape(mp, seed, capCol);
	return mix(col, m.rgb, m.a);
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

const _SPEEDWAY_SHADER := _HEAD + "
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
	if (abs(q.x) > 0.95 || q.y < -0.75 || q.y > 0.75) return col;
	vec4 cv = carRear(q, body);
	return mix(col, cv.rgb, cv.a * fade);
}
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

const _REEF_SHADER := _HEAD + "
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
	if (abs(q.x) > 0.95 || q.y < -0.6 || q.y > 1.1) return col;
	col += tint * smoothstep(0.65, 0.0, length(q * vec2(1.0, 0.55))) * 0.12;
	vec4 j = jelly(q, t, tint);
	return mix(col, j.rgb, j.a);
}
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

const _KITTY_SHADER := _HEAD + "
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;
	vec3 col = mix(vec3(1.0, 0.82, 0.89), vec3(1.0, 0.64, 0.79), uv.y);
	// soft candy stripes
	col = mix(col, col * 1.04, aaline(fract(a.x * 10.0) - 0.5, 0.18) * 0.3);
	// LOTS of hearts drifting up across the whole screen, each fading in and out
	for (int i = 0; i < 26; i++) {
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
	vec2 c = vec2(0.215 * aspect, 0.150);
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
	for (int i = 0; i < 46; i++) {
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
	for (int i = 0; i < 22; i++) {
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
	if (abs(q.x) > 0.65 || abs(q.y) > 0.55) return col;
	col += tint * smoothstep(0.55, 0.0, length(q)) * 0.30;
	vec4 f = fairyFig(q, flap, tint);
	return mix(col, f.rgb, f.a);
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
	col += vec3(0.5, 1.0, 0.6) * (aaline(gsq.x, 0.0016) * step(abs(gsq.y), 0.075) + aaline(gsq.y, 0.0016) * step(abs(gsq.x), 0.075)) * gtw * 0.55; // sparkle rays
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

const _DEEPSPACE_SHADER := _HEAD + "
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
	if (length(q) > 1.5) return col;
	vec4 ast = asteroidShape(q, seed);
	return mix(col, ast.rgb, ast.a);
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
	if (length(q) > 1.3) return col;
	col += vec3(0.30, 0.50, 0.80) * smoothstep(1.1, 0.0, length(q)) * 0.14;
	vec4 st = stationShape(q, t);
	return mix(col, st.rgb, st.a);
}
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

# ---------------------------------------------------------------------------
# SKIN BACKGROUNDS — bespoke animated scenes that belong to a complete wheel
# SKIN (not a purchasable theme). When a skin is equipped on the gameplay
# screen and the player hasn't equipped a separate paid theme, the skin paints
# its own world here. Keyed by the skin id in CoinsManager.SIMON_SKINS.
#
# VOLCANO ("inferno"): a high-end, fully animated apocalyptic volcanic range.
# A churning blood-red ash sky, a ridge of FIVE volcanoes that each erupt on
# their own slow cycle (crater flare + lava fountain + ash plume), dark grey
# volcanic rock ground veined with flowing molten lava, lava rivers in the
# foreground, rising embers and drifting ash. Detail lives in the top band and
# the side gutters / bottom (the circular wheel covers the centre), so the
# scene reads around the wheel rather than behind it.
# ---------------------------------------------------------------------------
const _VOLCANO_SHADER := _HEAD + "
float vridge(vec2 p) { return abs(fbm(p) - 0.5) * 2.0; }
void fragment() {
	vec2 uv = UV;
	vec2 a = vec2(uv.x * aspect, uv.y);
	float t = TIME;

	// ===================== APOCALYPTIC SKY =====================
	vec3 col = mix(vec3(0.045, 0.020, 0.035), vec3(0.17, 0.045, 0.045), smoothstep(0.0, 0.50, uv.y));
	col = mix(col, vec3(0.46, 0.11, 0.05), smoothstep(0.40, 0.60, uv.y));
	// billowing smoke / ash cover, domain-warped so it churns organically
	vec2 sq = vec2(a.x * 1.6, uv.y * 2.2);
	vec2 sw = vec2(fbm(sq + vec2(t * 0.035, 0.0)), fbm(sq + vec2(4.7, 2.1) - vec2(t * 0.020, 0.0)));
	float smk = fbm(sq * 1.2 + sw * 1.8 + vec2(t * 0.030, -t * 0.012));
	float smkMask = smoothstep(0.46, 0.96, smk) * smoothstep(0.64, 0.02, uv.y);
	vec3 smkCol = mix(vec3(0.055, 0.045, 0.055), vec3(0.36, 0.14, 0.07), smoothstep(0.30, 0.90, smk));
	col = mix(col, smkCol, smkMask * 0.88);
	// dull blood-red sun smothered in the haze, upper-right
	vec2 sunp = vec2(0.66 * aspect, 0.19);
	float sd = distance(a, sunp);
	col += vec3(0.72, 0.17, 0.05) * smoothstep(0.46, 0.0, sd) * 0.55;
	col = mix(col, vec3(0.88, 0.32, 0.13), aafill(sd - 0.072) * (0.55 + 0.25 * smk));

	// ===================== VOLCANO RANGE =====================
	float horizon = 0.60;
	float terrain = horizon;          // upper silhouette of the range (smallest y wins)
	float craterGlow = 0.0;           // hot glow at each crater, flares while erupting
	float fountain = 0.0;             // molten fountain spewing during eruptions
	vec3 plume = vec3(0.0);           // ash plumes + ejected sparks
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float cx = (0.10 + 0.20 * fi) * aspect;
		float pk = 0.40 + 0.08 * hash11(fi * 1.7) - 0.11 * (1.0 - abs(fi - 2.0) * 0.5);  // centre taller
		float hw = (0.17 + 0.10 * hash11(fi * 3.3)) * aspect;
		float dx = a.x - cx;
		float coneY = pk + (horizon - pk) / hw * abs(dx);
		float craterW = 0.05 * aspect;
		coneY += 0.030 * smoothstep(craterW, 0.0, abs(dx));          // caldera notch at the apex
		terrain = min(terrain, coneY);

		// eruption cycle: dormant most of the time, then a building pulse
		float cyc = fract(t * (0.040 + 0.022 * hash11(fi * 5.1)) + hash11(fi * 7.3));
		float erupt = smoothstep(0.0, 0.08, cyc) * smoothstep(0.58, 0.16, cyc);

		float above = pk - a.y;                                       // > 0 above the crater
		float craterD = distance(vec2(dx, above), vec2(0.0, -0.015));
		craterGlow += smoothstep(0.055, 0.0, craterD) * (0.30 + 1.3 * erupt) * (0.6 + 0.4 * hash11(fi * 2.0));

		// molten fountain — a noisy glowing column thrown up from the crater
		float fw = (0.018 + 0.016 * erupt) * aspect;
		float fn = gnoise(vec2(dx * 36.0, a.y * 20.0 - t * 4.5));
		fountain += smoothstep(fw * (0.6 + fn), 0.0, abs(dx))
			* smoothstep(0.10 + 0.16 * erupt, 0.0, max(above, 0.0)) * step(0.0, above) * erupt;

		// ash plume rising and drifting from the crater
		float drift = 0.05 * sin(above * 7.0 + t * 0.6 + fi) + above * 0.18;
		float pmask = smoothstep(0.11 + 0.06 * erupt, 0.0, abs(dx - drift))
			* smoothstep(0.0, 0.04, above) * smoothstep(0.60, 0.0, above);
		float pn = gnoise(vec2(dx * 7.0 - drift * 2.0, above * 6.0 - t * 0.5));
		plume += vec3(0.13, 0.075, 0.065) * pmask * (0.45 + 0.9 * erupt) * smoothstep(0.15, 0.85, pn);
		plume += vec3(1.0, 0.46, 0.10) * pmask * erupt * smoothstep(0.72, 0.97, pn) * 1.6;  // sparks
	}
	float skyMask = 1.0 - smoothstep(terrain - 0.012, terrain + 0.012, uv.y);
	col += plume * skyMask;
	col += vec3(1.0, 0.74, 0.30) * craterGlow * skyMask;
	col = mix(col, mix(vec3(1.0, 0.52, 0.10), vec3(1.0, 0.96, 0.62), clamp(fountain, 0.0, 1.0)),
		clamp(fountain, 0.0, 1.0) * skyMask);
	// hot rim where the molten range meets the sky
	col += vec3(1.0, 0.34, 0.08) * smoothstep(0.045, 0.0, uv.y - terrain) * step(uv.y, terrain + 0.045) * 0.5;

	// ===================== VOLCANIC GROUND =====================
	float isGround = step(terrain, uv.y);
	vec3 rock = mix(vec3(0.115, 0.085, 0.090), vec3(0.045, 0.045, 0.055), smoothstep(horizon, 1.0, uv.y));
	rock *= 0.78 + 0.5 * fbm(vec2(a.x * 8.0, uv.y * 8.0));                 // rocky mottle
	rock += vec3(0.10, 0.05, 0.05) * vridge(vec2(a.x * 14.0, uv.y * 14.0)) * 0.4;  // fractured facets
	// cracked network of glowing lava veins, creeping downhill
	vec2 vq = vec2(a.x * 5.0, uv.y * 5.0 - t * 0.22);
	float vein = 1.0 - smoothstep(0.0, 0.05, abs(fbm(vq) - fbm(vq + vec2(3.1, 1.7))));
	vein *= smoothstep(horizon - 0.04, 1.0, uv.y);                        // grows toward the foreground
	float vflow = 0.6 + 0.4 * sin(uv.y * 26.0 - t * 3.0);
	rock = mix(rock, mix(vec3(0.92, 0.26, 0.05), vec3(1.0, 0.9, 0.42), vein * vflow), vein * 0.92);
	rock += vec3(1.0, 0.42, 0.12) * vein * 0.55;
	// broad lava rivers winding through the foreground
	for (int j = 0; j < 3; j++) {
		float fj = float(j);
		float rx = (0.16 + 0.34 * fj) * aspect;
		float wob = 0.05 * sin(uv.y * 6.5 + t * 0.8 + fj * 2.0) + 0.025 * sin(uv.y * 16.0 - t);
		float river = smoothstep(0.05, 0.0, abs(a.x - rx - wob)) * smoothstep(0.64, 0.82, uv.y);
		float flow = 0.5 + 0.5 * sin(uv.y * 38.0 - t * 6.0 + fj);
		rock = mix(rock, mix(vec3(0.96, 0.30, 0.04), vec3(1.0, 0.92, 0.52), flow), river);
		rock += vec3(1.0, 0.46, 0.12) * river * 0.7;
	}
	col = mix(col, rock, isGround);

	// ===================== ATMOSPHERE OVERLAYS =====================
	// rising embers — additive sparks that flicker as they climb
	for (int i = 0; i < 20; i++) {
		float fi = float(i);
		float ex = hash11(fi * 1.3) * aspect;
		float ey = fract(hash11(fi * 3.7) - t * (0.05 + 0.12 * hash11(fi * 2.1)));
		vec2 ep = vec2(ex + 0.02 * sin(t * (1.0 + hash11(fi)) + fi), ey);
		float tw = 0.5 + 0.5 * sin(t * 4.0 + fi * 2.0);
		float ed = distance(a, ep);
		col += vec3(1.0, 0.50, 0.12) * aafill(ed - (0.0016 + 0.0014 * hash11(fi * 5.0))) * (0.6 + 0.8 * tw);
		col += vec3(1.0, 0.40, 0.10) * smoothstep(0.012, 0.0, ed) * 0.16 * tw;
	}
	// drifting ash flakes settling down
	for (int i = 0; i < 12; i++) {
		float fi = float(i);
		float ay = fract(hash11(fi * 6.1) + t * (0.03 + 0.05 * hash11(fi)));
		vec2 apx = vec2(hash11(fi * 4.3) * aspect + 0.03 * sin(t + fi), ay);
		col = mix(col, col * 0.45, aafill(distance(a, apx) - 0.0022) * 0.55);
	}
	// warm grade, bottom heat bloom + heavy apocalyptic vignette
	col = mix(col, col * vec3(1.06, 0.86, 0.80), 0.16);
	col += vec3(0.16, 0.035, 0.0) * smoothstep(0.72, 1.0, uv.y);
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	col *= mix(0.42, 1.0, smoothstep(1.28, 0.22, length(p)));
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
	CoinsManager.simon_changed.connect(_on_themes_changed)   # equipping a skin can change the bg
	get_tree().root.size_changed.connect(_fit_to_viewport)
	_apply_theme()

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
	if not _active:
		return ""
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
	var key := _resolved_bg_key()
	if key.is_empty():
		_bg.material = null
		_bg.color = Color(0, 0, 0, 0)                       # fully transparent
		return
	_mat.shader = _get_shader(key)
	_bg.material = _mat
	_bg.color = Color(1, 1, 1, 1)                           # opaque so shader fills
	_fit_to_viewport()
