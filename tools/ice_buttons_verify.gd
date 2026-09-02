extends Node
# Acceptance check for the ICE KINGDOM snowflake buttons (ice_buttons.gd and the
# _apply_button_skin path in memory_game_ui.gd), modelled on tools/hgui_verify.gd.
#
# Verifies the claims a screenshot cannot: that the seven assets are one
# manufactured button in seven colours, that each one lands on the stock button's
# exact contract (node names, origin, y range, two surfaces meaning the same two
# things), that the swap reaches every button on all THREE boards without
# disturbing the press clips or the hit areas, and that unequipping puts the
# stock board back vertex for vertex.
#
# Runs headless -- it inspects meshes and nodes and never needs a frame drawn:
#   Godot_..._console.exe --headless --path . tools/ice_buttons_verify.tscn

const ICE := preload("res://ice_buttons.gd")

# The stock button contract, measured off the shipping boards.
const SURF_Y := Vector2(0.245, 0.525)
const FRAME_Y0 := 0.0
const ARM_BOT := 0.275             # the flake's underside once clear of its hub
const HUB_R := 0.335               # ... and the radius that hub reaches
const FRAME_RADIUS := 1.0          # what the board reserves per button
const AREA_RADIUS := 1.12          # _add_button_area's cylinder
const AREA_Y := Vector2(-0.01, 0.61)
const PRESS := 0.115

var _fails := 0

func _ok(cond: bool, what: String, detail: String = "") -> void:
	if cond:
		print("  ok    %s" % what)
	else:
		_fails += 1
		print("  FAIL  %s%s" % [what, ("  [%s]" % detail) if detail != "" else ""])

func _radius(aabb: AABB) -> float:
	var p := aabb.position
	var e := aabb.end
	return maxf(maxf(absf(p.x), absf(e.x)), maxf(absf(p.z), absf(e.z)))

func _ready() -> void:
	print("\n=== Ice Kingdom snowflake buttons ===\n")
	_assets()
	await _boards()
	print("\n%s  (%d failure%s)\n" % ["PASS" if _fails == 0 else "FAIL",
			_fails, "" if _fails == 1 else "s"])
	get_tree().quit(1 if _fails > 0 else 0)

# --------------------------------------------------------------- the assets
func _assets() -> void:
	print("-- asset contract --")
	var shapes: Dictionary = {}
	for key: String in ICE.KEYS:
		var kit: Dictionary = ICE.build(key)
		if kit.is_empty():
			_ok(false, "%s loads" % key, "ice_buttons.build returned nothing")
			continue
		var s: Mesh = kit["surface"]
		var f: Mesh = kit["frame"]
		var sa := s.get_aabb()
		var fa := f.get_aabb()
		_ok(s.get_surface_count() == 2 and f.get_surface_count() == 2,
				"%s: two surfaces on each mesh" % key,
				"%d / %d" % [s.get_surface_count(), f.get_surface_count()])
		_ok(is_equal_approx(sa.position.y, SURF_Y.x) and is_equal_approx(sa.end.y, SURF_Y.y),
				"%s: flake occupies the stock y range" % key,
				"%.4f..%.4f" % [sa.position.y, sa.end.y])
		_ok(_radius(sa) <= FRAME_RADIUS + 0.0005,
				"%s: flake inside the reserved footprint" % key,
				"r %.4f" % _radius(sa))
		_ok(is_equal_approx(fa.position.y, FRAME_Y0),
				"%s: socket sits on the board" % key, "y0 %.4f" % fa.position.y)
		# Clearance is per-region, not global: outboard of the hub the flake's
		# underside is ARM_BOT, and under the hub itself it is SURF_Y.x -- which is
		# lower, and is why the socket's bowl is deeper than its collar.
		_ok(fa.end.y < ARM_BOT - PRESS,
				"%s: socket collar clears the pressed arms" % key,
				"%.4f vs %.4f" % [fa.end.y, ARM_BOT - PRESS])
		_ok(_max_y_within(f, HUB_R) < SURF_Y.x - PRESS,
				"%s: socket bowl clears the pressed hub" % key,
				"%.4f vs %.4f" % [_max_y_within(f, HUB_R), SURF_Y.x - PRESS])
		_ok(_radius(fa) < _radius(sa),
				"%s: socket is narrower than the flake it carries" % key,
				"%.4f vs %.4f" % [_radius(fa), _radius(sa)])
		# It has to fit the hit cylinder the board already hangs off the holder.
		# Only the flake travels; the socket is stationary, like the stock frame.
		_ok(_radius(sa) <= AREA_RADIUS and _radius(fa) <= AREA_RADIUS
				and sa.end.y <= AREA_Y.y and (sa.position.y - PRESS) >= AREA_Y.x
				and fa.position.y >= AREA_Y.x,
				"%s: inside the existing Area3D shape" % key,
				"flake %.3f..%.3f (pressed %.3f), r %.3f" % [
					sa.position.y, sa.end.y, sa.position.y - PRESS, _radius(sa)])
		# the two driven slots must both actually emit, or the state machine has
		# nothing to drive
		for pair: Array in [[s, 0, "face"], [s, 1, "rim"], [f, 1, "under-glow"]]:
			var m := (pair[0] as Mesh).surface_get_material(pair[1]) as StandardMaterial3D
			_ok(m != null and m.emission_enabled,
					"%s: %s slot emits" % [key, pair[2]],
					"material %s" % ("null" if m == null else m.resource_name))
		shapes[key] = [s.get_aabb(), _surf_verts(s), _surf_verts(f)]

	print("-- one button, seven colours --")
	var ref: Array = shapes.get(ICE.KEYS[0], [])
	for key: String in ICE.KEYS:
		if not shapes.has(key) or ref.is_empty():
			continue
		var got: Array = shapes[key]
		_ok(got[1] == ref[1] and got[2] == ref[2],
				"%s: same mesh as %s" % [key, ICE.KEYS[0]],
				"%s vs %s" % [str(got[1]) + "/" + str(got[2]), str(ref[1]) + "/" + str(ref[2])])
		_ok((got[0] as AABB).position.is_equal_approx((ref[0] as AABB).position)
				and (got[0] as AABB).size.is_equal_approx((ref[0] as AABB).size),
				"%s: same dimensions as %s" % [key, ICE.KEYS[0]])

