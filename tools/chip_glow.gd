extends Node
# HIGHLIGHT_FACE sweep for the ROYAL CASINO chips.
#
# The flash the computer plays the sequence back with is the single most important
# thing a button does, and on this skin it very nearly did not happen: at the first
# rig the chips sat at luminance 0.55-0.80 on LIGHT alone — up in the shoulder of the
# tone curve — and lighting the highlight rung moved a chip by ONE COUNT.
#
# So the lift is measured rather than chosen, against the number that actually
# matters: THE STOCK BUTTON'S OWN STEP. Whatever the stock board does between idle
# and highlight is what every player of this game has learned to read, and the chips
# have to do about the same.
#
# Run WITHOUT --headless:
#   Godot_..._console.exe --path . tools/chip_glow.tscn -- [easy|medium|hard]
#
# Prints, per chip and per candidate lift: idle and highlight mean colour inside the
# chip, the luminance STEP between them, and the saturation at highlight (the cost —
# a flash that whitens the button has taken away the thing the player is reading).

const CHIPS := preload("res://chip_buttons.gd")
const SHOT_W := 1280
const SHOT_H := 720

# THE SWEEP IS TWO-DIMENSIONAL, and it has to be.
#
# A one-dimensional sweep of the highlight lift was the first attempt and it proved
# the lift is the wrong knob: from 1.00 to 4.60 the worst chip's step only moved
# +0.013 -> +0.069, against a stock button's +0.179. The reason is structural rather
# than a matter of degree —
#
#   * the board writes emission through an sRGB round trip and this renderer uses the
#     stored colour raw, so a highlight rung of k lands as about k^(1/2.4) of the
#     idle emission. Even k = 5 is only 1.9x.
#   * so the SIZE of the step is set almost entirely by how much of the chip's idle
#     pixel is EMISSION rather than LIGHT. At the shipped rig it was about a fifth,
#     and 1.9x of a fifth is nothing.
#
# So this sweeps the rig's energy against the emission base and looks for the pair
# that puts a chip's idle luminance near a stock button's and its step near a stock
# button's, without bleaching the colour out at highlight.
#
# Both are changed at RUNTIME rather than by editing constants: the rig is nodes
# under `SkinLights`, and `_face_base` / `_ring_base` are the linear emission the
# board's state machine multiplies. Scaling those is exactly what changing
# BODY_EMISSION / RING_EMISSION does.
# Pass `check` as the second user argument to measure the SHIPPED values alone,
# which is what a re-tune is confirmed with.
const RIGS := [1.00, 0.50, 0.25]
const EMITS := [1.0, 2.0, 6.0, 20.0]
const CHECK_RIGS := [1.00]
const CHECK_EMITS := [1.0]

var _dev: MemoryGameUI
var _vp: SubViewport
var _dev_vp: SubViewport
var _cam: Camera3D
var _board: Node3D
var _rig0: Array[float] = []
var _face0: Array[Color] = []
var _ring0: Array[Color] = []
var _glow0: Array[Color] = []

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var which := String(args[0]) if args.size() > 0 else "hard"
	for _i in 10:
		await get_tree().process_frame

	# --- the reference: the stock board, untouched ---
	await _build(which, "default")
	print("\n=== STOCK BUTTONS (the step every player has learned) ===")
	await _measure("stock")
	_tear()
	await get_tree().process_frame

	await _build(which, CHIPS.THEME_ID)
	var rig := _dev._vp.get_node_or_null("SkinLights")
	_rig0.clear()
	if rig != null:
		for l in rig.get_children():
			_rig0.append((l as Light3D).light_energy)
	_face0.clear()
	_ring0.clear()
	_glow0.clear()
	for i in _dev._count:
		_face0.append(_dev._face_base[i])
		_ring0.append(_dev._ring_base[i])
		_glow0.append(_dev._glow_base[i])
	print("\n=== POKER CHIPS: rig energy x emission base ===")
	print("(shipped: rig 1.00, emission 1.00 — key %.2f, BODY_EMISSION %.2f)"
		% [(_rig0[0] if not _rig0.is_empty() else 0.0), CHIPS.BODY_EMISSION])
	var rigs: Array = CHECK_RIGS if args.has("check") else RIGS
	var emits: Array = CHECK_EMITS if args.has("check") else EMITS
	for r: float in rigs:
		for e: float in emits:
			if rig != null:
				for k in rig.get_child_count():
					(rig.get_child(k) as Light3D).light_energy = _rig0[k] * r
			for i in _dev._count:
				_dev._face_base[i] = _face0[i] * e
				_dev._ring_base[i] = _ring0[i] * e
				_dev._glow_base[i] = _glow0[i] * e
				_dev._apply_emission(i)
			await _measure("rig %.2f  emit %.1f" % [r, e])
	get_tree().quit()


