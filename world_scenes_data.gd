# GENERATED - do not hand-edit. Regenerate with:
#     blender -b Themes2.blend -P tools/dump_world_truth.py -- tools/lume_world_truth.json
#     python3 tools/gen_world_data.py tools/lume_world_truth.json world_scenes_data.gd
#
# The Blender ground truth for the LUME WORLDS (Themes2.blend). Two things in
# these scenes cannot survive a glTF round trip, and both are here:
#
#   * Every material multiplies a "Col" vertex attribute into Base Color AND, where
#     the surface glows, into Emission Color. glTF's COLOR_0 only ever multiplies
#     BASE colour, so the .glb keeps the emissive factor as a flat constant and the
#     whole per-vertex shape of every sky, nebula, mist card and light shaft is
#     lost. `vc_emis` is what puts it back.
#   * The AREA lights. glTF has point / spot / directional and nothing else, so the
#     panels that shape every render — plus the six shared LUME presentation
#     panels each theme re-tints and re-scales — export as empty nodes.
#
# All colours are LINEAR (Blender's working space), never sRGB. All positions and
# bases are already in GODOT space: Blender is Z-up, Godot Y-up, (x, y, z) -> (x, z, -y).
extends RefCounted
class_name WorldScenesData

# Per-material Principled values.
#   base / emis    linear colour; `vc_*` says the "Col" attribute multiplies it
#   emis_strength  Blender's Emission Strength (already folded through nothing —
#                  world_scenes.gd applies the exposure match itself)
#   vc_alpha       Alpha is driven by the attribute's own alpha channel
#   blend          real alpha blending; the rest are Blender's dithered mode,
#                  which at alpha 1.0 is indistinguishable from opaque
const MATERIALS := {
	"ICE_M_Castle": {
		"base": Color(0.229725, 0.396798, 0.689176), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.274194, 0.548387, 1.000000), "emis_strength": 3.107557, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.5000, "ior": 1.4500},
	"ICE_M_Crack": {
		"base": Color(0.010000, 0.030000, 0.060000), "base_a": 1.0000, "vc_base": false,
		"emis": Color(0.160000, 0.580000, 1.000000), "emis_strength": 2.200000, "vc_emis": false,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.1500, "specular": 0.5000, "ior": 1.4500},
	"ICE_M_Crystal": {
		"base": Color(0.146935, 0.641170, 1.000000), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.142857, 0.571429, 1.000000), "emis_strength": 2.337598, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.0600, "specular": 0.5000, "ior": 1.3300},
	"ICE_M_CrystalCore": {
		"base": Color(0.000000, 0.000000, 0.000000), "base_a": 1.0000, "vc_base": false,
		"emis": Color(0.400000, 0.860000, 1.000000), "emis_strength": 5.000000, "vc_emis": false,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.5000, "specular": 0.5000, "ior": 1.4500},
	"ICE_M_Deck": {
		"base": Color(0.153391, 0.357912, 0.620867), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.000000, 0.000000, 0.000000), "emis_strength": 0.000000, "vc_emis": false,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.1450, "specular": 0.7200, "ior": 1.3600},
	"ICE_M_Far": {
		"base": Color(0.228250, 0.370906, 0.599155), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.342374, 0.542093, 0.884467), "emis_strength": 1.700000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.5000, "ior": 1.4500},
	"ICE_M_Icicle": {
		"base": Color(0.060000, 0.240000, 0.460000), "base_a": 1.0000, "vc_base": false,
		"emis": Color(0.140000, 0.420000, 0.740000), "emis_strength": 0.900000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.0600, "specular": 0.5000, "ior": 1.3100},
	"ICE_M_Mid": {
		"base": Color(0.222092, 0.364866, 0.602821), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.206228, 0.396593, 0.761458), "emis_strength": 1.400000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.5000, "ior": 1.4500},
	"ICE_M_Mist": {
		"base": Color(0.000000, 0.000000, 0.000000), "base_a": 1.0000, "vc_base": true,
		"emis": Color(1.000000, 1.000000, 1.000000), "emis_strength": 1.000000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": true, "blend": true,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.0000, "ior": 1.5000},
	"ICE_M_NearCliff": {
		"base": Color(0.103758, 0.161401, 0.265159), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.025363, 0.051879, 0.097994), "emis_strength": 1.000000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.5000, "ior": 1.4500},
	"ICE_M_Rim": {
		"base": Color(0.109565, 0.226434, 0.383477), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.000000, 0.000000, 0.000000), "emis_strength": 0.000000, "vc_emis": false,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.2200, "specular": 0.5000, "ior": 1.4500},
	"ICE_M_Rock": {
		"base": Color(0.065739, 0.109565, 0.182608), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.000000, 0.000000, 0.000000), "emis_strength": 0.000000, "vc_emis": false,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.7200, "specular": 0.5000, "ior": 1.4500},
	"ICE_M_Sky": {
		"base": Color(0.000000, 0.000000, 0.000000), "base_a": 1.0000, "vc_base": true,
		"emis": Color(1.000000, 1.000000, 1.000000), "emis_strength": 1.000000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": true, "blend": true,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.0000, "ior": 1.5000},
	"ICE_M_SnowParticle": {
		"base": Color(0.000000, 0.000000, 0.000000), "base_a": 1.0000, "vc_base": true,
		"emis": Color(1.000000, 1.000000, 1.000000), "emis_strength": 2.200000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": true, "blend": true,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.0000, "ior": 1.5000},
	"ICE_M_Sparkle": {
		"base": Color(0.000000, 0.000000, 0.000000), "base_a": 1.0000, "vc_base": true,
		"emis": Color(1.000000, 1.000000, 1.000000), "emis_strength": 6.000000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": true, "blend": true,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.0000, "ior": 1.5000},
	"FOREST_M_Bark": {
		"base": Color(0.247084, 0.183548, 0.122366), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.000000, 0.000000, 0.000000), "emis_strength": 0.000000, "vc_emis": false,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.8600, "specular": 0.5000, "ior": 1.4500},
	"FOREST_M_Biolum": {
		"base": Color(0.052000, 0.156000, 0.182000), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.130435, 0.815217, 1.000000), "emis_strength": 1.913600, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.5000, "specular": 0.5000, "ior": 1.4500},
	"FOREST_M_FarTree": {
		"base": Color(0.000000, 0.000000, 0.000000), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.178696, 0.285913, 0.160826), "emis_strength": 1.200000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.5000, "ior": 1.4500},
	"FOREST_M_Firefly": {
		"base": Color(0.000000, 0.000000, 0.000000), "base_a": 1.0000, "vc_base": true,
		"emis": Color(1.000000, 1.000000, 1.000000), "emis_strength": 7.000000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": true, "blend": true,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.0000, "ior": 1.5000},
	"FOREST_M_Flower": {
		"base": Color(0.490000, 0.420000, 0.770000), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.448000, 0.364000, 0.924000), "emis_strength": 0.550000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.6000, "specular": 0.5000, "ior": 1.4500},
	"FOREST_M_Leaf": {
		"base": Color(0.148381, 0.336330, 0.108813), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.158273, 0.395682, 0.118705), "emis_strength": 0.550000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.7200, "specular": 0.5000, "ior": 1.4500},
	"FOREST_M_MidTree": {
		"base": Color(0.000000, 0.000000, 0.000000), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.080069, 0.136117, 0.080069), "emis_strength": 1.100000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.5000, "ior": 1.4500},
	"FOREST_M_Mist": {
		"base": Color(0.000000, 0.000000, 0.000000), "base_a": 1.0000, "vc_base": true,
		"emis": Color(1.000000, 1.000000, 1.000000), "emis_strength": 1.000000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": true, "blend": true,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.0000, "ior": 1.5000},
	"FOREST_M_Moss": {
		"base": Color(0.122945, 0.254086, 0.078685), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.000000, 0.000000, 0.000000), "emis_strength": 0.000000, "vc_emis": false,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.8500, "specular": 0.5000, "ior": 1.4500},
	"FOREST_M_Mushroom": {
		"base": Color(0.243600, 0.639450, 0.639450), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.211765, 1.000000, 0.941176), "emis_strength": 1.100006, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.5500, "specular": 0.5000, "ior": 1.4500},
	"FOREST_M_Pollen": {
		"base": Color(0.000000, 0.000000, 0.000000), "base_a": 1.0000, "vc_base": true,
		"emis": Color(1.000000, 1.000000, 1.000000), "emis_strength": 2.200000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": true, "blend": true,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.0000, "ior": 1.5000},
	"FOREST_M_RimStone": {
		"base": Color(0.305339, 0.289269, 0.218559), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.000000, 0.000000, 0.000000), "emis_strength": 0.000000, "vc_emis": false,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.8000, "specular": 0.5000, "ior": 1.4500},
	"FOREST_M_Root": {
		"base": Color(0.262314, 0.196165, 0.127735), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.000000, 0.000000, 0.000000), "emis_strength": 0.000000, "vc_emis": false,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.8400, "specular": 0.5000, "ior": 1.4500},
	"FOREST_M_Shaft": {
		"base": Color(0.000000, 0.000000, 0.000000), "base_a": 1.0000, "vc_base": true,
		"emis": Color(1.000000, 1.000000, 1.000000), "emis_strength": 1.500000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": true, "blend": true,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.0000, "ior": 1.5000},
	"FOREST_M_Sky": {
		"base": Color(0.000000, 0.000000, 0.000000), "base_a": 1.0000, "vc_base": true,
		"emis": Color(1.000000, 1.000000, 1.000000), "emis_strength": 1.000000, "vc_emis": true,
		"alpha": 1.0000, "vc_alpha": true, "blend": true,
		"metallic": 0.0000, "roughness": 1.0000, "specular": 0.0000, "ior": 1.5000},
	"FOREST_M_Soil": {
		"base": Color(0.144634, 0.102851, 0.064282), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.000000, 0.000000, 0.000000), "emis_strength": 0.000000, "vc_emis": false,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.9000, "specular": 0.5000, "ior": 1.4500},
	"FOREST_M_Stone": {
		"base": Color(0.369621, 0.347123, 0.263556), "base_a": 1.0000, "vc_base": true,
		"emis": Color(0.000000, 0.000000, 0.000000), "emis_strength": 0.000000, "vc_emis": false,
		"alpha": 1.0000, "vc_alpha": false, "blend": false,
		"metallic": 0.0000, "roughness": 0.7200, "specular": 0.5000, "ior": 1.4500},
}

