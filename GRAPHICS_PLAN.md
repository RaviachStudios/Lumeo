# Lumeo — Graphics Redesign Plan

Branch: `graphics`. Goal: reskin the app to match the mockups (gallery JPEGs the
user provided ~2026-06-13) using **only Godot-native, text-authorable assets**
(no external/source PNGs): procedural meshes, PBR materials, lights, glow
environments, `.gdshader` shaders, and hand-authored `.svg` icons.

## Confirmed decisions
- **Variable button counts stay.** The wheel mesh is generated procedurally from
  `num_buttons` (GameState.num_colors), so it adapts to 4/5/6 segments. Do NOT
  hard-code a 5-segment wheel.
- **No avatars** in the leaderboard. Ignore the avatar thumbnails shown in the
  leaderboard mockup. (Avatars would need per-user backend data anyway.)
- I author blind, then iterate via run + screenshot. No guarantee of pixel-perfect
  photorealism; target is a high-quality glossy/neon look.

## Capability notes / constraints
- I cannot sculpt in the Godot GUI. I build 3D by writing `.tscn`/mesh/material/
  shader files and tuning numerically across run+screenshot iterations.
- Icons: no asset library available → author clean **SVG** icons as text
  (leaf, flame, chart, trophy, eye, hand, refresh, crown, play, gear).
- Glassmorphism blur, gradient text, bloom: all done with shaders / WorldEnvironment.

## The 3D wheel — approach
1. Geometry generated procedurally (`ArrayMesh`/`SurfaceTool`): ring of beveled
   wedge segments + center hub, count = `num_buttons`.
2. `StandardMaterial3D` per segment: metallic/roughness (+clearcoat) for gloss,
   plus an emission channel driven for the light-up.
3. `OmniLight3D`(s) + `WorldEnvironment` with glow/bloom (HDR) for the neon halo.
4. Rendered through a `SubViewport`, displayed as a texture inside the existing
   2D game screen (game.gd). Light a button = raise that segment's
   `emission_energy`. Keep existing radial hit-testing (`_get_button_at`) or switch
   to a 3D raycast.
5. Android cost mitigations: modest viewport resolution, low MSAA, fallback to
   baking the wheel to images if low-end devices struggle.

## Phases
- **Phase 0 (IN PROGRESS): de-risk the wheel + shared visual kit.**
  Procedural 3D wheel scene + SubViewport wired into game.gd, light-up/glow
  working on screen. In parallel set up reusable kit: color palette, glow
  WorldEnvironment, reusable glass-panel scene, gradient-text shader.
- **Phase 1: Home.** Gradient LUMEO logo, elliptical orbital ring with animated
  glowing orbs, glass buttons + icon badges, profile/settings chips.
- **Phase 2: Difficulty + How-to-play.** Glass cards, leaf/chart/flame +
  eye/hand/refresh icons, gradient titles.
- **Phase 3: Leaderboards.** Tabs, rank rows, crown + laurel, score chips.
  (No avatars.)
- **Phase 4: Polish & perf.** Orbit animations, transitions, press feedback,
  real-device performance pass, APK-size check.

Each phase ends with run + screenshot vs mockup, then iterate.

## Current code starting points (pre-redesign)
- All screens drawn procedurally via `_draw()` + `StyleBoxFlat`; no UI assets yet.
- `game.gd`: wheel via `draw_colored_polygon` arcs; `BUTTON_COLORS` has 6 entries;
  `_get_button_at` does radial angle hit-testing; `_lit[]`/`_press_anim[]` drive
  visuals; `num_buttons = GameState.num_colors`.
- Screens are independent scripts swapped by `game_manager.gd` (`_swap`), so each
  can be restyled without touching game logic.
</content>
