extends Node
# Sweeps the two free constants in the world lighting — LIGHT_SCALE and
# AMBIENT_GAIN — against all six Blender reference renders in one process, and
# prints the per-channel ratio for each combination so the pair can be chosen from
# numbers rather than impressions.
#
#   Godot..._console.exe --path . res://tools/world_tune.tscn -- [light,ambient ...]
#
# Each world is rendered at the reference's own 1920x1080 through the reference
# camera (WorldScenes.make_preview_camera), so framing is out of the question and
# only materials and lighting are being measured. The cells the BUTTONS occupy in
# the reference are excluded, because the Godot side has no board in it.
const REF_DIR := "C:/Users/sahar/OneDrive/Documents/APP IDEAS/Simon/Themes2/renders/"
const REF := {
	# world_ice is gone from here with the world itself — see world_scenes.gd.
	"world_forest": "lume_forest.png",
}
const COLS := 8
const ROWS := 5
const BUTTON_CELLS := [
	Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1),
	Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2),
	Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3),
]
const W := 1920
const H := 1080

var _ref_mean: Dictionary = {}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var combos: Array = args if args.size() > 0 else ["1.4,0.60,1.0"]
	for i in 10: await get_tree().process_frame
	for id in REF:
		var img := Image.load_from_file(REF_DIR + String(REF[id]))
		_ref_mean[id] = _mean(img) if img != null else Vector3.ZERO
	for c in combos:
		var parts := String(c).split(",")
		WorldScenes.LIGHT_SCALE = parts[0].to_float()
		WorldScenes.AMBIENT_GAIN = parts[1].to_float()
		if parts.size() > 2:
			WorldScenes.TONE_IRRADIANCE = parts[2].to_float()
		WorldScenes.clear_cache()
		print("\n=== LIGHT_SCALE=%.3f  AMBIENT_GAIN=%.3f  TONE_IRRADIANCE=%.3f" % [WorldScenes.LIGHT_SCALE, WorldScenes.AMBIENT_GAIN, WorldScenes.TONE_IRRADIANCE])
		var acc := Vector3.ZERO
		var n := 0
		for idv in WorldScenes.ORDER:
			var id := String(idv)
			var got := await _render(id)
			if got == null:
				continue
			var mg := _mean(got)
			var mr: Vector3 = _ref_mean[id]
			var ratio := Vector3(mg.x / maxf(mr.x, 1e-4), mg.y / maxf(mr.y, 1e-4), mg.z / maxf(mr.z, 1e-4))
			print("  %-15s ref %5.1f %5.1f %5.1f   godot %5.1f %5.1f %5.1f   ratio %.2f %.2f %.2f"
				% [id, mr.x * 255.0, mr.y * 255.0, mr.z * 255.0,
					mg.x * 255.0, mg.y * 255.0, mg.z * 255.0, ratio.x, ratio.y, ratio.z])
			acc += Vector3(log(ratio.x), log(ratio.y), log(ratio.z))
			n += 1
		if n > 0:
			var g := acc / float(n)
			print("  GEOMETRIC MEAN RATIO  %.3f %.3f %.3f   (1.000 is a match)"
				% [exp(g.x), exp(g.y), exp(g.z)])
	get_tree().quit()

func _render(id: String) -> Image:
	var scene := WorldScenes.build(id)
	if scene == null:
		return null
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.add_child(WorldScenes.make_preview_environment(WorldScenes.world_of(id)))
	vp.add_child(WorldScenes.make_preview_camera(float(W) / float(H)))
	vp.add_child(scene)
	add_child(vp)
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	await get_tree().process_frame
	return img

func _mean(img: Image) -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	for r in ROWS:
		for c in COLS:
			if BUTTON_CELLS.has(Vector2i(c, r)):
				continue
			acc += _cell(img, c, r)
			n += 1
	return acc / maxf(float(n), 1.0)

func _cell(img: Image, c: int, r: int) -> Vector3:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := int(float(c) / COLS * w)
	var x1 := int(float(c + 1) / COLS * w)
	var y0 := int(float(r) / ROWS * h)
	var y1 := int(float(r + 1) / ROWS * h)
	var acc := Vector3.ZERO
	var n := 0
	var sx := maxi(1, (x1 - x0) / 20)
	var sy := maxi(1, (y1 - y0) / 20)
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