# Every light that shapes a world, in Godot space. The first block of each list
# is the world's own rig; entries marked `shared` are the six LUME presentation
# panels at the multiplier and tint this theme scales them to (see the .blend's
# `lume_lights` / `activate_theme`) — untouched originals that only this theme's
# activation re-weights, which is why they are captured per world rather than once.
const LIGHTS := {
	"Ice": [
		{"name": "ICE_Light_Moon", "type": "SUN", "energy": 2.6000, "shared": false,
			"color": Color(0.60000, 0.76000, 1.00000), "size": 0.0000, "size_y": 0.0000, "radius": 0.0000,
			"origin": Vector3(-11.00000, 14.00000, -16.00000),
			"basis": Basis(Vector3(-0.803100, 0.000000, 0.595850), Vector3(0.349860, 0.809460, 0.471550), Vector3(-0.482320, 0.587170, -0.650080))},
		{"name": "ICE_Light_Sheen", "type": "AREA", "energy": 340.0000, "shared": false,
			"color": Color(0.66000, 0.82000, 1.00000), "size": 13.0000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(-2.60000, 5.60000, -8.50000),
			"basis": Basis(Vector3(-0.947540, 0.000000, 0.319650), Vector3(0.171080, 0.844720, 0.507130), Vector3(-0.270020, 0.535210, -0.800400))},
		{"name": "ICE_Light_Rim", "type": "AREA", "energy": 150.0000, "shared": false,
			"color": Color(0.34000, 0.62000, 1.00000), "size": 8.0000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(3.50000, 2.40000, -7.00000),
			"basis": Basis(Vector3(-0.877370, -0.000000, -0.479810), Vector3(-0.141420, 0.955580, 0.258600), Vector3(0.458500, 0.294750, -0.838390))},
		{"name": "ICE_Light_Fill", "type": "AREA", "energy": 42.0000, "shared": false,
			"color": Color(0.42000, 0.60000, 0.95000), "size": 12.0000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(0.00000, 3.40000, 6.50000),
			"basis": Basis(Vector3(1.000000, 0.000000, -0.000000), Vector3(0.000000, 0.876220, -0.481920), Vector3(0.000000, 0.481920, 0.876220))},
		{"name": "ICE_Light_Xtal_L", "type": "POINT", "energy": 70.0000, "shared": false,
			"color": Color(0.20000, 0.62000, 1.00000), "size": 0.0000, "size_y": 0.0000, "radius": 0.5500,
			"origin": Vector3(-3.75000, 1.30000, -0.30000),
			"basis": Basis(Vector3(1.000000, 0.000000, -0.000000), Vector3(0.000000, 0.000000, -1.000000), Vector3(0.000000, 1.000000, -0.000000))},
		{"name": "ICE_Light_Xtal_R", "type": "POINT", "energy": 70.0000, "shared": false,
			"color": Color(0.20000, 0.62000, 1.00000), "size": 0.0000, "size_y": 0.0000, "radius": 0.5500,
			"origin": Vector3(3.85000, 1.30000, -0.10000),
			"basis": Basis(Vector3(1.000000, 0.000000, -0.000000), Vector3(0.000000, 0.000000, -1.000000), Vector3(0.000000, 1.000000, -0.000000))},
		{"name": "ICE_Light_Xtal_LB", "type": "POINT", "energy": 40.0000, "shared": false,
			"color": Color(0.20000, 0.62000, 1.00000), "size": 0.0000, "size_y": 0.0000, "radius": 0.5500,
			"origin": Vector3(-3.05000, 1.30000, -1.75000),
			"basis": Basis(Vector3(1.000000, 0.000000, -0.000000), Vector3(0.000000, 0.000000, -1.000000), Vector3(0.000000, 1.000000, -0.000000))},
		{"name": "ICE_Light_Xtal_RB", "type": "POINT", "energy": 40.0000, "shared": false,
			"color": Color(0.20000, 0.62000, 1.00000), "size": 0.0000, "size_y": 0.0000, "radius": 0.5500,
			"origin": Vector3(3.00000, 1.30000, -1.70000),
			"basis": Basis(Vector3(1.000000, 0.000000, -0.000000), Vector3(0.000000, 0.000000, -1.000000), Vector3(0.000000, 1.000000, -0.000000))},
		{"name": "Key_Light", "type": "AREA", "energy": 49.5000, "shared": true,
			"color": Color(0.58000, 0.75000, 1.00000), "size": 5.0000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(-3.40000, 4.60000, 3.00000),
			"basis": Basis(Vector3(0.682320, -0.000000, 0.731060), Vector3(0.537420, 0.677920, -0.501600), Vector3(-0.495600, 0.735140, 0.462560))},
		{"name": "Rim_Light", "type": "AREA", "energy": 84.0000, "shared": true,
			"color": Color(0.58000, 0.75000, 1.00000), "size": 4.5000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(2.80000, 5.40000, -6.00000),
			"basis": Basis(Vector3(-0.894430, 0.000000, -0.447210), Vector3(-0.296540, 0.748550, 0.593080), Vector3(0.334760, 0.663080, -0.669520))},
		{"name": "Fill_Light", "type": "AREA", "energy": 8.8000, "shared": true,
			"color": Color(0.58000, 0.75000, 1.00000), "size": 4.0000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(4.60000, 1.70000, 2.20000),
			"basis": Basis(Vector3(0.420460, -0.000000, -0.907310), Vector3(-0.289260, 0.947820, -0.134050), Vector3(0.859960, 0.318820, 0.398520))},
		{"name": "Top_Soft", "type": "AREA", "energy": 6.7600, "shared": true,
			"color": Color(0.58000, 0.75000, 1.00000), "size": 14.0000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(0.00000, 6.20000, -0.20000),
			"basis": Basis(Vector3(-1.000000, -0.000000, -0.000000), Vector3(-0.000000, 0.016530, 0.999860), Vector3(0.000000, 0.999860, -0.016530))},
		{"name": "Rim_Light_B", "type": "AREA", "energy": 64.6000, "shared": true,
			"color": Color(0.58000, 0.75000, 1.00000), "size": 7.0000, "size_y": 1.4000, "radius": 0.0000,
			"origin": Vector3(-4.60000, 4.60000, -5.40000),
			"basis": Basis(Vector3(-0.751630, -0.000000, 0.659590), Vector3(0.367840, 0.830050, 0.419170), Vector3(-0.547500, 0.557680, -0.623890))},
		{"name": "Reflector_Front", "type": "AREA", "energy": 18.9000, "shared": true,
			"color": Color(0.58000, 0.75000, 1.00000), "size": 11.0000, "size_y": 3.0000, "radius": 0.0000,
			"origin": Vector3(0.00000, 6.00000, 6.40000),
			"basis": Basis(Vector3(1.000000, 0.000000, -0.000000), Vector3(0.000000, 0.725890, -0.687810), Vector3(0.000000, 0.687810, 0.725890))},
		{"name": "Reflector_Back", "type": "AREA", "energy": 36.0000, "shared": true,
			"color": Color(0.58000, 0.75000, 1.00000), "size": 11.0000, "size_y": 3.0000, "radius": 0.0000,
			"origin": Vector3(0.00000, 7.20000, -5.60000),
			"basis": Basis(Vector3(-1.000000, -0.000000, -0.000000), Vector3(-0.000000, 0.581240, 0.813730), Vector3(0.000000, 0.813730, -0.581240))},
	],
	"Forest": [
		{"name": "FOREST_Light_Sun", "type": "SUN", "energy": 2.4000, "shared": false,
			"color": Color(1.00000, 0.90000, 0.62000), "size": 0.0000, "size_y": 0.0000, "radius": 0.0000,
			"origin": Vector3(-9.00000, 14.00000, -16.00000),
			"basis": Basis(Vector3(-0.852600, 0.000000, 0.522560), Vector3(0.318840, 0.792290, 0.520210), Vector3(-0.414020, 0.610140, -0.675510))},
		{"name": "FOREST_Light_Shaft", "type": "AREA", "energy": 380.0000, "shared": false,
			"color": Color(1.00000, 0.92000, 0.58000), "size": 9.0000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(-3.00000, 6.00000, -8.00000),
			"basis": Basis(Vector3(-0.931780, -0.000000, 0.363030), Vector3(0.210940, 0.813860, 0.541420), Vector3(-0.295460, 0.581060, -0.758340))},
		{"name": "FOREST_Light_Rim", "type": "AREA", "energy": 190.0000, "shared": false,
			"color": Color(0.55000, 1.00000, 0.72000), "size": 8.0000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(4.20000, 2.40000, -7.20000),
			"basis": Basis(Vector3(-0.843660, 0.000000, -0.536880), Vector3(-0.148400, 0.961040, 0.233190), Vector3(0.515960, 0.276410, -0.810790))},
		{"name": "FOREST_Light_Fill", "type": "AREA", "energy": 45.0000, "shared": false,
			"color": Color(0.52000, 0.78000, 0.62000), "size": 12.0000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(0.00000, 3.20000, 6.50000),
			"basis": Basis(Vector3(1.000000, 0.000000, -0.000000), Vector3(0.000000, 0.894430, -0.447210), Vector3(0.000000, 0.447210, 0.894430))},
		{"name": "FOREST_Light_Deep", "type": "AREA", "energy": 260.0000, "shared": false,
			"color": Color(0.30000, 0.85000, 0.72000), "size": 26.0000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(0.00000, -8.00000, -24.00000),
			"basis": Basis(Vector3(1.000000, 0.000000, -0.000000), Vector3(0.000000, 0.951060, -0.309020), Vector3(0.000000, 0.309020, 0.951060))},
		{"name": "FOREST_Light_Mush_L", "type": "POINT", "energy": 14.0000, "shared": false,
			"color": Color(0.24000, 0.95000, 0.88000), "size": 0.0000, "size_y": 0.0000, "radius": 0.5000,
			"origin": Vector3(-3.60000, 0.45000, -0.60000),
			"basis": Basis(Vector3(1.000000, 0.000000, -0.000000), Vector3(0.000000, 0.000000, -1.000000), Vector3(0.000000, 1.000000, -0.000000))},
		{"name": "FOREST_Light_Mush_R", "type": "POINT", "energy": 14.0000, "shared": false,
			"color": Color(0.24000, 0.95000, 0.88000), "size": 0.0000, "size_y": 0.0000, "radius": 0.5000,
			"origin": Vector3(3.70000, 0.45000, -0.50000),
			"basis": Basis(Vector3(1.000000, 0.000000, -0.000000), Vector3(0.000000, 0.000000, -1.000000), Vector3(0.000000, 1.000000, -0.000000))},
		{"name": "FOREST_Light_Mush_LB", "type": "POINT", "energy": 14.0000, "shared": false,
			"color": Color(0.24000, 0.95000, 0.88000), "size": 0.0000, "size_y": 0.0000, "radius": 0.5000,
			"origin": Vector3(-3.00000, 0.45000, -2.40000),
			"basis": Basis(Vector3(1.000000, 0.000000, -0.000000), Vector3(0.000000, 0.000000, -1.000000), Vector3(0.000000, 1.000000, -0.000000))},
		{"name": "FOREST_Light_Mush_RB", "type": "POINT", "energy": 14.0000, "shared": false,
			"color": Color(0.24000, 0.95000, 0.88000), "size": 0.0000, "size_y": 0.0000, "radius": 0.5000,
			"origin": Vector3(3.00000, 0.45000, -2.40000),
			"basis": Basis(Vector3(1.000000, 0.000000, -0.000000), Vector3(0.000000, 0.000000, -1.000000), Vector3(0.000000, 1.000000, -0.000000))},
		{"name": "FOREST_Light_Back", "type": "AREA", "energy": 240.0000, "shared": false,
			"color": Color(0.95000, 1.00000, 0.62000), "size": 12.0000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(-1.50000, 3.20000, -9.00000),
			"basis": Basis(Vector3(-0.982870, 0.000000, 0.184290), Vector3(0.056080, 0.952580, 0.299070), Vector3(-0.175550, 0.304290, -0.936270))},
		{"name": "Key_Light", "type": "AREA", "energy": 56.1000, "shared": true,
			"color": Color(0.92000, 1.00000, 0.80000), "size": 5.0000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(-3.40000, 4.60000, 3.00000),
			"basis": Basis(Vector3(0.682320, -0.000000, 0.731060), Vector3(0.537420, 0.677920, -0.501600), Vector3(-0.495600, 0.735140, 0.462560))},
		{"name": "Rim_Light", "type": "AREA", "energy": 71.4000, "shared": true,
			"color": Color(0.92000, 1.00000, 0.80000), "size": 4.5000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(2.80000, 5.40000, -6.00000),
			"basis": Basis(Vector3(-0.894430, 0.000000, -0.447210), Vector3(-0.296540, 0.748550, 0.593080), Vector3(0.334760, 0.663080, -0.669520))},
		{"name": "Fill_Light", "type": "AREA", "energy": 9.9000, "shared": true,
			"color": Color(0.92000, 1.00000, 0.80000), "size": 4.0000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(4.60000, 1.70000, 2.20000),
			"basis": Basis(Vector3(0.420460, -0.000000, -0.907310), Vector3(-0.289260, 0.947820, -0.134050), Vector3(0.859960, 0.318820, 0.398520))},
		{"name": "Top_Soft", "type": "AREA", "energy": 6.7600, "shared": true,
			"color": Color(0.92000, 1.00000, 0.80000), "size": 14.0000, "size_y": 0.2500, "radius": 0.0000,
			"origin": Vector3(0.00000, 6.20000, -0.20000),
			"basis": Basis(Vector3(-1.000000, -0.000000, -0.000000), Vector3(-0.000000, 0.016530, 0.999860), Vector3(0.000000, 0.999860, -0.016530))},
		{"name": "Rim_Light_B", "type": "AREA", "energy": 54.4000, "shared": true,
			"color": Color(0.92000, 1.00000, 0.80000), "size": 7.0000, "size_y": 1.4000, "radius": 0.0000,
			"origin": Vector3(-4.60000, 4.60000, -5.40000),
			"basis": Basis(Vector3(-0.751630, -0.000000, 0.659590), Vector3(0.367840, 0.830050, 0.419170), Vector3(-0.547500, 0.557680, -0.623890))},
		{"name": "Reflector_Front", "type": "AREA", "energy": 21.0000, "shared": true,
			"color": Color(0.92000, 1.00000, 0.80000), "size": 11.0000, "size_y": 3.0000, "radius": 0.0000,
			"origin": Vector3(0.00000, 6.00000, 6.40000),
			"basis": Basis(Vector3(1.000000, 0.000000, -0.000000), Vector3(0.000000, 0.725890, -0.687810), Vector3(0.000000, 0.687810, 0.725890))},
		{"name": "Reflector_Back", "type": "AREA", "energy": 36.0000, "shared": true,
			"color": Color(0.92000, 1.00000, 0.80000), "size": 11.0000, "size_y": 3.0000, "radius": 0.0000,
			"origin": Vector3(0.00000, 7.20000, -5.60000),
			"basis": Basis(Vector3(-1.000000, -0.000000, -0.000000), Vector3(-0.000000, 0.581240, 0.813730), Vector3(0.000000, 0.813730, -0.581240))},
	],
}

