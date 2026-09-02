extends Node
# Puts a Godot background render next to its Blender reference and prints numbers
# rather than impressions: a coarse grid of mean sRGB values over both images, the
# per-cell delta, and a whole-image summary.
#
#   Godot..._console.exe --path . res://tools/bg_compare.tscn -- [id ...]
#
# The Godot renders come from tools/bg_sheet.gd (run that first, on `hard` — the
# difficulty whose camera the Blender previews were framed through). The references
# are read straight out of the Themes folder, outside the project.
#
# Cells are sampled on the reference's own 1920x1080 grid and on the render's
# 1280x720 one, so the two are compared by FRACTION of the frame, not by pixel
# index. The buttons occupy the middle of both, so the cells that matter for the
# background are the outer ring — the report marks which is which.

const REF_DIR := "C:/Users/sahar/OneDrive/Documents/APP IDEAS/Simon/Themes/preview/"
const REF_FILE := {
	"bg_neongrid": "BG_NeonGrid.png", "bg_deepspace": "BG_DeepSpace.png",
	"bg_circuit": "BG_Circuit.png",
	"bg_hexfloor": "BG_HexFloor.png", "bg_darkmetal": "BG_DarkMetal.png",
	"bg_crystal": "BG_CrystalCave.png", "bg_volcanic": "BG_Volcanic.png",
	"bg_arcade": "BG_ArcadeRoom.png",
}

# The Themes2 worlds come from a different .blend and a different render folder,
# and their references have the BUTTONS in them (they were rendered through the
# real Ref_LUME_Buttons_Hard rig), so the button cells are excluded from the
# summary here exactly as they are for Themes1 — for the opposite reason, but to
# the same end: what is being measured is the world.
const WORLD_REF_DIR := "C:/Users/sahar/OneDrive/Documents/APP IDEAS/Simon/Themes2/renders/"
const WORLD_REF_FILE := {
	# `world_ice` is deliberately absent: Ice Kingdom is generated in Godot now
	# (ice_world.gd) and has no Blender render to be compared against. lume_ice.png
	# is still in Themes2/renders as the reference for the .glb, which is still on
	# disk — see the note in world_scenes.gd.
	"world_forest": "lume_forest.png",
}

static func _ref_path(id: String) -> String:
	if WORLD_REF_FILE.has(id):
		return WORLD_REF_DIR + String(WORLD_REF_FILE[id])
	return REF_DIR + String(REF_FILE.get(id, ""))

const COLS := 8
const ROWS := 5
# Cells the buttons cover on both images, so a background comparison is not
# dominated by how the six discs happen to land. Column,row pairs (0-based).
const BUTTON_CELLS := [
	Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1),
	Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2),
	Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3),
]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var ids: Array = []
	for a in args:
		if String(a) != "ref":
			ids.append(a)
	if ids.is_empty():
		ids = BackgroundScenes.ORDER
	for id in ids:
		_compare(String(id))
	get_tree().quit()

func _compare(id: String) -> void:
	var ref := Image.load_from_file(_ref_path(id))
	# "-- ref <id> ..." compares the reference-camera render from tools/world_ref.gd
	# instead of the gameplay one, which takes framing out of the question and leaves
	# only materials and lighting.
	var use_ref := OS.get_cmdline_user_args().has("ref")
	var got := Image.load_from_file(ProjectSettings.globalize_path(
		("user://wref_%s.png" if use_ref else "user://bg_hard_%s.png") % id))
	if ref == null or got == null:
		print("MISSING  %s  ref=%s got=%s" % [id, ref != null, got != null])
		return
	print("\n=== %s   ref %dx%d   godot %dx%d" % [id, ref.get_width(), ref.get_height(),
		got.get_width(), got.get_height()])
	print("  cell    ref(sRGB 0-255)      godot                delta       ")
	var sum_ref := Vector3.ZERO
	var sum_got := Vector3.ZERO
	var n := 0
	for r in ROWS:
		var line := ""
		for c in COLS:
			var a := _cell_mean(ref, c, r)
			var b := _cell_mean(got, c, r)
			var is_btn := BUTTON_CELLS.has(Vector2i(c, r))
			if not is_btn:
				sum_ref += a
				sum_got += b
				n += 1
			line += "%s%3d,%3d,%3d/%3d,%3d,%3d%s " % [
				"[" if is_btn else " ",
				int(a.x * 255.0), int(a.y * 255.0), int(a.z * 255.0),
				int(b.x * 255.0), int(b.y * 255.0), int(b.z * 255.0),
				"]" if is_btn else " "]
		print("  r%d %s" % [r, line])
	var mr := sum_ref / float(n)
	var mg := sum_got / float(n)
	print("  BACKGROUND MEAN (button cells excluded, %d cells)" % n)
	print("    ref   %5.1f %5.1f %5.1f" % [mr.x * 255.0, mr.y * 255.0, mr.z * 255.0])
	print("    godot %5.1f %5.1f %5.1f" % [mg.x * 255.0, mg.y * 255.0, mg.z * 255.0])
	print("    delta %+5.1f %+5.1f %+5.1f   ratio %.2f %.2f %.2f" % [
		(mg.x - mr.x) * 255.0, (mg.y - mr.y) * 255.0, (mg.z - mr.z) * 255.0,
		mg.x / maxf(mr.x, 0.0001), mg.y / maxf(mr.y, 0.0001), mg.z / maxf(mr.z, 0.0001)])
	# The brightest background cell on each side: the thing that shows up as a
	# hotspot when a Blender area panel is rebuilt as a point light.
	var pr := _peak(ref)
	var pg := _peak(got)
	print("    peak bg cell  ref %s -> %3d   godot %s -> %3d" % [pr.cell, int(pr.v * 255.0),
		pg.cell, int(pg.v * 255.0)])

func _cell_mean(img: Image, c: int, r: int) -> Vector3:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := int(float(c) / COLS * w)
	var x1 := int(float(c + 1) / COLS * w)
	var y0 := int(float(r) / ROWS * h)
	var y1 := int(float(r + 1) / ROWS * h)
	var acc := Vector3.ZERO
	var n := 0
	var sx := maxi(1, (x1 - x0) / 24)
	var sy := maxi(1, (y1 - y0) / 24)
	var y := y0
	while y < y1:
		var x := x0
		while x < x1:
			var p := img.get_pixel(x, y)
			acc += Vector3(p.r, p.g, p.b)
			n += 1
			x += sx
		y += sy
	return acc / maxf(float(n), 1.0)

func _peak(img: Image) -> Dictionary:
	var best := 0.0
	var cell := Vector2i.ZERO
	for r in ROWS:
		for c in COLS:
			if BUTTON_CELLS.has(Vector2i(c, r)):
				continue
			var m := _cell_mean(img, c, r)
			var v := (m.x + m.y + m.z) / 3.0
			if v > best:
				best = v
				cell = Vector2i(c, r)
	return {"cell": cell, "v": best}
