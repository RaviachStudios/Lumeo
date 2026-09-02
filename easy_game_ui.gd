extends MemoryGameUI
class_name EasyGameUI

# The EASY gameplay device: the three-button physical game board authored in
# Blender and exported as res://models/MemoryGame_UI_Easy.glb.
#
# It replaces the procedural four-colour SimonWheel, which is what easy played on
# until now. There is no wheel on this difficulty any more: no four coloured
# sectors, no circular board, no centre hub. Easy uses the same physical
# button language as Moderate and Hard, because it is now literally the same
# device class.
#
# This is MemoryGameUI (the Medium board) with a different board spec and nothing
# else — the same relationship hard_game_ui.gd has to it. All three GLBs are built
# identically: `Button_<Colour>` parents holding a `_Frame` and a `_Surface` mesh,
# one `Press_<Colour>` clip per button that sinks only that surface, the metal on
# frame surface 0 with the under-glow on surface 1, the coloured top on surface 0
# of the surface mesh with its bright rim on surface 1. The buttons are
# dimensionally identical across the three boards, vertex for vertex (frame radius
# 1.0, top at y = 0.525, press travel 0.115, 2785/769/2594/384 verts), which is
# why the Area3D shape, the emission state machine, the ground pools, the camera
# fitting, the render-on-demand cadence and the shop's frame cosmetics all carry
# over with no per-board special-casing whatsoever.
#
# What differs is only what this file overrides:
#   * the GLB and its three colour keys,
#   * the spacing, which this board does not need (see below),
#   * the camera, fitted to THIS board's own Blender reference,
#   * the round readout, which is the parent's 2D pill rather than a plate.
#
# Gameplay is entirely game.gd's, unchanged. Easy's sequence generation, timing,
# round progression, scoring and win/loss never enter this file — it receives
# set_lit / set_press / set_level and answers segment_at_point, exactly as
# SimonWheel did, through the identical API.

const EASY_MODEL: PackedScene = preload("res://models/MemoryGame_UI_Easy.glb")

# Button index -> the GLB's colour key. Three buttons, so three indices, and
# game.gd's sequence generator (`randi() % num_buttons`) hands out 0..2 unchanged.
#
# The order is the board's own left-to-right, back-to-front reading and the order
# the colours are named everywhere this device is described: Cyan, Yellow,
# Magenta. Being the first three indices, they keep the first three of
# AudioManager's per-index tones — the same three notes easy's first three wheel
# segments have always sounded.
const EASY_KEYS := ["Cyan", "Yellow", "Magenta"]

# ---------------------------------------------------------------------------
# Spacing
# ---------------------------------------------------------------------------
# The other two boards are authored 2.15 apart centre-to-centre for a frame
# DIAMETER of 2.0 — a 0.15 gap, which reads as discs crowding each other — and the
# parent pushes their button parents out by 32% to open it to 0.84.
#
# This board is authored 2.4501 apart on all three edges: a 0.45 gap, which is
# where the other two USED to stop. 15% takes it to 0.82, which is where they stop
# now — so the three difficulties open to the same clear space between neighbours,
# from three different authored starts. That is the whole reason this number is not
# 1.0 any more: it was left alone while 0.45 was the target and the target moved.
#
# The cost is the same one Medium and Hard pay (see MemoryGameUI.SPACING_SCALE):
# the board's span is wider, the fit frames the span, so each button loses about
# 8 % of its on-screen width. On a three-button board those are still the biggest
# buttons in the game.
const EASY_SPACING := 1.15

# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------
# Fitted to this board's own reference render (EasyV3/MemoryGame_UI_Easy_idle.png)
# rather than copied from Medium or Hard. Three buttons give only three centroids,
# which is not enough to pin a pose and a lens, so the fit solves against each
# button's white rim ELLIPSE as well — its full projected envelope (left, right,
# top, bottom) at the authored ring radius. Twelve measurements, six unknowns
# (elevation, field, distance, two target coordinates and the ring radius), and it
# lands at 0.38 px RMS.
#
# The solve is self-checking twice over. The ring radius it recovers, 0.6584, is
# the radius the GLB actually authors that ring at (0.662) to within 0.6%, which
# nothing in the fit forced it to be. And putting Godot's own camera back at this
# pose reprojects the three rims onto the reference's pixels at 1.08 px RMS
# (tools/egui_shot.gd measures exactly that) — the residual being that same 0.6%,
# since the harness projects the authored 0.662 rather than the fitted radius.
#
# Match the ENVELOPE of each rim, never its centroid: a ring seen in perspective
# projects with its near half larger, so the mean of its pixels sits 14-23 px
# nearer the camera than its centre does. Fitting centroids to centres bakes that
# bias straight into the elevation.
#
# Elevation 33.44 deg sits between Hard's 33.51 and Medium's 33.86, and the field
# is within 0.6 deg of Hard's — the three boards really are the same tabletop seen
# the same way, which is the point. High enough to show the frame thickness, the
# raised surface and the gap between them; low enough that the two back buttons
# read clearly higher and further away than the near one. Nothing is top-down and
# nothing is orthographic.
const EASY_CAM_FOV := 44.00                      # horizontal, with KEEP_WIDTH
const EASY_CAM_ELEV_DEG := 33.44
# The fitted pose, re-expressed about a pivot on the button-top plane so the
# numbers read naturally. It is the same camera position the solve produced,
# (0, 4.456, 6.974) — only the look-at point along the ray was moved.
const EASY_CAM_TARGET := Vector3(0.0, 0.26, 0.62)
const EASY_CAM_DIST_START := 7.61

# Only three buttons have to share the frame, so they get to be big — this is the
# difficulty where they should feel most tactile, and the near one ends up 711 px
# across at 1920. Height is what binds, and these two numbers are really "the
# vertical band the board gets", measured off game.gd's own HUD rather than
# guessed:
#
#   * the watch-ad pill along the top ends 9.4% down, and this board's back edge
#     is its widest part — the two rear buttons reach further into the top-left
#     corner than a pentagon's or a hexagon's back vertex does;
#   * the status pill starts 88.3% down, and this board's near button is dead
#     centre at the FRONT, right above it (the other two boards leave their bottom
#     centre open, through the pentagon's open front and the hexagon's flat one).
#
# The bottom of that band is now spent rather than reserved: the status pill sits
# in FRONT of the near button's black frame (see memory_game_ui.gd), so only the
# pill's own row below 94% is off limits and no coloured face ever goes behind it
# — 120 px clear at every aspect. The top is a hard stop, though, and it is what
# caps this board: 0.84 centred at 52.0% puts the back rims 4 px under the watch-ad
# pill's row, and anything bigger walks into it. Against the old 0.75/48.9% that is
# ~9% on every button and ~22 px lower down the screen. Nothing is ever cropped at
# any aspect — the fit is re-run on every resize, and the HUD rects are fractions,
# so the clearance scales with it.
const EASY_FIT_FILL_X := 0.90
const EASY_FIT_FILL_Y := 0.84
const EASY_FIT_CENTRE_Y := 0.520

# The board spec. Everything not named here stays exactly as MemoryGameUI has it.
# The Jade darkening is inherited and is simply inert: this board has no Jade
# button, so _recolour_jade finds nothing and returns. There is no Jade/Cyan
# two-teals problem to correct here in any case — cyan, yellow and magenta are as
# far apart as three hues get.
func _init() -> void:
	_model = EASY_MODEL
	_keys = EASY_KEYS
	_count = EASY_KEYS.size()
	_spacing = EASY_SPACING
	_cam_fov = EASY_CAM_FOV
	_cam_elev = EASY_CAM_ELEV_DEG
	_cam_target = EASY_CAM_TARGET
	_cam_dist_start = EASY_CAM_DIST_START
	_fit_fill_x = EASY_FIT_FILL_X
	_fit_fill_y = EASY_FIT_FILL_Y
	_fit_centre_y = EASY_FIT_CENTRE_Y
	# Nothing board-side for the level number: it is the parent's right-edge LEVEL
	# tab (level_tab.gd), the same readout in the same place on all three
	# difficulties. The empty middle of the triangle stays empty — the old wheel's
	# centre hub is not coming back in any form.
