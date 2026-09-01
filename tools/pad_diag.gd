extends Node
# Diagnostic: what does Godot actually have after importing LilyPad_Purple.glb?
# Prints the mesh resource's own facts (surfaces, formats, LOD levels, blend
# shapes, material) and then renders the pad six ways at 900x900 so the artifact
# can be attributed rather than guessed at.
#
#   Godot_..._console.exe --path . tools/pad_diag.tscn
const SRC := "res://models/buttons/LilyPad_Purple.glb"
const N := 900

func _ready() -> void:
	for _i in 6: await get_tree().process_frame
	var ps: PackedScene = load(SRC)
	var root := ps.instantiate()
	var mi := _find(root)
	var mesh: ArrayMesh = mi.mesh
	print("\n=== imported mesh ===")
	print("  node        %s   transform %s" % [mi.name, str(mi.transform)])
	print("  surfaces    %d" % mesh.get_surface_count())
	print("  aabb        %s" % str(mesh.get_aabb()))
	for s in mesh.get_surface_count():
		var fmt := mesh.surface_get_format(s)
		var names := PackedStringArray()
		for pair: Array in [[Mesh.ARRAY_FORMAT_VERTEX, "VERTEX"], [Mesh.ARRAY_FORMAT_NORMAL, "NORMAL"],
				[Mesh.ARRAY_FORMAT_TANGENT, "TANGENT"], [Mesh.ARRAY_FORMAT_COLOR, "COLOR"],
				[Mesh.ARRAY_FORMAT_TEX_UV, "UV"], [Mesh.ARRAY_FORMAT_TEX_UV2, "UV2"],
				[Mesh.ARRAY_FORMAT_INDEX, "INDEX"]]:
			if fmt & int(pair[0]):
				names.append(String(pair[1]))
		print("  surf %d      verts %d  tris %d  [%s]" % [s,
			mesh.surface_get_array_len(s), mesh.surface_get_array_index_len(s) / 3,
			", ".join(names)])
		print("              compress flags 0x%X" % (fmt >> 24))
		# LOD levels are the thing an .import default quietly turns on.
		var arrays := mesh.surface_get_arrays(s)
		var blend := mesh.surface_get_blend_shape_arrays(s)
		print("              blend shapes %d" % blend.size())
		print("              %s" % _lod_info(mesh, s))
		var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var tan: Variant = arrays[Mesh.ARRAY_TANGENT]
		# Are the normals still the exported ones?
		var bad := 0
		for nv: Vector3 in nrm:
			if absf(nv.length() - 1.0) > 0.02:
				bad += 1
		print("              non-unit normals %d of %d" % [bad, nrm.size()])
		if tan != null:
			var t: PackedFloat32Array = tan
			var nan := 0
			for i in range(0, t.size(), 4):
				if is_nan(t[i]) or is_nan(t[i+1]) or is_nan(t[i+2]):
					nan += 1
				elif absf(Vector3(t[i], t[i+1], t[i+2]).length() - 1.0) > 0.05:
					nan += 1
			print("              broken tangents %d of %d" % [nan, t.size() / 4])
		var m := mesh.surface_get_material(s) as StandardMaterial3D
		if m != null:
			print("  material    albedo %s  metallic %.2f  rough %.2f" %
				[str(m.albedo_color), m.metallic, m.roughness])
			print("              vertex_color_as_albedo %s   srgb %s" %
				[m.vertex_color_use_as_albedo, m.vertex_color_is_srgb])
			print("              cull %s   shading %s   transparency %s" %
				[m.cull_mode, m.shading_mode, m.transparency])
			print("              emission %s  x%.2f  op %d" %
				[str(m.emission), m.emission_energy_multiplier, m.emission_operator])
	root.free()
	get_tree().quit()

func _lod_info(mesh: ArrayMesh, s: int) -> String:
	# The LOD chain the importer baked in comes back inside the surface dictionary
	# RenderingServer keeps; ArrayMesh does not expose it any other way.
	var d := RenderingServer.mesh_get_surface(mesh.get_rid(), s)
	var lods: Dictionary = d.get("lods", {})
	var keys: Array = lods.keys()
	keys.sort()
	return "%d extra LOD level(s), thresholds %s" % [lods.size(), str(keys)]

func _find(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D: return n
	for c in n.get_children():
		var f := _find(c)
		if f != null: return f
	return null
