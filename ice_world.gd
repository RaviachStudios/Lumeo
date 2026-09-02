extends Node3D
class_name IceWorld

# ICE KINGDOM — the gameplay background the snowflake buttons stand on.
#
# It is the second background with no asset behind it at all (the first is the
# Magical Lake): no .blend, no .glb, no image — a plane, a shader and a scatter of
# generated props. BackgroundScenes stays the single façade for every kind, and
# nothing outside it has to know which kind an id is.
#
# ---------------------------------------------------------------------------
# Why it replaced an imported world
# ---------------------------------------------------------------------------
# `world_ice` used to be one of the two Themes2 worlds — an island of blue crystal
# built in Blender and imported through world_scenes.gd (the .glb is still on disk
# and still buildable; see the note left in that file). It was a good picture and
# the wrong picture for this game:
#
#   * COLUMNS OF CRYSTAL down both sides of the frame, at nearly full saturation
#     and brighter than anything on the board;
#   * WHITE CRACK LINES across the deck, running under and between the buttons at
#     something close to maximum contrast;
#   * a strong vignette that put the darkest part of the picture exactly where the
#     six snowflakes are.
#
# The snowflakes ([[ice_buttons.gd]]) render at a mean of about 160-190 counts, and
# they are the thing the player has to read, in a game whose entire subject is
# telling six colours apart at speed. A background that is brighter, more saturated
# and busier than they are does not "compete with the buttons" as a matter of taste
# — it takes the picture's contrast budget and spends it somewhere else.
#
# So this one is built to a single rule, and every number below is answerable to it:
#
#     NOTHING IN THE BACKGROUND MAY BE BRIGHTER, MORE SATURATED OR BUSIER THAN A
#     BUTTON, AND THE MIDDLE OF THE FRAME IS THE QUIETEST PART OF IT.
#
# Which is the opposite arrangement to the one it replaced: the play area is now
# the LIGHTEST part of the surface, everything else falls away from it, and the
# only high-frequency detail in the frame lives out in the gutters where no button
# ever is. Measured again after the sky and the milestones, on all three boards:
# background mean 46-53 % of a button and peak 80-100 %, against 51-66 / 74-93 after
# the environment pass and 63-67 / 88-91 before it.
#
# The PEAK figure needs its footnote, because it is the one number that got worse.
# A button's own mean fell about a tenth when the board was re-seated for the
# horizon (FRAME_BIAS makes it 7 % smaller and therefore further away), so the same
# background measures higher against it. The absolute peak came DOWN — 128 counts
# before the sky, 120 after it — and finding that number cost five separate palette
# edits aimed at four different props before ice_shot was taught to print the
# peak's rgb. Read that line, not the picture, if it ever goes over again.
#
# There is a great deal more IN the picture — a night sky, a moon, stars, two
# mountain ranges and an aurora that were not there at all — and the mean came
# DOWN. That is not luck: the sky is the darkest region in the frame by design (see
# SKY_TOP), because the alternative arrangement, a bright band across the top of a
# picture whose subject is at the bottom of it, moves the eye off the board every
# time the aurora breathes.
#
# The peak is a SPARKLE and has been every time it has been measured — see the note
# beside them in the ice shader before spending an edit on anything else.
#
# ---------------------------------------------------------------------------
# What it is
# ---------------------------------------------------------------------------
# A frozen lake under a night sky, seen from just above the ice:
#
#   * A SKY, which is the thing it did not have and the reason it read as a
#     placeholder however much was scattered on the ground. This camera cannot see
#     a horizon (see HORIZON_FY), so one is MADE: the ice discards itself on a
#     screen line and behind that line stands one flat card carrying a deep
#     blue-violet gradient, sparse stars, a soft moon, two procedural mountain
#     ranges, a cloud band along their feet and TWO AURORA CURTAINS that are almost
#     still for eight seconds in every eleven and then swell for three.
#
#   * a sheet of ice at y = 0, which the buttons stand on and the board's own
#     coloured light pools land on — and which REFLECTS the sky, because a frozen
#     lake at night that does not is a blue floor. The reflection is the same
#     `sky_at` the card above it compiles, called with its vertical coordinate
#     mirrored, and it brings the aurora, the crests and the moon down onto the
#     surface the game is played on;
#   * the MOON'S PATH: a column of broken glitter under the moon, which is the one
#     highlight this background has and the most recognisable thing about its
#     subject;
#   * swept bands, pressure ridges and cracks in the surface — the first of those is
#     the only detail term with no mask on it, and the reason is in its note;
#   * a soft pale bloom under the play area, so the board rests ON something;
#   * cracks, frost grain, layered ice bands and a scatter of tiny sparkles in the
#     surface, all masked OUT of the play area and fading in only past the outermost
#     button;
#   * ice formations — low crystal clusters and frozen plates — placed through the
#     CAMERA into the frame's gutters, never in the middle;
#   * frost-capped rocks in the corners and the near gutters, the one thing out here
#     that is not made of ice;
#   * a broken ICE WALL along the far edge of the visible ground, spanning the whole
#     width of the frame — what gives the picture a back;
#   * snow drifting down through the frame, a third of it slower and turning: those
#     are floating ice crystals rather than snow;
#   * mist banks crawling over the far ice and the side gutters;
#   * and a fog that swallows all of it before the horizon, so the ice arrives at
#     the sky's own bottom colour and the join between them cannot be seen.
#
# And TWO MILESTONE EVENTS, which are the only times this background is allowed to
# be the thing the player is looking at (see THE MILESTONE EVENTS):
#
#   * every THIRD completed level, a ring of crystals grows out of the ice around
#     the outer edges of the frame, glows, and shatters into snow. ~1.35 s.
#   * every EIGHTH, the aurora swells, the ground cools, a reindeer pulls a sleigh
#     across the top of the sky and a light sweep crosses the ice. ~4.85 s.
#
# Both freeze the round for their whole duration — they return the seconds to
# game.gd, which is the entire contract — and both leave nothing behind.
#
# The last four of those were added after a pass that found the first version too
# empty. The two things that made it empty are worth knowing before adding anything
# else out here, because neither is a matter of quantity:
#
#   * A SCATTER CANNOT FILL THIS FRAME. _frame_point samples the world and keeps
#     what lands in shot, which is the right tool for a scatter and cannot produce a
#     wall across the top of the picture: the far band it draws from projects into
#     the two upper corners and nowhere else, so sixteen crystal clusters rendered as
#     two little heaps. Anything that has to COVER a part of the frame is placed from
#     the frame instead (_screen_point, _ice_at_screen).
#   * MOST OF THE DETAIL COSTS NOTHING TO DRAW. The frost streaks, the layered bands,
#     the sparkles and the mist are terms in the sheet's own fragment shader, and the
#     two new prop types are MultiMeshes of one mesh each. Measured before and after:
#     +1.54 ms/frame became +1.43.
#
# ---------------------------------------------------------------------------
# Everything is unshaded, and the palette is authored on SCREEN
# ---------------------------------------------------------------------------
# Both for the same reasons the lake is (see lake_world.gd's header, which paid for
# them): the board's Environment is a dark studio with a bright ProceduralSky as its
# reflection source and AgX at tonemap_exposure 0.40, neither of which is ours to
# move; a lit material in that room mirrors the sky and comes out grey; and AgX at
# that exposure is nothing like a gamma curve, so a colour "chosen in linear" lands
# nowhere near the screen colour it was meant to be.
#
# So every surface here computes its own shading and writes the result out, and
# every colour below is written as the sRGB the player is meant to SEE and
# converted once, at build time, by `tone`.

# The visual layer a background occupies. Declared again rather than imported so the
# dependency between the modules stays strictly one-way (BackgroundScenes -> here).
const BG_LAYER := 2

# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------
# The id is unchanged from the imported world this replaces, and that is deliberate:
# it is what saved wallets, `selected_theme`, the SPECIAL SKINS shelf and
# ice_buttons.gd's THEME_ID all contain. A player who owned Ice Kingdom yesterday
# owns it today and gets the new ground under the same snowflakes.
const CATALOG := {
	"world_ice": {"name": "Ice Kingdom"},
}

const ORDER := ["world_ice"]

# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------
# The board's SubViewport does not redraw while nothing is moving, so an animated
# background is nudged at this rate instead (MemoryGameUI._tick_bg_idle).
#
# 15, not the lake's 30. Everything that moves here moves SLOWLY — snow falling at
# 12 cm/s and a polish that drifts across the ice over half a minute — and the rate
# only has to beat the fastest thing in the frame. The imported world it replaces
# shipped STILL (no redraw at all), so this is a real cost that did not exist
# before; it is the price of the snow, and it is charged at the floors' rate rather
# than the lake's.
const IDLE_HZ := 15.0

# ---------------------------------------------------------------------------
# Measured inverse of the board's tone curve
# ---------------------------------------------------------------------------
# Linear radiance for screen counts 0, 4, 8 ... 256, through AgX at
# tonemap_exposure 0.40.
#
# THIS IS THE SAME TABLE AS LakeWorld.TONE_RAMP AND MUST STAY THE SAME. It is not a
# property of either background — it is a property of the BOARD's Environment, which
# both of them are rendered through — and it is measured, not modelled, by
# tools/lake_tone.tscn. It is copied rather than shared because these two are
# siblings and neither should depend on the other; if a third generated background
# ever appears, that is the point at which this and the placement helpers at the
# bottom of this file should be lifted into a module both can use.
# tools/ice_verify.tscn asserts the two tables are identical, so the copy cannot
# quietly drift.
const TONE_RAMP: Array = [
	0.00000, 0.10043, 0.12500, 0.14464, 0.16736, 0.18900, 0.20832, 0.22960,
	0.25306, 0.27387, 0.29460, 0.31690, 0.33718, 0.35744, 0.37801, 0.39685,
	0.41663, 0.43740, 0.45920, 0.47958, 0.50000, 0.52129, 0.54277, 0.56294,
	0.58386, 0.60555, 0.62741, 0.64809, 0.66945, 0.69152, 0.71431, 0.73785,
	0.76217, 0.78729, 0.81324, 0.84004, 0.86773, 0.89633, 0.92587, 0.95639,
	0.98791, 1.02047, 1.05625, 1.09549, 1.13620, 1.17841, 1.22219, 1.26760,
	1.31813, 1.37425, 1.43276, 1.49376, 1.56821, 1.64638, 1.72844, 1.83234,
	1.94247, 2.07431, 2.23132, 2.40021, 2.61347, 2.95141, 3.33305, 3.85670,
	4.46263,
]


# The linear radiance that this Environment turns into `c` on screen. Per channel,
# by lerping the measured ramp — the curve has a toe and a shoulder that are not one
# power law.
static func tone(c: Color) -> Vector3:
	return Vector3(_tone1(c.r), _tone1(c.g), _tone1(c.b))


static func _tone1(v: float) -> float:
	var x := clampf(v, 0.0, 1.0) * 255.0 / 4.0
	var i := int(floor(x))
	if i >= TONE_RAMP.size() - 1:
		return float(TONE_RAMP[TONE_RAMP.size() - 1])
	return lerpf(float(TONE_RAMP[i]), float(TONE_RAMP[i + 1]), x - float(i))


# ---------------------------------------------------------------------------
# Palette, as sRGB on screen
# ---------------------------------------------------------------------------
# The whole background lives between screen 14 and screen 96, and the two colours
# that go above that (SHEEN and SNOW) are used at a few per cent. For comparison,
# the six snowflakes render at 160-190 and their frost sockets higher still: the
# brightest thing the ice ever does is about half as bright as the dimmest part of
# a button.
#
# It is also a NARROW palette on purpose — five blues, one of them barely violet.
# A restrained hue range is what makes six saturated buttons read as the only
# colours in the picture.
#
# WHAT THE RANGE IS SPENT ON CHANGED after the sky arrived. Everything used to sit
# between screen 40 and 95, which is the definition of a flat image and was most of
# what "it looks cheap" meant — a picture can have a great deal of detail in it and
# still read as a poster if it has no tone. The rule forbids buying range at the
# bright end, so it is bought at the dark end instead (see VIG_GAIN): the sky is now
# the DARKEST region in the frame, the gutters fall away toward HAZE, and the play
# area is left alone and becomes the lightest thing in the picture by contrast.

# The ice inside the arena: the LIGHTEST large area in the frame by a wide margin,
# and that is the arena's whole proposition. It went up when the shore arrived, and
# the reference is why:
#
#     reference rink, middle        L 168      reference snowflakes  L 122-167
#     reference rink, by the flakes L 145      reference banks       L  40- 82
#
# Its ice is BRIGHTER than its flakes. This one is not — the buttons have to stay
# the strongest thing on screen, which is a harder constraint than the picture it
# is copying accepted — but the RATIO is the reference's: a rink about two and a
# half times its bank, falling away to its own shore, with everything outside it
# darker still. Bright is not the same as busy, and this is the flattest, most
# even, least detailed large area in the frame.
const NEAR := Color8(62, 102, 140)
# ...deepening away from the play area, out to the sides and into the distance.
const MID := Color8(26, 54, 92)
# ...and dissolving into this, which is also what the 2D layer behind the board is
# cleared to, so the surface has no edge anywhere (the lesson lume_worlds.gd paid
# for twice: an edge inside the frame is a line across the picture).
const HAZE := Color8(13, 28, 52)
# What the polished surface mirrors: the pale cold light above it. Used through a
# fresnel and a tight specular, never as an area colour — this is the only value in
# the palette that would be too bright if it were.
const SHEEN := Color8(150, 200, 230)
# Frost: the bloom under the board, the crack lines, the frozen plates. Soft cyan.
const FROST := Color8(116, 176, 208)
# The one colour ice does not have, and the brief allows: a very faint violet in the
# mid-distance, at a tenth of the strength of anything else.
const AURORA := Color8(74, 66, 132)

# The crystal formations in the gutters: base (in shadow, nearly the ice's own
# colour, so they grow OUT of the surface instead of being placed on it) and tip.
# ...and SHARD_HI is what a facet pointing straight at the key light comes out as,
# which since the crystals were rebuilt with real facets is a value that actually
# gets REACHED — the cone this replaced never presented a face to the light, so the
# same number used to be a ceiling nothing touched. It came down when the peak
# measurement started landing on a crystal tip.
const SHARD_LO := Color8(26, 56, 90)
const SHARD_HI := Color8(90, 134, 168)
# The SNOW BANKS outside the arena's shore, and their lit lip. These are the three
# largest new areas in the picture and their values were MEASURED off the reference
# rather than chosen, because the thing that makes that image read as bright snow
# is not the snow:
#
#     reference ice inside the rink   L 145-168
#     reference snow banks around it  L  40- 82
#     reference sky                   L  20
#     reference snowflakes            L 122-167
#
# The banks are the DARKEST large region in that picture after the sky. They read
# as snow because they are a deep saturated blue carrying a few small bright
# accents — a lit crest, a crystal, a rim — against a rink that is twice their
# brightness, and not because there is any white in them. Which is the same
# arrangement this file has always been built to, arrived at from the other end:
# the rink is the lightest thing in the frame and everything around it falls away.
const BANK_LO := Color8(25, 43, 75)
const BANK_HI := Color8(58, 84, 120)
# The shore lip: the crest of the bank where it meets the ice and the light catches
# it. A thin band, and the only highlight the background carries outside a sparkle.
const LIP := Color8(120, 160, 194)
# The berm heaped along the shoreline: its shaded face, its lit face and the crest
# where the snow catches the light.
#
# All three came down about a tenth when the board was RE-FRAMED for the HUD's
# lanes (game.gd, MemoryGameUI's THE BAND). Nothing about the palette was wrong —
# what changed is how much of the picture each colour is responsible for. The board
# used to sit low with its near edge off the bottom of the screen, so the rink
# filled the frame and the bank was a border; framed fully inside the viewport the
# rink is smaller and the bank is most of the picture, and the same values measured
# 59-61 % of a button where they had measured 54-56. A palette is answerable to the
# AREA it covers, not only to itself. The crest is the brightest colour in the whole
# background and it is spent on about two per cent of the frame — a line of drift
# tops right round the arena — which is the one place this picture can afford one,
# because it is the shape that says where the game is played.
const BERM_LO := Color8(30, 50, 84)
const BERM_HI := Color8(58, 84, 122)
const BERM_CREST := Color8(88, 118, 154)
# What a violet crystal is: a MULTIPLIER on the blue ramp above, not a colour of
# its own, so the tinted quarter is lit by the same facet term and can never come
# out brighter than the crystal beside it. More red and less green — which on a
# blue is the whole distance from ice to amethyst.
const SHARD_TINT := Color(1.30, 0.82, 1.16)
# ...and the light the lit ones carry. A cold cyan-white, and the ONE colour in
# this file that is chosen to be seen rather than to recede.
const SHARD_GLOW := Color8(96, 186, 208)
# How strong it is at a crystal's tip. This is the number to move if the frame's
# peak measurement ever lands on a crystal again — and after the board was
# re-framed for the HUD's lanes it did exactly that (the bank grew, the berm crest
# came down with it, and a lit crystal became the brightest thing left), which is
# what took this from 0.36 to 0.29 — see the note beside it in the
# shader, and read tools/ice_shot.tscn's peak rgb before assuming it has.
const SHARD_GLOW_GAIN := 0.29
# The frozen plates lying flat out there: middle and rim.
const PLATE_LO := Color8(34, 70, 108)
const PLATE_HI := Color8(78, 132, 170)
# The ice walls standing along the far edge of the visible ground: base and crest.
# Darker than the crystals at both ends, because they are the FURTHEST thing in the
# picture and a distant wall that is lighter than the ice in front of it reads as a
# hole rather than as a form.
const RIDGE_LO := Color8(20, 44, 74)
const RIDGE_HI := Color8(66, 108, 146)
# ...and the snow lying along their tops. The wall runs right across the frame at
# the far edge of the bank, so a bare blue slab there is the one place the eye can
# see that the snow stops and something else starts. Kept below the bank's own
# crest value: it is the furthest thing in the picture and stands in fog.
const RIDGE_CAP := Color8(78, 112, 148)
const RIDGE_CAP_GAIN := 0.62
# Frozen rocks: the one thing out here that is not made of ice. Two dark slates and
# the frost that has settled on their tops — they are the only prop that spends its
# contrast DOWNWARD, which is exactly why they can carry detail without taking any
# of the brightness budget the buttons need.
const ROCK_LO := Color8(42, 64, 90)
const ROCK_HI := Color8(76, 106, 134)
const ROCK_CAP := Color8(112, 160, 192)
# Snow — and it is the FRAME'S BRIGHTEST PIXEL now, which it never was before the
# sky existed. A flake used to be a pale dot on ice at screen 60-90; against a night
# sky at screen 20 it is the highest-contrast thing in the picture, and
# tools/ice_shot.tscn's peak measurement landed on one the moment the board was
# seated low enough to show sky behind the falling snow.
#
# So it comes DOWN. It is still the palest colour in the file after the sheen, and
# at this value a flake crossing a lit snowflake is still a suggestion of one.
const SNOW := Color8(158, 190, 214)
# The mist banks drifting over the far ice. A pale cold grey-blue: it has to be
# LIGHTER than the deep ice it lies on or it reads as a stain, and darker than the
# sheen or it becomes the brightest area in the frame.
const MIST := Color8(48, 84, 118)

# --- the sky, and everything standing on the horizon ------------------------
# All of these are new with the sky (see THE SKY below) and all of them are DARKER
# than the ice they sit above, which is the opposite of how a photograph of a
# frozen lake at night is exposed and the only arrangement that works here: the
# player is looking at the bottom two thirds of the frame, and a bright band across
# the top pulls the eye off the board every time the aurora moves.
#
# Deep blue-violet at the top of the picture, easing to a colder blue where the
# mountains stand. The top value is the darkest colour in the file — darker than
# HAZE — so the sky reads as the far end of the same night the ice is lit by.
const SKY_TOP := Color8(17, 20, 52)
const SKY_LOW := Color8(27, 44, 80)
# Stars. Deliberately dim, and dimmer again since the sky arrived: a star is one or
# two pixels ADDED to a near-black sky, and additive light on a dark base moves a
# long way through the tone curve — tools/ice_shot.tscn's "brightest pixel in the
# frame" landed on a star twice, at two different authored values, before this one.
# At 48 counts on a 20-count sky they are still a threefold contrast, which is all a
# star needs to read as one.
const STAR := Color8(37, 47, 67)
# The moon, and the halo around it. The core is the single brightest pixel this
# background is allowed and it is pitched at the ice's own peak, not above it — a
# "soft moon" is not a stylistic note here, it is the measurement.
const MOON_CORE := Color8(72, 91, 118)
const MOON_HALO := Color8(31, 47, 76)
# THREE mountain ranges, back to front, and the snow all three carry. Each is
# darker and more solid than the one behind it, which is the whole of the depth up
# there: one range is a silhouette, two is a distance, three is a country.
const RANGE_FAR := Color8(36, 54, 92)
const RANGE_MID := Color8(28, 45, 79)
const RANGE_NEAR := Color8(16, 29, 56)
const RANGE_CAP := Color8(92, 128, 164)
# The aurora's two ends. It is mixed across its own width from the cyan to the
# violet, so one curtain carries the whole turquoise-to-purple range the brief asks
# for without needing three of them.
const AUR_CYAN := Color8(48, 140, 144)
const AUR_VIOLET := Color8(96, 68, 150)

# --- the two milestone events ----------------------------------------------
# These are the ONLY colours in this file that are allowed near a button's own
# brightness, and the exemption is narrow and deliberate: they are on screen for
# 1.3 s every third level and 4.9 s every eighth, the round is frozen for all of
# it, and nothing is being memorised while they run. The rule the rest of the file
# is answerable to — measured by tools/ice_shot.tscn — is a rule about the IDLE
# frame, which is the frame the player actually plays on.
#
# The light inside a growing crystal, and the powder it bursts into (SNOW).
const GLOW := Color8(120, 220, 236)
# The reindeer and the sleigh, as a flat relief against the night sky: a mid body,
# a pale icy rim on every edge of it, and a colder blue for the sleigh's hull. The
# rim is the drawing — at 190 px across, a silhouette is read by its outline.
const TEAM_HIDE := Color8(102, 140, 176)
const TEAM_LIGHT := Color8(176, 214, 236)
const TEAM_SLED := Color8(78, 118, 160)
# The wake behind the sleigh. The one additive surface in the background.
const WAKE := Color8(150, 208, 230)
# ...and the dark halo laid just OUTSIDE the team's own outline. It is the reason
# the sleigh reads at all: the crossing happens in the aurora's own band, and a
# pale silhouette on a lit sky is a pale silhouette on a lit sky. A dark edge round
# it separates it from BOTH states of that sky without needing either to change.
const TEAM_EDGE := Color8(14, 24, 48)

# Where the key light comes from, for the props' own lambert term. High, front-left
# and slightly behind the camera's shoulder, which is where the board's own studio
# puts its key — so a crystal in the gutter is lit the same way a button is even
# though nothing here can light anything.
const SUN_DIR := Vector3(-2.4, 3.0, 2.0)
# ...and where the ice's specular comes from: the camera mirrored about the
# vertical, low and on the far side. The lake had to learn this the hard way — shade
# a horizontal surface from a front-upper key and the half-vector sits ~55 deg off
# its normal, so pow(dot, n) is zero for any usable exponent and the whole sheet
# renders as a flat wash with no highlight anywhere.
const GLINT_DIR := Vector3(0.30, 0.34, -1.0)

# ---------------------------------------------------------------------------
# The surface
# ---------------------------------------------------------------------------
# Two triangles, sized to run past the frame at every aspect on every board so
# there is nothing to think about; the far half is uniform fog long before it ends.
const ICE_Y := 0.0
const ICE_SIZE := 90.0

# Where the near-to-deep ramp runs, in board units away from the camera (-z is away).
#
# ALL FOUR OF THESE SPANS ARE SHORT, and the first draft's were not — they were the
# lake's, which run out to 15 and 24 m. The ground is not visible that far: this
# camera looks down at 33.5 deg through a lens whose top edge is still about 21 deg
# below horizontal, so the ice leaves the top of the picture at roughly z = -5 and
# the bottom edge sees no further than z = +7. A fog that starts at 4.5 m and is
# complete at 15 reaches 2 % at the top of the frame — which is why the first
# render had no depth in it at all, only a flat blue plane with props on it.
# Everything here is sized to the 12 m of ground the player can actually see.
const DEPTH_NEAR := -1.0
const DEPTH_FAR := 5.0
# ...and where it has dissolved into HAZE entirely, which is a little past the top
# edge, so the dissolve is a gradient the player never sees the end of.
const HAZE_NEAR := 2.0
const HAZE_FAR := 6.5
# The same deepening applied sideways, which is what frames the play area: the
# middle of the sheet stays light and the gutters fall away.
const SIDE_NEAR := 3.4
const SIDE_FAR := 8.5

# ---------------------------------------------------------------------------
# The horizon
# ---------------------------------------------------------------------------
# WHERE THE ICE STOPS, as a fraction of the frame's height from the top, and it is
# a SCREEN fraction for the same reason the far wall's band is one: it cannot be
# asked for in metres.
#
# Read the note on RIDGE_FY0 before changing this, and then read this one, because
# together they are the whole reason this background had no sky in it until now:
#
#   THIS CAMERA CANNOT SEE A HORIZON. It looks down at 33.5 deg through a lens
#   whose top edge is still about 21 deg below the horizontal, so the ground plane
#   fills the frame from corner to corner and the true horizon line is somewhere
#   above the top edge. Every distant thing the brief asks for — a mountain range,
#   a moon, stars, an aurora — is above that line. Nothing that stands ON the ice
#   can be any of them: a wall at the far end of the world has its BASE off the top
#   of the picture (see _screen_point's note, and the frog's, which found the same
#   thing on the lake).
#
# So the horizon is MADE. The ice discards itself above this line (in the ice
# shader, against SCREEN_UV, which is the same line on every board and at every
# aspect), and behind it stands a single flat card carrying the whole distance.
# The join is invisible because both sides of it are HAZE: the ice fades into it
# over HORIZON_BAND, and the sky's bottom row is that colour exactly.
#
# 0.175 is where it is because of what is ON the frame at the top. Higher and the
# sky is a strip too thin to put a mountain range in; lower and it starts eating
# the top row of buttons, which on Hard begins at 0.035 of the height. At 0.175 the
# tallest snowflake crosses the horizon — which is what a snowflake standing on a
# frozen lake in front of mountains DOES — and the two ranges are kept low and
# dark in the middle third of the frame so the crossing happens against quiet sky.
const HORIZON_FY := 0.165
# ...and how much of the frame the ice takes to dissolve into HAZE on its way up to
# it. Wide enough that the eye never finds the cut, narrow enough that the near
# ice keeps its own colour.
const HORIZON_BAND := 0.075

# How far in front of the camera the sky card stands, and how big it is. Neither
# number is composition — the card is shaded entirely in SCREEN space, so its only
# job is to be behind everything and to cover the frame. Nothing else in this
# background is further than about 7 m, and the board's camera is set to far=200.
const SKY_DIST := 40.0
const SKY_SPAN := 200.0

# ---------------------------------------------------------------------------
# How this background asks to be FRAMED
# ---------------------------------------------------------------------------
# (delta on how much of the viewport's height the board spans, delta on where its
# centre sits) — see BackgroundScenes.frame_bias, which is the only hook in the
# whole background system that moves the BOARD rather than the scenery, and exists
# for this one background.
#
# The first version of the sky put the horizon at 0.195 of the height and left the
# board where every other background has it: filling 0.90, centred at 0.487, which
# is a top row of buttons starting at 0.037. The snowflakes therefore stood ON the
# skyline, with a mountain range crossing the topmost one — the single worst thing
# in the picture, and not fixable from the background at all. The buttons are 0.90
# of the frame; the sky has nowhere to be.
#
# So the board comes DOWN and IN a little: it spans 0.835 of the height centred at
# 0.637, which puts its top edge at 0.22 — clear of the horizon at 0.165 — and its
# near edge past the bottom of the frame, which is where a tabletop's near edge
# belongs anyway. The margin below the lowest VISIBLE thing on the board is about
# 40 px on a 720 frame, so the near pedestals reach the edge and none is cropped.
#
# WHAT IT COSTS is about 7 % off the buttons' size, and that is a real cost in a
# game about telling six colours apart at speed, paid on ONE skin because that skin
# has a horizon. The first pass took 12 % and it was too much — the frame went half
# empty. It buys three things: no button crosses the skyline; the sky keeps a full
# 0.165 of the height rather than being squeezed to a strip; and the band between
# the shore and the board is clear ice, which is what makes the reflection worth
# having.
const FRAME_BIAS := Vector2(-0.065, 0.150)

