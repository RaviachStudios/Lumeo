extends Node
# WHAT CAME OUT OF BLENDER — an audit of res://models/DealerHands.glb as Godot
# actually imported it, printed rather than guessed at.
#
# The asset (APP IDEAS/Simon/HandsForCasino/README.md) makes promises the engine
# side depends on: one skinned mesh with vertex colours and no textures, an armature
# whose AP_* points are exported, four named clips, and — the one Godot is most
# likely to break — the upper arms' POSITION tracks, which the importer strips if it
# judges them constant. Every one of those is asserted here, because each fails
# silently and looks like a bug somewhere else: no colours is a flat grey slab, no
# AP_ bones is a card thrown from the origin, no position track is a deal with no
# reach in it.
#
#   Godot_..._console.exe --path . tools/dealer_probe.tscn
#
# Needs no GPU and prints the numbers casino_dealer.gd is written against.

const GLB := "res://models/DealerHands.glb"
const WANT_CLIPS := ["IDLE", "DEAL_CARD", "DEAL_CARD_QUICK", "ROYAL_FLUSH_CELEBRATION"]
const WANT_AP := ["AP_CardHold.R", "AP_CardFwd.R", "AP_CardUp.R", "AP_Release.R",
	"AP_Deck.L", "AP_Pickup.L"]

var _fails := 0


func _ok(cond: bool, what: String, detail: String = "") -> void:
	if not cond:
		_fails += 1
	print("  [%s] %s%s" % ["PASS" if cond else "FAIL", what,
		("  -- " + detail) if detail != "" else ""])