func _build(which: String, theme: String) -> void:
	CoinsManager.selected_theme = theme
	_vp = SubViewport.new()
	_vp.size = Vector2i(SHOT_W, SHOT_H)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var bg := ColorRect.new()
	bg.color = BackgroundScenes.backdrop_color(theme).linear_to_srgb()
	bg.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(bg)
	match which:
		"easy": _dev = EasyGameUI.new()
		"medium": _dev = MemoryGameUI.new()
		_: _dev = HardGameUI.new()
	_dev.input_enabled = false
	_dev.size = Vector2(SHOT_W, SHOT_H)
	_vp.add_child(_dev)
	await get_tree().process_frame
	_dev.configure(_dev._count, [])
	for c in _dev.get_children():
		if c is SubViewportContainer:
			_dev_vp = (c as SubViewportContainer).get_child(0) as SubViewport
	for c in _dev_vp.get_children():
		if c is Camera3D:
			_cam = c
	_board = _dev.find_child("MemoryGame_UI", true, false) as Node3D
	await _settle(20)


func _tear() -> void:
	_vp.queue_free()


# One line per combination: the worst chip's step and the worst highlight saturation,
# which are the two numbers the choice is actually made on. A flash that whitens the
# button has taken away the thing the player is reading.
func _measure(label: String) -> void:
	for i in _dev._count:
		_dev.set_lit(i, false)
	await _settle(16)
	var idle := _read()
	var worst_step := 9.0
	var worst_sat := 9.0
	var lo_idle := 9.0
	var hi_idle := -9.0
	var detail := ""
	for i in _dev._count:
		for j in _dev._count:
			_dev.set_lit(j, j == i)
		await _settle(14)
		var hi := _read()
		var step: float = hi[i].get_luminance() - idle[i].get_luminance()
		worst_step = minf(worst_step, step)
		worst_sat = minf(worst_sat, hi[i].s)
		lo_idle = minf(lo_idle, idle[i].get_luminance())
		hi_idle = maxf(hi_idle, idle[i].get_luminance())
		detail += "      %-8s idle lum %.2f sat %.2f -> hi lum %.2f sat %.2f  STEP %+.3f\n" % [
			_dev._keys[i], idle[i].get_luminance(), idle[i].s,
			hi[i].get_luminance(), hi[i].s, step]
	for j in _dev._count:
		_dev.set_lit(j, false)
	print("  %-22s idle lum %.2f..%.2f   worst STEP %+.3f   worst hi sat %.2f"
		% [label, lo_idle, hi_idle, worst_step, worst_sat])
	print(detail.rstrip("\n"))


func _read() -> Array[Color]:
	var img := _vp.get_texture().get_image()
	var out: Array[Color] = []
	for key: String in _dev._keys:
		var holder := _board.find_child("Button_%s" % key, true, false) as Node3D
		out.append(_mean(img, _cam.unproject_position(
			holder.position + Vector3(0.0, 0.33, 0.0)), 20.0))
	return out


func _settle(n: int) -> void:
	_dev.set_process(true)
	if _dev_vp:
		_dev_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _i in n:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _mean(img: Image, p: Vector2, r: float) -> Color:
	var acc := Color(0, 0, 0)
	var n := 0
	for dy in range(int(-r), int(r) + 1):
		for dx in range(int(-r), int(r) + 1):
			if Vector2(dx, dy).length() > r:
				continue
			acc += img.get_pixel(clampi(int(p.x + dx), 0, SHOT_W - 1),
				clampi(int(p.y + dy), 0, SHOT_H - 1))
			n += 1
	return acc / maxf(1.0, float(n))