# The bloom under the play area, as a multiple of the board's own reach: full
# strength inside the ring, gone by the time it reaches the props.
const STAGE_IN := 0.20
const STAGE_OUT := 1.95
const STAGE_GAIN := 0.075

# Where the cracks are allowed to be, also as a multiple of the reach. NOTHING
# below 1.06 — a button's own frame ends at about 1.0 of the reach, so the mask
# opens outside the outermost button and not one pixel inside it. This is the
# single most important number in the file after the palette: high-contrast detail
# under or between the buttons is exactly the complaint this background exists to
# answer.
const CRACK_IN := 1.06
const CRACK_OUT := 1.60
# And how strong they are once they are allowed. It was 0.14 — a hairline chosen
# when the whole picture sat between screen 40 and 95 and anything more would have
# been the loudest thing in it. The grade (see VIG_GAIN) took the far field DOWN,
# and a hairline on a darker surface is a hairline nobody can see: the middle of
# this frame is the largest area in it and it was reading as an empty gradient,
# which is most of what "cheap" meant.
#
# 0.195 of FROST, still masked entirely out of the play area, still fading with
# distance so it cannot alias in the far field.
#
# It went 0.14 -> 0.26 -> 0.195: at 0.26 a crack line out in the gutter became the
# frame's brightest pixel, which tools/ice_shot.tscn caught and no amount of looking
# at the picture would have. A pressure ridge now spends more of its contrast
# DOWNWARD (the shadow side is stronger than the lit side) for the same reason.
const CRACK_GAIN := 0.195

# ---------------------------------------------------------------------------
# THE ARENA
# ---------------------------------------------------------------------------
# The change that turns this background from a place into a STAGE, and it is one
# shape: an oval of polished ice with a shore, and snow everywhere outside it.
#
# Before it, the ice was an unbounded sheet that faded to fog in every direction —
# a frozen lake seen from the middle of it, which is a landscape. Nothing in the
# frame said where the game was played, so the six buttons stood on the same
# surface as the mist, the rocks and the far wall, and the picture had no centre
# that was not simply "where the buttons happen to be". A rink has an EDGE, and an
# edge is the whole difference between a wilderness and an arena.
#
# WHY IT IS AN ELLIPSE, AND WHY IT IS AN ELLIPSE ON THE SCREEN.
#
# A circle on a ground plane seen from 33.5 degrees above projects to an ellipse
# whose near edge runs off the bottom of the frame long before its far edge gets
# anywhere near the horizon, so a rink drawn as a true circle centred on the
# buttons shows the player its two SIDES and nothing else.
#
# THE SHORE IS A SCREEN SHAPE, and this is the file's own oldest lesson arriving
# for the fifth time (see _screen_point, RIDGE_FY0/FY1, HORIZON_FY and the
# milestone crystals): anything that has to COVER a chosen part of the picture is
# placed FROM the picture. Two earlier versions of this arena were written in world
# metres and both failed, in different ways, for the same reason:
#
#   * SIZED IN BOARD REACHES (2.15 x 1.78 of them) every shore landed outside the
#     visible ground — the ice leaves the top of the frame at about z = -5 and the
#     bottom edge sees no further than z = +7, so a rink 12 m across simply IS the
#     whole picture, and the render was indistinguishable from the sheet it
#     replaced;
#   * SOLVED FROM THREE RAYS through the ice it was worse, because it exposed the
#     real constraint: THIS BOARD IS NEARLY AS BIG AS THE GROUND THE CAMERA CAN
#     SEE. On Medium the furthest button's plate reaches z = -3.1 and the ice is
#     gone by z = -5; the frame's bottom corners sit at |x| = 3.05 where the
#     buttons already reach 3.0. An ellipse tight enough to put snow in the bottom
#     corners cuts straight through the far button, and one wide enough to clear
#     the far button leaves no bank anywhere. There is no world ellipse that does
#     both, on this board, at this camera.
#
# So the shore is an ellipse in SCREEN_UV, and it is SOLVED AGAINST THE BUTTONS'
# OWN PROJECTED DISCS rather than against the board's reach: every button is
# projected, its screen radius taken, and the ellipse scaled until the last of them
# is inside it by ARENA_MARGIN. That is what makes one arena correct on Easy's
# three buttons and Hard's six at every aspect — and, far more to the point, what
# makes it STRUCTURALLY unable to draw a shoreline through the play area, which is
# the one mistake this shape could make that would be worse than not existing.
#
# Nothing is lost by leaving world space. The camera is fixed for the life of a
# layout, so every world curve on this plane IS a fixed screen curve and the
# converse holds; the ice's horizon and the grade's vignette are already screen
# shapes for exactly this reason. What the shoreline keeps of the world is its
# WOBBLE, which is sampled off the ground's own noise, so the edge wanders with the
# ice rather than with the frame.

# The shore's proportions — its width against its height, as a shape rather than a
# size, because the size is solved. Wider than tall: the reference's rink shows
# both side shores across the middle of the picture and its far shore up under the
# banks, which is an ellipse about four fifths as wide as it is deep on screen.
const ARENA_RX := 0.82
const ARENA_RY := 1.00
# How far below the buttons' own screen centroid the ellipse is centred. Pushing it
# DOWN is what carries the near shore off the bottom edge, so the ice runs out of
# the picture at the player's end and the arena has no near wall — the reference's
# composition, and the one that keeps the frame open rather than making a bowl the
# player looks into. It is also what tilts the visible shore toward the TOP of the
# frame, which is where a keystoned ground plane has room for one.
#
# The value is the reference's: its buttons' screen centroid is at 0.552 and the
# ellipse fitted to its shoreline is centred at 0.80.
const ARENA_CY := 0.248
# The clearance between the outermost button's projected disc and the shoreline,
# ADDED to the ellipse rather than multiplied onto it, and it is small — which is
# not slack, it is what the reference does. Fitting an ellipse to the reference's
# own shoreline (it passes through frame 0.10 and 0.90 at half height and 0.235
# across the middle) gives centre (0.5, 0.80) and radii (0.47, 0.565); its top
# flake's plate reaches 0.965 of the way out to that shore and its side flakes
# 0.985. There is essentially no gap in the picture this is copying, and there is
# no room for one either: this board fills the frame.
#
# The first version multiplied by 1.30 instead, which on Medium put the side shores
# off both edges and the far shore above the horizon — an arena nobody could see,
# for the third time and for a third distinct reason.
# It went 0.030 -> 0.060 once tools/ice_verify.tscn could measure what 0.030
# actually bought. The solve makes k = base + margin, so a button's outermost point
# lands at base/(base + margin) of the way to the shore — with base ~0.595 on all
# three boards, a margin of 0.030 puts it at 0.95, which is INSIDE the shore's own
# transition: the ground at the rim of the button nearest the shore was measurably
# about half snow. 0.060 puts it at 0.91, clear of the band with room to spare, and
# costs about 5 % on the ellipse — at mid-height the visible side bank narrows from
# 0.09 of the frame to 0.064, which is still a bank.
const ARENA_MARGIN := 0.060
# ...and the floor under the solve, so a board whose buttons project into almost
# nothing (a very wide aspect) still gets an arena rather than a dot.
const ARENA_MIN := 0.30
# THE BOTTOM CORNERS, which a pure ellipse does not give you.
#
# The reference's foreground banks are the second thing the eye reads after the
# flakes — two big snow mounds carrying crystals, framing the bottom of the picture
# — and they cannot come out of the shore's ellipse, because the ellipse's centre
# has been pushed DOWN the frame (ARENA_CY) to carry the near shore off the bottom
# edge. Fitting an ellipse to the reference's own shoreline and then asking it
# where its bottom-left corner is puts that corner INSIDE the rink at ae 0.985 —
# and the reference plainly has snow there. Its shore is not an ellipse at the
# bottom; it curves in.
#
# So it curves in here too: a term added to the arena coordinate that grows toward
# the two bottom corners and is zero everywhere else. It is a SCREEN shape like the
# rest of the arena, and — this is the part that makes it safe rather than a tuned
# hack — _solve_arena evaluates the same term at every button and grows the ellipse
# until the squeeze cannot reach one. The two are answerable to each other by
# construction, so no board and no aspect can put a bank corner on a button.
const ARENA_CORNER := 0.375
const ARENA_CORNER_Y := Vector2(0.44, 1.02)   # where down the frame it fades in
const ARENA_CORNER_X := 0.32                  # ...and how far in from either edge
# How far past the shoreline a prop has to stand before it is allowed to exist, in
# the same arena units. Everything out here — crystals, rocks, plates, the far wall
# — is now placed on the BANK and never on the rink, and that is most of what makes
# the arena read as designed rather than as a light patch on a lake: a crystal
# standing on the ice the game is played on says the ice is not a stage.
#
# It clears SHORE_BAND and ARENA_WOB with a little to spare, so a prop cannot land
# in the transition where the ground under it is half snow and half ice.
const PROP_CLEAR := 0.055
# ...and how far out past the shore the bank is dressed, in the same units. Past
# this the ground is either off the frame or so compressed by the keystone that a
# prop standing there is a smear — see EDGE_TOP, which is the same observation made
# about the top of the picture.
const BANK_DEPTH := 0.55
# ...and WHERE in it each kind of prop belongs, measured out from the SHORELINE in
# arena units, so every one of them is placed relative to the berm's own profile
# rather than to the ellipse the berm was derived from.
#
#   crystals grow out of the drift, so they straddle its shoulder and crest;
#   plates LIE FLAT, so they may only go where the berm has run out — a disc on a
#   slope is a disc buried at one end and floating at the other, which is what the
#   first pass produced and what these two bands exist to stop.
const SHARD_BAND := Vector2(0.035, 0.250)


const ARENA_WOB := 0.040
# The ice-to-snow transition, and the lit lip on the snow side of it. Both in arena
# units. The band is soft because a hard edge here would be the highest-contrast
# line in the picture and it runs right around the play area.
# It came down from 0.115 when the berm arrived. A wide, soft shore was the right
# answer while the shoreline was only a colour change — a hard edge drawn in a
# fragment shader right around the play area is the highest-contrast line in the
# picture — but the BERM carries the edge now, and its foot stands on this
# transition and hides it. What a wide band costs is clearance: at 0.115 it reached
# back under the outermost button, and the ground at that button's rim measured
# about half snow (tools/ice_verify.tscn's "no button reaches the shoreline").
const SHORE_BAND := 0.060
const SHORE_LIP := 0.075
# How strong the lip is. It is the one place in the frame where the background is
# allowed a highlight, and it is allowed one because it is the arena's own edge —
# the line that says "the game is played inside here" — but see the peak note in
# the sparkles: this is now the second candidate for the frame's brightest pixel.
# It came down to a fifth of its first value when the BERM arrived: the lip and the
# berm are two answers to the same question and only one of them may be loud. With
# both at full strength the shoreline measured as the frame's brightest pixel at
# 126 % of a button and still read as a painted ring — contrast in the right place
# with no form under it. The berm carries the form now and this is the soft wash
# where its foot meets the ice.
const SHORE_GAIN := 0.26

const SEED := 0x1cef

# ---------------------------------------------------------------------------
# Cost
# ---------------------------------------------------------------------------
# NINE draw calls: the sky card, the ice, four MultiMeshes (the far wall, crystals,
# rocks, plates), one batched quad sheet (snow) and the milestone burst's two, which
# draw nothing at all between events. No particle system, no lights, no shadows and
# no textures — every animation in here is a function of TIME inside a shader, which
# is the pattern the eight Themes1 floors established.
#
# The reindeer and its sleigh are a TENTH, and only for 4.85 s in every eight
# levels: they are built when a celebration starts and freed when it ends.
#
# The CPU work is a scatter when the board's layout settles, and — while one of the
# two events is running — six numbers a frame.
#
# Measured with tools/lake_cost.tscn (1080x2160, Hard board, 150 frames): +2.08
# ms/frame against the lake's +2.20 and Living Forest's +1.80, in a harness that
# redraws the board every frame. The sky cost about a quarter of a millisecond of
# that, and it would have cost four times as much without the discard at the top of
# its fragment shader: it is a full-screen quad of which four fifths is behind
# opaque ice, and throwing those fragments away in the first instruction is the
# whole difference.
#
# THE REFLECTION IS THE EXPENSIVE HALF (about +0.37 with the moon's path, the
# pressure ridges and the grade), because it compiles a second sky and evaluates it
# for every ice pixel in a band a third of the frame tall. That is the price of the
# thing that makes the surface read as ice, it was paid deliberately, and it still
# leaves this background cheaper than the lake that already ships.
#
# The level-8 celebration adds +0.36 ms WHILE IT RUNS — 4.85 s in every eight
# levels, with the sleigh built and freed inside the measurement. The every-third
# burst adds nothing measurable: it is a MultiMesh whose instances already exist
# and a quad sheet, both animated off one uniform.
#
# The history is the argument for how this file has been allowed to grow: four
# draw calls at +1.54, six at +1.43 after the environment pass, nine at +1.71 after
# the sky and the milestones. Everything added in three passes has been a shader
# term, a MultiMesh instance or a batched quad, and nothing has been an object.
#
# It IS more than the imported world it replaces, and the reason is not the drawing
# — that world was a full .glb island and cost about the same to draw. It is that
# the imported one shipped STILL, so the board never nudged a redraw for it while
# the player was thinking. This one has snow in it, and snow that does not fall is
# a texture. IDLE_HZ 15 is where that cost is kept in hand: half the lake's idle
# rate, on a background whose fastest moving thing crosses a button in two seconds.

# How much of each thing. The three that existed before are up, and the two new
# ones are the answer to "it is too empty": a scatter that only samples the SIDE
# gutters can only ever fill the two top corners, however many of it there are.
#
# The counts are instances in a MultiMesh, which is very nearly free — the cost of
# this pass is two more draw calls and the shader terms below, not these numbers.
# The mid-size clusters filling the bank BETWEEN the big formations. Fewer than
# the twenty-four the open lake carried, and each of them larger: the brief for the
# arena is large environmental shapes rather than clutter, and twenty-four small
# ones spread round a bank is exactly the clutter it asks not to have.
const N_SHARDS := 20
const SHARD_SCREEN := Vector2(0.045, 0.098)
const N_PLATES := 20
const N_SNOW := 46
# The far ice wall. Placed ACROSS the top band by screen x rather than scattered,
# because the top band is the one part of this frame with room all the way across
# and a rejection sampler will never find it (see _ridge_point).
const N_RIDGES := 16
# Frozen rocks, in the corners and the near gutters.
const N_ROCKS := 12
# ...and how wide one may be ON SCREEN, as a fraction of the frame's width. Half
# the plates' cap: a plate is a soft patch and a rock is a solid silhouette, and the
# first pass at the plates' size put a boulder a quarter of the frame across in each
# bottom corner.
const ROCK_SCREEN := 0.038
# ...and how far apart two of them must be on screen, likewise.
const ROCK_APART := 0.075
# Small crystal clusters along the foot of the wall, so the far edge has two sizes
# of thing in it rather than one.
const N_FAR_SHARDS := 10
# ...and the BIG formations at the far left and far right of the frame — the two
# pillars of the composition, and the last thing added to it.
#
# They cannot come from the scatter, and the reason is the one _screen_point exists
# for: the side gutters project into a narrow wedge, and a candidate big enough to
# frame the picture almost never lands in it. These are placed from two screen
# rectangles at the very edges instead, three a side, and they are the only props
# allowed to be a quarter of the frame tall.
const N_EDGE_SHARDS := 12
const EDGE_SHARD_X := 0.150      # how far in from each edge they may stand
const EDGE_SHARD_TALL := 0.30    # ...and how tall on screen one may be
# Their brightness jitter is capped LOW. A crystal four times the area of its
# neighbours at the same value is four times the amount of the frame's brightness
# budget spent out in the gutter, and the peak this background is measured on is
# already an edge crystal.
const EDGE_SHARD_LIT := 0.60
# ...and how tall one is ON SCREEN, as a fraction of the frame's height, which is
# a different question from EDGE_SHARD_TALL: that is a CAP and this is a TARGET.
#
# The difference decided the whole look of the bank. Sized by a range in metres and
# then clipped to fit, a formation standing at the top of the frame comes out four
# times smaller than the same draw at the bottom of it — this camera keystones the
# ground that hard — so the far bank filled with gravel and the near corners with
# boulders, which is the arrangement that reads as scrub rather than as a skyline.
# Asked for a screen height and given whatever metres that takes
# (_height_for_screen), the same nine formations read as one range of sizes all the
# way round the arena, which is what the reference has and what "a few large
# stylized formations" means.
const BIG_SHARD_SCREEN := Vector2(0.170, 0.300)
# ...and how far apart two of them must be on screen, so nine read as a formation
# and not as a hedge.
const BIG_SHARD_APART := 0.105
# How far above the horizon a big formation's crest may reach, as a fraction of the
# frame. Small: two or three crests breaking the line tie the bank to the mountains
# behind it, and a row of them is a second skyline competing with the first.
const BIG_SHARD_SKY := 0.075

# How far outside the outermost button's reach a prop must be, as a multiple of it,
# and how far past that it is worth sampling before the projection decides.
const DRESS_CLEAR := 1.20
const DRESS_FAR := 2.4

# The frame margin, as a fraction of width and height. Props are kept off the very
# edge so none is a sliver, and out of the top band, where the ground is compressed
# so hard that a prop there is a smear.
#
# EDGE_TOP is now measured from the HORIZON rather than from the top of the frame,
# and that is not a tidy-up: above HORIZON_FY there is no ice, so a prop placed
# there is a prop standing in the sky. It was 0.10 of the frame when the frame was
# all ground.
const EDGE_X := 0.015
const EDGE_TOP := HORIZON_FY + 0.055
const EDGE_BOTTOM := 0.015

# How tall something standing in the gutter may be on screen, and how wide something
# lying flat may be, as fractions of the frame. Both lower than the lake's (0.15 /
# 0.060): a reed is a silhouette a few pixels wide and an ice crystal is a solid
# body, so the same screen height is a great deal more picture.
const SCREEN_TALL := 0.125
const SCREEN_FLAT := 0.075

# The far wall's own two margins. It lives in the band of ground the general
# EDGE_TOP (0.10) exists to keep props OUT of — which is right for a crystal, whose
# base would be a smear up there, and wrong for the one prop whose whole job is to
# be the far edge of the world.
#
# RIDGE_TOP is how high up the frame a crest may reach, and it is allowed a little
# way PAST the horizon on purpose: a far shore whose every peak stops dead on the
# waterline is a cut-out, and the two or three crests that break the line are what
# tie the ice to the mountains behind it.
const RIDGE_TOP := HORIZON_FY - 0.048
const RIDGE_TALL := 0.085
# ...and the band of the FRAME it stands in, from the top down. Screen fractions and
# not world depths, and that distinction is the whole placement:
#
# The first version asked for a depth (z between -5.2 and -3.6, "the band where
# there is still ground and still contrast" measured on Hard) and bisected the frame
# for it. On Hard that was right. On EASY the whole visible ground is nearer than
# -3.6 — three buttons are framed from closer in — so the bisection ran off the top
# of the picture, every slot failed its height fit, and the far wall was placed
# ZERO times. That is exactly the failure the placement helpers were written to stop
# (see _frame_point): a sampler that cannot meet its bar produces nothing, silently,
# on the difficulty nobody re-rendered.
#
# "Just under the top edge" is what the wall actually wants, it is the same thing on
# every board and at every aspect, and it cannot be asked for in metres.
#
# It is now just under the HORIZON instead, for the reason EDGE_TOP moved: the top
# edge of the frame is sky now, and a wall of ice standing in it would be a wall
# standing in front of the mountains at a tenth of their distance. Down here it is
# the frozen shore the lake ends at, which is what it always read as — and the
# mountains behind it are what it never had.
const RIDGE_FY0 := HORIZON_FY + 0.012
const RIDGE_FY1 := HORIZON_FY + 0.105

# ---------------------------------------------------------------------------
# Façade
# ---------------------------------------------------------------------------

static func has_scene(id: String) -> bool:
	return CATALOG.has(id)


static func display_name(id: String) -> String:
	return String(CATALOG.get(id, {}).get("name", id))


# What the 2D layer behind the board is cleared to. Returned in LINEAR light, which
# is the convention BackgroundScenes.backdrop_color already has.
static func backdrop_color(_id: String) -> Color:
	return Color(HAZE.r, HAZE.g, HAZE.b).srgb_to_linear()


# The ice IS the plane y = 0, like a Themes1 floor and unlike a Themes2 world's
# raised deck, so the board's coloured pools want the board's own defaults.
static func pool_plane_y(_id: String) -> float:
	return 0.0


# No edge, so no clip: the pools' own GLOW_R_CUT is what ends them.
static func pool_radius(_id: String) -> float:
	return 0.0


# How much of the pools survives on this surface. See BackgroundScenes.pool_gain:
# GLOW_PEAK was fitted against a near-black board, and the lake had to pull it down
# to 0.40 because bright turquoise water washed out under six of them. Ice is much
# darker than water and the pools are the ONE place a button's colour is allowed to
# reach the background — a lit snowflake laying its own colour on the ice is most of
# what makes this skin feel like one object — so it keeps nearly all of it.
# It went back UP to 0.70 when the arena arrived, and the reason is a change in
# what the pools land on. At 1.0 a lit flake washed a third of the FRAME with its
# own colour, because the frame was one unbroken sheet of ice that carried the
# glow to the edges of the picture; 0.62 was the value that stopped that. The rink
# has a shoreline now — the pool stops at the bank whatever its strength — so the
# same light spreads over a bounded, lighter, cleaner surface and reads as a
# reflection in a floor instead of a stain on a landscape. Which is also the brief:
# the six colours are supposed to be IN this place, not on top of it.
const POOL_GAIN := 0.70


static func is_animated(_id: String) -> bool:
	return true


# ---------------------------------------------------------------------------
# The scene
# ---------------------------------------------------------------------------
# GDScript cannot resolve a script's own `class_name` from inside that script, and a
# script cannot preload itself either, so the one place this file has to name itself
# does it through the resource cache. `load` on an already-loaded script is a
# dictionary lookup, and it happens once.
static var _script: GDScript = null


static func build(id: String) -> Node3D:
	if not CATALOG.has(id):
		return null
	if _script == null:
		_script = load("res://ice_world.gd") as GDScript
	var root: Variant = _script.new()
	root.name = "IceKingdom"
	root.construct()
	return root as Node3D


# Tell the ice where this board's buttons are and how far the outermost one reaches,
# so the bloom can be sized to the play area, the cracks can be kept out of it and
# the props can be laid in the gutters. Called by MemoryGameUI whenever the board's
# ground layout is (re)established, which is also every resize and every difficulty
# change.
static func set_board_layout(scene: Node3D, centres: PackedVector2Array, reach: float,
		cam: Camera3D, vp_size: Vector2) -> void:
	if scene != null and scene.has_method("set_layout"):
		scene.call("set_layout", centres, reach, cam, vp_size)


# The player has just COMPLETED round `round_no`, offered on EVERY round. Ice
# Kingdom answers every third with the crystal burst (THE MILESTONE EVENTS) and
# ignores the rest — the decision is HERE and not in game.gd, which is what lets a
# second background want a different number without anything above knowing.
#
# What comes back is a duration and nothing else: the seconds the round must stay
# frozen for what was just started, or 0.0 for nothing. Same contract as the lake's.
static func note_milestone(scene: Node3D, round_no: int) -> float:
	if scene != null and scene.has_method("start_streak_event"):
		return float(scene.call("start_streak_event", round_no))
	return 0.0


# The level the player has just completed, for the milestone the every-third one is
# not big enough for. Ice Kingdom answers every eighth with the aurora and the
# sleigh; same contract, same returned freeze.
static func note_finale(scene: Node3D, level_no: int) -> float:
	if scene != null and scene.has_method("start_party_event"):
		return float(scene.call("start_party_event", level_no))
	return 0.0


# How often the board should nudge its SubViewport to redraw. IDLE_HZ normally; the
# app's own rate while a milestone is on screen, because IDLE_HZ is sized to snow
# falling at 12 cm/s and a sleigh crosses the whole frame in 2.3 s.
static func idle_hz_for(scene: Node3D) -> float:
	if scene != null and scene.has_method("event_active") \
			and bool(scene.call("event_active")):
		return EVENT_HZ
	return IDLE_HZ


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------
# A shop card renders the ice through the Hard board's own pose, the same as every
# other 3D background, so the card shows the framing the player gets.
const PREVIEW_FOV := 43.44
const PREVIEW_ELEV_DEG := 33.51
const PREVIEW_TARGET := Vector3(0.0, 0.35, 0.54)
const PREVIEW_DIST := 10.04


static func make_preview_camera(_aspect: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = PREVIEW_FOV
	cam.near = 0.15
	cam.far = 200.0
	var e := deg_to_rad(PREVIEW_ELEV_DEG)
	cam.look_at_from_position(
		PREVIEW_TARGET + Vector3(0.0, sin(e), cos(e)) * PREVIEW_DIST,
		PREVIEW_TARGET, Vector3.UP)
	return cam


# The palette is solved against the BOARD's Environment, so a preview has to be
# rendered through the same one or every colour here lands somewhere else.
static func make_preview_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = backdrop_color("world_ice")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.40
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	return we


# ---------------------------------------------------------------------------
# The node
# ---------------------------------------------------------------------------

var _ice: MeshInstance3D
var _imat: ShaderMaterial
var _sky: MeshInstance3D
var _smat: ShaderMaterial
var _dress: Node3D
var _shards: MultiMeshInstance3D
var _plates: MultiMeshInstance3D
var _ridges: MultiMeshInstance3D
var _rocks: MultiMeshInstance3D
var _snow: MeshInstance3D
var _berm: MeshInstance3D
var _centres := PackedVector2Array()
# The shore's ellipse, in fractions of the frame: its two radii and its centre.
# Solved against the buttons' own projected discs in _solve_arena and read by every
# prop placement out here, because a crystal standing on the rink is the one
# mistake this shape cannot absorb.
var _arena := Vector2.ZERO
var _arena_at := Vector2.ZERO
var _reach := 0.0
var _vp_size := Vector2.ZERO
var _cam_pose := Transform3D()


func construct() -> void:
	_build_sky()
	_build_ice()
	_dress = Node3D.new()
	_dress.name = "Dressing"
	add_child(_dress)
	# The far wall FIRST, so it is drawn behind everything else in the gutters —
	# they are all opaque and depth-tested, but the wall is the furthest thing in
	# the picture and the order costs nothing.
	_ridges = _multi("Ridges", _ridge_mesh(),
		_shard_material(RIDGE_LO, RIDGE_HI, Vector2(HAZE_NEAR + 1.4, HAZE_FAR + 3.2),
			RIDGE_CAP_GAIN))
	_shards = _multi("Crystals", _shard_mesh(), _shard_material())
	_rocks = _multi("Rocks", _rock_mesh(), _rock_material())
	_plates = _multi("Plates", _plate_mesh(), _plate_material())
	_berm = MeshInstance3D.new()
	_berm.name = "Berm"
	_berm.material_override = _berm_material()
	_berm.layers = BG_LAYER
	_berm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dress.add_child(_berm)
	_dimmable.append(_berm.material_override as ShaderMaterial)
	_snow = _snow_node()
	_dress.add_child(_snow)
	_dimmable.append(_imat)
	_dimmable.append(_snow.material_override as ShaderMaterial)
	_build_streak()
	# Nothing here has any per-frame CPU cost: the snow falls in its vertex shader
	# and the ice polishes itself in its fragment shader, both off TIME.
	set_process(false)


# Everything that answers to `dim`. Collected rather than looked up, because the
# prop materials live on their MultiMeshInstance3D as material_overrides and a
# background that has to darken itself should not be walking its own scene tree to
# find out how.
var _dimmable: Array[ShaderMaterial] = []


# One number cools the whole scene. `k` is a multiplier on every surface's own
# radiance: 1.0 is the background as it normally is, and the two events take it
# down to EV_DIM / PT_DIM and back.
#
# The BUTTONS are not in this and cannot be — they are the board's, not ours. That
# is the right way round: cooling the background during a celebration is the same
# gesture as brightening the buttons, and it is the one of the two this file is
# allowed to make.
# BOTH materials, always. The ice reflects the sky, so an aurora that swells only on
# the card is an aurora the lake does not know about — which is exactly the seam
# sharing sky_at exists to prevent.
func _set_aurora_boost(v: float) -> void:
	if _smat != null:
		_smat.set_shader_parameter("aurora_boost", v)
	if _imat != null:
		_imat.set_shader_parameter("aurora_boost", v)


func _set_dim(k: float) -> void:
	for m: ShaderMaterial in _dimmable:
		m.set_shader_parameter("dim", k)
	if _smat != null:
		# The sky takes a third of it. Some is needed or the horizon detaches from
		# the ground it stands behind; all of it would cancel the celebration, whose
		# whole shape is the sky coming UP while the ice goes down.
		_smat.set_shader_parameter("dim", lerpf(1.0, k, 0.34))


# The only per-frame code in this background, and it runs for about six seconds in
# every eight levels. Both events are closed forms off their own clock, so this
# writes uniforms and one transform and does no work of its own.
func _process(dt: float) -> void:
	if _ev_on:
		_ev_t += dt
		_pose_streak()
		if _ev_t >= EV_TOTAL:
			stop_streak_event()
	if _pt_on:
		_pt_t += dt
		_pose_party()
		if _pt_t >= PT_TOTAL:
			stop_party_event()
	if not _ev_on and not _pt_on:
		set_process(false)


func _multi(nm: String, mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.layers = BG_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 8, 80))
	_dress.add_child(mi)
	if mat is ShaderMaterial:
		_dimmable.append(mat as ShaderMaterial)
	return mi


