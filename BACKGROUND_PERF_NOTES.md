# Animated Background — Performance Architecture

## The root cause (confirmed on device)
Each themed background was ONE full-screen `ColorRect` running a heavy procedural
fragment shader that recomputed the entire scene **per pixel, every frame, at the
phone's native resolution** (~2.5M px) on the `gl_compatibility` renderer. The
specific perf killers were the **dense per-pixel dot loops** (e.g. Fairies' 30
sparkles + 5 fireflies, Deep Space's 50 stars) — each iteration doing trig +
`fwidth` over every pixel. Micro-optimising the shader (sin-free hash, fewer fbm
octaves, fewer loop iterations) only shaved a constant factor and was **not
enough**. The durable fix is architectural: stop running a full-screen shader.

## The architecture now
Three layers, no full-screen shader per frame:

1. **Baked static plate.** The non-moving scenery (sky, ground, trees, nebula,
   rainbow, etc.) is rendered ONCE into a texture via an offscreen `SubViewport`
   (`UPDATE_ONCE`, MSAA off, freed immediately — never the continuous-redraw path
   that OOM-crashed the wheel) and shown as a still image. ~zero per-frame cost.
2. **Particles** (`CPUParticles2D`, GL/Mali-safe) for the dense dot loops —
   sparkles, fireflies, stars. The GPU only touches the few pixels each dot covers.
3. **Sprites** (`Sprite2D`) for the distinct "hero" props — fairies, the green
   star, shooting stars, birds, galaxies, the ring station, asteroids, fighters.
   Their art is **baked from the SAME SDF functions** the shaders used
   (`birdProfile`, `fairyFig`, `asteroidShape`, `shipShape`, `galaxyAt`,
   `stationShape`), so they look identical; animation is replicated in GDScript.

### Where it lives
- `background_manager.gd`
  - `_NODE_THEMES` — maps `fairies`/`rainbow`/`deepspace` to their static-plate
    shader (`_FAIRIES_STATIC`, `_RAINBOW_STATIC`, `_DEEPSPACE_STATIC`).
  - `_setup_node_theme()` bakes the plate, shows it, and spawns the props node.
  - `bake_sprites()` — batch-bakes prop textures (transparent) in one frame.
  - `_STATIC_BAKE` (`forest`) — fully-static theme, baked whole (no props).
- `theme_props.gd` (`ThemeProps`, a `Node2D`) — builds + animates the particle/
  sprite props per theme. Coordinate note: shader "a"-space `(ax,ay)` → screen
  pixel `(ax,ay)*sz.y`; `_apx()` / `_alen()` do the conversion.

### When baking happens / where it's stored
Plates are baked into an in-RAM cache (`_plate_cache`, key -> ImageTexture) — **nothing
is written to flash**. The cache is warmed ahead of time so entering gameplay is instant:
- **At startup** (`_ready` -> `_prebake_equipped`): the equipped theme's plate is baked
  during the loading screen (BackgroundManager is an autoload, so this overlaps it).
- **On equip** (`_on_themes_changed`): the newly equipped theme is pre-baked, and the
  cache is evicted down to the equipped (+ currently displayed) theme so RAM stays at
  ~1-2 plates (~10 MB each).
- **Pre-warm:** each node theme's dynamic shader is rendered once into a 16x16 throwaway
  viewport right after its plate bakes, so gl_compatibility compiles it then, not on the
  first gameplay frame.
- Entering gameplay (`set_active(true)`) shows the cached plate immediately. If the bake
  somehow hasn't finished, the full shader paints until `_ensure_plate` lands and swaps in
  (graceful fallback). Leaving gameplay no longer drops the plate, so re-entry is instant.
- A real resolution change clears the cache and re-bakes (orientation is landscape-locked,
  so this is rare).

### Theme status
- **Node themes** (plate + dynamic hero-prop shader + particles), in `_NODE_PLATE`/
  `_NODE_DYN`: `fairies`, `rainbow`, `deepspace`, `desert`, `speedway`, `cosmos`,
  `neon`, `aurora`, `kitty`, `reef`, `clouds`.
- **Static bake** (whole scene baked, no props), in `_STATIC_BAKE`: `forest`.
- **Full-screen (unconverted):** `skybound`, `inferno` — these are pure full-screen
  animated *noise* (drifting cloudscape / rising fire) with NO discrete props to
  extract, so the plate+props split doesn't apply. They're already micro-optimized
  (sin-free hash, 4-octave fbm). The only further lever is rendering the noise at
  reduced resolution (soft noise tolerates it) — not done yet.

Per-theme: each theme's static parts (and slow drifts that are imperceptible when
frozen — e.g. clouds' fbm sheets, reef caustics, cosmos nebula, neon window blink)
are baked into the plate; dense dot/star/heart/bubble loops become particles; the
distinct animated props stay in the dynamic shader, each wrapped in a bounding-box
or band early-out so it only costs where it actually is.

### Deep Space — extra optimisation
Deep Space's dynamic shader is the heaviest (galaxies/station/asteroids/fighters).
Its `_DEEPSPACE_DYN` const recomputed each prop's position with `hash11` AND ran
`galaxyAt`/`placeAsteroid` (which call `cos`/`sin`/`fbm`) for *every* pixel — the
per-pixel transcendentals were the lag. It's now replaced at startup by
`_build_deepspace_dyn()`, which **bakes each prop's hash-derived constants in as
GLSL literals** (no per-pixel `hash11`) and **wraps every prop in a cheap
bounding-box guard** so `galaxyAt`/`shipShape`/`placeAsteroid` only run for the few
pixels the prop covers. Empty space now costs ~a texture sample + a handful of
compares. If another theme lags the same way (e.g. flocks using `flyBird`, or
Aurora's curtains), the same bake-constants-and-box-guard technique applies.

### Box-guard seams (IMPORTANT when adding/editing props)
A prop's bounding-box `if (...) return;` guard creates a faint rectangular seam
tracing the box, because the prop's edges are drawn with `aafill`/`aaline`, which
call `fwidth()` — and a screen-space derivative is **undefined** along the boundary
where neighbouring fragments in the 2x2 quad took the early `return`. (`aafill` of a
far distance with a garbage `fwidth` returns ~0.5, not 0, so the box edge lights up.)
This showed as boxes around the birds, fighters, mushrooms, etc.

Fix, applied to every guarded prop: multiply the prop's contribution by an analytic,
derivative-FREE window (`win1` per axis / `radWin` for a radius, defined in
`_SHAPES_GLSL`) that is **1 across all visible prop content** and reaches **0 just
inside a slightly-enlarged guard**, so the seam at the boundary is forced to zero.
For single-expression props multiply the alpha (`... * win`); for multi-term props
snapshot `vec3 col0 = col;` at the top of the block and `col = mix(col0, col, win);`
at the end. Keep `inner` ≥ the prop's content extent (no clipping = no quality loss)
and `outer` < the guard size (so the seam lands where the window is already 0). Also
avoid hard `step()` cutoffs on glows/rays (e.g. the fairy star's cross-rays) — use a
`smoothstep` falloff instead. Note: `place*` helpers are shared by the baked plates
too, so the seam would otherwise be baked into the static image (forest mushrooms).

### Skins
Complete-skin backgrounds (`_SKIN_SHADERS`, key `skin:<id>`) can be node themes too.
**Volcano** (`skin:inferno`) is a node theme AND a gameplay-reactive one (see Event
gestures). The scene is FOUR 3D-looking volcanoes, one in each corner (front-above
view, so each summit reads as an elliptical caldera), on a CLEAN dark-grey volcanic
plain (no ground lava). Each volcano is a detailed rock cone: normal-shaped lighting
off the silhouette (`nx`), rim light + core-shadow edges, 2-octave rock texture,
radial strata/gullies, base AO, warm crater light on the upper cone, and a caldera
(rim band + shaded bowl + hot lava pool). Shared GLSL lives in `_VOLCANO_FUNCS`
(`volcanoBody`, `placeVolcano`, `volcanoScene`, `eruptAt`):
- `_VOLCANO_STATIC` bakes the whole frozen scene via `volcanoScene` (plain + the four
  volcano bodies with their baked crater lava-pool glow) — all the fbm/SDF cost is
  paid once.
- `_VOLCANO_DYN` samples the plate, **flickers the already-baked hot (red-dominant)
  pixels** keyed off the plate colour (a cheap living-lava glow with NO fbm), then
  draws four `eruptAt` eruptions driven by a `uniform vec4 erupt` (one activity per
  volcano, apex = `center + (0, -0.80*s)`), then grades + vignettes. `eruptAt` is
  fully derivative-free (smoothstep/length) so its box guard needs no `win1` seam fix.
- `_VOLCANO_SHADER` (preview / live fallback) = `volcanoScene` + free-running auto
  eruptions, since the shop preview has no gameplay events.
- Embers + ash are particles (ash falls — note the `dir_y = +1` arg to
  `_add_particles`), tuned in `theme_props.gd`'s `skin:inferno` branch.
`skin:` for the *Aurora Borealis* skin is unrelated.

### Event gestures (kitty + volcano)
Some themes can react to gameplay events. Both the kitty and the Volcano skin do,
via the same path: `game.gd` → `BackgroundManager.notify_level_complete(level)` →
the active props node's `on_level_complete(level)`, which pushes uniforms to the dyn
shader through a BG setter. Only these two enable `_process`
(`set_process(key == "kitty" or key == "skin:inferno")`).

**Volcano** erupts on every level complete. `theme_props.gd` keeps a per-volcano
activity (`_erupt[4]`): `on_level_complete` stages a burst peak (staggered per
crater via `_erupt_delay`) — **mid (1.4)** on every level, **heavy (2.2)** at levels
5, 10 and every 3rd level after 10, **big (3.0)** on every level from 20 on. Each
frame `_process_volcano` fires any due burst, decays all four back toward a low
breathing idle, and calls `BackgroundManager.set_volcano_erupt(a0..a3)` → the dyn's
`erupt` vec4. So the scene is calm between levels and bursts on success. To retune
the tiers, edit `on_level_complete`; to retune eruption look, edit `eruptAt`.

The kitty reacts to level completion:
- `game.gd` calls `BackgroundManager.notify_level_complete(level)` when a level is
  cleared; BG forwards to the active props node's `on_level_complete()` if present.
- The kitty's eyes/mouth are driven by shader uniforms (`eye_l`, `eye_r`, `smile`)
  set via `BackgroundManager.set_kitty_eyes()`. Its `ThemeProps` runs a `_process`
  gesture controller: idle = random **two-eye blink + smile**; on level complete =
  **one-eye wink + a speech-cloud** (a real `Node2D` bubble with a `Label`, 7 random
  messages). Only the kitty enables `_process` (`set_process(key == "kitty")`).
- To add a gesture theme: give its dyn shader expression uniforms, add an
  `on_level_complete()` (and/or idle logic) in its `ThemeProps` branch, and a BG
  setter if it needs to push uniforms.

### Aurora
Aurora's curtains were ~10 four-octave `fbm`/pixel across the upper half. Now: an
inline 2-octave `anoise` for the curtain + 1-octave `gnoise` for the shimmer, plus a
per-layer `if (band < 0.004) continue;` early-out. ~15-20x less noise work.

### Adding another theme
1. Write a `_X_STATIC` plate shader (the full scene minus the moving props).
2. Add `"x": _X_STATIC` to `_NODE_THEMES`.
3. Add a `_build_x()` in `theme_props.gd` that bakes the prop art (reuse the
   theme's SDF functions) and appends mover callables.

## Debug
`DEBUG_FPS := true` in `background_manager.gd` shows a top-left readout:
`<fps> [<theme>/<mode>]` where mode is `NODES` (plate+props), `BAKED` (static
image), `FULL` (original full-screen shader), or `none`. **Set it to `false`
before shipping.**

## Known minor visual deviations (by design, to keep it cheap)
- Frozen slow drifts baked into the plate (Fairies bokeh, Deep Space nebula) —
  imperceptible at their original speeds.
- The green star's cross-rays rotate with the star (were screen-aligned).
- Galaxy "arm winding" and the station's window/spoke rotation are approximated
  by a slow rigid sprite spin; the station's docking beacons no longer blink.
- Wing flap is a 2-frame swap (fairies, birds) rather than continuous.

## Not yet validated
GLSL shader compilation and the on-device *look* of the baked sprites can't be
verified headlessly (the dummy renderer skips shader compilation). Each theme
needs an on-device pass: watch `adb logcat` for `SHADER ERROR`, confirm the FPS
label reads `NODES`, and eyeball parity with the original.