# Highest point of `m` inside plan radius `r` -- the socket's profile is not flat,
# so a global AABB cannot answer "does the bowl clear the hub".
func _max_y_within(m: Mesh, r: float) -> float:
	var best := -1e9
	for i in m.get_surface_count():
		for v: Vector3 in (m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if Vector2(v.x, v.z).length() <= r:
				best = maxf(best, v.y)
	return best


func _surf_verts(m: Mesh) -> int:
	var n := 0
	for i in m.get_surface_count():
		n += (m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n

# ------------------------------------------------------- the live boards
func _boards() -> void:
	# Let CoinsManager finish loading the saved wallet first: it assigns
	# selected_theme during start-up and would otherwise overwrite the one this
	# test sets, which is exactly what made the FIRST board tested look broken.
	for _i in 8:
		await get_tree().process_frame
	var was := CoinsManager.selected_theme
	for spec: Array in [["Easy", EasyGameUI], ["Medium", MemoryGameUI], ["Hard", HardGameUI]]:
		print("-- %s board --" % spec[0])
		CoinsManager.selected_theme = ICE.THEME_ID
		_ok(ICE.active(), "Ice Kingdom reads as equipped")
		var dev: MemoryGameUI = (spec[1] as Script).new() if spec[1] is Script else spec[1].new()
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		add_child(vp)
		vp.add_child(dev)
		dev.size = Vector2(1920, 1080)
		await get_tree().process_frame
		dev.configure(0, [])
		var board: Node3D = dev._board
		var ap: AnimationPlayer = dev._ap
		var stock: Dictionary = {}
		print("   (skin on: %s, keys %s, board %s)" % [
				dev.button_skin_id() == ICE.THEME_ID, str(dev._keys), "null" if board == null else board.name])
		for key: String in dev._keys:
			var surf := board.find_child("Button_%s_Surface" % key, true, false) as MeshInstance3D
			var frame := board.find_child("Button_%s_Frame" % key, true, false) as MeshInstance3D
			var holder := board.find_child("Button_%s" % key, true, false) as Node3D
			var kit: Dictionary = ICE.build(key)
			_ok(surf.mesh == kit.get("surface"), "%s wears the ice flake" % key)
			_ok(frame.mesh == kit.get("frame"), "%s wears the ice socket" % key)
			_ok(ap != null and ap.has_animation("Press_%s" % key),
					"%s keeps its Press_ clip" % key)
			var hits := 0
			for c in holder.get_children():
				if c is Area3D:
					hits += 1
			_ok(hits == 1, "%s has exactly one hit area" % key, "%d" % hits)
		_ok(dev._face_mats.size() == dev._count and dev._ring_mats.size() == dev._count
				and dev._glow_mats.size() == dev._count,
				"the emission state machine bound all %d buttons" % dev._count)
		_ok(dev._areas.size() == dev._count, "all %d buttons are hit-testable" % dev._count)
		# and the cosmetic bezel is kept off a snowflake
		for key: String in dev._keys:
			var f := board.find_child("Button_%s_Frame" % key, true, false) as MeshInstance3D
			_ok(f.get_parent().get_node_or_null(ButtonFrames.INSTANCE_NAME) == null,
					"%s wears no circular bezel" % key)
			stock[key] = f.mesh

		# unequip: the stock board must come back
		CoinsManager.selected_theme = "default"
		dev._on_background_changed()
		var restored := true
		for key: String in dev._keys:
			var surf := board.find_child("Button_%s_Surface" % key, true, false) as MeshInstance3D
			if surf.mesh == ICE.build(key).get("surface"):
				restored = false
		_ok(restored, "unequipping restores the stock buttons")
		_ok(dev._areas.size() == dev._count, "hit areas survive the round trip",
				"%d" % dev._areas.size())
		var dup := 0
		for key: String in dev._keys:
			var holder := board.find_child("Button_%s" % key, true, false) as Node3D
			var n := 0
			for c in holder.get_children():
				if c is Area3D:
					n += 1
			if n != 1:
				dup += 1
		_ok(dup == 0, "no duplicate hit areas after the round trip", "%d holders" % dup)
		vp.queue_free()
		await get_tree().process_frame
	CoinsManager.selected_theme = was