func _ready() -> void:
	print("\n=== DealerHands.glb ===\n")
	var packed := load(GLB) as PackedScene
	_ok(packed != null, "the asset is in the project and imports")
	if packed == null:
		get_tree().quit(1)
		return
	var root := packed.instantiate()
	add_child(root)
	print("-- tree --")
	_dump(root, 0)

	var skel := _find(root, "Skeleton3D") as Skeleton3D
	var mesh := _find(root, "MeshInstance3D") as MeshInstance3D
	var ap := _find(root, "AnimationPlayer") as AnimationPlayer
	print("\n-- the pieces --")
	_ok(skel != null, "an armature came through")
	_ok(mesh != null, "...and a mesh")
	_ok(ap != null, "...and an AnimationPlayer")
	if skel == null or mesh == null or ap == null:
		_finish()
		return

	# ---- the mesh -------------------------------------------------------
	print("\n-- the mesh --")
	var am := mesh.mesh
	var tris := 0
	for s in am.get_surface_count():
		tris += am.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	_ok(am.get_surface_count() == 1, "ONE surface, so one draw call",
		"%d" % am.get_surface_count())
	print("   %d triangles, aabb %s" % [tris, str(am.get_aabb())])
	var arrays := am.surface_get_arrays(0)
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	# THE WHOLE LOOK IS IN THE VERTEX COLOURS and there is no fallback: rgb is the
	# tint and ALPHA is the material id the table's shader picks a response from.
	# The exporter drops the attribute if it is not the mesh's active one, and the
	# hands import as a flat slab.
	_ok(cols.size() > 0, "the vertex colours survived the export",
		"%d" % cols.size())
	if cols.size() > 0:
		var ids: Dictionary = {}
		for c: Color in cols:
			ids[snappedf(c.a, 0.25)] = true
		var keys: Array = ids.keys()
		keys.sort()
		_ok(keys.size() >= 3, "...carrying at least skin, cloth and metal in ALPHA",
			str(keys))
	_ok(arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_WEIGHTS] != null,
		"the mesh is skinned")
	var mat := am.surface_get_material(0)
	print("   material: %s" % ("none" if mat == null else mat.get_class()))

	# ---- the rig --------------------------------------------------------
	print("\n-- the rig --")
	print("   %d bones" % skel.get_bone_count())
	var names: Dictionary = {}
	for i in skel.get_bone_count():
		names[skel.get_bone_name(i)] = i
	for nm: String in WANT_AP:
		_ok(names.has(nm), "attachment point %s" % nm)
	for nm: String in ["upperarm.L", "upperarm.R", "forearm.L", "forearm.R",
			"hand.L", "hand.R"]:
		_ok(names.has(nm), "bone %s" % nm)
	if names.has("AP_CardHold.R"):
		var i: int = names["AP_CardHold.R"]
		print("   AP_CardHold.R rest %s" % str(skel.get_bone_global_rest(i).origin))

	# ---- the clips ------------------------------------------------------
	print("\n-- the clips --")
	var lib := ap.get_animation_library(ap.get_animation_library_list()[0])
	for nm: String in WANT_CLIPS:
		var got := lib.has_animation(nm)
		_ok(got, "clip %s" % nm)
		if got:
			var a := lib.get_animation(nm)
			print("     %.3f s, %d tracks, loop %d"
				% [a.length, a.get_track_count(), a.loop_mode])
	# THE ONE GODOT BREAKS. `animation/remove_immutable_tracks` throws away channels
	# it judges constant, and the reach in the deal is the upper arm TRANSLATING —
	# lose it and the dealer mimes the throw without going anywhere.
	if lib.has_animation("DEAL_CARD"):
		var deal := lib.get_animation("DEAL_CARD")
		var moved := false
		for t in deal.get_track_count():
			var path := String(deal.track_get_path(t))
			if deal.track_get_type(t) == Animation.TYPE_POSITION_3D \
					and path.ends_with(":upperarm.R"):
				var a0 := deal.position_track_interpolate(t, 0.0)
				var a1 := deal.position_track_interpolate(t, deal.length * 0.45)
				moved = a0.distance_to(a1) > 0.0005
		_ok(moved, "DEAL_CARD still translates upperarm.R (the reach)",
			"set animation/remove_immutable_tracks=false if this fails")

	# ---- what the engine reads off the clips ---------------------------
	# The numbers casino_dealer.gd is written against, in ASSET units (one unit is
	# one hand length, the felt is y = 0). Printed rather than assumed: the release
	# point's height decides whether a card leaves the fingers above the chips, and
	# the lowest bone in each clip decides where the whole rig can be stood.
	print("\n-- poses, in hand lengths off the felt --")
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var lib_name := ap.get_animation_library_list()[0]
	for probe: Array in [["IDLE", 0.0], ["DEAL_CARD", 0.5909],
			["DEAL_CARD_QUICK", 0.5714], ["ROYAL_FLUSH_CELEBRATION", 0.5]]:
		var nm: String = probe[0]
		if not lib.has_animation(nm):
			continue
		var frac: float = probe[1]
		var alen := lib.get_animation(nm).length
		ap.play(("%s/%s" % [lib_name, nm]) if lib_name != "" else nm)
		ap.seek(alen * frac, true)
		var low := 1e9
		var low_bone := ""
		for i in skel.get_bone_count():
			var o := skel.get_bone_global_pose(i).origin
			if o.y < low:
				low = o.y
				low_bone = skel.get_bone_name(i)
		print("   %-24s t=%.3f  hand.L %s  hand.R %s" % [nm, alen * frac,
			_v(skel, names, "hand.L"), _v(skel, names, "hand.R")])
		print("       hold %s  release %s  deck %s  lowest %s at %.3f"
			% [_v(skel, names, "AP_CardHold.R"), _v(skel, names, "AP_Release.R"),
			_v(skel, names, "AP_Deck.L"), low_bone, low])

	# ---- the pickup is real ---------------------------------------------
	# THE ONE THING THE DEAL HAS TO CONTAIN. The right hand must close on the deck's
	# top card, not near it: the game hands the card over on this exact frame, so a
	# clip whose pinch never arrives is a card that changes hands in mid-air. The
	# card is pushed half out of the deck first (the deck thumb's shove), which is
	# why this is held to under a card's length rather than to zero.
	if lib.has_animation("DEAL_CARD_QUICK"):
		var qa := lib.get_animation("DEAL_CARD_QUICK")
		ap.play(("%s/%s" % [lib_name, "DEAL_CARD_QUICK"]) if lib_name != ""
			else "DEAL_CARD_QUICK")
		var best := 1e9
		var best_t := 0.0
		var clear := 1e9
		for i in 121:
			var t := qa.length * float(i) / 120.0
			ap.seek(t, true)
			var d: float = skel.get_bone_global_pose(int(names["AP_CardHold.R"])).origin 				.distance_to(skel.get_bone_global_pose(int(names["AP_Pickup.L"])).origin)
			if d < best:
				best = d
				best_t = t
			# ...and the hands may not pass through each other while doing it
			for a: String in ["f_index.03.R", "f_middle.03.R", "thumb.03.R"]:
				for b: String in ["f_index.03.L", "f_middle.03.L", "hand.L"]:
					if names.has(a) and names.has(b):
						clear = minf(clear, skel.get_bone_global_pose(int(names[a])).origin
							.distance_to(skel.get_bone_global_pose(int(names[b])).origin))
		_ok(best < 0.48, "the pinch reaches the deck's top card",
			"%.3f hand lengths at t=%.3f, a card is 0.48" % [best, best_t])
		_ok(clear > 0.10, "...without the two hands passing through each other",
			"%.3f apart at the closest" % clear)
	_finish()


func _v(skel: Skeleton3D, names: Dictionary, nm: String) -> String:
	if not names.has(nm):
		return "-"
	var o: Vector3 = skel.get_bone_global_pose(int(names[nm])).origin
	return "(%.2f,%.2f,%.2f)" % [o.x, o.y, o.z]


func _finish() -> void:
	print("\n%s  (%d failure%s)\n" % ["PASS" if _fails == 0 else "FAIL", _fails,
		"" if _fails == 1 else "s"])
	get_tree().quit(1 if _fails > 0 else 0)


func _dump(n: Node, depth: int) -> void:
	print("   %s%s [%s]" % ["  ".repeat(depth), n.name, n.get_class()])
	for c in n.get_children():
		_dump(c, depth + 1)


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null
