extends Node
# Does the cosmetic frames' idle actually reach the screen?
#
# It is not obvious that it does. The idle runs on TIME inside the frame shader, and
# the board deliberately does NOT redraw while nothing is moving — so without
# MemoryGameUI._tick_frame_idle nudging it, an idle board would show one frozen
# phase of the breath forever. This measures the thing end to end: it samples the
# board's own SubViewport over more than one 6 s loop and reports how much the light
# in the frame band actually moves.
#
# Needs a real GPU (it reads the render target back), so run WITHOUT --headless:
#   godot --path . tools/frame_idle_probe.tscn --resolution 1280x720

const W := 1280
const H := 720
const SAMPLES := 17
const STEP := 0.40            # seconds between samples -> 6.8 s, one full loop and a bit

var _dev: MemoryGameUI
var _vp: SubViewport          # the board's own SubViewport — holds the 3D camera
var _outer: SubViewport       # a container we control, so the readback is real

func _ready() -> void:
	FirebaseManager.uid = "idleprobe"
	CoinsManager._apply_doc({})
	for _i in 5:
		await get_tree().process_frame

	# The board composites into whatever is behind it, and reading the WINDOW back on
	# this driver hands over a stale buffer — as does reading a render target that is
	# in UPDATE_ONCE. So the board goes inside a SubViewport we hold at UPDATE_ALWAYS
	# and read from, which is the same arrangement frame_shot uses.
	_outer = SubViewport.new()
	_outer.size = Vector2i(W, H)
	_outer.transparent_bg = false
	_outer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_outer.msaa_2d = Viewport.MSAA_DISABLED
	add_child(_outer)
	var bg := ColorRect.new()
	bg.color = Color8(8, 16, 40)
	bg.size = Vector2(W, H)
	_outer.add_child(bg)

	_dev = MemoryGameUI.new()
	_dev.input_enabled = false
	_dev.size = Vector2(W, H)
	_outer.add_child(_dev)
	await get_tree().process_frame
	_dev.configure(5, [])
	for c in _dev.get_children():
		if c is SubViewportContainer:
			_vp = (c as SubViewportContainer).get_child(0) as SubViewport

	var worst := ""
	var worst_amp := 999.0
	var every: Array = ButtonFrames.ORDER.duplicate()
	for sid: String in ButtonFrames.SKIN_FRAMES.keys():
		every.append(String(ButtonFrames.SKIN_FRAMES[sid]))
	for id: String in every:
		if id == ButtonFrames.DEFAULT_ID:
			continue
		_dev.apply_button_frame(id)
		var amp := await _measure(id)
		if amp < worst_amp:
			worst_amp = amp
			worst = id

	# And the control: DEFAULT has no idle at all, so it must NOT move.
	_dev.apply_button_frame(ButtonFrames.DEFAULT_ID)
	var flat := await _measure("default")

	print("\nquietest cosmetic: %s at %.2f%%" % [worst, worst_amp * 100.0])
	print("DEFAULT (control): %.2f%%" % (flat * 100.0))
	var ok := worst_amp > 0.01 and flat < 0.004
	print("\n%s" % ("PASS — every frame breathes, and DEFAULT does not"
		if ok else "FAIL — see the numbers above"))
	get_tree().quit(0 if ok else 1)

# Sample the mean brightness of the FRAME BAND — an annulus around one button,
# outside the coloured surface and inside the frame's outer edge — over one loop,
# and return the peak-to-peak swing as a fraction of the mean. Sampling the whole
# image would drown a ring 0.19 wide in a mostly-empty board.
func _measure(id: String) -> float:
	var lo := 1e9
	var hi := -1e9
	var sum := 0.0
	for i in SAMPLES:
		var t := Time.get_ticks_msec() * 0.001
		while Time.get_ticks_msec() * 0.001 - t < STEP:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var v := _band_mean()
		lo = minf(lo, v)
		hi = maxf(hi, v)
		sum += v
	var mean := sum / float(SAMPLES)
	var amp := (hi - lo) / maxf(mean, 0.0001)
	print("  %-16s mean %.4f  swing %.4f  (%.2f%% of mean, %d samples)"
		% [id, mean, hi - lo, amp * 100.0, _last_n])
	return amp

var _last_n := 0

# The front-left (Crimson) button's frame band, in screen space, measured through
# the device's own camera so it tracks whatever framing the fit landed on.
func _band_mean() -> float:
	# Read back the OUTER viewport (UPDATE_ALWAYS). Neither the window nor the board's
	# own UPDATE_ONCE render target reads back reliably on this driver — which is
	# exactly the trap this probe exists to avoid falling into. The board's container
	# fills the outer viewport 1:1, so unprojected coordinates map straight over.
	var img := _outer.get_texture().get_image()
	var holder := _dev.frame_mesh("Crimson").get_parent() as Node3D
	var cam: Camera3D = null
	for c in _vp.get_children():
		if c is Camera3D:
			cam = c
	if cam == null or holder == null:
		return 0.0
	var total := 0.0
	var n := 0
	# 96 points around the ring at three radii inside the frame's own band.
	for k in 96:
		var a := TAU * float(k) / 96.0
		for r: float in [0.80, 0.87, 0.94]:
			var world: Vector3 = holder.global_position \
				+ Vector3(cos(a) * r, 0.22, sin(a) * r)
			var p := cam.unproject_position(world)
			var px := Vector2i(p)
			if px.x < 0 or px.y < 0 or px.x >= img.get_width() or px.y >= img.get_height():
				continue
			var c := img.get_pixelv(px)
			total += (c.r + c.g + c.b) / 3.0
			n += 1
	_last_n = n
	return total / maxf(1.0, float(n))

