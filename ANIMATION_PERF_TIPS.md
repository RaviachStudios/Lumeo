# Non-Laggy Animation & Graphics — Quick Tips

How we keep the animated skins/themes smooth on real phones (`gl_compatibility`
renderer, Mali/Adreno GPUs, ~2.5M pixels). These are the rules that fixed the
lag; the deep architecture write-up is in `BACKGROUND_PERF_NOTES.md`.

The one thing to remember: **a full-screen fragment shader runs your code on
every pixel, every frame.** ~2.5 million times, 60× a second. A loop of 40 with a
few `fbm()` calls inside is *fine* in isolation and *lethal* per-pixel. So the
whole game is: **pay each cost only where and when it's actually visible.**

## 1. Bake anything that doesn't move
The sky, ground, mountains, static rock — render them ONCE into a texture (offscreen
`SubViewport`, `UPDATE_ONCE`) and just sample that image each frame. Even slow drifts
that are imperceptible when frozen (nebula, haze, distant clouds) go in the baked
plate. Per-frame cost of baked content ≈ one texture lookup.
→ In code: `*Scene()` / `_X_STATIC` does the heavy detail; the dyn shader only
samples `static_tex` and adds the movers.

## 2. Movers are particles or sprites, NOT per-pixel loops
- **Dense dots** (embers, sparks, stars, bubbles) → `CPUParticles2D`. The GPU only
  touches the handful of pixels each dot covers, instead of every pixel testing
  "am I near any of 30 dots?".
- **Distinct hero props** (birds, fairies) → `Sprite2D`, animated in GDScript. Bake
  the art from the SAME SDF the shader used so it looks identical.
- Compare the Rainbow dyn shader: sample plate + 5 bounding-box-guarded birds, done.
  Embers are particles. That's the target shape for a dyn shader.

## 3. Guard every per-prop block — spatially AND in time
A prop occupies a small region for a short window. Wrap its work so the GPU skips it
everywhere/whenever it contributes nothing. This is the single biggest lever.
- **Spatial (box/column) guard:** `if (abs(a.x - cone.x) < cone.w + margin) { ... }`.
  A prop in a screen corner then costs ~nothing across the other 80% of the screen.
- **Time guard:** if every term in a block is multiplied by a factor that hits 0
  after N seconds (e.g. `burst = ... * smoothstep(3.0, 0.0, lt)`), wrap the block in
  `if (lt < 3.05) { ... }`. Time factors are the same for all pixels, so the branch
  is coherent and nearly free — and it's **provably identical output**, you're just
  not computing a guaranteed-zero.
- Both guards let you keep the expensive-looking loop (40 debris chunks, etc.) at
  full quality, because it only runs in the box, during the burst.

## 3b. If you keep a dot/chunk loop in the shader, reject per element
A loop like `for (40 debris) { d = distance(a, ep); col += smoothstep(sz, 0, d); }`
runs a `distance()` (a `sqrt`) + `smoothstep` for **all 40** elements on **every**
pixel — even though each chunk only lights a box a few pixels wide. Add a cheap
axis-aligned reject right after you compute the element's position, before the sqrt:

```glsl
vec2 ep = ...;                                            // this chunk's position
if (abs(a.x - ep.x) > R || abs(a.y - ep.y) > R) continue; // R = the chunk's max radius + tiny margin
float d = distance(a, ep); col += smoothstep(sz, 0.0, d); // only runs near the chunk now
```

This turns an O(N)-per-pixel loop into "O(chunks actually near this pixel)" — the same
win a particle system gives you — while keeping the exact shader look. It's **provably
identical**: outside the box the `smoothstep` was already 0, so `col` is unchanged
(works for additive `+=` and for `col = mix(...)` darkening alike). Pick `R` ≥ the
element's largest visible radius (bloom included) so nothing is ever clipped. We use
this on the volcano's 40 debris chunks, ash, vent smoke/embers and the sky embers.

## 4. `fbm()` / trig are the expensive per-pixel ops — count them
`fbm` is several octaves of noise (many `sin`/hash). A helper that calls `fbm` twice
(e.g. `coneTop`) invoked 4× in an inner loop = 8 `fbm`/pixel — and if that inner loop
runs for 3 active props, 24 `fbm`/pixel, every frame. Put those loops **inside** the
guards from tip 3 so they only run where needed. Prefer sin-free hash noise and the
fewest octaves that still look right.

## 5. Gate work behind the cheapest test first
Compute a cheap mask (is this pixel in the river band? on the cone body?) and
`if (mask > 0.001)` before the expensive shading. An early `continue` for dormant
props (`if (fade < 0.001) continue;`) skips their whole cost.