# ---------------- the sky ----------------
# ONE quad, standing 40 m in front of the camera, parallel to the image plane, and
# shaded entirely in SCREEN space. Everything the brief asks for above the waterline
# is in its fragment shader: the gradient, the stars, the moon, two mountain ranges,
# the cloud band along their tops and the aurora.
#
# It is a card and not a place, and that is the honest description of it. There is
# no geometry out there, no second camera and no cube map — at 33.5 deg of downtilt
# the sky is a strip 126 px tall on a 720 px frame, and a strip is a painting. What
# it buys is what the picture did not have: a BACK to the world that is further away
# than the ice, so the far shore reads as a shore rather than as the edge of a
# plane.
func _build_sky() -> void:
	var qm := QuadMesh.new()
	qm.size = Vector2(SKY_SPAN, SKY_SPAN)
	var sh := Shader.new()
	sh.code = SKY_SHADER
	_smat = ShaderMaterial.new()
	_smat.shader = sh
	_apply_sky_params(_smat)
	_smat.set_shader_parameter("dim", 1.0)

	_sky = MeshInstance3D.new()
	_sky.name = "Sky"
	_sky.mesh = qm
	_sky.material_override = _smat
	_sky.layers = BG_LAYER
	_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The card is posed from the camera in _scatter. Until one arrives it stands
	# where a Hard board's would put it, so a scene built and rendered without ever
	# being given a layout (every shop card goes through that path) still has a sky.
	_sky.transform = Transform3D(Basis(), Vector3(0.0, 4.0, -SKY_DIST))
	add_child(_sky)


# Every uniform SKY_COMMON declares, set on whichever material is asked for. There
# are two of them and there must never be two sets of values: the ice REFLECTS the
# sky by compiling the same function, and a reflection whose moon is two per cent
# away from the moon is a bug nobody can see and everybody can feel.
func _apply_sky_params(m: ShaderMaterial) -> void:
	m.set_shader_parameter("c_top", tone(SKY_TOP))
	m.set_shader_parameter("c_low", tone(SKY_LOW))
	m.set_shader_parameter("c_haze", tone(HAZE))
	m.set_shader_parameter("c_star", tone(STAR))
	m.set_shader_parameter("c_moon", tone(MOON_CORE))
	m.set_shader_parameter("c_moon_halo", tone(MOON_HALO))
	m.set_shader_parameter("c_rng_far", tone(RANGE_FAR))
	m.set_shader_parameter("c_rng_mid", tone(RANGE_MID))
	m.set_shader_parameter("c_rng_near", tone(RANGE_NEAR))
	m.set_shader_parameter("c_rng_cap", tone(RANGE_CAP))
	m.set_shader_parameter("c_aur_a", tone(AUR_CYAN))
	m.set_shader_parameter("c_aur_b", tone(AUR_VIOLET))
	m.set_shader_parameter("horizon", HORIZON_FY)
	m.set_shader_parameter("moon_at", MOON_AT)
	m.set_shader_parameter("aur_base", AUR_BASE)
	m.set_shader_parameter("aur_swell", AUR_SWELL)
	m.set_shader_parameter("aur_period", AUR_PERIOD)
	m.set_shader_parameter("aur_cap", AUR_CAP)
	m.set_shader_parameter("aurora_boost", 0.0)


# Where the moon sits, in fractions of the FRAME — not of the sky band, so it does
# not move when the horizon does. Two things decide it and neither is taste:
#
#   * it is on the RIGHT because the LEVEL badge is drawn over the top-left corner
#     of this viewport (see the home HUD's note), and a moon behind a HUD card is a
#     moon nobody sees;
#   * and it is off the centre line because the centre of the top of the frame is
#     where the topmost button stands on Medium and Hard.
const MOON_AT := Vector2(0.815, 0.052)

# ---------------------------------------------------------------------------
# The aurora, and the one number in this file the brief is most specific about
# ---------------------------------------------------------------------------
# "VERY subtle and occasional. It should NOT constantly pulse or dominate the
# screen." Which is a statement about a DUTY CYCLE, not about a brightness, and it
# is built as one: the curtains are always there at AUR_BASE — faint enough to read
# as the colour of the night rather than as an effect — and once every AUR_PERIOD
# seconds they swell to AUR_BASE + AUR_SWELL over about a second, hold, and take
# two more to come back down.
#
# The swell is 3.4 s of every 11.5, and the shape of it is a smoothstep pair rather
# than a sine, so the quiet stretch really is quiet: a sine at the same period is
# never NOT moving, which is the thing the brief is asking not to happen.
#
# It is also deliberately prime-ish against nothing: the aurora's clock is TIME, it
# is never reset, and no gameplay event starts it. The brief asks for that too
# ("avoid synchronized pulsing with gameplay") and the way to get it is to have
# nothing to synchronise WITH — the level-8 celebration adds `aurora_boost` on top
# of whatever phase the curtains happen to be in, and never restarts them.
const AUR_BASE := 0.090
const AUR_SWELL := 0.175
const AUR_PERIOD := 11.5
# The ceiling on what the curtains may add, in RADIANCE — the one term in this
# background that adds rather than mixes, and therefore the one that needs a bound
# rather than an argument.
#
# It does NOT bind at rest: the aurora at its own swell peak is well under it, and
# measuring proved that (the frame's brightest pixel turned out to be a star, not a
# curtain, and capping the aurora at a third of this changed the number by nothing).
# What it bounds is the LEVEL-8 CELEBRATION, which adds PT_BOOST on top of whatever
# phase the curtains are in — the one moment the two could stack into something
# brighter than a lit button.
const AUR_CAP := 0.75

# ---------------------------------------------------------------------------
# The reflection
# ---------------------------------------------------------------------------
# How much of the frame BELOW the horizon the whole sky folds into, how strong the
# reflection is at the shore, and how far the ice breaks it up.
#
# The first is the one that decides whether it reads as ice or as a hole. A plane
# seen from 33.5 deg above returns a compressed image; at 1.0 (the sky's own height)
# the mountains come back nearly full size and the picture turns into two worlds
# meeting at a line. At 0.30 of the frame the ranges return as a band a third their
# height, which is what a low viewpoint actually does and what reads as looking ACROSS
# something rather than into it.
#
# The second is capped low for the reason every other accent here is: the reflection
# carries the ONLY bright things in the picture — the moon and the aurora — down onto
# the surface the buttons stand on. It is also masked out of the play area entirely
# (see the ice shader), so what this number controls is the far field alone.
const REFL_SPAN := 0.32
const REFL_GAIN := 0.58
const REFL_BREAK := 0.055

# THE MOON'S PATH: how wide the column of glitter under the moon is, as a fraction
# of the frame's WIDTH, and how strong it is.
#
# It is a separate term from the reflection above and not a consequence of it, and
# that is deliberate. A reflection returns the moon as a disc a few pixels across;
# what a frozen lake at night actually does is throw a broken COLUMN of light down
# the surface toward the viewer, because every facet tilted the right way returns
# it. That column is the single most recognisable thing about the subject and it is
# worth its own eight lines.
#
# It is also the one highlight this background has. Everything else here spends its
# contrast downward.
const MOON_PATH := Vector2(0.075, 0.88)

# ---------------------------------------------------------------------------
# The grade
# ---------------------------------------------------------------------------
# A vignette on the ice, centred on the BOARD rather than on the frame, and it is
# the last thing added to this background because it is what the first three passes
# were missing: the picture had detail and no TONE. Everything in it — sky, ice,
# mountains, crystals — sat between screen 40 and screen 95, which is the definition
# of a flat image, and no amount of extra content fixes that.
#
# The rule forbids adding highlights (nothing may out-bright a button), so the range
# has to be bought at the DARK end. The gutters and the far corners go down toward
# HAZE; the play area is untouched and therefore becomes, by contrast, the brightest
# region in the frame — which is the arrangement this whole file exists to produce.
const VIG_IN := 0.30
const VIG_OUT := 0.95
const VIG_GAIN := 0.46
# Where its centre sits, as a fraction of the frame. Under the board, not in the
# middle of the picture — the board is seated low here (see FRAME_BIAS).
const VIG_AT := Vector2(0.5, 0.66)


# ---------------- the ice ----------------

func _build_ice() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(ICE_SIZE, ICE_SIZE)
	var sh := Shader.new()
	sh.code = ICE_SHADER
	_imat = ShaderMaterial.new()
	_imat.shader = sh
	_imat.set_shader_parameter("c_near", tone(NEAR))
	_imat.set_shader_parameter("c_mid", tone(MID))
	_imat.set_shader_parameter("c_haze", tone(HAZE))
	_imat.set_shader_parameter("c_sheen", tone(SHEEN))
	_imat.set_shader_parameter("c_frost", tone(FROST))
	_imat.set_shader_parameter("c_aurora", tone(AURORA))
	_imat.set_shader_parameter("c_mist", tone(MIST))
	_imat.set_shader_parameter("c_bank_lo", tone(BANK_LO))
	_imat.set_shader_parameter("c_bank_hi", tone(BANK_HI))
	_imat.set_shader_parameter("c_lip", tone(LIP))
	# A placeholder, overwritten by _solve_arena the moment there is a camera to
	# solve against. It is set here at all so the material is complete before the
	# first frame: an unset vec4 is (0,0,0,0), and an arena with a zero radius puts
	# the whole frame on the far side of the shore.
	_imat.set_shader_parameter("arena",
		Vector4(ARENA_RX, ARENA_RY, SHORE_BAND, SHORE_LIP))
	_imat.set_shader_parameter("arena_at", Vector2(0.5, 0.5 + ARENA_CY))
	_imat.set_shader_parameter("arena_wob", ARENA_WOB)
	_imat.set_shader_parameter("corner", Vector4(ARENA_CORNER_Y.x,
		ARENA_CORNER_Y.y, ARENA_CORNER, ARENA_CORNER_X))
	_imat.set_shader_parameter("shore_gain", SHORE_GAIN)
	_imat.set_shader_parameter("glint_dir", GLINT_DIR.normalized())
	_imat.set_shader_parameter("depth_span", Vector2(DEPTH_NEAR, DEPTH_FAR))
	_imat.set_shader_parameter("haze_span", Vector2(HAZE_NEAR, HAZE_FAR))
	_imat.set_shader_parameter("side_span", Vector2(SIDE_NEAR, SIDE_FAR))
	_imat.set_shader_parameter("stage_span", Vector2(1.0, 6.0))
	_imat.set_shader_parameter("crack_span", Vector2(3.0, 6.0))
	_imat.set_shader_parameter("stage_gain", STAGE_GAIN)
	_imat.set_shader_parameter("crack_gain", CRACK_GAIN)
	_apply_sky_params(_imat)
	_imat.set_shader_parameter("horizon_band", HORIZON_BAND)
	_imat.set_shader_parameter("refl",
		Vector3(REFL_SPAN, REFL_GAIN, REFL_BREAK))
	_imat.set_shader_parameter("moon_path", MOON_PATH)
	_imat.set_shader_parameter("vig", Vector4(VIG_IN, VIG_OUT, VIG_GAIN, 0.0))
	_imat.set_shader_parameter("vig_at", VIG_AT)
	_imat.set_shader_parameter("dim", 1.0)
	_imat.set_shader_parameter("sweep", Vector2(0.0, 0.0))

	_ice = MeshInstance3D.new()
	_ice.name = "Ice"
	_ice.mesh = pm
	_ice.material_override = _imat
	_ice.position = Vector3(0.0, ICE_Y, 0.0)
	_ice.layers = BG_LAYER
	_ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ice)


# ---------------- layout ----------------

func set_layout(centres: PackedVector2Array, reach: float, cam: Camera3D,
		vp_size: Vector2) -> void:
	_centres = centres
	# Both of these are in metres and both are derived from the board rather than
	# chosen, which is what makes one environment correct on all three difficulties:
	# Easy's three buttons reach ~2.4 and Hard's six reach ~3.5, so the bloom under
	# the play area and the radius the cracks are kept out of move with them.
	var r := maxf(reach, 0.5)
	_imat.set_shader_parameter("stage_span", Vector2(r * STAGE_IN, r * STAGE_OUT))
	_imat.set_shader_parameter("crack_span", Vector2(r * CRACK_IN, r * CRACK_OUT))
	# The fallback arena, so the material is never incomplete: _scatter solves the
	# real one against the buttons a few lines below, and cannot without a camera.
	if _arena == Vector2.ZERO:
		_set_arena(Vector2(ARENA_RX, ARENA_RY), Vector2(0.5, 0.5 + ARENA_CY))
	if cam == null or vp_size.x < 8.0 or vp_size.y < 8.0:
		return
	# Re-laid whenever the board, the frame OR THE CAMERA moves. The camera is the
	# one that is easy to miss: the board's ground layout is settled several times
	# during a build and the first of those runs before _fit_camera has solved the
	# distance, so keying only on the reach and the viewport size leaves the whole
	# dressing placed through a camera 30 % too close (measured on the lake).
	var pose := cam.global_transform
	if absf(reach - _reach) > 0.05 or _vp_size != vp_size \
			or not pose.is_equal_approx(_cam_pose):
		_vp_size = vp_size
		_cam_pose = pose
		_scatter(reach, cam, vp_size)


# Lay every prop out for a board whose outermost button reaches `reach`. Only
# instance transforms are written — no mesh is rebuilt and no material is touched —
# so a resize or a difficulty change costs two array fills and one small mesh.
func _scatter(reach: float, cam: Camera3D, vp: Vector2) -> void:
	_reach = reach
	# The sky card first: it is not scattered, it is POSED — parked square in front
	# of the camera at a distance nothing else in this background comes near, so it
	# is behind every prop by depth alone and needs no draw order of its own. The
	# board's camera is set to far = 80 m; SKY_DIST is 40.
	if _sky != null and cam != null:
		var ct := cam.global_transform
		_sky.global_transform = Transform3D(ct.basis, ct.origin - ct.basis.z * SKY_DIST)
	# THE ARENA FIRST, because every prop below is placed against it: the shore is
	# what decides where the dressing may stand, and solving it after the scatter
	# would put this frame's crystals on last frame's ice.
	_solve_arena(reach, cam, vp)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var lo := reach * DRESS_CLEAR
	var hi := reach * DRESS_CLEAR + DRESS_FAR
	# The berm first: it is the shoreline made solid, and the props are spaced
	# against the shore rather than against each other's meshes.
	_berm.mesh = _berm_mesh(cam, vp)
	_fill_ridges(_ridges.multimesh, rng, lo * 0.80, cam, vp)
	_fill_shards(_shards.multimesh, rng, lo, hi, cam, vp)
	_fill_rocks(_rocks.multimesh, rng, lo, cam, vp)
	_fill_plates(_plates.multimesh, rng, lo, hi, cam, vp)
	# The snow is laid through the frame as well, and over a wider band than the
	# props: it is the one thing here that is allowed above the play area, because
	# it is two pixels of pale blue at a tenth of a button's brightness.
	_snow.mesh = _snow_mesh(N_SNOW, reach * 0.55, hi + 2.0, cam, vp)

	# The two milestone events are laid out HERE, with everything else, and not when
	# they fire. Both of them are placed through the camera exactly like the props
	# are, so both would otherwise have to do that work on the frame a level ends —
	# which is the one frame in a round that is already doing something.
	_plan_streak(rng, cam, vp, lo)
	_plan_flight(cam, vp)


# The sleigh's crossing, solved once per layout: three points on a plane PT_DIST in
# front of the camera, the basis that holds the team square to it, and the scale
# that makes it PT_SPAN of the frame wide.
#
# It is all in FRAME fractions, which is what makes one crossing correct on Easy,
# Medium and Hard: "in from off the left edge, over the top of the picture and out
# past the right" is the same instruction on every board, and a lane in metres is
# not — the same lane that clears Hard's buttons runs through Easy's.
func _plan_flight(cam: Camera3D, vp: Vector2) -> void:
	var a := cam.project_position(PT_IN * vp, PT_DIST)
	var m := cam.project_position(PT_MID * vp, PT_DIST)
	var c := cam.project_position(PT_OUT * vp, PT_DIST)
	_pt_a = a
	_pt_c = c
	# The control point that puts the curve THROUGH the middle point at u = 0.5,
	# rather than merely toward it. A Bezier that only leans at its apex flattens
	# the arc to about half the height it was drawn at.
	_pt_ctrl = m * 2.0 - (a + c) * 0.5
	_pt_basis = cam.global_transform.basis
	# One frame width at that distance, so the team can be sized on screen.
	var l := cam.project_position(Vector2(0.0, vp.y * 0.5), PT_DIST)
	var r := cam.project_position(Vector2(vp.x, vp.y * 0.5), PT_DIST)
	_pt_scale = l.distance_to(r) * PT_SPAN / TEAM_LEN
	_laid_out = true
	# A layout that lands mid-crossing (a resize, a rotation) re-solves the lane
	# under the sleigh rather than leaving it flying down the old one.
	if _pt_on:
		_pose_party()


# ---------------------------------------------------------------------------
# The arena, solved against the buttons
# ---------------------------------------------------------------------------
# Project every button, take its screen disc, and grow the shore's ellipse until
# the last of them is inside it by ARENA_MARGIN. See THE ARENA for why the shape
# lives on the screen and not in the world; in one line, this board is nearly as
# large as the ground the camera can see, and the only ellipse that both clears the
# far button and reaches the frame's corners is one solved in the picture.
#
# It is solved against the BUTTONS and not against `reach` on purpose. Reach is one
# number for a ring that is not round — Medium's five sit at 2.10 m from the middle
# and Hard's six do not — so a margin measured off it is loose in some directions
# and tight in others, and the direction it is tight in is the one that would put a
# shoreline through a button.
func _solve_arena(reach: float, cam: Camera3D, vp: Vector2) -> void:
	# The button's own radius on the ground: `reach` is the outermost plate's edge,
	# so what is left over from the furthest centre is how big a plate is.
	var furthest := 0.0
	for c: Vector2 in _centres:
		furthest = maxf(furthest, c.length())
	var brad := clampf(reach - furthest, reach * 0.15, reach * 0.60)
	var cx := 0.0
	var cy := 0.0
	var pts := PackedVector2Array()
	var rads := PackedVector2Array()
	for c: Vector2 in _centres:
		var w := Vector3(c.x, ICE_Y, c.y)
		if cam.is_position_behind(w):
			continue
		var sp := cam.unproject_position(w) / vp
		# The plate's screen radius, measured in both axes rather than assumed
		# equal: this camera keystones hard enough that a disc on the ground is a
		# markedly flatter ellipse on the screen than it is a circle on the ice.
		var ex := cam.unproject_position(w + Vector3(brad, 0.0, 0.0)) / vp
		var ez := cam.unproject_position(w + Vector3(0.0, 0.0, brad)) / vp
		pts.append(sp)
		rads.append(Vector2(absf(ex.x - sp.x), absf(ez.y - sp.y)))
		cx += sp.x
		cy += sp.y
	if pts.is_empty():
		_set_arena(Vector2(ARENA_RX, ARENA_RY), Vector2(0.5, 0.5 + ARENA_CY))
		return
	cx /= float(pts.size())
	cy /= float(pts.size())
	# Horizontally the board is symmetric on every difficulty and the frame is the
	# thing the arena has to sit in, so the centre is the FRAME's middle rather than
	# the buttons'. Vertically it is the buttons', pushed down so the near shore
	# leaves the picture.
	var at := Vector2(0.5, cy + ARENA_CY)
	var k := ARENA_MIN
	for i in pts.size():
		var d := pts[i] - at
		var r := rads[i]
		# The disc is inside the ellipse if its centre's ellipse-distance plus the
		# largest fraction of a radius it spans is inside. Conservative in the
		# corners, which is the direction to be wrong in.
		var g := Vector2(d.x / ARENA_RX, d.y / ARENA_RY).length()
		if g < 0.001:
			continue
		# How much further out the disc's OUTERMOST point is, along the direction
		# the ellipse actually grows in. Taking max(rx, ry) instead — which is what
		# this did first — charges every button its widest radius in whichever
		# direction it happens to lie, and the top button of a ring is the one that
		# decides the answer: it is directly above the centre, so only its (much
		# smaller) vertical radius matters, and being charged its horizontal one
		# pushed the whole ellipse out by a sixth. The shore went above the horizon.
		var inc := (absf(d.x) * r.x / (ARENA_RX * ARENA_RX)
			+ absf(d.y) * r.y / (ARENA_RY * ARENA_RY)) / g
		# ...and the corner squeeze is charged to the ellipse here, which is what
		# makes it safe. The shader's arena coordinate is (g / k) + corner, so the
		# button is inside the shore only while k >= (g + inc) / (1 - corner). The
		# floor under the divisor is a guard, not a tuning: it bounds how much any
		# one button in a corner may inflate the whole arena.
		var squeeze := _corner_bias(pts[i] + Vector2(0.0, r.y)) * ARENA_CORNER
		k = maxf(k, (g + inc) / maxf(1.0 - squeeze, 0.45))
	k += ARENA_MARGIN
	_set_arena(Vector2(k * ARENA_RX, k * ARENA_RY), at)


func _set_arena(rad: Vector2, at: Vector2) -> void:
	_arena = rad
	_arena_at = at
	if _imat != null:
		_imat.set_shader_parameter("arena",
			Vector4(rad.x, rad.y, SHORE_BAND, SHORE_LIP))
		_imat.set_shader_parameter("arena_at", at)


# How far out a point on the screen is in ARENA UNITS: below 1 is over the rink,
# above it is over the bank. Every prop out here is placed against this and not
# against a radius, which is what stops the dressing standing on the ice it is
# supposed to surround.
func _arena_at_screen(sp: Vector2, vp: Vector2) -> float:
	var f := sp / vp
	return Vector2((f.x - _arena_at.x) / maxf(_arena.x, 0.01),
		(f.y - _arena_at.y) / maxf(_arena.y, 0.01)).length() \
		+ _corner_bias(f) * ARENA_CORNER


# How hard the shore is pulled inward at this point on the screen. Zero over almost
# all of the frame and rising into the two bottom corners.
#
# IT IS WRITTEN THE SAME WAY IN THE ICE SHADER AND THE TWO MUST STAY IDENTICAL —
# the solve's guarantee that no bank can reach a button is exactly the statement
# that this function is the one the shader draws with. Written as
# 1 - smoothstep(0, X, m) rather than smoothstep(X, 0, m) because GLSL leaves the
# reversed-edge form UNDEFINED (the same trap the horizon fade paid for), and the
# GDScript half is written to match the GLSL half rather than the other way round.
static func _corner_bias(f: Vector2) -> float:
	var m := minf(f.x, 1.0 - f.x)
	return smoothstep(ARENA_CORNER_Y.x, ARENA_CORNER_Y.y, f.y) \
		* (1.0 - smoothstep(0.0, ARENA_CORNER_X, m))


# The same question asked of a point on the ice. INF-safe and behind-camera-safe:
# either returns a large number, so a candidate that cannot be projected is
# rejected as "on the bank" and then fails its own frame test a moment later.
func _arena_at_point(p: Vector3, cam: Camera3D, vp: Vector2) -> float:
	if p == Vector3.INF or cam == null or cam.is_position_behind(p):
		return 9.0
	return _arena_at_screen(cam.unproject_position(p), vp)


# Is this a place something may stand? Everything in the gutters asks this now.
func _on_bank(p: Vector3, cam: Camera3D, vp: Vector2) -> bool:
	return _arena_at_point(p, cam, vp) > 1.0 + PROP_CLEAR


# _frame_point, but it keeps asking until the answer is on the BANK.
#
# The retry lives here and not inside the sampler because the sampler is one of the
# four helpers this file shares with the lake verbatim (see Placement, through the
# CAMERA) and the arena is not the lake's. Six outer attempts at ninety inner ones
# is far more than the rejection rate needs — the sampler already draws from a band
# outside the play area, so most of what it returns is on the bank to begin with —
# and returning INF after that is the same contract it always had: the caller drops
# the prop rather than placing it badly.
func _bank_point(rng: RandomNumberGenerator, lo: float, hi: float, cam: Camera3D,
		vp: Vector2, arc: float = 0.0, near_z: float = 1e9) -> Vector3:
	for _outer in 6:
		var p := _frame_point(rng, lo, hi, cam, vp, arc, near_z)
		if p == Vector3.INF:
			return p
		if _on_bank(p, cam, vp):
			return p
	return Vector3.INF


# A point on the BANK, drawn from a ring just outside the shore.
#
# This is the third and last form of the placement problem this file keeps meeting,
# and it is worth naming all three together because each was the right answer to
# the previous one:
#
#   _frame_point   samples the WORLD and keeps what lands in shot. Right for a
#                  scatter on an unbounded plane; produces two heaps in the top
#                  corners when asked to cover the frame.
#   _screen_point  samples a RECTANGLE of the picture. Right for anything that must
#                  cover a named part of it — a wall across the top, a rock in a
#                  corner.
#   _shore_point   samples the RING AROUND THE ARENA. Right for the bank, which is
#                  neither a region of the world nor a rectangle of the screen but
#                  an annulus defined by a shape solved at run time.
#
# Rejection sampling the bank out of the whole frame — which is what this did first
# — spends most of its tries on the rink, because after the arena the rink IS most
# of the frame: thirty-four requested crystals came back as twenty-one, and they
# arrived bunched wherever the sampler happened to get lucky rather than spread
# round the arena. Drawing an angle and a depth in the ellipse's own coordinates
# instead puts every candidate on the bank by construction and spreads them evenly
# all the way round it, which is what the reference has and what "surround the
# arena" means.
#
# `deep` is how far out past the shore it may sit, in arena units.
func _shore_point(rng: RandomNumberGenerator, cam: Camera3D, vp: Vector2,
		near: float, far: float) -> Vector3:
	if _arena.x < 0.01:
		return Vector3.INF
	for _try in TRIES:
		# THE ANGLE IS DRAWN THROUGH THE PICTURE, not off a uniform turn of the
		# circle, and the difference is visible in every render: a keystoned ground
		# plane gives the arena's near and corner arcs several times the screen area
		# of its far arc, so an angle drawn uniformly puts most of the dressing
		# along the top of the frame and leaves the two bottom corners — where the
		# reference stands its biggest banks — with almost nothing on them.
		#
		# Picking a point in the FRAME and keeping only its direction weights the
		# draw by how much picture the bank actually occupies out that way, which is
		# the same argument _screen_point is built on, applied to an angle instead of
		# a position. The point itself is thrown away; only the bearing survives, so
		# the prop still lands at a controlled depth on the berm's own profile.
		var f0 := Vector2(rng.randf_range(EDGE_X, 1.0 - EDGE_X),
			rng.randf_range(EDGE_TOP, 1.0 - EDGE_BOTTOM))
		var d0 := (f0 - _arena_at) / _arena
		if d0.length() < 0.80:
			continue
		var a := atan2(d0.y, d0.x)
		var dir := Vector2(cos(a) * _arena.x, sin(a) * _arena.y)
		var e0 := _shore_e(a, vp)
		var out := lerpf(near, far, rng.randf())
		var f := _arena_at + dir * (e0 + out)
		if f.x < EDGE_X or f.x > 1.0 - EDGE_X \
				or f.y < EDGE_TOP or f.y > 1.0 - EDGE_BOTTOM:
			continue
		var q := _ice_at_screen(f * vp, cam)
		if q == Vector3.INF:
			continue
		# ...and it stands on the BERM, not on the ice under it.
		var cp := _ice_at_screen(
			(_arena_at + dir * (e0 + float(BERM_PROFILE[2][0]))) * vp, cam)
		if cp != Vector3.INF:
			q.y = ICE_Y + _berm_profile_at(out, _berm_crest(a, cp, cam, vp))
		return q
	return Vector3.INF