# Mesh objects per world, with the material in each slot, in the order the
# exporter wrote the primitives. `vcol` is whether the mesh actually carries the
# "Col" attribute: a material may ask for it on a mesh that has none, and Godot
# hands the shader white in that case, which is the same thing Blender's own
# exporter concluded when it wrote the flat factor into the .glb.
const OBJECTS := {
	"Ice": [
		{"name": "ICE_Platform", "slots": ["ICE_M_Deck", "ICE_M_Rim", "ICE_M_Rock"], "vcol": true},
		{"name": "ICE_Icicles", "slots": ["ICE_M_Icicle"], "vcol": false},
		{"name": "ICE_Crystals", "slots": ["ICE_M_Crystal"], "vcol": true},
		{"name": "ICE_CrystalCores", "slots": ["ICE_M_CrystalCore"], "vcol": false},
		{"name": "ICE_RimShards", "slots": ["ICE_M_Crystal"], "vcol": true},
		{"name": "ICE_Sky", "slots": ["ICE_M_Sky"], "vcol": true},
		{"name": "ICE_MoonHalo", "slots": ["ICE_M_Sky"], "vcol": true},
		{"name": "ICE_Moon", "slots": ["ICE_M_Sky"], "vcol": true},
		{"name": "ICE_Mtn_Far", "slots": ["ICE_M_Far"], "vcol": true},
		{"name": "ICE_Mtn_Mid", "slots": ["ICE_M_Mid"], "vcol": true},
		{"name": "ICE_Cliffs_Near", "slots": ["ICE_M_NearCliff"], "vcol": true},
		{"name": "ICE_Castle", "slots": ["ICE_M_Castle"], "vcol": true},
		{"name": "ICE_BigCrystals", "slots": ["ICE_M_Crystal"], "vcol": true},
		{"name": "ICE_BigCrystalCores", "slots": ["ICE_M_CrystalCore"], "vcol": false},
		{"name": "ICE_BgArches", "slots": ["ICE_M_Mid"], "vcol": true},
		{"name": "ICE_Mist_Far", "slots": ["ICE_M_Mist"], "vcol": true},
		{"name": "ICE_Mist_Mid", "slots": ["ICE_M_Mist"], "vcol": true},
		{"name": "ICE_Mist_Near", "slots": ["ICE_M_Mist"], "vcol": true},
		{"name": "ICE_Mist_Edge", "slots": ["ICE_M_Mist"], "vcol": true},
		{"name": "ICE_PlatformCracks", "slots": ["ICE_M_Crack"], "vcol": false},
		{"name": "ICE_MistWisp_A", "slots": ["ICE_M_Mist"], "vcol": true},
		{"name": "ICE_MistWisp_B", "slots": ["ICE_M_Mist"], "vcol": true},
		{"name": "ICE_MistWisp_C", "slots": ["ICE_M_Mist"], "vcol": true},
		{"name": "ICE_Snow", "slots": ["ICE_M_SnowParticle"], "vcol": true},
		{"name": "ICE_Snow_Far", "slots": ["ICE_M_SnowParticle"], "vcol": true},
		{"name": "ICE_Sparkles_00", "slots": ["ICE_M_Sparkle"], "vcol": true},
		{"name": "ICE_Sparkles_01", "slots": ["ICE_M_Sparkle"], "vcol": true},
		{"name": "ICE_Sparkles_02", "slots": ["ICE_M_Sparkle"], "vcol": true},
		{"name": "ICE_Sparkles_03", "slots": ["ICE_M_Sparkle"], "vcol": true},
		{"name": "ICE_Sparkles_04", "slots": ["ICE_M_Sparkle"], "vcol": true},
		{"name": "ICE_Sparkles_05", "slots": ["ICE_M_Sparkle"], "vcol": true},
		{"name": "ICE_Sparkles_06", "slots": ["ICE_M_Sparkle"], "vcol": true},
		{"name": "ICE_Sparkles_07", "slots": ["ICE_M_Sparkle"], "vcol": true},
		{"name": "ICE_Sparkles_08", "slots": ["ICE_M_Sparkle"], "vcol": true},
		{"name": "ICE_Sparkles_09", "slots": ["ICE_M_Sparkle"], "vcol": true},
	],
	"Forest": [
		{"name": "FOREST_Platform", "slots": ["FOREST_M_Stone", "FOREST_M_RimStone", "FOREST_M_Soil"], "vcol": true},
		{"name": "FOREST_Roots", "slots": ["FOREST_M_Root"], "vcol": true},
		{"name": "FOREST_Moss", "slots": ["FOREST_M_Moss"], "vcol": true},
		{"name": "FOREST_Trees", "slots": ["FOREST_M_Bark"], "vcol": true},
		{"name": "FOREST_Leaves", "slots": ["FOREST_M_Leaf"], "vcol": true},
		{"name": "FOREST_GlowPlants", "slots": ["FOREST_M_Biolum"], "vcol": true},
		{"name": "FOREST_Stones", "slots": ["FOREST_M_Stone"], "vcol": true},
		{"name": "FOREST_Sky", "slots": ["FOREST_M_Sky"], "vcol": true},
		{"name": "FOREST_Trees_Far", "slots": ["FOREST_M_FarTree"], "vcol": true},
		{"name": "FOREST_Trees_Mid", "slots": ["FOREST_M_MidTree"], "vcol": true},
		{"name": "FOREST_Trees_Near", "slots": ["FOREST_M_MidTree"], "vcol": true},
		{"name": "FOREST_Shaft_0", "slots": ["FOREST_M_Shaft"], "vcol": true},
		{"name": "FOREST_Shaft_1", "slots": ["FOREST_M_Shaft"], "vcol": true},
		{"name": "FOREST_Shaft_2", "slots": ["FOREST_M_Shaft"], "vcol": true},
		{"name": "FOREST_Shaft_3", "slots": ["FOREST_M_Shaft"], "vcol": true},
		{"name": "FOREST_Shaft_4", "slots": ["FOREST_M_Shaft"], "vcol": true},
		{"name": "FOREST_Shaft_5", "slots": ["FOREST_M_Shaft"], "vcol": true},
		{"name": "FOREST_Shaft_6", "slots": ["FOREST_M_Shaft"], "vcol": true},
		{"name": "FOREST_Haze_0", "slots": ["FOREST_M_Mist"], "vcol": true},
		{"name": "FOREST_Haze_1", "slots": ["FOREST_M_Mist"], "vcol": true},
		{"name": "FOREST_Haze_2", "slots": ["FOREST_M_Mist"], "vcol": true},
		{"name": "FOREST_Haze_3", "slots": ["FOREST_M_Mist"], "vcol": true},
		{"name": "FOREST_Pollen", "slots": ["FOREST_M_Pollen"], "vcol": true},
		{"name": "FOREST_Pollen_Far", "slots": ["FOREST_M_Pollen"], "vcol": true},
		{"name": "FOREST_Fireflies_00", "slots": ["FOREST_M_Firefly"], "vcol": true},
		{"name": "FOREST_Fireflies_01", "slots": ["FOREST_M_Firefly"], "vcol": true},
		{"name": "FOREST_Fireflies_02", "slots": ["FOREST_M_Firefly"], "vcol": true},
		{"name": "FOREST_Fireflies_03", "slots": ["FOREST_M_Firefly"], "vcol": true},
		{"name": "FOREST_Fireflies_04", "slots": ["FOREST_M_Firefly"], "vcol": true},
		{"name": "FOREST_Fireflies_05", "slots": ["FOREST_M_Firefly"], "vcol": true},
		{"name": "FOREST_Fireflies_06", "slots": ["FOREST_M_Firefly"], "vcol": true},
		{"name": "FOREST_Fireflies_07", "slots": ["FOREST_M_Firefly"], "vcol": true},
		{"name": "FOREST_Fireflies_08", "slots": ["FOREST_M_Firefly"], "vcol": true},
		{"name": "FOREST_Fireflies_09", "slots": ["FOREST_M_Firefly"], "vcol": true},
		{"name": "FOREST_Fireflies_10", "slots": ["FOREST_M_Firefly"], "vcol": true},
		{"name": "FOREST_Fireflies_11", "slots": ["FOREST_M_Firefly"], "vcol": true},
		{"name": "FOREST_GlowMushrooms", "slots": ["FOREST_M_Mushroom"], "vcol": true},
		{"name": "FOREST_Flowers", "slots": ["FOREST_M_Flower"], "vcol": true},
	],
}