## 6. Watch for box-guard seams
A bounding-box `if (...) return/continue;` around a prop drawn with `aafill`/`aaline`
(which call `fwidth()`) leaves a faint rectangular seam at the box edge, because the
screen-space derivative is undefined where neighbouring fragments took the early-out.
Fix: multiply the prop by an analytic, derivative-free window that's 1 across all
visible content and 0 just inside the guard (`win1`/`radWin` in `_SHAPES_GLSL`), or
guard *effects that are already 0 at the boundary* (a time factor, a `smoothstep`
that's zero there) so no seam can form. Purely additive/`mix` effects with a smooth
falloff (like the volcano eruption) don't seam.

---

## Applied to the Volcano skin (`_LAVA_DYN` / `volcanoAnim`)
The gameplay dyn shader was doing full-screen, per-pixel, every frame:
- a **40-iteration molten-debris loop per active cone** — up to 3 cones cooling at
  once = **120 iterations/pixel**, run even for cones long past their eruption;
- the vent mouth/smoke/ember + molten-stream + 4× `coneTop` **occlusion loop**
  (~24 `fbm`/pixel) for **every** cone at **every** pixel, corner to corner.

Fixes (no visual change — same loops, same counts, same look):
- **Time guard** on the big eruption (fireball, shock ring, 40-chunk debris, ash):
  wrapped in `if (lt < 3.05 && <box>)`. Every term there is already `* burst` /
  `* fb` / `* smoothstep(…, lt)` that is 0 past ~3s, so this is provably identical —
  it just stops running the 40-loop for the two cooling cones and after the burst.
- **Column guard** `nearCol = abs(a.x - v.x) < v.z + 0.16` on each cone's vent +
  molten stream + occlusion loop. The stream only ever draws in a narrow column
  around the cone axis, so the ~24-`fbm` occlusion cost is now paid only there
  instead of across the whole screen.

And to lighten the **steady state** (between eruptions, the common case during play):
- **Per-element AABB reject** (tip 3b) on every dot/chunk loop — the 40 debris chunks,
  ash, vent smoke/embers, and the 14 ambient sky embers now skip their `distance()`/
  `smoothstep()` on the ~99% of pixels not touching that element.
- **River band gate** `if (a.y > 0.62)` around the whole lava-river flow + surge pass,
  so `riverMask` and its shading never run on the top ~⅔ of the screen where the river
  and its glow can't reach.

Net: away from an actively-erupting cone, a fragment now costs a plate sample + a few
compares instead of 100+ loop iterations and dozens of `fbm`. Same eruptions, same
detail, same 40 debris chunks, same embers and river — just not computed where they're
invisible.

### Later pass — lossless CSE of the `fbm`-bearing helpers (no visual change at all)
Because up to 3 cones are cooling at once, some cone's stream column is *always* active, so
the occlusion path is a permanent cost, not just an eruption spike. `coneTop()` (2 `fbm`) and
`groundTop()` (2 `fbm`) depend only on `a.x` + per-cone constants, yet were recomputed a lot
per fragment: the occlusion `k`-loop evaluated **all four** cones' `coneTop()` for **each**
active cone whose column covers the fragment (≈12 `coneTop` = 24 `fbm` where columns overlap),
and `onSlopes` called `groundTop()` twice. Now each is computed **once per fragment** — the four
`coneTop` and `groundTop` are cached (`cTopY[4]`/`gTop`), evaluated **lazily** the first time the
fragment enters any active `nearCol` column so sky fragments still pay zero. Because the inputs
are identical, the cached values are bit-for-bit the same `fbm` outputs — the image is unchanged;
only the redundant recompute is gone. In overlapping columns this drops the per-cone `fbm` in the
stream/occlusion path from ~24–36 down to 10. (`volc()` is branch-only/no `fbm`, so its 4-entry
cache is free.) The river flow and every noise value elsewhere are untouched — reducing `fbm`
octaves there would change pixels, which this pass deliberately does **not** do.

## Applied to the Luna Park skin (`_LUNA_DYN` / `lunaMotion`)
The whole still world (sky, boardwalk, tent, booths, baked track, string wires) is
already in the plate; `lunaMotion` only adds the movers. But it was paying its two
biggest movers across huge regions every frame:
- the **21-bulb string-light twinkle loop** ran `lpStr()` + a box test for every pixel
  on the whole screen, though every bulb sits in the top ~0.11 strip;
- the **Ferris wheel** ran its A-frame lines, twin rims, 12-spoke loop, hub, 12-gondola
  loop (12× `cos/sin/sin` + box test) and 24-rim-bulb loop (24× `cos/sin` + box test)
  for *every* pixel in a bounding box covering ~40% of the screen — corner to corner
  inside the box, even though each part only ever draws in a thin ring or the disc.

Fixes (no visual change — same loops, same counts, same look; every guarded term is
already 0 outside its guard, so output is provably identical):
- **Top-strip gate** `if (a.y < 0.14)` around the whole string-twinkle loop — the
  bottom ~85% of the screen never touches `lpStr()`/`lpBulb()`.
- **Radial (annulus) guards** inside the Ferris-wheel box, using the `rr = length(d)`
  it already computes: rims only run in `rr ∈ [0.82·FR, FR+0.02]`, spokes only in
  `rr < 0.9·FR`, the hub only in `rr < 0.06`, gondolas only in `|rr−FR| < 0.08`, and
  the rim bulbs only in `|rr−FR| < 0.02`. A pixel deep in the disc now runs only the
  spokes; a pixel out near the frame runs almost nothing — instead of all five loops.
- **Vertical guard** `if (a.y > 0.255)` on the A-frame legs + contact shadow (they
  hang below the hub), and `if (celeEnv > 0.01)` on the celebration bloom.
- **Track-region gate** `if (a.x > 1.0 && a.y < 0.42)` around the idle coaster-train
  loop, which was iterating its 4 cars for every pixel on the screen.

Net: a fragment away from the wheel's rim and the top light strip now costs a plate
sample plus a couple of compares, instead of ~48 `cos/sin` + several loops of `aaline`.
Same wheel, same twinkle, same gondolas — just not computed where they're invisible.
