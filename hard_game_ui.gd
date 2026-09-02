extends MemoryGameUI
class_name HardGameUI

# The HARD gameplay device: the six-button physical game board authored in
# Blender and exported as res://models/MemoryGame_UI_Hard.glb.
#
# This is MemoryGameUI (the Medium board) with a different board spec and nothing
# else. The two GLBs are built the same way — `Button_<Colour>` parents holding a
# `_Frame` and a `_Surface` mesh, a `Press_<Colour>` clip per button that sinks
# only that surface, the metal on frame surface 0 with the under-glow on surface 1,
# the coloured top on surface 0 of the surface mesh with its bright rim on 1 — and
# the buttons are dimensionally identical (frame radius 1.0, top at y = 0.525,
# press travel 0.115). So every behaviour the parent implements applies here
# untouched: the spacing, the emission state machine, the per-button Area3D
# hit-testing, the ground pools, the camera fitting, the render-on-demand cadence
# and the shop's button-frame cosmetics.
#
# What differs is only what this file overrides:
#   * the GLB and its six colour keys,
#   * the camera, refitted to THIS board's Blender reference,
#   * the round readout, which is a 2D HUD pill instead of a plate on the board.
#
# Gameplay is entirely game.gd's, unchanged. Hard's difficulty, sequence
# generation, scoring, win/loss and round progression never enter this file — it
# receives set_lit / set_press / set_level and answers segment_at_point, exactly
# as SimonWheel did.

const HARD_MODEL: PackedScene = preload("res://models/MemoryGame_UI_Hard.glb")

# Button index -> the GLB's colour key, in game.gd's BUTTON_COLORS order
# (Red, Green, Blue, Yellow, Orange, Pink) so AudioManager.play_button_tone keeps
# the per-index tones Hard has always had. The first five match the Medium board's
# order exactly, so a colour means the same thing on both difficulties.
const HARD_KEYS := ["Crimson", "Jade", "Cyan", "Amber", "Violet", "Magenta"]

# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------
# Fitted to this board's own reference render (HardV3/MemoryGame_UI_Hard_idle.png)
# rather than inherited from Medium's: solving the six measured button centroids
# in the 1920x1080 render for camera pose and lens lands on elevation 33.5 deg and
# a 43.4 deg horizontal field, to 0.75 px RMS. The field is well determined —
# refitting with it pinned at 40 or 48 deg cannot do better than 3-4 px.
#
# The elevation is within half a degree of Medium's, which is what makes the two
# difficulties feel like the same tabletop seen the same way: the far side of the
# hexagon reads higher and further, the near side lower and closer, and the frame
# thickness and the gap under each raised surface stay visible. Nothing is
# top-down and nothing is orthographic.
const HARD_CAM_FOV := 43.44                      # horizontal, with KEEP_WIDTH
const HARD_CAM_ELEV_DEG := 33.51
const HARD_CAM_TARGET := Vector3(0.0, 0.35, 0.54)
const HARD_CAM_DIST_START := 10.04               # the reference's own distance

# The hexagon is wider than it is deep on screen and it has no flat back edge to
# hang anything off, so it takes the frame it can get: full width, and the tallest
# vertical band the HUD leaves it. Height is what binds here at every shipping
# aspect, so these numbers are really "the vertical band the board gets": 3.7%
# clear of the top edge — enough for a device's own furniture — down to 6.3% of
# the bottom one, seated 3.7% below screen centre so the near buttons come up to
# the player.
#
# Same band as Medium's, and for the same reason (see memory_game_ui.gd): the
# bottom of it is spent on the row game.gd's status pill occupies, which the pill
# now shares by sitting in front of the near button's black frame. It never covers
# a coloured face — 75+ px clear at every aspect. Nothing is ever cropped at any
# aspect either; the fit is re-run on every resize.
const HARD_FIT_FILL_X := 0.96
const HARD_FIT_FILL_Y := 0.90
const HARD_FIT_CENTRE_Y := 0.487

# ---------------------------------------------------------------------------
# Round readout
# ---------------------------------------------------------------------------
# Nothing board-side. The level number is the parent's right-edge LEVEL tab
# (level_tab.gd), the same readout in the same place on all three difficulties.
# It used to be a plate lying on the board here — a hexagon has no flat back edge
# to hang one off, and paying for one in the camera fit cost ~15% of every
# button's on-screen size, so this board never had one and now nothing does.

# The board spec. Everything not named here stays exactly as MemoryGameUI has it —
# including SPACING_SCALE (this board is authored at the same 2.15 centre-to-centre
# as Medium's, so the same 32% push opens the same 0.84 gap between frames) and the
# Jade darkening (Jade and Cyan are authored the same two-teals-apart here as they
# were there, and keeping the same correction keeps green the same green on both
# difficulties).
func _init() -> void:
	_model = HARD_MODEL
	_keys = HARD_KEYS
	_count = HARD_KEYS.size()
	_cam_fov = HARD_CAM_FOV
	_cam_elev = HARD_CAM_ELEV_DEG
	_cam_target = HARD_CAM_TARGET
	_cam_dist_start = HARD_CAM_DIST_START
	_fit_fill_x = HARD_FIT_FILL_X
	_fit_fill_y = HARD_FIT_FILL_Y
	_fit_centre_y = HARD_FIT_CENTRE_Y