# ...and the same for the screen-rectangle sampler.
func _bank_screen_point(rng: RandomNumberGenerator, x0: float, x1: float,
		y0: float, y1: float, cam: Camera3D, vp: Vector2, clear: float) -> Vector3:
	for _outer in 6:
		var p := _screen_point(rng, x0, x1, y0, y1, cam, vp, clear)
		if p == Vector3.INF:
			return p
		if _on_bank(p, cam, vp):
			return p
	return Vector3.INF


# ---------------------------------------------------------------------------
# The ice shader
# ---------------------------------------------------------------------------
# Flat geometry, shaded entirely analytically. Six terms, in this order, and the
# order is the design:
#
#   depth    the sheet's own colour: lightest under the play area, falling away
#            with distance AND out to the sides. This is what frames the board
#            without putting anything near it.
#   stage    a wide, soft bloom centred on the board, so the buttons rest on a
#            surface rather than float on a wash. It is the only term that is
#            allowed inside the play area and it has no edges anywhere.
#   frost    two octaves of value noise at very low amplitude — the grain that
#            stops a flat blue plane reading as a flat blue plane. +-5 counts.
#   cracks   thin frost lines, MASKED OUT of the play area entirely (crack_span)
#            and faded with distance so they never alias in the far field.
#   polish   a broad mirrored sheen and a fresnel toward the pale sky. This is what
#            makes it read as ICE rather than as a blue floor, and both terms are
#            strongest at the top of the frame, which is furthest from the buttons.
#   fog      the far dissolve, applied last so no highlight survives into it and
#            the surface simply stops existing rather than having an edge.
#
# Everything is in radiance, because the palette was solved to radiance once at
# build time. Nothing in here converts a colour.
const ICE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
""" + SKY_COMMON + """
uniform vec3 c_near;
uniform vec3 c_mid;
uniform vec3 c_sheen;
uniform vec3 c_frost;
uniform vec3 c_aurora;
uniform vec3 c_mist;
uniform vec3 c_bank_lo;
uniform vec3 c_bank_hi;
uniform vec3 c_lip;
uniform vec4 arena;           // (half-width, half-depth, shore band, lip width),
                              //  the first two in METRES and the last two in
                              //  arena units — see THE ARENA
uniform vec2 arena_at;        // ...and where its centre sits on screen. It is NOT
                              //  the middle of the board: the ellipse is pushed
                              //  DOWN the frame so its near shore falls below the
                              //  bottom edge and the ice runs out of the picture.
uniform float arena_wob;      // how far the shoreline wanders, in arena units
uniform vec4 corner;          // (fade-in y0, y1, strength, x reach) — how hard the
                              //  shore is pulled in at the two bottom corners
uniform float shore_gain;
uniform vec3 glint_dir;
uniform vec2 depth_span;      // where the near-to-deep ramp runs, in metres away
uniform vec2 haze_span;       // and where the surface has dissolved entirely
uniform vec2 side_span;       // the same deepening applied sideways
uniform vec2 stage_span;      // the bloom under the play area, in metres from the middle
uniform vec2 crack_span;      // where cracks are allowed to appear, likewise
uniform float stage_gain;
uniform float crack_gain;
uniform float horizon_band;   // how much of the frame the ice takes to reach HAZE
uniform vec3 refl;            // (how far the sky's reflection reaches, how strong,
                              //  how much the ice breaks it up)
uniform vec2 moon_path;       // (how wide the moon's glitter column is, how strong)
uniform vec4 vig;             // (in, out, gain, unused) — the grade
uniform vec2 vig_at;          // ...and where its centre sits on screen
uniform float dim;            // the milestone events' cool-down of the whole scene
uniform vec2 sweep;           // (where across the frame, how strong) — level 8 only

varying vec3 wpos;

// hash12, vnoise, skyline, aurora_amp and sky_at all come from SKY_COMMON above —
// this shader compiles the same sky the card does, because it has to REFLECT it.

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// --- the horizon, FIRST, and in screen space.
	//
	// The ground plane fills this frame from corner to corner (see HORIZON_FY),
	// so the only way the picture gets a sky is for the ice to stop drawing itself.
	// It stops on a SCREEN line rather than at a world distance because that is the
	// same line on Easy, Medium and Hard and at every aspect — the same reason the
	// far wall is placed by screen band and not by z.
	//
	// A discard is free here: this material is opaque and unshaded, there is no
	// depth pre-pass to invalidate and nothing behind the cut but the sky card.
	if (SCREEN_UV.y < horizon) {
		discard;
	}
	vec2 p = wpos.xz;
	float away = -wpos.z;
	float rad = length(p);
	float asp = VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0);

	// --- THE ARENA, and it is computed FIRST because half the terms below are
	//     gated on it.
	//
	// `ae` is the distance out from the middle of the board in ARENA UNITS: below
	// 1.0 is the rink, above it is the bank. One slow noise octave wanders the
	// shoreline by a few per cent so the oval is a cleared pond and not a painted
	// circle — low frequency on purpose, because a shoreline with detail in it is a
	// second busy thing running right around the play area.
	// The shape is on the SCREEN (see THE ARENA); the WOBBLE is on the ground, so
	// the shoreline wanders with the ice under it rather than with the frame.
	float ae = length((SCREEN_UV - arena_at) / max(arena.xy, vec2(0.01)))
		+ (vnoise(p * 0.17 + vec2(6.3, 2.9)) - 0.5) * 2.0 * arena_wob;
	// THE BOTTOM CORNERS. The same function _corner_bias is in GDScript, and the
	// two MUST stay identical: _solve_arena grows the ellipse until this term
	// cannot reach a button, and that guarantee is only worth anything while both
	// halves draw the same shape. Written as 1 - smoothstep(lo, hi, m) rather than
	// smoothstep(hi, lo, m) because GLSL leaves the reversed-edge form UNDEFINED.
	float cm = min(SCREEN_UV.x, 1.0 - SCREEN_UV.x);
	ae += corner.z * smoothstep(corner.x, corner.y, SCREEN_UV.y)
		* (1.0 - smoothstep(0.0, corner.w, cm));
	// 1 on the ice, 0 on the snow, and the transition is soft: a hard edge here
	// would be the highest-contrast line in the frame and it encircles the board.
	float onice = 1.0 - smoothstep(1.0 - arena.z, 1.0, ae);

	// Detail falls off with distance, for the reason the lake's does: a 30 cm
	// feature is a couple of pixels across up at the top of the frame, and left at
	// full strength the far field crawls with aliasing instead of receding.
	//
	// The RANGE is the thing to get right and the first version got it wrong by
	// copying the lake's. This camera stands about 10 m back, so every pixel in the
	// frame is 7-16 m from it: a falloff that is over by 11 m switches the detail
	// off across the whole picture, and the grain and the cracks below were
	// invisible rather than subtle. Measured against the board's own camera fit.
	// 11 to 24 m, and it moved out when the board was re-seated. The camera solves
	// its own distance from the board's size, and asking it to frame a SMALLER board
	// (BackgroundScenes.frame_bias) puts it about a metre and a half further back —
	// so a falloff that ended at 19 was switching the ice's whole detail set off
	// across the middle of the frame, which is exactly the symptom this span was
	// written to fix the first time.
	float det = 1.0 - smoothstep(11.0, 24.0, distance(CAMERA_POSITION_WORLD, wpos));

	// --- depth. Away from the camera AND out to the sides.
	float dep = clamp((away - depth_span.x) / max(depth_span.y - depth_span.x, 0.001),
		0.0, 1.0);
	float sid = smoothstep(side_span.x, side_span.y, rad);
	// THE RINK DEEPENS TOWARD ITS OWN SHORE, not toward the horizon, and that swap
	// is what turns a sheet of ice into an arena. It used to run off world distance
	// (dep) and world radius (sid), which on this camera means the ice was already
	// at its deepest value by the time it reached the shoreline — so both sides of
	// the shore were the same colour and the boundary, correctly placed, could not
	// be seen. A rink is LIT: brightest in the middle where the game is played,
	// falling away to its edges, and the bank beyond is darker still.
	//
	// The world terms are kept at a fraction of their old weight, because genuine
	// distance haze still has to happen inside the rink or the far ice reads as
	// flat as a table.
	float bowl = smoothstep(0.34, 1.02, ae);
	float deepness = clamp(max(bowl, max(dep * dep, sid) * 0.50), 0.0, 1.0);
	vec3 col = mix(c_near, c_mid, deepness);

	// --- the stage. Widest, softest term in the frame and the only one under the
	//     buttons: a slow rise toward the middle with no edge at either end.
	float stage = 1.0 - smoothstep(stage_span.x, stage_span.y, rad);
	col += c_frost * (stage_gain * stage * stage);

	// --- the aurora. A BAND rather than a ramp: it peaks halfway to the fog and is
	//     gone at both ends, so the one colour that is not ice sits in the middle
	//     distance where the eye reads it as atmosphere, and never near a button.
	col += c_aurora * (0.42 * dep * (1.0 - dep) * (1.0 - 0.5 * sid));

	// --- SWEPT ICE. Broad, soft bands of very slightly different value, stretched
	//     along one axis and crawling at a couple of centimetres a second.
	//
	// This is the ONE detail term with no mask on it — it runs under the buttons and
	// through the middle of the frame — and it is allowed there because of its
	// amplitude, which is about four counts on a surface at seventy. The rule this
	// file is written to says the middle of the picture must be the QUIETEST part of
	// it; it does not say the middle has to be empty, and for three passes it was.
	//
	// Every other term here is masked out of the play area by radius, so as the
	// board was seated lower and the ice around it grew, the largest area of the
	// frame became the one area nothing was allowed to touch. Polished ice is not
	// featureless — it is swept, and it holds broad soft bands of light that a flat
	// gradient does not. That is what this is, and it is why it may be everywhere.
	float sw1 = vnoise(p * vec2(0.115, 0.30) + vec2(TIME * 0.018, 0.0));
	float sw2 = vnoise(p * vec2(0.052, 0.14) + vec2(-TIME * 0.009, 7.3));
	col *= 1.0 + 0.075 * (sw1 - 0.5) + 0.055 * (sw2 - 0.5);

	// --- frost grain. A multiplier on the ice's own colour rather than an added
	//     light, so it darkens as well as lightens and cannot lift the black point.
	float g1 = vnoise(p * 0.30);
	float g2 = vnoise(p * 1.25 + vec2(19.3, 7.1));
	// A third octave, STRETCHED along one axis. Isotropic noise reads as dirt; ice
	// freezes and gets swept in a direction, and one anisotropic octave is the whole
	// difference between "a blue plane with grain on it" and "a surface with a
	// history". It is the only grain term allowed at full strength under the board,
	// because at +-2 counts it is texture rather than detail.
	float g3 = vnoise(p * vec2(2.1, 0.42) + vec2(5.7, 31.4));
	col *= 1.0 + 0.115 * ((g1 - 0.5) * 1.4 + (g2 - 0.5) * 0.6 * det)
		+ 0.048 * (g3 - 0.5) * det;

	// --- cracks. The mask is FIRST and it is hard: outside the play area or
	//     nothing. A ridge of noise, which is what gives a branching line rather
	//     than a stripe, at two scales so they cross.
	// `onice` joins the mask, so every one of the ice's own detail terms — cracks,
	// layers, pressure ridges and sparkles — stops at the shore. It is also what
	// makes the arena CHEAPER than the sheet it replaced over most of the frame:
	// the bank takes this branch never and the reflection branch below never, and
	// between them those are the two expensive halves of this shader.
	float mask = smoothstep(crack_span.x, crack_span.y, rad) * det * onice;
	if (mask > 0.001) {
		float f1 = vnoise(p * 0.34 + vec2(3.7, 11.9));
		float f2 = vnoise(p * 0.77 + vec2(23.1, 5.5));
		float cr = smoothstep(0.030, 0.0, abs(f1 - 0.5)) * 1.0
			+ smoothstep(0.018, 0.0, abs(f2 - 0.5)) * 0.55;
		col += c_frost * (crack_gain * cr * mask);

		// --- LAYERED ICE. Broad contour bands off a large, slow noise: sheets that
		//     froze at different times, seen edge on. Wide and soft where the cracks
		//     are thin and sharp, so the two read as different kinds of history
		//     rather than as more of the same line. Inside the same mask and the
		//     same branch — the play area may have neither.
		float lay = vnoise(p * 0.115 + vec2(41.2, 8.6));
		float band = abs(fract(lay * 7.0) - 0.5);
		col += c_frost * (0.10 * smoothstep(0.30, 0.06, band) * mask);

		// --- PRESSURE RIDGES. Long, nearly straight seams where two sheets have
		//     met and buckled, running roughly ACROSS the lake rather than in the
		//     branching pattern the cracks above make. They are what a frozen lake
		//     has that a cracked pane of glass does not, and they are the term that
		//     gives the middle of this frame something to be.
		//
		//     Nearly straight, not straight: the noise is sampled on a heavily
		//     stretched axis, so a seam wanders by a few centimetres over metres.
		float seam = vnoise(p * vec2(0.085, 0.62) + vec2(13.7, 2.4));
		float ridge = smoothstep(0.055, 0.0, abs(seam - 0.5));
		// A dark shadow on one side and a lit crest on the other, which is what
		// makes a seam read as something standing UP out of the ice.
		float side = seam - 0.5;
		col += c_frost * (0.105 * ridge * mask * step(0.0, side));
		col *= 1.0 - 0.15 * ridge * mask * step(side, 0.0);

		// --- SPARKLES. A sparse cell grid, one point in about seven cells, each
		//     twinkling on its own phase. They are the only thing in this background
		//     that gets anywhere near a button's brightness, which is why they are
		//     three pixels across, outside the play area by the same mask as the
		//     cracks, and gone with distance like everything else.
		//
		//     AND THEY ARE THE FRAME'S BRIGHTEST PIXEL. tools/ice_shot.tscn's
		//     "brightest anywhere in it" has landed on a sparkle on all three boards
		//     every time it has been run — around 125-129 counts against a Hard
		//     button's mean of 134. Four palette edits were spent on crystals,
		//     plates and the far wall before that was established, none of which
		//     moved the number by a tenth: THIS is the term to change if that
		//     measurement ever goes over, and the harness prints the peak's rgb now
		//     so nobody has to guess again.
		vec2 sp = p * 3.1;
		vec2 sc = floor(sp);
		float sh = hash12(sc);
		if (sh > 0.855) {
			vec2 sf = fract(sp) - vec2(hash12(sc + 3.7), hash12(sc + 9.1));
			float tw = 0.5 + 0.5 * sin(TIME * 2.1 + sh * 61.0);
			col += c_sheen * (smoothstep(0.012, 0.0, dot(sf, sf))
				* tw * tw * 0.42 * mask);
		}
	}

	// --- polish. The sheet is a mirror, so its normal is straight up and both of
	//     these are pure functions of where the camera is: a tight glint where the
	//     mirrored light lands, and the pale sky sitting in the surface everywhere
	//     the view grazes it.
	//
	// Exponent 2.5 on the fresnel rather than the textbook 5, and for the reason
	// the lake measured: this camera looks down at 33.5 deg and never gets near
	// grazing, so a fifth power of (1 - dot) is a term that cannot be seen at any
	// mix weight. The polish is broken up by a large, slow noise so the ice reads
	// as swept and imperfect rather than as a mirror.
	vec3 vdir = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 hv = normalize(normalize(glint_dir) + vdir);
	float nh = clamp(hv.y, 0.0, 1.0);
	float swept = 0.55 + 0.45 * vnoise(p * 0.16 + vec2(TIME * 0.012, 0.0));
	col += c_sheen * (pow(nh, 42.0) * 0.055 + pow(nh, 7.0) * 0.016) * swept * onice;
	float fres = pow(1.0 - clamp(vdir.y, 0.0, 1.0), 2.5);
	col = mix(col, c_sheen, clamp(fres * 0.42, 0.0, 0.13) * onice);

	// --- THE BANK, and the SHORE.
	//
	// Everything above this line was the rink; everything outside it is snow, and
	// the two are blended here rather than branched because the shore between them
	// is a soft band a few per cent of the arena wide and both sides of it have to
	// be evaluated inside it. Outside that band `onice` is exactly 0 or exactly 1
	// and one of the two colours is thrown away — which costs two noise samples on
	// the ice and nothing at all on the snow, where the branches it skips are the
	// expensive ones.
	//
	// The snow is SHADED, not textured: a broad drift noise decides how much of the
	// bank is turned toward the light, and a finer one breaks its surface. That is
	// the whole model. It is deliberately the flattest, quietest large area in the
	// picture — the reference's banks measure L 40-82 against a rink at 145-168,
	// and that ratio, not any amount of white, is what makes them read as snow.
	if (onice < 0.999) {
		float d1 = vnoise(p * 0.155 + vec2(31.7, 12.4));
		float d2 = vnoise(p * 0.62 + vec2(4.9, 27.1));
		// Drifts lie ACROSS the wind, so the coarse octave is stretched — the same
		// reason the ice has one anisotropic grain term.
		float d3 = vnoise(p * vec2(0.42, 1.35) + vec2(17.2, 3.8));
		float lit = clamp(0.24 + 0.70 * d1 + 0.38 * (d2 - 0.5) * det
			+ 0.34 * (d3 - 0.5), 0.0, 1.0);
		// LINEAR in `lit`, and it was squared first. Squaring a term whose mean is
		// about a half throws away three quarters of the range it has to work with,
		// and what came out was an even dark field — snow with no drifts in it,
		// which reads as ground. The bank is the largest new area in the picture
		// and the ONLY thing it has to do is have form.
		vec3 bank = mix(c_bank_lo, c_bank_hi, lit);
		// The bank falls away with distance toward the same HAZE the ice ends at,
		// so the two arrive at the horizon together and the shore does not survive
		// into the fog as a line across the far field. Toward c_mid — which is
		// where this went first — is toward the RINK's own colour, i.e. the far
		// bank fading back into the thing it is supposed to be distinct from.
		bank = mix(bank, c_haze, clamp(dep * dep * 0.75, 0.0, 0.75));
		col = mix(bank, col, onice);

		// --- THE LIP. The crest of the bank where it meets the ice, catching the
		//     light. It is the arena's edge made visible, and it is the ONE
		//     highlight this background carries that is not a sparkle: without it
		//     the ice and the snow meet as two flat values and the rink reads as a
		//     stain rather than as a surface something surrounds.
		//
		//     It sits just OUTSIDE the shore (on the snow side), because that is
		//     where a bank of snow actually catches light — a lip drawn inside the
		//     ice is a ring painted on the floor.
		float lip = smoothstep(1.0, 1.0 + arena.w * 0.5, ae)
			* (1.0 - smoothstep(1.0 + arena.w * 0.5, 1.0 + arena.w, ae));
		// Broken up so it is a shoreline and not a stencil, and taken by distance
		// like everything else so the far shore is a suggestion of one.
		float brk = 0.55 + 0.45 * vnoise(p * 0.95 + vec2(8.1, 21.6));
		col += c_lip * (shore_gain * lip * brk * (0.35 + 0.65 * det));
	}

	// --- MIST BANKS, between the polish and the fog and in that order for a reason:
	//     mist lies ON the surface, so it has to cover the sheen (a highlight
	//     shining through fog is glass, not ice) and be covered by the far dissolve
	//     (or the picture ends in a bright band instead of fading out).
	//
	//     Two octaves crawling in different directions at a few centimetres a
	//     second — slow enough that nothing in it can be watched, which is the whole
	//     brief for atmosphere. The zone term keeps it out of the middle: full
	//     strength in the distance and in the side gutters, nothing under the board.
	float m1 = vnoise(p * 0.082 + vec2(TIME * 0.011, TIME * 0.004));
	float m2 = vnoise(p * 0.205 + vec2(-TIME * 0.017, 6.9));
	float mist = smoothstep(0.36, 0.84, m1 * 0.68 + m2 * 0.32);
	// ...and it lies on ICE. A bank of snow with fog sitting on it is the same
	// value as the rink again, which is the whole thing the arena exists to avoid —
	// and MIST is lighter than the bank, so left ungated this term alone put the
	// shoreline back where it could not be seen. It keeps the far field (dep) so
	// the distance still has atmosphere in it.
	float mzone = max(smoothstep(stage_span.y * 0.62, side_span.y, rad) * onice,
		dep * dep * mix(0.45, 1.0, onice));
	col = mix(col, c_mist, clamp(mist * mzone * 0.58, 0.0, 0.58));
	// ...and it takes back what it gave. A bank that only ever LIGHTENS raises the
	// whole background's mean, which is the one measurement this file is answerable
	// to; the clear air between banks is darker than the ice would have been on its
	// own, so the far field gains contrast at the same average brightness.
	col *= 1.0 - 0.105 * (1.0 - mist) * mzone;

	// --- THE REFLECTION, and the reason this file compiles the sky twice.
	//
	// A frozen lake at night that does not carry the sky on it is a blue floor. This
	// is the single term that makes the surface read as ICE rather than as ground,
	// and it is nearly free: the sky is already a pure function of two screen
	// numbers (see SKY_COMMON), so reflecting it is calling that function with the
	// vertical one MIRRORED about the horizon.
	//
	// Three things make it a reflection rather than a mirror:
	//
	//   * it is SQUASHED. refl.x is how much of the frame the whole sky folds into —
	//     a plane seen from 33.5 deg above returns a compressed image, and an
	//     uncompressed one reads as a hole in the floor with a second world in it;
	//   * it is BROKEN, by the ice's own noise, in u and in s. Ice is not water and
	//     not glass: the reflection has to come apart into bands;
	//   * and it STOPS. Its weight falls away from the shore as the square of the
	//     distance and is masked out of the play area entirely, so no button ever
	//     stands on an aurora.
	//
	// What comes with it for free is the best detail in the picture: the moon lays a
	// path of light down the ice, because the moon is in sky_at and the reflection
	// does not know it is a moon.
	// ...and it is the RINK that reflects, not the snow. Snow is the one surface in
	// this picture with no specular in it at all, so gating both terms on `onice`
	// is physically the obvious thing and also the largest single saving the arena
	// buys back: outside the shore this whole branch — a second evaluation of the
	// sky for every pixel — is skipped.
	float below = SCREEN_UV.y - horizon;
	if (below > 0.0 && below < refl.x && onice > 0.002) {
		float sr = 1.0 - below / refl.x;            // 1 at the shore, 0 where it ends
		// Two scales of break-up: a slow swell that bends the whole reflection, and
		// a finer one that shivers its edges. Both crawl, at a few centimetres a
		// second, which is the same clock the mist and the polish are on.
		float b1 = vnoise(p * 0.55 + vec2(TIME * 0.023, 0.0)) - 0.5;
		float b2 = vnoise(p * 2.30 + vec2(-TIME * 0.031, 5.5)) - 0.5;
		float wob = (b1 * 0.75 + b2 * 0.25) * refl.z;
		vec3 rf = sky_at(clamp(SCREEN_UV.x + wob, 0.0, 1.0),
			clamp(sr + wob * 0.55, 0.0, 1.0), asp);
		// HOLD, then fade — not a falloff from the shore, which is what the first
		// version did and why there was no reflection worth the name.
		//
		// The sky's own bottom rows ARE haze (that is what hides the join), so a
		// weight that peaks at the shoreline peaks on the one part of the sky that
		// has nothing in it. Everything worth reflecting — the aurora, the moon, the
		// crests — lives at s 0.2-0.6, which lands roughly HALF WAY down this band;
		// so the weight is flat across the first half and only then falls away.
		float w = refl.y * (1.0 - smoothstep(0.50, 1.0, 1.0 - sr)) * onice;
		col = mix(col, rf, clamp(w, 0.0, refl.y));

		// --- THE MOON'S PATH. A column of broken glitter under the moon, and the
		//     one highlight this background is allowed. Not a consequence of the
		//     reflection above — that returns a disc a few pixels across — but the
		//     thing a frozen lake actually does with a moon: every facet tilted the
		//     right way sends it back, so the return is a COLUMN, and it breaks up
		//     into flakes rather than staying a line.
		float mx = (SCREEN_UV.x - moon_at.x) * asp / moon_path.x;
		float column = exp(-mx * mx);
		if (column > 0.004) {
			// Facets: fine across the path and coarse along it, so the glitter reads
			// as ice catching the light and not as a beam. It crawls at a
			// hundredth of the frame a second, which is under the threshold at
			// which anything in this picture may be watched.
			float f1 = vnoise(vec2(SCREEN_UV.x * 150.0,
				SCREEN_UV.y * 34.0 + TIME * 0.06));
			float f2 = vnoise(vec2(SCREEN_UV.x * 44.0 + 9.0,
				SCREEN_UV.y * 90.0 - TIME * 0.04));
			float glint = smoothstep(0.55, 0.98, f1 * 0.65 + f2 * 0.35);
			col += c_moon * (column * glint * moon_path.y * sr * onice);
		}
	}

	// --- THE GRADE, and it goes in before the fog so the far field keeps its own
	//     dissolve. See VIG_GAIN: this background may not add a highlight, so the
	//     tonal range it did not have is bought at the dark end instead.
	vec2 vd = (SCREEN_UV - vig_at) * vec2(asp * 0.60, 1.0);
	col *= 1.0 - vig.z * smoothstep(vig.x, vig.y, length(vd));

	// --- the light sweep. Off for all but about a second of every eighth level,
	//     and a pure function of a uniform when it is on: a soft vertical band of
	//     the same sheen the ice already mirrors, travelling across the frame. It
	//     goes in BEFORE the fog so the far ice does not carry it.
	if (sweep.y > 0.001) {
		float sd = (SCREEN_UV.x - sweep.x) / 0.24;
		col += c_sheen * (exp(-sd * sd) * sweep.y * 0.16);
	}

	// --- fog, last, and now in two parts.
	//
	// The world-space one is the original: distance eats the surface. It never
	// completes inside this frame — measured through the board's own camera fit,
	// the furthest ice the player can see is about 2.6 m past the board, where this
	// span has barely started — which is exactly why the second one exists.
	col = mix(col, c_haze, smoothstep(haze_span.x, haze_span.y, away));
	// The screen-space one is the SHORE. The ice has to arrive at HAZE by the time
	// it reaches the cut or the horizon is a visible seam, and it cannot be asked to
	// do that in metres for the reason above. This is the join, and both sides of it
	// are the same colour, so there is nothing to see where the two meet.
	// Written as 1 - smoothstep(lo, hi, x) and not as smoothstep(hi, lo, x):
	// GLSL leaves the reversed-edge form UNDEFINED, and this is the one term in
	// the file whose exact value at its end matters — it is the join.
	col = mix(col, c_haze,
		1.0 - smoothstep(horizon, horizon + horizon_band, SCREEN_UV.y));

	ALBEDO = col * dim;
}
"""


# ---------------------------------------------------------------------------
# The sky shader
# ---------------------------------------------------------------------------
# Everything above the waterline, in one fragment shader, and every term in it is a
# function of SCREEN_UV and TIME. Nothing here is in world space at all.
#
# THAT IS THE WHOLE TRICK AND IT IS WORTH SAYING PLAINLY. A background that has to
# be correct on three boards, at every aspect, through a camera whose distance is
# solved per board, cannot compose a distance in metres — the lake and this file's
# own far wall both learned that, and both answered it by placing things FROM the
# frame. The sky takes the last step: it is not placed from the frame, it IS the
# frame. The moon is at 0.815 of the width because that is where it should be in
# the picture; there is no moon, no distance to it, and nothing to fit.
#
# What that costs is that the sky cannot parallax, and at this camera it never
# would: the board's camera does not move during a round.
#
# The terms, in the order they are laid down, which is back to front:
#
#   gradient   deep blue-violet overhead, colder and lighter at the horizon
#   stars      a sparse cell grid, dim, fading out toward the horizon haze
#   moon       a soft disc and a wide halo, up in the right-hand third
#   aurora     two curtains, drawn BEFORE the mountains so the ranges occlude them
#   ranges     two procedural skylines, the far one pale, the near one dark
#   cloud      a slow band of mist lying along the mountains' feet
#   haze       the last few per cent into HAZE, which is what the ice fades to
# The sky is written ONCE, as a function, and both the sky card and the ICE compile
# it — because the second thing a frozen lake at night has to do, after having a sky
# at all, is REFLECT it.
#
# That is why this is a shared string rather than two shaders that look alike. A
# reflection assembled from a second, similar set of terms is a reflection that
# drifts out of step with what it reflects on the first edit anybody makes to
# either; `sky_at` cannot, because there is one of it.
#
# It takes BAND coordinates — u across the frame, s from 0 at the top of the picture
# to 1 at the horizon — so the ice reflects by calling it with s MIRRORED and u
# nudged by the ice's own noise. Everything in it is a function of those two numbers
# and TIME; there is no geometry behind any of it.
const SKY_COMMON := """
uniform vec3 c_top;
uniform vec3 c_low;
uniform vec3 c_haze;
uniform vec3 c_star;
uniform vec3 c_moon;
uniform vec3 c_moon_halo;
uniform vec3 c_rng_far;
uniform vec3 c_rng_mid;
uniform vec3 c_rng_near;
uniform vec3 c_rng_cap;
uniform vec3 c_aur_a;
uniform vec3 c_aur_b;
uniform float horizon;
uniform vec2 moon_at;
uniform float aur_base;
uniform float aur_swell;
uniform float aur_period;
uniform float aurora_boost;   // the level-8 celebration, added on top of the phase
uniform float aur_cap;        // ...and the ceiling the sum may never pass

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// One skyline: three octaves along a single axis. `k` is how many peaks fit across
// the frame and `sd` picks which range this is.
float skyline(float x, float k, float sd) {
	return vnoise(vec2(x * k + sd, sd)) * 0.62
		+ vnoise(vec2(x * k * 2.3 + sd * 3.1, sd + 1.0)) * 0.26
		+ vnoise(vec2(x * k * 5.3 + sd * 7.7, sd + 2.0)) * 0.12;
}