# Blender's view-transform exposure for each world, as `activate_theme` sets it.
# world_scenes.gd turns this into the linear pre-scale that makes the same light
# reach AgX in both engines (see EXPOSURE_MATCH).
const EXPOSURE := {
	"Ice": -0.2000,
	"Forest": -0.2000,
}

# The island's own silhouette, measured through the reference camera.
#
#   far       how far the play SURFACE reaches away from the camera, in Blender y
#   radius    how close its nearest boundary comes in the other three directions —
#             the limit on how far a world may be scaled down before a button
#             overhangs the edge of the deck it is standing on
#   top       how high the play surface itself stands. An island deck is NOT at
#             y = 0 the way a Themes1 floor is — it is 55-71 mm above it — so
#             anything the engine lays ON the surface has to be put here. See
#             MemoryGameUI's ground pools.
#   skyline   the platform vertex that sits HIGHEST in the reference frame, and the
#             normalised v it sits at (0 = top of frame). Every board looks at the
#             island from a slightly different seat and sees less far than the
#             reference lens does; scaling the world until this point lands on this
#             v again is what puts the reveal band — the whole deep background —
#             back at the size the composition was designed around.
#             See WorldScenes.fit_scale.
const DECK := {
	"Ice": {"far": 3.7449, "radius": 4.2134, "top": 0.0548, "skyline_v": 0.135108,
		"skyline": Vector3(0.00000, 0.07500, -3.91487)},
	"Forest": {"far": 3.7677, "radius": 4.2292, "top": 0.0710, "skyline_v": 0.133156,
		"skyline": Vector3(-0.27083, 0.07500, -3.94437)},
}

# The camera both were composed against: LUME_Gameplay_Camera, unmoved, at a
# 43.60 deg horizontal lens on a 1920x1080 frame. The shop preview uses exactly this
# pose so a card frames a world the way its author did.
const REF_CAM_ORIGIN := Vector3(0.0000, 5.8500, 8.9500)
const REF_CAM_FOV := 43.6028

# The authored loop: 300 frames at 30 fps, with frame 301 keyed identical to frame 1,
# so the clip is exactly 10.0000 s long and the last key sits one frame before the repeat.
const LOOP_FPS := 30
const LOOP_FRAMES := 300
const LOOP_SECONDS := 10.000000