// How bright the aurora is RIGHT NOW. Pulled out of sky_at so the ice can key its
// own terms off the same number without shading a second sky.
//
// A smoothstep pair on the period's own phase, not a sine: the point of the brief's
// "occasional" is that most of the cycle is FLAT. Nothing resets this clock, so the
// swell cannot line up with anything the player did.
float aurora_amp() {
	float ph = fract(TIME / aur_period);
	float swell = smoothstep(0.0, 0.09, ph) * (1.0 - smoothstep(0.14, 0.30, ph));
	swell *= 0.72 + 0.28 * sin(TIME * 0.037);
	return aur_base + aur_swell * swell + aurora_boost;
}

// The three ranges, as a height above the horizon in band units. Separated out
// because the ICE needs the near range's silhouette to know where its own
// reflection of the mountains has to stop.
//
// `mid` is what keeps the MIDDLE of the frame open: all three skylines are pulled
// down toward the horizon in the centre third, so the topmost button crosses quiet
// sky and never a peak.
vec3 range_heights(float u) {
	float mid = exp(-pow((u - 0.5) / 0.26, 2.0));
	return vec3(
		(0.30 + 0.34 * skyline(u, 5.9, 21.0)) * (1.0 - 0.50 * mid),
		(0.22 + 0.32 * skyline(u, 4.6, 0.0)) * (1.0 - 0.46 * mid),
		(0.11 + 0.24 * skyline(u, 3.0, 11.0)) * (1.0 - 0.36 * mid));
}

// WHICH WAY A SLOPE FACES, from the skyline's own gradient: +1 where the range
// falls away toward the moon and is therefore lit, -1 where it climbs away from it
// and is in shadow.
//
// This is the term that turns three coloured fills into three mountain ranges. A
// skyline is a silhouette and a silhouette is flat, however good its outline is —
// what says "mountain" is that every peak has a bright flank and a dark one meeting
// on the ridge. It costs two extra skyline() calls per range and it is the single
// biggest thing in this shader.
float range_face(float u, float k, float sd, float towards) {
	float e = 0.0045;
	float g = (skyline(u + e, k, sd) - skyline(u - e, k, sd)) / (2.0 * e);
	return clamp(-g * towards * 0.55, -1.0, 1.0);
}

// One range: the fill, its facets, its snow and the air in front of it.
vec3 range_shade(float u, float s, float top, float k, float sd, vec3 body,
		vec3 cap, vec3 haze, float capw, float hz0, float hz1, float lit) {
	// Lit and shadowed flanks. The shadow side goes toward the haze rather than to
	// black, because these are miles away and the air between is what limits how
	// dark anything out there can be.
	float face = range_face(u, k, sd, sign(0.815 - u));
	vec3 c = mix(body * (1.0 - 0.16 * max(-face, 0.0)),
		mix(body, cap, 0.55 * lit), max(face, 0.0) * 0.75);
	// Snow, on the crest and mostly on the lit flank — a cap that runs evenly along
	// a whole skyline is a painted stripe, not snow.
	float crest = 1.0 - smoothstep(0.0, capw, s - top);
	c = mix(c, cap, crest * (0.30 + 0.55 * max(face, 0.0)) * lit);
	return mix(c, haze, hz0 + hz1 * smoothstep(0.62, 1.0, s));
}

vec3 sky_at(float u, float s, float asp) {
	s = clamp(s, 0.0, 1.0);
	float v = s * horizon;
	vec3 col = mix(c_top, c_low, pow(s, 0.75));

	// --- stars. Sparse (one cell in forty), dim, and gone by the time the haze
	//     starts: a star inside the mountains' fog is a pixel of noise.
	vec2 sp = vec2(u * asp, v) * 90.0;
	vec2 sc = floor(sp);
	float sh = hash12(sc);
	if (sh > 0.945) {
		vec2 sf = fract(sp) - vec2(hash12(sc + 1.7), hash12(sc + 4.3));
		// Twinkling at a different rate per star and never all the way off, so the
		// field breathes instead of blinking.
		float tw = 0.62 + 0.38 * sin(TIME * 0.65 + sh * 77.0);
		col += c_star * (smoothstep(0.075, 0.0, dot(sf, sf)) * tw
			* (1.0 - smoothstep(0.42, 0.92, s)));
	}

	// --- the moon: a wide, faint bloom, a tighter halo, then the disc. Circular in
	//     PIXELS, which is what the aspect correction on x is for — a moon authored
	//     in UV is an ellipse on every device but one.
	vec2 md = (vec2(u, v) - moon_at) * vec2(asp, 1.0);
	float ml = length(md);
	col = mix(col, c_moon_halo, exp(-ml / 0.150) * 0.30);
	col = mix(col, c_moon_halo, exp(-ml / 0.048) * 0.55);
	// The disc, with a soft edge and a gradient across it, so it reads as a sphere
	// rather than as a hole punched in the sky. Two faint maria on the lit side,
	// because a perfectly even disc reads as a lamp.
	float disc = 1.0 - smoothstep(0.020, 0.030, ml);
	float mare = 1.0 - 0.10 * smoothstep(0.014, 0.004,
		length(md - vec2(0.006, -0.005)))
		- 0.07 * smoothstep(0.010, 0.003, length(md + vec2(0.008, 0.004)));
	col = mix(col, c_moon * (0.82 + 0.18 * clamp(-md.x * 24.0, -1.0, 1.0)) * mare,
		disc);

	// --- the aurora, before the ranges: it is the furthest thing in the picture and
	//     the mountains have to stand in front of it.
	float amp = aurora_amp();
	vec3 aur = vec3(0.0);
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float dr = TIME * (0.021 + 0.009 * fi);
		// The curtain's centre line: two waves with no common period, so it never
		// repeats inside a session.
		float cy = 0.19 + 0.17 * fi
			+ sin(u * (4.1 + 1.7 * fi) + dr * 2.1 + fi * 2.0) * 0.105
			+ sin(u * (9.3 - 2.1 * fi) - dr * 1.4) * 0.045;
		float th = 0.115 + 0.055 * fi;
		float d = (s - cy) / th;
		float body = exp(-d * d * 2.4);
		// Folds. A curtain is vertical streaks and nothing else makes it read as
		// one; they drift sideways at a few per cent of the width a second.
		// Folds, and they are RAISED TO A POWER rather than mixed flat. An aurora
		// averaged across its own width is a pale smear — which is what this was,
		// and it was the brightest thing in the frame while reading as fog. The
		// exponent is what turns the same energy into streaks with dark between
		// them, and a streak at twice the brightness of a smear is a quarter of its
		// area, so the picture gets structure and LOSES its peak at the same time.
		float f1 = vnoise(vec2(u * 15.0 + dr * 2.6 + fi * 7.0, s * 1.1));
		float f2 = vnoise(vec2(u * 41.0 - dr * 4.1 + fi * 3.0, s * 0.6));
		float fold = pow(clamp(0.10 + 0.66 * f1 + 0.34 * f2, 0.0, 1.0), 2.1) * 1.9;
		// Faded out at both ends of the frame, so the curtain has no edges in it.
		float ends = smoothstep(0.0, 0.20, u) * (1.0 - smoothstep(0.80, 1.0, u));
		aur += mix(c_aur_a, c_aur_b, clamp(0.18 + 0.66 * u + 0.28 * fi, 0.0, 1.0))
			* (body * fold * ends);
	}
	// CAPPED, in radiance, and this is a guarantee rather than a tuning. Everything
	// else in this background is bounded by a colour constant; the aurora is the one
	// term that ADDS, so its brightness is the product of an amplitude, a fold and
	// a swell and can be argued about but not bounded. tools/ice_shot.tscn measures
	// the frame's brightest pixel against a button's mean, and at the top of a swell
	// that pixel was an aurora streak — so the sum gets a ceiling and the argument
	// ends.
	col += min(aur * amp, vec3(aur_cap));

	// --- the three ranges, back to front. THREE and not two, and that is where most
	//     of the depth up here comes from: one range is a silhouette, two is a
	//     distance, three is a country. Each is paler, taller and hazier than the
	//     one in front of it.
	vec3 h = range_heights(u);
	// The moon lights the crests on ITS side of the frame. It is a two-line term and
	// it is what stops the ranges reading as flat cut paper — a snow cap that is the
	// same value across a whole skyline is a shape, not a mountain.
	float lit = 0.55 + 0.75 * clamp(1.0 - abs(u - moon_at.x) * 1.8, 0.0, 1.0);

	float s0 = 1.0 - h.x;
	col = mix(col, range_shade(u, s, s0, 5.9, 21.0, c_rng_far, c_rng_cap, c_haze,
		0.050, 0.40, 0.34, lit), smoothstep(s0 - 0.010, s0 + 0.010, s));

	float s1 = 1.0 - h.y;
	col = mix(col, range_shade(u, s, s1, 4.6, 0.0, c_rng_mid, c_rng_cap, c_haze,
		0.065, 0.16, 0.40, lit), smoothstep(s1 - 0.009, s1 + 0.009, s));

	float s2 = 1.0 - h.z;
	col = mix(col, range_shade(u, s, s2, 3.0, 11.0, c_rng_near, c_rng_cap, c_haze,
		0.040, 0.01, 0.42, lit), smoothstep(s2 - 0.007, s2 + 0.007, s));

	// --- cloud. One slow band lying along the feet of the ranges, which is what
	//     stops three skylines meeting the ice as three hard lines.
	float cl = vnoise(vec2(u * 3.1 + TIME * 0.0055, s * 3.4 + 4.0));
	col = mix(col, c_haze,
		smoothstep(0.60, 1.0, s) * smoothstep(0.36, 0.78, cl) * 0.34);

	// --- and into HAZE for the last few per cent, which is exactly the colour the
	//     ice arrives at from the other side. The join is invisible because there is
	//     nothing to see: both sides of it are the same value.
	return mix(col, c_haze, smoothstep(0.92, 1.0, s));
}
"""


const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
""" + SKY_COMMON + """
uniform float dim;

void fragment() {
	// The card covers the frame and is only ever SEEN above the horizon — the ice is
	// opaque and nearer. Everything below the cut is thrown away in the first
	// instruction rather than shaded and then depth-rejected: this is a full-screen
	// quad on a phone, and four fifths of it is work nobody sees.
	//
	// A pixel the ice somehow misses comes out as the backdrop the 2D layer is
	// cleared to, which is HAZE — the same colour this shader would have painted
	// there anyway. So the saving costs nothing.
	if (SCREEN_UV.y > horizon + 0.01) {
		discard;
	}
	float asp = VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0);
	ALBEDO = sky_at(SCREEN_UV.x, SCREEN_UV.y / max(horizon, 0.001), asp) * dim;
}
"""


# ---------------------------------------------------------------------------
# Dressing
# ---------------------------------------------------------------------------
# Two MultiMeshes and one batched quad sheet, all generated here, all unshaded with
# their own analytic light, and none of them anywhere near a button.
#
# Every prop shader MIXES between two solved colours rather than scaling one, and
# that is not style — it is the lake's most expensive lesson repeated. `tone` gives
# the radiance that produces a chosen screen colour, and AgX at exposure 0.40 has an
# enormous toe (screen 4 needs 0.100, screen 24 needs 0.208), so a colour solved for
# screen (34,70,108) and multiplied by a lambert floor of 0.30 does not render as a
# darker version of itself. It renders BLACK.

# --- crystals ------------------------------------------------------------
# A cluster of three tapered spikes on a common base. One mesh, instanced: the
# variation is in the transform (scale, rotation, aspect) and in the per-instance
# custom data (a brightness jitter), never in a second mesh.
static func _shard_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	# base offset, height, width, lean, how much of the height is prism before the
	# tip starts. Four, not three: a cluster needs one that reads as the subject and
	# three that read as company, and the fourth is what stops it being a symmetry.
	var spikes := [
		[Vector2(0.00, 0.00), 1.00, 0.26, Vector2(0.02, 0.01), 0.62],
		[Vector2(-0.27, 0.09), 0.64, 0.19, Vector2(-0.13, 0.04), 0.55],
		[Vector2(0.25, -0.11), 0.48, 0.16, Vector2(0.11, -0.06), 0.58],
		[Vector2(0.06, 0.26), 0.33, 0.13, Vector2(0.03, 0.09), 0.50],
	]
	for sp: Array in spikes:
		var base: Vector2 = sp[0]
		var h: float = sp[1]
		var w: float = sp[2]
		var lean: Vector2 = sp[3]
		var shoulder: float = sp[4]
		# A hexagonal PRISM with a pyramid on it, which is what ice actually does and
		# — far more to the point — is a shape made of flat faces that each catch the
		# light differently. The five-sided cone this replaced had no facets at all:
		# its shading was a vertical gradient, so a crystal read as a paper dart
		# whatever colour it was given. Six flat sides at 60 degrees to each other
		# is the whole difference between a silhouette and a solid.
		var n := 6
		var ring: Array[Vector3] = []
		var top: Array[Vector3] = []
		for i in n:
			var a := TAU * float(i) / float(n) + 0.30
			var o := Vector3(cos(a) * w, 0.0, sin(a) * w)
			ring.append(Vector3(base.x, 0.0, base.y) + o)
			# The prism narrows a little on the way up, so the sides are not a tube.
			top.append(Vector3(base.x + lean.x * shoulder, h * shoulder,
				base.y + lean.y * shoulder) + o * 0.82)
		var tip := Vector3(base.x + lean.x, h, base.y + lean.y)
		for i in n:
			var j := (i + 1) % n
			# The side, as one flat quad with ONE normal — flat-shaded on purpose.
			var a0: Vector3 = ring[i]
			var a1: Vector3 = ring[j]
			var b1: Vector3 = top[j]
			var b0: Vector3 = top[i]
			var fn := (a1 - a0).cross(b0 - a0).normalized()
			var c := verts.size()
			verts.append(a0); verts.append(a1); verts.append(b1); verts.append(b0)
			for _k in 4:
				norms.append(fn)
			# UV.y is the height fraction and UV.x marks a facet's EDGE, which the
			# shader uses for the thin bright line along every crease.
			uvs.append(Vector2(0.0, 0.0)); uvs.append(Vector2(1.0, 0.0))
			uvs.append(Vector2(1.0, shoulder)); uvs.append(Vector2(0.0, shoulder))
			idx.append_array([c, c + 1, c + 2, c, c + 2, c + 3])
			# ...and the pyramid facet above it.
			var pn := (b1 - b0).cross(tip - b0).normalized()
			var d := verts.size()
			verts.append(b0); verts.append(b1); verts.append(tip)
			norms.append(pn); norms.append(pn); norms.append(pn)
			uvs.append(Vector2(0.0, shoulder)); uvs.append(Vector2(1.0, shoulder))
			uvs.append(Vector2(0.5, 1.0))
			idx.append_array([d, d + 1, d + 2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# `lo`, `hi` and `haze` are parameters only because the far ice wall wants the same
# shading model at a different palette and a LATER fog: it stands where the ice is
# already 80 % gone, so on the sheet's own haze span it would be a rumour rather
# than a form.
static func _shard_material(lo: Color = SHARD_LO, hi: Color = SHARD_HI,
		haze: Vector2 = Vector2(HAZE_NEAR, HAZE_FAR),
		cap: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 c_lo;
uniform vec3 c_hi;
uniform vec3 c_haze;
uniform vec3 c_tint;          // the violet a quarter of them are pulled toward
uniform vec3 c_glow;          // ...and the light the lit ones carry
uniform float glow_gain;
uniform vec3 c_cap;           // snow lying on whatever faces up
uniform float cap_gain;
uniform vec3 ldir;
uniform vec2 haze_span;
uniform float dim;
varying vec3 wn;
varying float hgt;
varying float jit;
varying float away;
varying float edge;
varying float glow;
varying float hue;
void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	hgt = UV.y;
	edge = UV.x;
	jit = INSTANCE_CUSTOM.y;
	glow = INSTANCE_CUSTOM.z;
	hue = INSTANCE_CUSTOM.w;
	away = -(MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
}
void fragment() {
	// THE FACET FIRST, and this is the reverse of how it started. The first version
	// weighted height at 0.70 against lambert at 0.30, which on a five-sided cone is
	// a vertical gradient with a hint of light in it — thirty of them in the gutters
	// read as a row of paper darts, and that one term was most of why this
	// background looked cheap. Now the FACE decides, and height only lifts the tips.
	float lam = clamp(dot(wn, ldir), 0.0, 1.0);
	vec3 c = mix(c_lo, c_hi,
		clamp(0.16 + 0.74 * lam + 0.26 * hgt * hgt, 0.0, 1.0) * jit);
	// A quarter of them are violet rather than blue. The palette is deliberately
	// narrow (see Palette) so that the buttons are the only colours in the picture,
	// and this is the one exception the reference insists on: its banks carry cyan
	// crystals AND purple ones, and the pair is most of what makes them read as
	// stylized rather than as rock. It is a TINT on the same two-ended ramp, so a
	// violet crystal is lit and shaded by exactly the same facet term as a blue one
	// and cannot come out brighter than its neighbour.
	c = mix(c, c * c_tint, hue);
	// The crease. A thin bright line down every edge where two facets meet, which is
	// what ice does and what a flat-shaded solid needs to stop reading as origami.
	float crease = smoothstep(0.90, 1.0, abs(edge - 0.5) * 2.0);
	c = mix(c, c_hi, crease * 0.30 * jit);
	// THE GLOW, and it is lit from INSIDE rather than added on top: the weight
	// climbs with height, so a formation is dark at the foot where it meets the
	// snow and brightest at the tips. Added flat it is a coloured object; ramped up
	// the body it is a crystal with light in it, which is the same finding the
	// snowflakes themselves paid for — a flat self-lit surface has no gradient to
	// show its shape with.
	//
	// It is also why glow_gain is a uniform and not a number in here: this is the
	// term most likely to become the frame's brightest pixel, and it needs to be
	// turnable from the palette without recompiling an opinion.
	if (glow > 0.001) {
		c += c_glow * (glow * glow_gain * (0.10 + 0.90 * hgt * hgt));
	}
	// SNOW LYING ON IT, on whatever faces up, and it is zero for the crystals. The
	// far wall is the one prop in the frame that is a LANDFORM rather than a
	// growth, and a bare blue slab across the top of an arena whose banks are snow
	// is the join the eye finds first. It is keyed off the world normal and not off
	// height, because what carries snow is a surface that is flat, not one that is
	// high — the flat tops of the slabs take it and their faces do not, which is
	// what gives the wall a lit crest instead of a lighter half.
	if (cap_gain > 0.001) {
		c = mix(c, c_cap, cap_gain * smoothstep(0.45, 0.92, wn.y)
			* (0.55 + 0.45 * jit));
	}
	// ...and the fog takes them, exactly as it takes the ice they stand on, so
	// nothing out there ever reads as a cut-out.
	ALBEDO = mix(c, c_haze, smoothstep(haze_span.x, haze_span.y, away)) * dim;
}
"""
	m.shader = sh
	m.set_shader_parameter("dim", 1.0)
	m.set_shader_parameter("c_lo", tone(lo))
	m.set_shader_parameter("c_hi", tone(hi))
	m.set_shader_parameter("c_haze", tone(HAZE))
	m.set_shader_parameter("c_tint", SHARD_TINT)
	m.set_shader_parameter("c_glow", tone(SHARD_GLOW))
	m.set_shader_parameter("glow_gain", SHARD_GLOW_GAIN)
	m.set_shader_parameter("c_cap", tone(RIDGE_CAP))
	m.set_shader_parameter("cap_gain", cap)
	m.set_shader_parameter("ldir", SUN_DIR.normalized())
	m.set_shader_parameter("haze_span", haze)
	return m


func _fill_shards(mm: MultiMesh, rng: RandomNumberGenerator, lo: float, hi: float,
		cam: Camera3D, vp: Vector2) -> void:
	var xf: Array[Transform3D] = []
	var cd: Array[Color] = []
	# Every pass here samples the BANK — the whole of it, from the screen — and none
	# of them samples the world. That is the change the arena brought with it and it
	# is worth stating, because the two are the same finding one step apart:
	#
	# The open lake had no boundary, so a prop's only requirement was to be OUT of
	# the play area, and a world annulus with a screen test on the end of it (see
	# _frame_point) was the right tool. The arena HAS a boundary, and the region a
	# prop may stand in is now a ring on the SCREEN whose inner edge is the shore —
	# a shape that has no world radius at all. Sampled from the world it fills in
	# the top corners and nowhere else, which is the failure _screen_point was
	# written for in the first place.
	#
	# So the bank is sampled uniformly across the picture and everything that lands
	# on the rink is thrown away. Uniform on SCREEN is also the right weighting: it
	# puts props where there is picture to fill rather than where there is ground.
	var taken := PackedVector2Array()

	# --- the BIG formations. Nine of them, spread all the way round the bank, and
	#     they are what the reference is actually made of: a few large stylized
	#     shapes rather than a lot of small ones. They are placed first so they get
	#     the pick of the room, and everything else is spaced against them.
	for _i in N_EDGE_SHARDS:
		var p := Vector3.INF
		var sp := Vector2.ZERO
		for _try in 26:
			var q := _shore_point(rng, cam, vp, SHARD_BAND.x, SHARD_BAND.y)
			if q == Vector3.INF:
				continue
			var sq := cam.unproject_position(q)
			var ok := true
			for e: Vector2 in taken:
				if e.distance_to(sq) < vp.y * BIG_SHARD_APART:
					ok = false
					break
			if not ok:
				continue
			p = q
			sp = sq
			break
		if p == Vector3.INF:
			continue
		# ASKED FOR A SCREEN HEIGHT, then cut down to whatever actually fits under
		# the horizon. Both halves matter: the first is what makes nine formations
		# read as one family of sizes round a keystoned bank, the second is what
		# stops the near ones growing out of the top of the frame.
		var want := _height_for_screen(p,
			rng.randf_range(BIG_SHARD_SCREEN.x, BIG_SHARD_SCREEN.y), cam, vp)
		# ...and they are the ONE prop allowed to break the skyline. Everything else
		# out here is held under EDGE_TOP because a prop whose BASE is above the
		# horizon is a prop standing in the sky — but a formation whose base is on
		# the far bank and whose crest rises past the waterline is the silhouette
		# the reference is built on, and holding these under the horizon too is what
		# made the far bank a flat pale band with gravel on it. The far ice wall is
		# already allowed the same licence, and for the same reason (RIDGE_TOP).
		var h := minf(want, _fit_height(p, want, cam, vp,
			HORIZON_FY - BIG_SHARD_SKY, EDGE_SHARD_TALL))
		if h < 0.12:
			continue
		taken.append(sp)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		var w: float = h * rng.randf_range(0.42, 0.68)
		t.basis = t.basis.scaled(Vector3(w, h, w))
		xf.append(t)
		cd.append(_shard_data(rng, EDGE_SHARD_LIT, 0.60))

	# --- the mid-size clusters, filling in between them. Same sampler, a smaller
	#     screen height and a looser spacing, and they carry the glow far less
	#     often: a bank where everything glows is a light source, not a place.
	for _i in N_SHARDS:
		var p := Vector3.INF
		var sp := Vector2.ZERO
		for _try in 14:
			var q := _shore_point(rng, cam, vp, SHARD_BAND.x, SHARD_BAND.y)
			if q == Vector3.INF:
				continue
			var sq := cam.unproject_position(q)
			var ok := true
			for e: Vector2 in taken:
				if e.distance_to(sq) < vp.y * 0.052:
					ok = false
					break
			if not ok:
				continue
			p = q
			sp = sq
			break
		if p == Vector3.INF:
			continue
		var want := _height_for_screen(p,
			rng.randf_range(SHARD_SCREEN.x, SHARD_SCREEN.y), cam, vp)
		var h := minf(want, _fit_height(p, want, cam, vp))
		if h < 0.06:
			continue
		taken.append(sp)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		var w: float = h * rng.randf_range(0.55, 0.95)
		t.basis = t.basis.scaled(Vector3(w, h, w))
		xf.append(t)
		cd.append(_shard_data(rng, 1.10, 0.22))

	# ...and a third, SMALLER pass at the foot of the far wall, placed by screen x
	# the way the wall itself is. The two scatters above will not reach here on
	# their own — the far bank is a thin band and they are spaced against each
	# other — and the far edge needs two sizes of thing in it or the wall reads as a
	# cut-out standing on nothing.
	for i in N_FAR_SHARDS:
		var fx := lerpf(0.0, 1.0, (float(i) + rng.randf_range(0.1, 0.9))
			/ float(N_FAR_SHARDS))
		var p := _ice_at_screen(Vector2(fx * vp.x,
			rng.randf_range(RIDGE_FY1, RIDGE_FY1 + 0.075) * vp.y), cam)
		if p == Vector3.INF or Vector2(p.x, p.z).length() < lo * 0.85 \
				or not _on_bank(p, cam, vp):
			continue
		p.y = ICE_Y + _bank_lift(p, cam, vp)
		var h := minf(rng.randf_range(0.16, 0.40),
			_fit_height(p, 0.40, cam, vp, RIDGE_TOP + 0.02, SCREEN_TALL * 0.5))
		if h < 0.06:
			continue
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		var w: float = h * rng.randf_range(0.7, 1.3)
		t.basis = t.basis.scaled(Vector3(w, h, w))
		xf.append(t)
		cd.append(_shard_data(rng, 1.00, 0.0))
	_fill(mm, xf, cd)


# One crystal's per-instance data: (unused, brightness jitter, glow, hue).
#
# THE GLOW IS A DUTY CYCLE ACROSS THE SCATTER, not a property of a crystal, and
# that is the whole of why the bank can carry it at all. `chance` is how often an
# instance lights at all; a lit one takes a random share of the full strength. So
# nine big formations produce two or three that glow, one of them strongly — which
# is what the reference has — instead of nine that all do, which is a string of
# fairy lights round the arena and the single fastest way to spend the frame's
# whole brightness budget out in the gutters.
#
# `hue` blends the crystal from the ice's own blue toward violet. A quarter of them,
# and never the far ones: the mid-distance is where the picture can afford a second
# colour (it is where the aurora already lives), and the far bank is where a second
# colour reads as a mistake in the fog.
static func _shard_data(rng: RandomNumberGenerator, lit: float,
		chance: float) -> Color:
	var glow := 0.0
	if rng.randf() < chance:
		glow = rng.randf_range(0.35, 1.0)
	var hue := 0.0
	if chance > 0.0 and rng.randf() < 0.28:
		hue = rng.randf_range(0.45, 1.0)
	return Color(rng.randf(), rng.randf_range(0.44, lit), glow, hue)


# --- the shore berm -------------------------------------------------------
# The bank of snow heaped along the shoreline, and the piece that makes the arena a
# PLACE rather than a light patch on a floor.
#
# Everything before it drew the shore in the ice's own fragment shader: a colour
# change, a soft transition and a lit lip. That is a correct picture of a shore and
# it reads as a painted ring, because the one thing an arena's edge has that a
# painted ring does not is VOLUME — a crest that catches the light, an inner face
# turned away from it, and a silhouette that the props behind stand up out of. The
# lip highlight was measuring as the frame's brightest pixel while still reading as
# a racetrack line, which is the diagnosis: contrast in the right place, with no
# form under it.
#
# It is ONE generated mesh, rebuilt per layout with everything else, and it follows
# the SOLVED shoreline rather than the ellipse — the corner squeeze (see
# ARENA_CORNER) means those are different curves, and a berm on the ellipse would
# leave the frame's bottom corners exactly where the reference puts its biggest
# banks. Each segment bisects for where the arena coordinate actually reaches 1.0.
const BERM_SEGS := 88
# The profile, out from the shoreline: (how far out in arena units, how high as a
# fraction of the crest). Four rings — the shore itself at zero, a shoulder, the
# crest, and a long back that runs down into the bank so the berm has no far edge.
const BERM_PROFILE: Array = [
	[0.000, 0.00],
	[0.045, 0.66],
	[0.130, 1.00],
	[0.280, 0.34],
	[0.420, 0.00],
]
# How tall the crest stands ON SCREEN, as a fraction of the frame's height. Sized
# on the screen and not in metres for the reason every other prop out here is: this
# camera keystones the ground hard enough that a berm 30 cm tall is a wall across
# the bottom of the picture and invisible at the top of it.
const BERM_SCREEN := 0.050
# ...and the floor and ceiling in METRES under that, so a segment whose ray comes
# down at a grazing angle cannot ask for a berm the height of a building.
const BERM_METRES := Vector2(0.06, 0.85)

func _berm_mesh(cam: Camera3D, vp: Vector2) -> ArrayMesh:
	if _arena.x < 0.01 or cam == null:
		return null
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var rows: Array = []          # one Array[Vector3] per angle, or [] if dead
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 71
	for i in BERM_SEGS:
		var a := TAU * float(i) / float(BERM_SEGS)
		var dir := Vector2(cos(a) * _arena.x, sin(a) * _arena.y)
		var e0 := _shore_e(a, vp)
		# The crest first, because its height is what the whole profile is scaled
		# by and it is the ring most likely to fall off the frame.
		var crest_f: Vector2 = _arena_at + dir * (e0 + float(BERM_PROFILE[2][0]))
		var crest_p := _ice_at_screen(crest_f * vp, cam)
		if crest_p == Vector3.INF:
			rows.append([])
			continue
		var h := _berm_crest(a, crest_p, cam, vp)
		var row: Array[Vector3] = []
		var ok := true
		for step: Array in BERM_PROFILE:
			var f: Vector2 = _arena_at + dir * (e0 + float(step[0]))
			var q := _ice_at_screen(f * vp, cam)
			if q == Vector3.INF:
				ok = false
				break
			row.append(Vector3(q.x, ICE_Y + h * float(step[1]), q.z))
		rows.append(row if ok else [])
	# ...and one quad strip between every pair of live neighbours. A dead segment
	# leaves a gap rather than a fan across the middle of the arena, which is what
	# closing the ring unconditionally does when a ray fails to come down.
	for i in BERM_SEGS:
		var r0: Array = rows[i]
		var r1: Array = rows[(i + 1) % BERM_SEGS]
		if r0.is_empty() or r1.is_empty():
			continue
		for j in BERM_PROFILE.size() - 1:
			var a0: Vector3 = r0[j]
			var a1: Vector3 = r1[j]
			var b1: Vector3 = r1[j + 1]
			var b0: Vector3 = r0[j + 1]
			var n := (a1 - a0).cross(b0 - a0).normalized()
			if n.y < 0.0:
				n = -n
			var base := verts.size()
			verts.append(a0); verts.append(a1); verts.append(b1); verts.append(b0)
			for _k in 4:
				norms.append(n)
			# UV.y is where up the profile this ring is, which is what the shader
			# shades by; UV.x is the ring's height fraction, for the crest light.
			var v0 := float(j) / float(BERM_PROFILE.size() - 1)
			var v1 := float(j + 1) / float(BERM_PROFILE.size() - 1)
			uvs.append(Vector2(float(BERM_PROFILE[j][1]), v0))
			uvs.append(Vector2(float(BERM_PROFILE[j][1]), v0))
			uvs.append(Vector2(float(BERM_PROFILE[j + 1][1]), v1))
			uvs.append(Vector2(float(BERM_PROFILE[j + 1][1]), v1))
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if idx.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Where the shore actually is along this direction, in ellipse units. Bisected
# rather than assumed to be 1.0, because the corner squeeze pulls it in and the
# berm has to sit on the shoreline the ice shader DRAWS, not on the ellipse the
# solve started from — the two differ by a third of the arena in the bottom
# corners, which is precisely where the reference's biggest banks are.
# How tall the berm's crest stands at this angle, in metres. Two closed-form
# wobbles rather than a noise, because this has to be answerable from two places
# that must agree exactly — the mesh, and every prop that stands on top of it.
func _berm_crest(a: float, crest_p: Vector3, cam: Camera3D, vp: Vector2) -> float:
	var wob := 0.72 + 0.28 * (0.5 + 0.5 * sin(a * 3.0 + 1.7)
		+ 0.35 * sin(a * 7.0 - 0.4))
	return clampf(_height_for_screen(crest_p, BERM_SCREEN, cam, vp),
		BERM_METRES.x, BERM_METRES.y) * wob


# The berm's own surface height, `out` arena units past the shoreline. This is what
# makes the dressing stand ON the bank instead of behind it: the crystals were
# placed on the ice plane at y = 0 while the berm rose in front of them, which
# buries half a scatter and is the one way a raised shoreline can look worse than
# no shoreline at all.
static func _berm_profile_at(out: float, crest: float) -> float:
	if out <= 0.0:
		return 0.0
	for i in BERM_PROFILE.size() - 1:
		var e0: float = BERM_PROFILE[i][0]
		var e1: float = BERM_PROFILE[i + 1][0]
		if out <= e1:
			var t := (out - e0) / maxf(e1 - e0, 0.0001)
			return crest * lerpf(float(BERM_PROFILE[i][1]),
				float(BERM_PROFILE[i + 1][1]), t)
	return 0.0


# The berm's height under an arbitrary world point. _shore_point knows the angle
# and depth it drew, so it needs none of this; the far ice wall, the rocks and the
# small crystals at the wall's foot are all placed by SCREEN BAND and have to work
# it out backwards, and a wall standing at y = 0 with a bank rising in front of it
# is a wall with its feet cut off.
func _bank_lift(p: Vector3, cam: Camera3D, vp: Vector2) -> float:
	if _arena.x < 0.01 or cam == null or p == Vector3.INF \
			or cam.is_position_behind(p):
		return 0.0
	var d := (cam.unproject_position(p) / vp - _arena_at) / _arena
	var e := d.length()
	if e < 0.001:
		return 0.0
	var a := atan2(d.y, d.x)
	var e0 := _shore_e(a, vp)
	if e <= e0:
		return 0.0
	var dir := Vector2(cos(a) * _arena.x, sin(a) * _arena.y)
	var cp := _ice_at_screen(
		(_arena_at + dir * (e0 + float(BERM_PROFILE[2][0]))) * vp, cam)
	if cp == Vector3.INF:
		return 0.0
	return _berm_profile_at(e - e0, _berm_crest(a, cp, cam, vp))


func _shore_e(a: float, vp: Vector2) -> float:
	var dir := Vector2(cos(a) * _arena.x, sin(a) * _arena.y)
	var lo := 0.35
	var hi := 2.4
	for _i in 14:
		var mid := (lo + hi) * 0.5
		if _arena_at_screen((_arena_at + dir * mid) * vp, vp) < 1.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


func _berm_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 c_lo;
uniform vec3 c_hi;
uniform vec3 c_crest;
uniform vec3 c_haze;
uniform vec3 ldir;
uniform vec2 haze_span;
uniform float dim;
varying vec3 wn;
varying vec3 wp;
varying float up;
varying float rise;
varying float away;
float bhash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float bnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bhash(i), bhash(i + vec2(1.0, 0.0)), f.x),
		mix(bhash(i + vec2(0.0, 1.0)), bhash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	up = UV.x;
	rise = UV.y;
	away = -wp.z;
}
void fragment() {
	// Snow, shaded by the face it presents and nothing else. The berm is the one
	// thing in this background whose whole value is its FORM, so its shading is
	// deliberately the plainest in the file: a lambert, a crest, and the same fog
	// everything else out here fades into.
	float lam = clamp(dot(wn, ldir), 0.0, 1.0);
	// Two octaves of drift on top of the lambert. Without them the berm is a
	// perfectly smooth ramp all the way round the arena — correct in form and
	// obviously extruded, which is the failure mode of every generated ring. The
	// coarse octave is STRETCHED, because drifts lie across the wind and an
	// isotropic one reads as dirt (the same finding as the ice's own grain).
	float n1 = bnoise(wp.xz * vec2(0.85, 2.6) + vec2(11.3, 4.1));
	float n2 = bnoise(wp.xz * 3.4 + vec2(27.9, 8.2));
	float drift = 1.0 + 0.30 * (n1 - 0.5) + 0.16 * (n2 - 0.5);
	// The ambient floor is HIGH — a third before the light is counted at all — and
	// it is the number this shader was got wrong on. Snow is the most strongly
	// backscattering surface in any winter frame; a berm shaded to near-black on
	// the faces turned away from the key light draws a hard dark ring right around
	// the rink, and a dark ring around a bright oval reads as a moat rather than as
	// a bank. The reference has no shadow anywhere on its shoreline.
	vec3 c = mix(c_lo, c_hi, clamp((0.32 + 0.68 * lam) * drift, 0.0, 1.0));
	// The crest catches the light. It is keyed off how high up the profile this is
	// AND off the face pointing up, so the top of the drift lights and the inner
	// slope — which is the one turned toward the rink, and the one the buttons are
	// seen against — stays dark. That contrast IS the arena's edge.
	c = mix(c, c_crest, smoothstep(0.55, 1.0, up) * smoothstep(0.35, 0.95, wn.y)
		* 0.85);
	// ...and the inner face, below the crest on the rink side, is pulled down: a
	// bank with a lit top and a shaded foot reads as heaped snow, and one lit all
	// over reads as a ramp.
	c *= 1.0 - 0.14 * (1.0 - smoothstep(0.0, 0.45, rise));
	ALBEDO = mix(c, c_haze, smoothstep(haze_span.x, haze_span.y, away)) * dim;
}
"""
	m.shader = sh
	m.set_shader_parameter("dim", 1.0)
	m.set_shader_parameter("c_lo", tone(BERM_LO))
	m.set_shader_parameter("c_hi", tone(BERM_HI))
	m.set_shader_parameter("c_crest", tone(BERM_CREST))
	m.set_shader_parameter("c_haze", tone(HAZE))
	m.set_shader_parameter("ldir", SUN_DIR.normalized())
	m.set_shader_parameter("haze_span", Vector2(HAZE_NEAR + 1.0, HAZE_FAR + 2.0))
	return m


# --- frozen plates -------------------------------------------------------
# Flat, irregular sheets of paler ice lying IN the surface. They are what "subtle
# crystalline shapes" is without anything standing up: at this camera a flat thing
# is a soft patch and a tall thing is a silhouette, and the gutters can carry a lot
# more of the first than of the second.
static func _plate_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 5
	var n := 11
	verts.append(Vector3.ZERO)
	uvs.append(Vector2(0.0, 0.0))
	var radii := PackedFloat32Array()
	for i in n:
		radii.append(rng.randf_range(0.72, 1.0))
	for i in n:
		var a := TAU * float(i) / float(n)
		verts.append(Vector3(cos(a) * radii[i], 0.0, sin(a) * radii[i]))
		# UV.x is the radius fraction, which drives both the colour and the fade.
		uvs.append(Vector2(1.0, 0.0))
	for i in n:
		idx.append_array([0, 1 + i, 1 + (i + 1) % n])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _plate_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled,
	depth_draw_never, blend_mix;
uniform vec3 c_lo;
uniform vec3 c_hi;
uniform float alpha;
uniform float dim;
varying float rf;
varying float jit;
void vertex() {
	rf = UV.x;
	jit = INSTANCE_CUSTOM.y;
}
void fragment() {
	// No outline, ever. A plate is a patch of the ice that froze differently, so
	// it fades out completely before its own edge — the alternative is a hard rim
	// lying on the ground, which is the busiest thing a flat prop can be.
	ALBEDO = mix(c_hi, c_lo, rf) * dim;
	ALPHA = alpha * jit * (1.0 - smoothstep(0.35, 1.0, rf));
}
"""
	m.shader = sh
	m.set_shader_parameter("dim", 1.0)
	m.set_shader_parameter("c_lo", tone(PLATE_LO))
	m.set_shader_parameter("c_hi", tone(PLATE_HI))
	m.set_shader_parameter("alpha", 0.75)
	# Under the board's own ground pools, which are drawn at GLOW_PRIORITY -2, and
	# over the ice.
	m.render_priority = -1
	return m


func _fill_plates(mm: MultiMesh, rng: RandomNumberGenerator, lo: float, hi: float,
		cam: Camera3D, vp: Vector2) -> void:
	var xf: Array[Transform3D] = []
	var cd: Array[Color] = []
	for _i in N_PLATES:
		# A plate LIES FLAT, so it may only go where the ground is flat: on the bank
		# past the back of the berm. Asked for a depth band in arena units instead —
		# which is how every other prop out here is placed — it came back EMPTY on
		# all three boards, because "half an arena past the shore" is off the frame
		# in most directions and on the berm's own slope in the rest. The question a
		# plate actually has is not how far out it is, it is whether the berm has
		# finished; so that is what it asks.
		var p := _bank_screen_point(rng, EDGE_X, 1.0 - EDGE_X,
			EDGE_TOP, 1.0 - EDGE_BOTTOM, cam, vp, lo * 0.5)
		if p == Vector3.INF:
			continue
		var s := minf(rng.randf_range(0.55, 1.35), _fit_flat(p, 1.35, cam, vp))
		if s < 0.18:
			continue
		# Just proud of whatever it lies on. Anything bigger and the near ones start
		# showing a step where they meet the ground; anything smaller z-fights.
		#
		# AND IT LIES ON THE BERM, which is why it is a lift and not a constant. The
		# plates were held to genuinely flat ground first — "past the back of the
		# bank", tested with _bank_lift — and came back ZERO on all three boards,
		# because on this camera the berm covers essentially the whole visible bank:
		# there is no flat ground out there to find. The berm's back falls about
		# 12 cm over half a metre, so a plate on it is out of true by a couple of
		# centimetres at its rim, which at this size and distance is nothing.
		p.y = ICE_Y + _bank_lift(p, cam, vp) + 0.004
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		t.basis = t.basis.scaled(Vector3(s, 1.0, s * rng.randf_range(0.75, 1.0)))
		xf.append(t)
		cd.append(Color(rng.randf(), rng.randf_range(0.55, 1.0), 0.0, 0.0))
	_fill(mm, xf, cd)


# --- the far ice wall ----------------------------------------------------
# The one prop that is not a scatter. A low, jagged wall of ice standing along the
# far edge of the ground the camera can actually see, placed ACROSS the top band by
# screen x so it spans the whole width of the frame at every aspect and on every
# board.
#
# It is what makes the picture have a BACK. Everything else out here lies on the
# surface or stands a few centimetres proud of it, so before this the ice simply
# faded to fog with nothing in the fog — which is the single biggest reason the
# first version read as an empty blue plane rather than as a place.
#
# Two things about it are deliberate and both were got wrong first:
#   * IT IS NOT AT THE BACK OF THE WORLD, it is at the back of the FRAME. This
#     camera fogs the ground out completely by 6.5 m; a wall placed "far away" is a
#     wall at 2 % contrast. RIDGE_Z_FAR/NEAR is the band where there is still ground
#     under the top of the picture and still something left of it to see.
#   * IT IS DARKER THAN THE ICE IN FRONT OF IT, at both ends of its ramp. A pale
#     distant wall on a dark far field reads as a hole in the world; a dark one
#     reads as a form the fog has not finished eating.
const RIDGE_COLS := 9

static func _ridge_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 23
	# The crest profile. One fixed jagged line, instanced with a different width and
	# a different lateral flip each time — nine columns is where a silhouette stops
	# reading as a sawtooth and has not yet become a smooth hill.
	var crest := PackedFloat32Array()
	# ...and a per-column DEPTH jitter, which is the whole of this rebuild. The
	# first version put every column's front face on the same plane, so every one of
	# them had the same normal and the whole wall shaded as one flat value: a row of
	# paper cut-outs standing on the ice, which at the far edge of the frame is the
	# most conspicuous cheap thing a background can do.
	#
	# Skewing each column's base and crest in z by a few centimetres turns nine
	# coplanar faces into nine facets pointing slightly different ways, and the wall
	# becomes broken slabs of ice with light on some of them.
	var zf := PackedFloat32Array()
	var zb := PackedFloat32Array()
	for i in RIDGE_COLS:
		var u := float(i) / float(RIDGE_COLS - 1)
		# Taper to nothing at both ends so neighbouring instances blend into each
		# other instead of butting up as a row of boxes.
		var taper := sin(clampf(u, 0.0, 1.0) * PI)
		crest.append((0.38 + 0.62 * rng.randf()) * pow(taper, 0.55))
		zf.append(rng.randf_range(-0.16, 0.16))
		zb.append(rng.randf_range(-0.20, 0.20))
	var d := 0.30
	# How wide the flat top of a slab is, as a fraction of its height. It is the
	# facet the moon actually lands on, so it does most of the work.
	var cap := 0.10
	for i in RIDGE_COLS - 1:
		var x0 := lerpf(-1.0, 1.0, float(i) / float(RIDGE_COLS - 1))
		var x1 := lerpf(-1.0, 1.0, float(i + 1) / float(RIDGE_COLS - 1))
		var h0: float = crest[i]
		var h1: float = crest[i + 1]
		# Front slope (toward the camera), back slope, and the flat top between them.
		var f0 := Vector3(x0, h0 * (1.0 - cap), zf[i] - cap * 0.5)
		var f1 := Vector3(x1, h1 * (1.0 - cap), zf[i + 1] - cap * 0.5)
		var k0 := Vector3(x0, h0, zb[i] * 0.4)
		var k1 := Vector3(x1, h1, zb[i + 1] * 0.4)
		var faces := [
			# base ring, crest ring, which side the normal is on
			[Vector3(x0, 0.0, -d + zf[i]), Vector3(x1, 0.0, -d + zf[i + 1]), f0, f1, 1.0],
			[Vector3(x0, 0.0, d + zb[i]), Vector3(x1, 0.0, d + zb[i + 1]), k0, k1, -1.0],
			[f0, f1, k0, k1, 1.0],
		]
		for fc: Array in faces:
			var b0: Vector3 = fc[0]
			var b1: Vector3 = fc[1]
			var c0: Vector3 = fc[2]
			var c1: Vector3 = fc[3]
			var sgn: float = fc[4]
			var n := (b1 - b0).cross(c0 - b0).normalized() * sgn
			var base := verts.size()
			verts.append(b0); verts.append(b1); verts.append(c1); verts.append(c0)
			for _k in 4:
				norms.append(n)
			# UV.x carries the facet's own edge, so the crease highlight in the
			# shared crystal shader lands on the joins between slabs; UV.y is the
			# height fraction it has always been.
			uvs.append(Vector2(0.0, 0.0)); uvs.append(Vector2(1.0, 0.0))
			uvs.append(Vector2(1.0, 1.0)); uvs.append(Vector2(0.0, 1.0))
			if sgn > 0.0:
				idx.append_array([base, base + 1, base + 2,
					base, base + 2, base + 3])
			else:
				idx.append_array([base, base + 2, base + 1,
					base, base + 3, base + 2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _fill_ridges(mm: MultiMesh, rng: RandomNumberGenerator, clear: float,
		cam: Camera3D, vp: Vector2) -> void:
	var xf: Array[Transform3D] = []
	var cd: Array[Color] = []
	for i in N_RIDGES:
		# Evenly spaced across the frame with a jitter, and past both edges at the
		# ends: a wall that stops inside the picture is a wall with a gap beside it.
		var fx := lerpf(-0.06, 1.06, (float(i) + rng.randf_range(0.15, 0.85))
			/ float(N_RIDGES))
		# FIVE heights in the band tried per slot, working DOWN the frame, and that
		# is not defensiveness — the wall is the one prop whose whole value is that it
		# SPANS the frame, so a slot that silently drops leaves a hole in the horizon
		# rather than one fewer prop in a scatter.
		var p := Vector3.INF
		var h := 0.0
		for attempt in 5:
			var fy := lerpf(RIDGE_FY0, RIDGE_FY1,
				(float(attempt) + rng.randf()) / 5.0)
			var q := _ice_at_screen(Vector2(fx * vp.x, fy * vp.y), cam)
			if q == Vector3.INF or Vector2(q.x, q.z).length() < clear \
					or not _on_bank(q, cam, vp):
				continue
			var fit := _fit_height(q, 1.25, cam, vp, RIDGE_TOP, RIDGE_TALL)
			if fit < 0.10:
				continue
			p = q
			p.y = ICE_Y + _bank_lift(q, cam, vp)
			h = minf(rng.randf_range(0.55, 1.25), fit)
			break
		if p == Vector3.INF:
			continue
		var w: float = rng.randf_range(1.5, 3.4)
		# Yawed only a little: these are meant to read as one broken edge seen
		# end-on, not as a scatter of walls pointing in different directions.
		var t := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.30, 0.30)), p)
		t.basis = t.basis.scaled(Vector3(w * (1.0 if rng.randf() < 0.5 else -1.0),
			h, rng.randf_range(0.5, 1.0)))
		xf.append(t)
		cd.append(Color(rng.randf(), rng.randf_range(0.78, 1.06), 0.0, 0.0))
	_fill(mm, xf, cd)


# --- frozen rocks --------------------------------------------------------
# Low frost-capped boulders, in the corners and the near gutters. They are the only
# thing out here that is not ice, and that is what they are for: five kinds of blue
# is a palette, five kinds of blue and one dark stone is a place.
#
# They are also the only prop that spends its contrast DOWNWARD. Everything else
# added in this pass has to be checked against the rule that nothing may out-bright
# a button; a rock cannot break it however many of them there are.
static func _rock_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 41
	var rings := 4
	var seg := 8
	var high := 0.60          # squashed: a boulder half-sunk in the ice, not a ball
	# The jittered hemisphere, built as a grid of points first so both triangles of
	# a quad share the same corners and the silhouette has no cracks in it.
	var grid: Array = []
	for r in rings + 1:
		var row := PackedVector3Array()
		var phi := (float(r) / float(rings)) * PI * 0.5
		for sg in seg:
			var th := TAU * float(sg) / float(seg)
			var j := rng.randf_range(0.80, 1.14)
			row.append(Vector3(sin(phi) * cos(th) * j, cos(phi) * high * j,
				sin(phi) * sin(th) * j))
		grid.append(row)
	# FLAT shaded, with a face normal per triangle: a rock is faceted, and a smooth
	# one at this size reads as a bubble.
	for r in rings:
		var a: PackedVector3Array = grid[r]
		var b: PackedVector3Array = grid[r + 1]
		for sg in seg:
			var s1 := (sg + 1) % seg
			for tri: Array in [[a[sg], b[sg], b[s1]], [a[sg], b[s1], a[s1]]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var n := (p1 - p0).cross(p2 - p0).normalized()
				var base := verts.size()
				for p: Vector3 in [p0, p1, p2]:
					verts.append(p)
					norms.append(n)
					# UV.y is the height fraction, which is what the frost cap reads.
					uvs.append(Vector2(0.0, clampf(p.y / high, 0.0, 1.0)))
				idx.append_array([base, base + 1, base + 2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _rock_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;
uniform vec3 c_lo;
uniform vec3 c_hi;
uniform vec3 c_cap;
uniform vec3 c_haze;
uniform vec3 ldir;
uniform vec2 haze_span;
uniform float dim;
varying vec3 wn;
varying float hgt;
varying float jit;
varying float away;
void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	hgt = UV.y;
	jit = INSTANCE_CUSTOM.y;
	away = -(MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
}
void fragment() {
	float lam = clamp(dot(wn, ldir), 0.0, 1.0);
	// A high floor under the lambert. The first pass used 0.25 and the shaded side
	// of a rock came out at screen 22 against ice at 90 — four boulder-shaped HOLES
	// in the corners of the frame, which is the loudest thing a dark prop can be.
	vec3 stone = mix(c_lo, c_hi, clamp(0.40 + 0.60 * lam, 0.0, 1.0) * jit);
	// The frost sits on the UPWARD faces of the top, which is the only place snow
	// stays. Keyed on the normal as well as the height, or it becomes a painted
	// band that goes round the rock's sides.
	// The frost is most of what makes these read as rocks rather than as dark
	//  patches: an unlit dome at this size is a blob, and a dome with a pale crust
	//  on its upward faces has a top and a side.
	float cap = smoothstep(0.34, 0.88, hgt) * smoothstep(0.10, 0.65, wn.y);
	vec3 c = mix(stone, c_cap, cap * 0.90);
	ALBEDO = mix(c, c_haze, smoothstep(haze_span.x, haze_span.y, away)) * dim;
}
"""
	m.shader = sh
	m.set_shader_parameter("dim", 1.0)
	m.set_shader_parameter("c_lo", tone(ROCK_LO))
	m.set_shader_parameter("c_hi", tone(ROCK_HI))
	m.set_shader_parameter("c_cap", tone(ROCK_CAP))
	m.set_shader_parameter("c_haze", tone(HAZE))
	m.set_shader_parameter("ldir", SUN_DIR.normalized())
	m.set_shader_parameter("haze_span", Vector2(HAZE_NEAR, HAZE_FAR))
	return m


func _fill_rocks(mm: MultiMesh, rng: RandomNumberGenerator, clear: float,
		cam: Camera3D, vp: Vector2) -> void:
	var xf: Array[Transform3D] = []
	var cd: Array[Color] = []
	# Four screen regions, and they are the four places a board of six buttons
	# leaves room: the two bottom corners and the two side gutters. Named as
	# fractions of the frame rather than found by search, because "the corners" is
	# the requirement here and a search would simply rediscover it.
	var zones := [
		[0.02, 0.22, 0.56, 0.90],   # bottom left
		[0.78, 0.98, 0.56, 0.90],   # bottom right
		[0.02, 0.15, 0.18, 0.58],   # left gutter
		[0.85, 0.98, 0.18, 0.58],   # right gutter
	]
	# ...and no two of them may sit on top of each other. Without this the four
	# zones are small enough that three rocks land in the same corner and merge into
	# one dark smudge — which is a worse defect than the emptiness this pass exists
	# to fix, because a smudge is the only thing in the frame with no shape.
	var taken: Array[Vector2] = []
	var apart := vp.x * ROCK_APART
	for i in N_ROCKS:
		var z: Array = zones[i % zones.size()]
		var p := Vector3.INF
		for attempt in 12:
			var q := _screen_point(rng, float(z[0]), float(z[1]), float(z[2]),
				float(z[3]), cam, vp, clear)
			if q == Vector3.INF or not _on_bank(q, cam, vp):
				continue
			var qs := cam.unproject_position(q)
			# The bar comes down as the tries run out. Spacing is a preference and a
			# rock in the corner is the requirement, so the last few attempts will
			# take a closer neighbour rather than leave the corner empty.
			var want := apart * (1.0 - 0.06 * float(attempt))
			var clash := false
			for t: Vector2 in taken:
				if t.distance_to(qs) < want:
					clash = true
					break
			if not clash:
				p = q
				taken.append(qs)
				break
		if p == Vector3.INF:
			continue
		p.y = ICE_Y + _bank_lift(p, cam, vp)
		# FITTED BY FOOTPRINT, not by height, and that is the difference between a
		# boulder and a hillside: a rock is read almost entirely off how much of the
		# frame it covers, and the same 0.5 m that is a stone at the back of the
		# picture is a slab across the corner two metres from the camera.
		var w := minf(rng.randf_range(0.30, 0.80),
			_fit_flat(p, 0.80, cam, vp, ROCK_SCREEN))
		if w < 0.10:
			continue
		var h: float = minf(w * rng.randf_range(0.48, 0.78), _fit_height(p, w, cam, vp))
		if h < 0.04:
			continue
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		t.basis = t.basis.scaled(Vector3(w, h, w * rng.randf_range(0.72, 1.0)))
		xf.append(t)
		cd.append(Color(rng.randf(), rng.randf_range(0.80, 1.15), 0.0, 0.0))
	_fill(mm, xf, cd)


# --- snow ----------------------------------------------------------------
# One batched sheet of camera-facing quads: the whole fall in ONE draw call and no
# particle system. Each quad's four vertices carry the SAME world position (its
# home) and differ only in UV, which the vertex shader uses as the corner offset
# after the billboard — so the fall, the sway and the fade are one function of TIME
# and a per-flake seed, evaluated on the GPU.
func _snow_node() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Snow"
	mi.material_override = _snow_material()
	mi.layers = BG_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertices are HOMES, not positions: the fall happens in the vertex shader,
	# after the bounds would have been derived, so they are given rather than found.
	mi.custom_aabb = AABB(Vector3(-24, -1, -24), Vector3(48, 10, 48))
	return mi


static func _snow_mesh(count: int, lo: float, hi: float, cam: Camera3D,
		vp: Vector2) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 17
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for _i in count:
		var home := _frame_point(rng, lo, hi, cam, vp)
		if home == Vector3.INF:
			continue
		# The top of the column each flake falls down. FALL_SPAN below is how far it
		# has to go; it wraps, so the sheet never runs out of snow.
		home.y = ICE_Y + rng.randf_range(0.9, 2.3)
		var sz := rng.randf_range(0.012, 0.026)
		var seed01 := rng.randf()
		# A THIRD of them are not snow: they are floating ice crystals, which fall at
		# a fifth of the rate, are a little smaller and twinkle instead of drifting
		# steadily. It costs nothing (one number per flake, read in the same vertex
		# shader) and it is what stops the fall reading as one weather effect on a
		# loop — two speeds in the same air is depth.
		var slow := 1.0 if rng.randf() < 0.34 else 0.0
		if slow > 0.5:
			sz *= 0.8
		var b := verts.size()
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			verts.append(home)
			uvs.append(c)
			uv2.append(Vector2(seed01 + slow * 2.0, sz))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# How far a flake falls before it wraps back to the top, and how fast. 12 cm/s: at
# this scale a lily pad is 2 m across, so a flake crossing its own body width takes
# about a fifth of a second and the fall reads as drifting rather than as rain.
const FALL_SPAN := 2.6
const FALL_RATE := 0.12


static func _snow_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled,
	depth_draw_never, blend_mix;
uniform vec3 tint;
uniform float span;
uniform float rate;
uniform float alpha;
uniform float dim;
uniform float extra;   // the milestone events' "snow becomes a little more visible"
varying vec2 quv;
varying float fade;
void vertex() {
	// UV2.x carries the flake's phase seed AND, in its integer part, which KIND of
	// flake it is: under 1 is falling snow, over 1 is a floating ice crystal. One
	// channel for both because a mesh attribute costs a vertex format and a fract()
	// costs nothing.
	float slow = step(1.0, UV2.x);
	float seed = fract(UV2.x);
	float s = seed * 6.2831853;
	float t = TIME;
	vec3 c = VERTEX;
	// Down, and wrapped. `s` staggers the phase so the flakes started at one moment
	// do not fall as one sheet; `slow` puts a third of them at a fifth of the rate.
	float d = fract((t * rate * mix(1.0, 0.2, slow)) / span + seed);
	c.y -= d * span;
	// A slow sway, at two periods with no common factor, so a flake wanders
	// instead of sliding. The floating ones wander further and turn over.
	c.x += mix(0.16, 0.34, slow) * sin(t * 0.33 + s);
	c.z += mix(0.11, 0.26, slow) * cos(t * 0.24 + s * 1.7);
	// Faded in at the top and out at the bottom, so nothing appears or vanishes.
	fade = smoothstep(0.0, 0.14, d) * (1.0 - smoothstep(0.72, 1.0, d));
	// ...and the ice crystals catch the light as they turn, which the snow does not.
	fade *= mix(1.0, 0.45 + 0.55 * pow(max(sin(t * 1.7 + s * 2.3), 0.0), 3.0), slow);
	vec4 vp = MODELVIEW_MATRIX * vec4(c, 1.0);
	// Billboard by offsetting in VIEW space, after the transform: one sheet, no
	// per-instance basis to rebuild, and it faces the camera at any board angle.
	vp.xy += UV * UV2.y;
	POSITION = PROJECTION_MATRIX * vp;
	quv = UV;
}
void fragment() {
	float d = clamp(1.0 - length(quv), 0.0, 1.0);
	ALBEDO = tint * dim;
	// Cubed, so a flake is a soft point rather than a disc with an edge.
	ALPHA = d * d * d * fade * alpha * extra;
}
"""
	m.shader = sh
	m.set_shader_parameter("tint", tone(SNOW))
	m.set_shader_parameter("span", FALL_SPAN)
	m.set_shader_parameter("rate", FALL_RATE)
	# The snow is the only thing in this background that ever passes in front of a
	# button, so it is held at a third of full and kept small. At this alpha a flake
	# crossing a lit snowflake is a suggestion of one.
	m.set_shader_parameter("alpha", 0.30)
	m.set_shader_parameter("dim", 1.0)
	m.set_shader_parameter("extra", 1.0)
	m.render_priority = 3
	return m


# ---------------------------------------------------------------------------
# THE MILESTONE EVENTS
# ---------------------------------------------------------------------------
# Two of them, and they answer the two hooks every 3D background is offered:
#
#   note_milestone(round_no)  — every completed round. Ice Kingdom answers every
#                               THIRD one with a ~1.35 s burst of crystals around
#                               the rim of the frame.
#   note_finale(level_no)     — every completed level, for the bigger moment. Ice
#                               Kingdom answers every EIGHTH with a ~4.85 s
#                               celebration: the aurora swells, a reindeer pulls a
#                               sleigh across the top of the sky, and the ice takes
#                               a light sweep across it.
#
# Both return the SECONDS THE ROUND MUST STAY FROZEN, which is the whole of the
# contract with game.gd (see BackgroundScenes.note_milestone). Neither can reach
# into the game, neither knows the score, and neither may be told anything but an
# integer. The freeze is measured from the event's own clock and runs PAST the last
# thing the player can see, so nothing resumes while a crystal is still fading or
# the sleigh is still inside the frame.
#
# What is deliberately NOT here:
#
#   * NO TWEENS. Both events are closed-form functions of one clock, exactly like
#     the lake's frog, and for the same reason: a background can be freed in the
#     middle of one (the player quits, the board rebuilds on a resize, the shop
#     swaps the skin) and a closed form leaves nothing running to stop.
#   * NO PARTICLE SYSTEM. The crystal burst is one MultiMesh and one batched quad
#     sheet; the sleigh's wake is a second quad sheet parented to it.
#   * NO PER-FRAME CPU BEYOND SIX NUMBERS. _pose_streak writes one uniform,
#     _pose_party writes five and one transform. Everything else — the growth, the
#     shatter, the puffs' flight, the wake's twinkle — is a function of that
#     uniform inside a vertex shader.
#   * AND NOTHING LEFT STANDING. The streak's two nodes are built once and kept
#     with visible_instance_count 0 between events, which draws nothing at all; the
#     sleigh is built at the start of a celebration and FREED at the end of it, so
#     the assertion "no reindeer nodes remain" is true in the strongest sense.

# --- the every-third-level burst ---
# A crystal's own grow-and-glow, how far apart the ring's start times are spread,
# when the first one lets go, and when the last puff has faded. The whole thing is
# quick on purpose: the brief asks for "fast and satisfying", not for a cutscene.
const EV_GROW := 0.40
const EV_STAGGER := 0.26
const EV_BURST := 0.62
const EV_TOTAL := 1.35
# How many grow, and how many puffs each throws. Fourteen is what covers both side
# gutters and the bottom corners without any two being closer than a crystal's
# width on screen.
const N_EV_CRYSTALS := 18
const EV_PUFFS := 5
# How far the scene cools while it happens. 0.80 and not lower: this event is a
# beat, not a blackout, and a deep dim on a 1.3 s event reads as the screen
# glitching rather than as the world reacting.
const EV_DIM := 0.80

# --- the every-eighth-level celebration ---
const PT_TOTAL := 4.85
# The floor the ground cools to while the aurora is up. Deeper than the streak's,
# because this one has somewhere to go: the whole point of PHASE 1 is that the sky
# gets brighter while the ground gets darker, and half of that contrast is the half
# the buttons are standing on.
const PT_DIM := 0.68
# What is added to the aurora's own amplitude at the peak of the celebration. It is
# ADDED, never assigned: the curtains keep whatever phase of their own 11.5 s cycle
# they happen to be in, so the celebration cannot look like it started them.
const PT_BOOST := 0.90
# When the sleigh enters and when it has completely left. 2.3 s to cross, which is
# the brief's number, and it starts after the aurora has had half a second to come
# up so the sighting happens IN a lit sky rather than announcing one.
const PT_FLY0 := 0.45
const PT_FLY1 := 2.75
# How far in front of the camera it flies. Behind the buttons (which stand about
# 10 m out) and a long way in front of the sky card at 40 — so a button the sleigh
# passes behind OCCLUDES it, which is the cheapest depth cue in the whole event and
# the one thing that stops it reading as a sticker on the sky.
const PT_DIST := 16.0
# ...and how long it is, as a fraction of the frame's width. Sized on screen rather
# than in metres for the reason everything else here is.
const PT_SPAN := 0.125
# ...and how long the MESH is in its own units, so PT_SPAN can be a fraction of the
# frame rather than a fraction of the frame times whatever the mesh happens to
# measure. The first version left this out and the team crossed the sky at 0.36 of
# the width — the number was right and the units were not.
const TEAM_LEN := 2.40
# ...and how far the mesh reaches above and below its own origin, in the same
# units. These are not decoration: the sky is 0.195 of the frame and the team is
# 0.06 of it tall, so the lane it can fly down is about eight per cent of the
# height. TEAM_TOP is the antler tips and TEAM_BOT is the leading hoof, and
# tools/ice_event.tscn checks the SILHOUETTE against them rather than checking the
# path — a crossing whose centre line clears the horizon and whose hooves do not is
# a crossing that paddles through the mountains.
const TEAM_TOP := 0.90
const TEAM_BOT := -0.32
# The crossing, in frame fractions: in from off the LEFT edge, up over a shallow
# arc, out past the RIGHT. Both ends are outside the frame, so it is never seen to
# appear or to stop — the brief is explicit about both.
#
# The arc peaks at 0.45 of the width rather than at the middle for the same reason
# the frog's exit does on the lake: the highest, best-read moment of a crossing
# should not happen where the topmost button is standing.
#
# THE LANE IS ABOUT THIRTY PIXELS TALL and every number here is answerable to it.
# The sky is HORIZON_FY of the frame and the team is 0.075 of it, so the band the
# crossing may use — antlers inside the top edge, hooves above the shore — is
# roughly 0.09 to 0.14 of the height. It moved when the horizon did (0.195 -> 0.165
# when the board was re-seated), and tools/ice_event.tscn caught it immediately:
# the same lane that cleared the old shore had the sleigh paddling through the new
# one. Re-read that check's numbers before touching any of these three.
const PT_IN := Vector2(-0.17, 0.132)
const PT_MID := Vector2(0.45, 0.092)
const PT_OUT := Vector2(1.17, 0.128)
# How much more snow there is while the celebration runs.
const PT_SNOW := 1.9

# The rate the board is asked to redraw itself at while either event is running.
# IDLE_HZ (15) is sized to snow falling at 12 cm/s and is nowhere near enough for a
# sleigh crossing the frame in two seconds — at 15 Hz it moves 90 px a frame.
const EVENT_HZ := 60.0


var _ev_on := false
var _ev_t := 0.0
var _ev_last := -1
var _ev_root: Node3D
var _ev_crystals: MultiMeshInstance3D
var _ev_cmat: ShaderMaterial
var _ev_puffs: MeshInstance3D
var _ev_pmat: ShaderMaterial
var _ev_slots: Array[Transform3D] = []

var _pt_on := false
var _pt_t := 0.0
var _pt_last := -1
var _sleigh: Node3D
var _pt_a := Vector3.ZERO
var _pt_ctrl := Vector3.ZERO
var _pt_c := Vector3.ZERO
var _pt_basis := Basis()
var _pt_scale := 1.0
# Set by _scatter, and read by BOTH events: it means A CAMERA HAS ARRIVED and the
# ring and the lane have been solved. An event fired before it would have nothing to
# place and nowhere to fly.
var _laid_out := false


# True while either event is on screen. The board reads it to decide how often to
# redraw (see BackgroundScenes.idle_hz), and the harnesses read it to know when
# something is running.
func event_active() -> bool:
	return _ev_on or _pt_on


# ---------------------------------------------------------------------------
# EVENT 1 — the crystal burst, every third completed level
# ---------------------------------------------------------------------------
# Crystals grow up out of the ice around the OUTER EDGES of the frame, glow, and
# shatter into snow. Nothing grows inside the play area, and that is structural
# rather than careful: the slots are drawn from three screen rectangles that are
# the gutters, and every candidate is additionally rejected inside the board's own
# reach (see _plan_streak).
#
# `round_no` is used for exactly two things — refusing a repeat, and seeding which
# of the ring's crystals go first — and is neither stored nor scored.
func start_streak_event(round_no: int) -> float:
	# Every third, and never on an eighth: level 24 is both, and two events on one
	# completion is one event too many. The BACKGROUND decides that, not game.gd,
	# which is why game.gd may offer it every single round.
	if round_no <= 0 or round_no % 3 != 0 or round_no % 8 == 0:
		return 0.0
	if _ev_on or _pt_on or round_no == _ev_last or not _laid_out:
		return 0.0
	_ev_last = round_no
	if _ev_slots.is_empty():
		return 0.0
	# Which crystals go first. Seeded off the round so occurrence N always looks
	# like occurrence N, and re-rolled per event so two in a row are not the same
	# ring lighting up in the same order.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(round_no) * 6151 + 29
	var mm := _ev_crystals.multimesh
	for i in _ev_slots.size():
		mm.set_instance_custom_data(i, Color(rng.randf(),
			rng.randf_range(0.85, 1.15), 0.0, 0.0))
	mm.visible_instance_count = _ev_slots.size()
	_ev_root.visible = true
	_ev_t = 0.0
	_ev_on = true
	_pose_streak()
	AudioManager.play_ice_crack()
	set_process(true)
	return EV_TOTAL


# Everything back to rest. Called by the clock and by anything that has to end an
# event early — a board swapping backgrounds mid-round, and every harness that runs
# two in a row.
func stop_streak_event() -> void:
	_ev_on = false
	_ev_t = 0.0
	if _ev_crystals != null:
		_ev_crystals.multimesh.visible_instance_count = 0
	if _ev_root != null and not _pt_on:
		_ev_root.visible = false
	if not _pt_on:
		_set_dim(1.0)
		set_process(false)


# One float and one dim per frame, and that is the whole of this event's CPU.
func _pose_streak() -> void:
	var t := _ev_t
	_ev_cmat.set_shader_parameter("t", t)
	_ev_pmat.set_shader_parameter("t", t)
	# In over a fifth of a second and out over the last third, so the cool never
	# lands as a cut. It is not allowed to fight the celebration's own dim.
	if not _pt_on:
		var k := smoothstep(0.0, 0.20, t) * (1.0 - smoothstep(0.85, EV_TOTAL, t))
		_set_dim(lerpf(1.0, EV_DIM, k))


# ---------------------------------------------------------------------------
# EVENT 2 — the aurora and the sleigh, every eighth completed level
# ---------------------------------------------------------------------------
# Four phases over 4.85 s, and the round is frozen for every one of them:
#
#   0.00-0.50  the ground cools and the aurora begins to come up
#   0.45-2.75  the aurora is at full and the sleigh crosses the sky
#   2.75-3.60  the aurora holds, a light sweep crosses the ice, the snow thickens
#   3.60-4.85  everything eases back to exactly where it was
#
# The banner ("ICE IN MY VEINS!") is game.gd's, fired against this clock and not
# awaited by it — the celebration's own duration is what releases the freeze.
func start_party_event(level_no: int) -> float:
	if level_no <= 0 or level_no % 8 != 0:
		return 0.0
	if _pt_on or level_no == _pt_last or not _laid_out:
		return 0.0
	_pt_last = level_no
	# A burst still fading when the celebration lands is a burst that would keep its
	# own dim running underneath this one. Ended, not left to finish.
	if _ev_on:
		stop_streak_event()
	_build_sleigh()
	_pt_t = 0.0
	_pt_on = true
	_pose_party()
	AudioManager.play_ice_shimmer()
	set_process(true)
	return PT_TOTAL


func stop_party_event() -> void:
	_pt_on = false
	_pt_t = 0.0
	# FREED, not hidden. The streak's crystals are a fixed ring that is worth
	# keeping between events; the sleigh is one node with two small meshes on it,
	# built in about a millisecond every eighth level, and freeing it is what makes
	# "no reindeer nodes remain afterwards" true rather than nearly true.
	if _sleigh != null:
		_sleigh.queue_free()
		_sleigh = null
	if _ev_root != null and not _ev_on:
		_ev_root.visible = false
	_set_dim(1.0)
	_set_aurora_boost(0.0)
	_imat.set_shader_parameter("sweep", Vector2(0.0, 0.0))
	_snow.material_override.set_shader_parameter("extra", 1.0)
	if not _ev_on:
		set_process(false)


func party_event_active() -> bool:
	return _pt_on


# Five uniforms and one transform per frame.
func _pose_party() -> void:
	var t := _pt_t
	# PHASE 1 and PHASE 4 are the same curve read forwards and backwards: up over
	# half a second, down over the last one and a quarter, flat in between.
	var env := smoothstep(0.0, 0.50, t) * (1.0 - smoothstep(3.60, PT_TOTAL, t))
	_set_dim(lerpf(1.0, PT_DIM, env))
	_set_aurora_boost(PT_BOOST * env)
	_snow.material_override.set_shader_parameter("extra", lerpf(1.0, PT_SNOW, env))

	# PHASE 4's light sweep across the ice: one pass, left to right, over 1.1 s,
	# starting as the sleigh leaves. Amplitude is a hump so it has no edges.
	var sw := clampf((t - 2.55) / 1.10, 0.0, 1.0)
	var swa := 0.0 if sw <= 0.0 or sw >= 1.0 else sin(sw * PI)
	_imat.set_shader_parameter("sweep", Vector2(lerpf(-0.25, 1.25, sw), swa * env))

	if _sleigh == null:
		return
	# PHASE 2. Outside its window the sleigh is not moved and not drawn — it is
	# hidden rather than parked off screen, because "off screen" is a promise about
	# a projection and hidden is a fact.
	if t < PT_FLY0 or t > PT_FLY1:
		_sleigh.visible = false
		return
	_sleigh.visible = true
	var u := (t - PT_FLY0) / maxf(PT_FLY1 - PT_FLY0, 0.001)
	# Constant speed across the frame — an eased crossing reads as the sleigh
	# slowing down in the middle of the sky, which is the one thing a sighting must
	# not do. The ARC is what varies, not the pace.
	var pos := _bez(u)
	# The tangent, so it banks into the climb and out of it. Taken from the curve
	# rather than tweened, so it cannot drift out of step with the position.
	var tan := (_bez(minf(u + 0.02, 1.0)) - _bez(maxf(u - 0.02, 0.0)))
	var ang := 0.0
	var fx := tan.dot(_pt_basis.x)
	var fy := tan.dot(_pt_basis.y)
	if absf(fx) > 0.0001:
		ang = atan2(fy, fx)
	# A small gallop bob on top, in the plane of the screen, at a rate that is not
	# a multiple of anything else in the frame.
	var bob := sin(_pt_t * 8.3) * 0.035 * _pt_scale
	var b := _pt_basis.rotated(_pt_basis.z.normalized(), ang).scaled(
		Vector3(_pt_scale, _pt_scale, _pt_scale))
	_sleigh.transform = Transform3D(b, pos + _pt_basis.y * bob)


# The crossing, as one quadratic Bezier through the three framed points. All three
# lie on the same plane in front of the camera, so a curve through them in world
# space is the same curve on screen.
func _bez(u: float) -> Vector3:
	var iu := 1.0 - u
	return _pt_a * (iu * iu) + _pt_ctrl * (2.0 * iu * u) + _pt_c * (u * u)


# ---------------------------------------------------------------------------
# The event nodes
# ---------------------------------------------------------------------------

# The ring of crystals and their puffs, laid out at the same moment everything else
# in the frame is: once, when the board's layout settles. The event itself then
# costs nothing to start.
func _plan_streak(rng: RandomNumberGenerator, cam: Camera3D, vp: Vector2,
		clear: float) -> void:
	_ev_slots.clear()
	# Three rectangles of the FRAME, which is what "around the outer edges" means
	# when the thing being framed is a ring of buttons: both side gutters, and the
	# bottom band under the near ones. There is deliberately no top band — that is
	# the sky now, and a crystal cannot grow out of it.
	var bands := [
		[0.015, 0.185, EDGE_TOP + 0.01, 0.90],
		[0.815, 0.985, EDGE_TOP + 0.01, 0.90],
		[0.100, 0.900, 0.760, 0.965],
	]
	# The buttons' own screen discs. The world-radius clearance _screen_point
	# applies is the rule the rest of this file uses and it is NOT enough here: a
	# point 4.2 m from the middle of the board can still project onto a button that
	# is nearer the camera than it is, and "do not grow a crystal under a button" is
	# a statement about the PICTURE. So it is checked in the picture.
	var discs: Array = []
	for c: Vector2 in _centres:
		var mid := Vector3(c.x, ICE_Y, c.y)
		var edge := mid + Vector3(1.15, 0.0, 0.0)
		if cam.is_position_behind(mid) or cam.is_position_behind(edge):
			continue
		var cs := cam.unproject_position(mid)
		discs.append([cs, cs.distance_to(cam.unproject_position(edge)) * 1.35])

	var placed := PackedVector2Array()
	for i in N_EV_CRYSTALS:
		var band: Array = bands[i % bands.size()]
		var p := Vector3.INF
		var s := Vector2.ZERO
		for _try in TRIES:
			var q := _screen_point(rng, band[0], band[1], band[2], band[3],
				cam, vp, clear)
			if q == Vector3.INF or not _on_bank(q, cam, vp):
				continue
			var sq := cam.unproject_position(q)
			# Spaced on SCREEN and not in the world, for the reason the rocks are:
			# a metre out at the side of a keystoned frame is a third of what a
			# metre is at the bottom of it, so world spacing clumps at one end.
			var ok := true
			for d: Array in discs:
				if sq.distance_to(d[0]) < float(d[1]):
					ok = false
					break
			if not ok:
				continue
			for e: Vector2 in placed:
				if e.distance_to(sq) < vp.x * 0.045:
					ok = false
					break
			if not ok:
				continue
			p = q
			s = sq
			break
		if p == Vector3.INF:
			continue
		# SIZED ON SCREEN, not in metres, and that is the difference between a ring
		# and a heap. The gutters of a keystoned frame run from 5 m away at the
		# bottom of the picture to 12 at the top, so one world height gives a
		# crystal four times as tall at the near end as at the far one — the first
		# pass at this put every readable crystal in the two bottom corners and a
		# row of specks up the sides.
		var want := _height_for_screen(p, rng.randf_range(0.055, 0.105), cam, vp)
		var h := minf(want, _fit_height(p, want, cam, vp, EDGE_TOP,
			SCREEN_TALL * 0.72))
		if h < 0.06:
			continue
		placed.append(s)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p)
		var w: float = h * rng.randf_range(0.50, 0.80)
		t.basis = t.basis.scaled(Vector3(w, h, w))
		_ev_slots.append(t)
	var mm := _ev_crystals.multimesh
	mm.instance_count = _ev_slots.size()
	for i in _ev_slots.size():
		mm.set_instance_transform(i, _ev_slots[i])
		mm.set_instance_custom_data(i, Color(rng.randf(), 1.0, 0.0, 0.0))
	# Nothing is drawn until an event asks for it — unless one is asking right now.
	# A re-scatter lands mid-event whenever the frame resizes or rotates during the
	# freeze, and blanking the ring there would end the burst on screen while the
	# round went on waiting out its clock.
	mm.visible_instance_count = _ev_slots.size() if _ev_on else 0
	_ev_puffs.mesh = _puff_mesh(_ev_slots, rng)


# One batched sheet of camera-facing quads, the same construction the snow uses: a
# quad's four vertices all carry the same home (the crystal's crest) and differ
# only in UV, and the flight outward is a function of the event clock in the vertex
# shader. Five per crystal is seventy quads for the whole burst.
static func _puff_mesh(slots: Array[Transform3D], rng: RandomNumberGenerator) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for xf: Transform3D in slots:
		var crest := xf.origin + Vector3(0.0, xf.basis.get_scale().y * 0.72, 0.0)
		for _k in EV_PUFFS:
			# UV2 carries the flight: x is the horizontal bearing (as a turn), y is
			# the speed. The rise is in the shader, the same for all of them, so a
			# burst reads as one event rather than as five sparks.
			var bear := rng.randf() * TAU
			var spd := rng.randf_range(0.22, 0.62)
			var sz := rng.randf_range(0.022, 0.048)
			var b := verts.size()
			for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1),
					Vector2(-1, 1)]:
				verts.append(crest)
				uvs.append(c)
				uv2.append(Vector2(bear + spd * 0.001, sz))
			idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_streak() -> void:
	_ev_root = Node3D.new()
	_ev_root.name = "Milestone"
	_ev_root.visible = false
	add_child(_ev_root)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _shard_mesh()
	_ev_crystals = MultiMeshInstance3D.new()
	_ev_crystals.name = "StreakCrystals"
	_ev_crystals.multimesh = mm
	_ev_cmat = _streak_material()
	_ev_crystals.material_override = _ev_cmat
	_ev_crystals.layers = BG_LAYER
	_ev_crystals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ev_crystals.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 12, 80))
	_ev_root.add_child(_ev_crystals)

	_ev_puffs = MeshInstance3D.new()
	_ev_puffs.name = "StreakPuffs"
	_ev_pmat = _puff_material()
	_ev_puffs.material_override = _ev_pmat
	_ev_puffs.layers = BG_LAYER
	_ev_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ev_puffs.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 12, 80))
	_ev_root.add_child(_ev_puffs)


# The crystal's whole life is in its vertex shader, off one uniform: it grows with
# a small overshoot, holds while the glow comes up, then flies apart along its own
# normals and fades. Nothing about it is tweened and nothing about it is per-frame
# on the CPU.
static func _streak_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled,
	depth_draw_opaque, blend_mix;
uniform vec3 c_lo;
uniform vec3 c_hi;
uniform vec3 c_glow;
uniform vec3 ldir;
uniform float t;
uniform float grow;
uniform float stagger;
uniform float burst;
uniform float total;
varying vec3 wn;
varying float hgt;
varying float jit;
varying float lit;
varying float gone;

void vertex() {
	float delay = INSTANCE_CUSTOM.x * stagger;
	jit = INSTANCE_CUSTOM.y;
	// Grow, with one small overshoot. A crystal that arrives at its height and
	// stops is a crystal that was scaled; one that goes 12 % past and settles is
	// one that pushed its way up through the ice.
	float g = clamp((t - delay) / grow, 0.0, 1.0);
	float e = 1.0 - pow(1.0 - g, 3.0);
	float sc = e * (1.0 + 0.12 * sin(g * 3.14159) * (1.0 - g));
	// Shatter. Along the face normal, accelerating, and only after this crystal's
	// own burst time — which is staggered with its growth, so the ring lets go in
	// the order it came up in.
	gone = clamp((t - delay - burst) / max(total - burst - stagger, 0.001), 0.0, 1.0);
	vec3 v = VERTEX * sc + NORMAL * (gone * gone * 0.42);
	// ...and it drops as it goes, so the pieces read as ICE and not as sparks.
	v.y -= gone * gone * 0.22;
	VERTEX = v;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	hgt = UV.y;
	// The glow: up quickly once it has grown, out again as it breaks.
	lit = smoothstep(0.35, 1.0, g) * (1.0 - gone);
}

void fragment() {
	float lam = clamp(dot(wn, ldir), 0.0, 1.0);
	vec3 c = mix(c_lo, c_hi, clamp(0.30 * lam + 0.70 * hgt * hgt, 0.0, 1.0) * jit);
	// The cyan light is added at the TIP and not over the whole body: a crystal lit
	// evenly is a lamp, and a crystal whose crest is lit is ice with something
	// inside it.
	c += c_glow * (lit * (0.25 + 0.75 * hgt * hgt));
	ALBEDO = c;
	ALPHA = 1.0 - gone;
}
"""
	m.shader = sh
	m.set_shader_parameter("c_lo", tone(SHARD_LO))
	m.set_shader_parameter("c_hi", tone(SHARD_HI))
	m.set_shader_parameter("c_glow", tone(GLOW))
	m.set_shader_parameter("ldir", SUN_DIR.normalized())
	m.set_shader_parameter("t", 0.0)
	m.set_shader_parameter("grow", EV_GROW)
	m.set_shader_parameter("stagger", EV_STAGGER)
	m.set_shader_parameter("burst", EV_BURST)
	m.set_shader_parameter("total", EV_TOTAL)
	m.render_priority = 1
	return m


static func _puff_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled,
	depth_draw_never, blend_mix;
uniform vec3 tint;
uniform float t;
uniform float burst;
uniform float total;
varying vec2 quv;
varying float fade;
void vertex() {
	float bear = UV2.x;
	float life = clamp((t - burst) / max(total - burst, 0.001), 0.0, 1.0);
	// Out, up, and then down: the arc of a handful of powder thrown into cold air.
	float r = (0.30 + 0.55 * fract(bear * 3.7)) * life;
	vec3 c = VERTEX;
	c.x += cos(bear) * r;
	c.z += sin(bear) * r;
	c.y += (0.55 * life - 0.75 * life * life) * 0.9;
	// In fast, out slow, and never fully on: these are the pieces of a crystal that
	// has just come apart, not a firework.
	fade = smoothstep(0.0, 0.10, life) * (1.0 - smoothstep(0.45, 1.0, life));
	vec4 vp = MODELVIEW_MATRIX * vec4(c, 1.0);
	vp.xy += UV * UV2.y * (0.6 + 0.7 * life);
	POSITION = PROJECTION_MATRIX * vp;
	quv = UV;
}
void fragment() {
	float d = clamp(1.0 - length(quv), 0.0, 1.0);
	ALBEDO = tint;
	ALPHA = d * d * d * fade * 0.72;
}
"""
	m.shader = sh
	m.set_shader_parameter("tint", tone(SNOW))
	m.set_shader_parameter("t", 0.0)
	m.set_shader_parameter("burst", EV_BURST)
	m.set_shader_parameter("total", EV_TOTAL)
	m.render_priority = 4
	return m


# ---------------------------------------------------------------------------
# The reindeer and the sleigh
# ---------------------------------------------------------------------------
# A SIDE VIEW held square to the camera, which at this size is not a shortcut — the
# whole team is about 190 px across on a 1280 px frame and 60 px tall, and a
# modelled quadruped at that size is a smudge with legs. What reads at 190 px is a
# silhouette with a bright rim on it, and that is exactly what this is: one flat
# relief in the plane of the screen, so every line of it is at full contrast against
# the sky whatever the board's camera is doing.
#
# The mesh is built once and cached; the NODE is built per celebration and freed
# after it.
static var _team_mesh: ArrayMesh = null

# Which colour a triangle takes, carried in UV.x, because a mesh with three
# materials on it is three draw calls and this is one.
const TEAM_BODY := 0.0
const TEAM_RIM := 1.0
const TEAM_SLEIGH := 2.0
const TEAM_HALO := 3.0


func _build_sleigh() -> void:
	if _sleigh != null:
		_sleigh.queue_free()
	_sleigh = Node3D.new()
	_sleigh.name = "AuroraSleigh"
	add_child(_sleigh)

	if _team_mesh == null:
		_team_mesh = _make_team_mesh()
	var mi := MeshInstance3D.new()
	mi.name = "Team"
	mi.mesh = _team_mesh
	mi.material_override = _team_material()
	mi.layers = BG_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The mesh is authored in a unit-ish box and the node is scaled to the frame, so
	# the bounds have to be given rather than derived from a transform that has not
	# happened yet.
	mi.custom_aabb = AABB(Vector3(-1.8, -1.2, -0.6), Vector3(3.6, 2.6, 1.2))
	_sleigh.add_child(mi)

	var wake := MeshInstance3D.new()
	wake.name = "Wake"
	wake.mesh = _wake_mesh()
	wake.material_override = _wake_material()
	wake.layers = BG_LAYER
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wake.custom_aabb = AABB(Vector3(-4.0, -1.5, -0.6), Vector3(5.0, 3.0, 1.2))
	_sleigh.add_child(wake)
	_sleigh.visible = false


# The whole team, in one triangle soup, authored looking at it from the side with
# the reindeer leading at +x. Nothing here is a primitive — a quadruped made of
# capsules reads as a machine — so the body is one closed outline and the legs are
# tapered strips off it.
static func _make_team_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	# --- the sleigh: a shallow hull with a curl at the front and a runner under it.
	#     Built first so the reindeer's rear leg can swing over it.
	var sled := PackedVector2Array([
		Vector2(-1.14, -0.04), Vector2(-1.16, 0.12), Vector2(-1.04, 0.20),
		Vector2(-0.66, 0.22), Vector2(-0.38, 0.18), Vector2(-0.30, 0.30),
		Vector2(-0.20, 0.32), Vector2(-0.22, 0.20), Vector2(-0.26, 0.06),
		Vector2(-0.44, -0.06), Vector2(-0.92, -0.08),
	])
	_halo(verts, uvs, idx, sled, 0.042)
	_fan(verts, uvs, idx, sled, TEAM_SLEIGH)
	_rim(verts, uvs, idx, sled, 0.026, TEAM_RIM)
	# The runner, and its upturned nose. Two strips, each with a dark one behind it.
	_edged(verts, uvs, idx, Vector2(-1.18, -0.08), Vector2(-0.32, -0.10),
		0.034, 0.034, TEAM_RIM)
	_edged(verts, uvs, idx, Vector2(-0.32, -0.10), Vector2(-0.18, 0.02),
		0.032, 0.020, TEAM_RIM)

	# --- the legs, in a flying gallop: the front pair reaching forward and the rear
	#     pair trailing back, which is the pose a reindeer in the sky is DRAWN in
	#     whatever it would really do. Drawn before the torso so they come out of it.
	var legs := [
		[Vector2(0.66, 0.06), Vector2(0.88, -0.30), 0.085, 0.040],
		[Vector2(0.72, 0.08), Vector2(1.00, -0.22), 0.100, 0.045],
		[Vector2(0.26, 0.04), Vector2(-0.04, -0.12), 0.090, 0.040],
		[Vector2(0.30, 0.06), Vector2(0.04, -0.24), 0.110, 0.050],
	]
	for lg: Array in legs:
		_edged(verts, uvs, idx, lg[0], lg[1], lg[2], lg[3], TEAM_BODY)
	# Hooves: one short, slightly wider strip at the end of each leg, which is all it
	# takes for a tapered stick to stop reading as a stick.
	for lg: Array in legs:
		var a: Vector2 = lg[1]
		_edged(verts, uvs, idx, a, a + (a - lg[0]).normalized() * 0.05,
			0.058, 0.048, TEAM_RIM)

	# --- the tail.
	_edged(verts, uvs, idx, Vector2(0.20, 0.16), Vector2(0.07, 0.30),
		0.090, 0.030, TEAM_BODY)

	# --- the torso. A closed outline rather than a capsule: a quadruped assembled
	#     from primitives reads as a machine at any size.
	var body := PackedVector2Array([
		Vector2(0.18, 0.10), Vector2(0.24, 0.25), Vector2(0.40, 0.31),
		Vector2(0.60, 0.30), Vector2(0.74, 0.26), Vector2(0.81, 0.15),
		Vector2(0.76, 0.03), Vector2(0.58, -0.03), Vector2(0.36, -0.03),
		Vector2(0.22, 0.02),
	])
	_halo(verts, uvs, idx, body, 0.045)
	_fan(verts, uvs, idx, body, TEAM_BODY)
	_rim(verts, uvs, idx, body, 0.026, TEAM_RIM)

	# --- the neck: one tapering strip from the shoulder up to the jaw. It is what
	#     turns a torso with a head next to it into an animal.
	_edged(verts, uvs, idx, Vector2(0.74, 0.20), Vector2(0.94, 0.42),
		0.190, 0.115, TEAM_BODY)

	# --- the head, muzzle forward.
	var head := PackedVector2Array([
		Vector2(0.86, 0.36), Vector2(0.88, 0.52), Vector2(1.02, 0.56),
		Vector2(1.20, 0.47), Vector2(1.19, 0.39), Vector2(1.00, 0.34),
	])
	_halo(verts, uvs, idx, head, 0.036)
	_fan(verts, uvs, idx, head, TEAM_BODY)
	_rim(verts, uvs, idx, head, 0.020, TEAM_RIM)
	# An ear, laid back.
	_edged(verts, uvs, idx, Vector2(0.93, 0.54), Vector2(0.86, 0.64),
		0.070, 0.030, TEAM_BODY)

	# --- the antlers. Two beams off the crown with two tines each, in the rim colour
	#     so they read against the sky at four pixels wide.
	var crown := Vector2(0.98, 0.56)
	for f in 2:
		var lean := 0.09 - 0.18 * float(f)
		var tip := crown + Vector2(0.10 + lean, 0.32)
		_edged(verts, uvs, idx, crown, tip, 0.048, 0.022, TEAM_RIM)
		var m1 := crown.lerp(tip, 0.42)
		_edged(verts, uvs, idx, m1, m1 + Vector2(0.13 + lean * 0.7, 0.09),
			0.034, 0.018, TEAM_RIM)
		var m2 := crown.lerp(tip, 0.74)
		_edged(verts, uvs, idx, m2, m2 + Vector2(-0.09 + lean, 0.11),
			0.030, 0.016, TEAM_RIM)

	# --- the harness. The one line that says the reindeer is PULLING rather than
	#     flying next to a sleigh, which is the brief's own emphasis.
	_edged(verts, uvs, idx, Vector2(-0.22, 0.16), Vector2(0.24, 0.16),
		0.022, 0.022, TEAM_RIM)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# A strip with a dark one behind it, which is what _halo is for a filled shape. A
# leg is four pixels wide on screen and the aurora is directly behind it: without
# this, half a gallop happens against a sky it is the same value as.
static func _edged(verts: PackedVector3Array, uvs: PackedVector2Array,
		idx: PackedInt32Array, a: Vector2, b: Vector2, w0: float, w1: float,
		key: float) -> void:
	_strip(verts, uvs, idx, a, b, w0 + 0.036, w1 + 0.036, TEAM_HALO, -0.002)
	_strip(verts, uvs, idx, a, b, w0, w1, key)


# The dark halo: the same outline pushed `grow` metres out from its own centroid and
# filled, laid down BEFORE the shape it belongs to and a shade behind it in z. It is
# two dozen triangles and it is what makes a flat relief legible on a sky whose
# brightness is not ours to control.
static func _halo(verts: PackedVector3Array, uvs: PackedVector2Array,
		idx: PackedInt32Array, poly: PackedVector2Array, grow: float) -> void:
	var mid := Vector2.ZERO
	for p: Vector2 in poly:
		mid += p
	mid /= float(poly.size())
	var out := PackedVector2Array()
	for p: Vector2 in poly:
		out.append(p + (p - mid).normalized() * grow)
	var c := verts.size()
	verts.append(Vector3(mid.x, mid.y, -0.002))
	uvs.append(Vector2(TEAM_HALO, 1.0))
	for p: Vector2 in out:
		verts.append(Vector3(p.x, p.y, -0.002))
		uvs.append(Vector2(TEAM_HALO, 1.0))
	for i in out.size():
		idx.append_array([c, c + 1 + i, c + 1 + (i + 1) % out.size()])


# A closed outline, filled from its own centroid. UV.x is the colour key and UV.y
# is 0 in the middle rising to 1 at the edge, which is what lets the fragment
# shader put a little depth into an otherwise flat shape.
static func _fan(verts: PackedVector3Array, uvs: PackedVector2Array,
		idx: PackedInt32Array, poly: PackedVector2Array, key: float) -> void:
	var mid := Vector2.ZERO
	for p: Vector2 in poly:
		mid += p
	mid /= float(poly.size())
	var c := verts.size()
	verts.append(Vector3(mid.x, mid.y, 0.0))
	uvs.append(Vector2(key, 0.0))
	for p: Vector2 in poly:
		verts.append(Vector3(p.x, p.y, 0.0))
		uvs.append(Vector2(key, 1.0))
	for i in poly.size():
		idx.append_array([c, c + 1 + i, c + 1 + (i + 1) % poly.size()])


# A band of width `w` lying just INSIDE an outline — the rim light, as geometry
# rather than as a shader term, because a rim computed from a normal needs the
# shape to have one and this shape is flat.
static func _rim(verts: PackedVector3Array, uvs: PackedVector2Array,
		idx: PackedInt32Array, poly: PackedVector2Array, w: float,
		key: float) -> void:
	var mid := Vector2.ZERO
	for p: Vector2 in poly:
		mid += p
	mid /= float(poly.size())
	var n := poly.size()
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var ai := a + (mid - a).normalized() * w
		var bi := b + (mid - b).normalized() * w
		var c := verts.size()
		for v: Vector2 in [a, b, bi, ai]:
			verts.append(Vector3(v.x, v.y, 0.001))
			uvs.append(Vector2(key, 1.0))
		idx.append_array([c, c + 1, c + 2, c, c + 2, c + 3])


# A tapered strip from `a` to `b`. Legs, antlers, runners and the harness are all
# this; the taper is what stops four rectangles reading as four rectangles.
static func _strip(verts: PackedVector3Array, uvs: PackedVector2Array,
		idx: PackedInt32Array, a: Vector2, b: Vector2, w0: float, w1: float,
		key: float, z: float = 0.0) -> void:
	var d := (b - a).normalized()
	var nrm := Vector2(-d.y, d.x)
	var c := verts.size()
	for v: Vector2 in [a - nrm * w0 * 0.5, a + nrm * w0 * 0.5,
			b + nrm * w1 * 0.5, b - nrm * w1 * 0.5]:
		verts.append(Vector3(v.x, v.y, z))
		uvs.append(Vector2(key, 1.0))
	idx.append_array([c, c + 1, c + 2, c, c + 2, c + 3])


static func _team_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled,
	depth_draw_opaque, blend_mix;
uniform vec3 c_body;
uniform vec3 c_rim;
uniform vec3 c_sled;
uniform vec3 c_edge;
uniform float fade;
varying float key;
varying float edge;
void vertex() {
	key = UV.x;
	edge = UV.y;
}
void fragment() {
	// Three keys, resolved with steps rather than with branches: the whole team is
	// one draw call and one material, and the colour is a mesh attribute.
	vec3 c = mix(c_body, c_sled, step(1.5, key));
	c = mix(c, c_rim, step(0.5, key) * (1.0 - step(1.5, key)));
	c = mix(c, c_edge, step(2.5, key));
	// A little fall-off from the middle of each filled shape to its edge, so a flat
	// silhouette still has a lit side.
	// Brighter in the middle of each filled shape and a touch darker at its edge,
	// which is the only modelling a flat relief gets and is enough at 190 px.
	c *= 0.88 + 0.24 * (1.0 - edge);
	ALBEDO = c;
	ALPHA = fade;
}
"""
	m.shader = sh
	m.set_shader_parameter("c_body", tone(TEAM_HIDE))
	m.set_shader_parameter("c_rim", tone(TEAM_LIGHT))
	m.set_shader_parameter("c_sled", tone(TEAM_SLED))
	m.set_shader_parameter("c_edge", tone(TEAM_EDGE))
	m.set_shader_parameter("fade", 1.0)
	m.render_priority = 2
	return m


# The wake: a short trail of small quads behind the sleigh, at fixed offsets in the
# team's own space, so it FOLLOWS rather than being recomputed. Each has its own
# phase, and the whole trail thins toward its tail.
static func _wake_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 71
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := 22
	for i in n:
		var f := float(i) / float(n - 1)
		var home := Vector3(-1.25 - f * 1.9, 0.05 + rng.randf_range(-0.18, 0.22),
			rng.randf_range(-0.10, 0.10))
		var sz := lerpf(0.085, 0.030, f) * rng.randf_range(0.7, 1.3)
		var b := verts.size()
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1),
				Vector2(-1, 1)]:
			verts.append(home)
			uvs.append(c)
			uv2.append(Vector2(rng.randf(), sz * (1.0 - f * 0.35)))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	# ...and two STEADY motes, one under each half of the team: the soft icy glow
	# the brief asks the sleigh to carry. They ride in the same sheet because a
	# glow is a mote that does not twinkle, and one flag in UV2.x is cheaper than a
	# second material — the same trick the snow uses for its floating crystals.
	for g: Array in [[Vector3(-0.66, 0.08, -0.05), 0.62],
			[Vector3(0.58, 0.16, -0.05), 0.50]]:
		var b2 := verts.size()
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1),
				Vector2(-1, 1)]:
			verts.append(g[0])
			uvs.append(c)
			uv2.append(Vector2(1.0 + rng.randf() * 0.9, g[1]))
		idx.append_array([b2, b2 + 1, b2 + 2, b2, b2 + 2, b2 + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _wake_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled,
	depth_draw_never, blend_add;
uniform vec3 tint;
varying vec2 quv;
varying float spark;
void vertex() {
	// UV2.x carries the mote's phase AND, in its integer part, which KIND it is:
	// under 1 is a twinkling wake mote, over 1 is one of the two steady glows the
	// team carries. One channel for both, because a mesh attribute costs a vertex
	// format and a fract() costs nothing.
	float steady = step(1.0, UV2.x);
	float seed = fract(UV2.x);
	spark = mix(0.45 + 0.55 * pow(max(sin(TIME * 3.1 + seed * 41.0), 0.0), 2.0),
		0.16 + 0.05 * sin(TIME * 1.1 + seed * 9.0), steady);
	vec3 c = VERTEX;
	c.y += 0.06 * sin(TIME * 1.7 + seed * 27.0) * (1.0 - steady);
	vec4 vp = MODELVIEW_MATRIX * vec4(c, 1.0);
	vp.xy += UV * UV2.y;
	POSITION = PROJECTION_MATRIX * vp;
	quv = UV;
}
void fragment() {
	float d = clamp(1.0 - length(quv), 0.0, 1.0);
	// Added, not mixed, and at a low weight: this is the only additive surface in
	// the background, and it is two dozen motes a few pixels across.
	ALBEDO = tint * (d * d * d * spark * 0.85);
	ALPHA = 1.0;
}
"""
	m.shader = sh
	m.set_shader_parameter("tint", tone(WAKE))
	m.render_priority = 5
	return m


# ---------------------------------------------------------------------------
# Placement, through the CAMERA
# ---------------------------------------------------------------------------
# These four helpers are the lake's, and they are COPIED rather than shared. The two
# backgrounds are siblings; neither should depend on the other, and a module for two
# callers is a module that exists to avoid a copy. If a third generated background
# appears, this is what to lift out of both — along with TONE_RAMP, which is the
# same measurement in both files and is asserted equal by tools/ice_verify.tscn.
#
# What they are for, in one paragraph, because it is not obvious and the lake paid
# for it twice: a tabletop camera keystones the ground so hard that a distance in
# METRES is not a position on screen. Measured on the lake at reach 3.47, props laid
# on a world annulus put the first one at screen x 1961 and another at (-444, 842) —
# every one of them outside a 1280x720 frame — because "4.5 m out" is comfortably in
# frame at the SIDE and far outside it toward the camera. So a candidate is
# PROJECTED and kept only if it lands where it is wanted, which is also what makes
# ONE environment correct on all three boards at every aspect with no per-board
# constant anywhere.

const TRIES := 90


# A point on the ice between `lo` and `hi` out from the middle of the board that
# lands in the frame's own gutter. Vector3.INF when nothing in TRIES does, and the
# caller then drops that prop rather than placing it badly.
#
# `arc`, in radians, restricts the angle to within that much of the +x or -x axis —
# the SIDE gutters. `near_z` rejects anything closer to the camera than that.
static func _frame_point(rng: RandomNumberGenerator, lo: float, hi: float,
		cam: Camera3D, vp: Vector2, arc: float = 0.0, near_z: float = 1e9) -> Vector3:
	var x0 := vp.x * EDGE_X
	var x1 := vp.x * (1.0 - EDGE_X)
	var y0 := vp.y * EDGE_TOP
	var y1 := vp.y * (1.0 - EDGE_BOTTOM)
	for _try in TRIES:
		var a := rng.randf() * TAU
		if arc > 0.0:
			a = (rng.randf() * 2.0 - 1.0) * arc + (0.0 if rng.randf() < 0.5 else PI)
		# Linear in radius, not in sqrt: sampling uniformly by AREA pushes most of
		# the draw to the outer edge of the band, which on a keystoned ground plane
		# is the far strip, and puts every prop in the top corners.
		var r := lerpf(lo, hi, rng.randf())
		var p := Vector3(cos(a) * r, ICE_Y, sin(a) * r)
		if p.z > near_z:
			continue
		# is_position_behind FIRST: unproject_position on a point behind the camera
		# hands back a mirrored screen position that passes every bounds test below.
		if cam.is_position_behind(p):
			continue
		var s := cam.unproject_position(p)
		if s.x < x0 or s.x > x1 or s.y < y0 or s.y > y1:
			continue
		return p
	return Vector3.INF


# How tall something standing at `p` may actually be, given that it wants to be
# `want` metres and has to fit under the top of the frame AND stay under
# SCREEN_TALL of the frame's height.
# `edge` and `tall` are the two margins, and they are parameters only because the
# far ice wall needs different ones: it stands in the top band that EDGE_TOP exists
# to keep everything else out of, and it is allowed to be a little taller on screen
# than a crystal because it is a silhouette in fog rather than a solid body.
static func _fit_height(p: Vector3, want: float, cam: Camera3D, vp: Vector2,
		edge: float = EDGE_TOP, tall: float = SCREEN_TALL) -> float:
	var top := p + Vector3(0.0, want, 0.0)
	if cam.is_position_behind(p) or cam.is_position_behind(top):
		return 0.0
	var s := cam.unproject_position(p)
	var rise := s.y - cam.unproject_position(top).y
	if rise <= 0.5:
		return 0.0
	var room := minf(s.y - vp.y * edge, vp.y * tall)
	if room <= 0.0:
		return 0.0
	return want * clampf(room / rise, 0.0, 1.0)


# How many METRES tall something at `p` has to be to stand `frac` of the frame's
# height on screen. The inverse of the question _fit_height answers, and the one a
# prop that must read at a CONSISTENT SIZE has to ask: this camera keystones the
# ground so hard that the same object is four times taller at the bottom of the
# picture than at the top of it.
static func _height_for_screen(p: Vector3, frac: float, cam: Camera3D,
		vp: Vector2) -> float:
	var top := p + Vector3(0.0, 1.0, 0.0)
	if cam.is_position_behind(p) or cam.is_position_behind(top):
		return 0.0
	var px := cam.unproject_position(p).y - cam.unproject_position(top).y
	if px <= 0.5:
		return 0.0
	return (vp.y * frac) / px


# The same cap for something lying FLAT: how wide it may be on screen. A plate has
# no height to cut down, and a radius that reads as a patch out at the far edge is
# a slab across the corner when the same draw puts it near the camera.
static func _fit_flat(p: Vector3, want: float, cam: Camera3D, vp: Vector2,
		cap: float = SCREEN_FLAT) -> float:
	var edge := p + Vector3(want, 0.0, 0.0)
	if cam.is_position_behind(p) or cam.is_position_behind(edge):
		return 0.0
	var px := cam.unproject_position(p).distance_to(cam.unproject_position(edge))
	if px <= 0.5:
		return want
	return want * minf(1.0, (vp.x * cap) / px)


# ---------------------------------------------------------------------------
# Placement, through the camera again — but FORWARDS this time
# ---------------------------------------------------------------------------
# _frame_point above samples the world and keeps what lands in frame. That is the
# right tool for a scatter and the wrong one for anything that has to COVER a part
# of the picture, and the difference is what "the background is too empty" turned
# out to mean here.
#
# Measured on the shipping Hard board: sixteen crystal clusters, every one of them
# correctly placed by _frame_point, produced two little heaps in the top corners and
# nothing anywhere else. The sampler was not broken — the far gutter it draws from
# projects almost entirely into those two corners, and no number of tries changes
# where a region of the world lands on screen. Wanting a wall across the top of the
# frame means starting from the top of the frame.
#
# So these two go the other way: pick the point ON SCREEN, and find the ice under it.

# The point on the ice directly under a point on the screen, or INF if that ray
# never comes down (above the horizon, or behind the camera).
static func _ice_at_screen(px: Vector2, cam: Camera3D) -> Vector3:
	var o := cam.project_ray_origin(px)
	var d := cam.project_ray_normal(px)
	if d.y > -0.0001:
		return Vector3.INF
	var t := (ICE_Y - o.y) / d.y
	if t <= 0.0 or t > 400.0:
		return Vector3.INF
	return o + d * t


# A point on the ice under a random point inside a screen rectangle, that is also
# at least `clear` metres from the middle of the board. INF when TRIES of those
# fail, and the caller then drops the prop rather than placing it badly.
static func _screen_point(rng: RandomNumberGenerator, x0: float, x1: float,
		y0: float, y1: float, cam: Camera3D, vp: Vector2, clear: float) -> Vector3:
	for _try in TRIES:
		var p := _ice_at_screen(Vector2(rng.randf_range(x0, x1) * vp.x,
			rng.randf_range(y0, y1) * vp.y), cam)
		if p == Vector3.INF:
			continue
		if Vector2(p.x, p.z).length() < clear:
			continue
		return p
	return Vector3.INF


static func _fill(mm: MultiMesh, xf: Array[Transform3D], cd: Array[Color]) -> void:
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_custom_data(i, cd[i])
