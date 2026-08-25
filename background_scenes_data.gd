# GENERATED — do not hand-edit. Regenerate with tools/gen_bg_data.py against
# Themes/Themes1.blend (see background_scenes.gd's header for the recipe).
#
# The Blender ground truth for the nine LUME gameplay backgrounds. The shipped
# .glb files cannot carry any of this: the exporter had to relink the "Glow"
# vertex-colour attribute into Base Color to make glTF write COLOR_0 at all, so
# every emissive material's baseColorFactor in the .glb is a placeholder (1,1,1,1)
# and its real albedo is only in the .blend. The area lights are not in the .glb
# either — glTF has no area light. Both are read out of the .blend and written
# here, so background_scenes.gd can rebuild each material and each light exactly.
#
# All colours are LINEAR (Blender's own working space), never sRGB.
extends RefCounted
class_name BackgroundScenesData

# Material name -> the Principled BSDF values as authored in Blender.
#   albedo    Base Color (linear). The .glb says (1,1,1,1) for every emissive one.
#   emis      Emission Strength; the emission COLOUR is the per-vertex Glow attribute.
#   glow      true when Emission Color is driven by the Glow vertex attribute.
#   alpha_vc  true when Alpha is driven by Glow.Alpha (only the Aurora ribbons vary).
#   blend     true for real alpha blending; the rest are opaque (Blender dithers them,
#             which at alpha 1.0 is indistinguishable from opaque).
const MATERIALS := {
	"BG_ArcadeRoom_M_Cabinet": {"albedo": Color(0.010500, 0.009800, 0.016500), "metallic": 0.3500, "roughness": 0.3600,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_ArcadeRoom_M_CabinetTrim": {"albedo": Color(0.018000, 0.017000, 0.026000), "metallic": 0.7500, "roughness": 0.2800,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_ArcadeRoom_M_Floor": {"albedo": Color(0.006200, 0.005800, 0.011000), "metallic": 0.3000, "roughness": 0.1550,
		"emis": 1.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_ArcadeRoom_M_Marquee": {"albedo": Color(0.006000, 0.006000, 0.012000), "metallic": 0.0000, "roughness": 0.3000,
		"emis": 1.8000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_ArcadeRoom_M_Neon": {"albedo": Color(0.010000, 0.008000, 0.020000), "metallic": 0.0000, "roughness": 0.2200,
		"emis": 3.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_ArcadeRoom_M_Screen": {"albedo": Color(0.004000, 0.004000, 0.008000), "metallic": 0.0000, "roughness": 0.1800,
		"emis": 2.2000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_Aurora_M_Ground": {"albedo": Color(0.003800, 0.004800, 0.008000), "metallic": 0.3500, "roughness": 0.2200,
		"emis": 1.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_Aurora_M_Motes": {"albedo": Color(0.000000, 0.000000, 0.000000), "metallic": 0.0000, "roughness": 0.5000,
		"emis": 3.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_Aurora_M_Ribbon": {"albedo": Color(0.000000, 0.000000, 0.000000), "metallic": 0.0000, "roughness": 0.5000,
		"emis": 1.1500, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": true},
	"BG_Aurora_M_Ridge": {"albedo": Color(0.002500, 0.003200, 0.005500), "metallic": 0.0000, "roughness": 0.6500,
		"emis": 1.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_Circuit_M_Bezel": {"albedo": Color(0.015000, 0.017000, 0.026000), "metallic": 0.8500, "roughness": 0.2800,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_Circuit_M_Chip": {"albedo": Color(0.009000, 0.010000, 0.014000), "metallic": 0.3500, "roughness": 0.5200,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_Circuit_M_ChipLED": {"albedo": Color(0.000000, 0.000000, 0.000000), "metallic": 0.0000, "roughness": 0.4000,
		"emis": 3.2000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_Circuit_M_HubGlow": {"albedo": Color(0.006000, 0.020000, 0.036000), "metallic": 0.0000, "roughness": 0.3000,
		"emis": 1.4000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_Circuit_M_Panel": {"albedo": Color(0.007500, 0.011500, 0.027000), "metallic": 0.2500, "roughness": 0.4200,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_Circuit_M_Pulse": {"albedo": Color(0.006000, 0.020000, 0.036000), "metallic": 0.0000, "roughness": 0.3000,
		"emis": 2.4000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_Circuit_M_Substrate": {"albedo": Color(0.004000, 0.006000, 0.015000), "metallic": 0.1500, "roughness": 0.6200,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_Circuit_M_Trace": {"albedo": Color(0.058000, 0.044000, 0.024000), "metallic": 0.9500, "roughness": 0.3000,
		"emis": 1.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_Circuit_M_Via": {"albedo": Color(0.075000, 0.058000, 0.032000), "metallic": 0.9500, "roughness": 0.3000,
		"emis": 2.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_CrystalCave_M_Core": {"albedo": Color(0.000000, 0.000000, 0.000000), "metallic": 0.0000, "roughness": 0.1000,
		"emis": 6.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_CrystalCave_M_Crystal": {"albedo": Color(0.010000, 0.014000, 0.030000), "metallic": 0.0000, "roughness": 0.0800,
		"emis": 2.8000, "glow": true, "alpha_vc": true, "coat": 0.4500, "blend": false},
	"BG_CrystalCave_M_Motes": {"albedo": Color(0.000000, 0.000000, 0.000000), "metallic": 0.0000, "roughness": 0.5000,
		"emis": 3.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_CrystalCave_M_Rock": {"albedo": Color(0.009000, 0.009200, 0.011200), "metallic": 0.1000, "roughness": 0.7200,
		"emis": 1.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_DarkMetal_M_AccentAmber": {"albedo": Color(0.020000, 0.010000, 0.002000), "metallic": 0.0000, "roughness": 0.2800,
		"emis": 2.6000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_DarkMetal_M_AccentCyan": {"albedo": Color(0.004000, 0.014000, 0.020000), "metallic": 0.0000, "roughness": 0.2800,
		"emis": 2.6000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_DarkMetal_M_Bolt": {"albedo": Color(0.032000, 0.033200, 0.037800), "metallic": 1.0000, "roughness": 0.2400,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_DarkMetal_M_Groove": {"albedo": Color(0.006000, 0.006300, 0.007800), "metallic": 1.0000, "roughness": 0.4600,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_DarkMetal_M_Gunmetal": {"albedo": Color(0.019500, 0.020300, 0.023600), "metallic": 1.0000, "roughness": 0.3000,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_DarkMetal_M_TurnedA": {"albedo": Color(0.024500, 0.025600, 0.029800), "metallic": 1.0000, "roughness": 0.1800,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_DarkMetal_M_TurnedB": {"albedo": Color(0.015800, 0.016500, 0.019600), "metallic": 1.0000, "roughness": 0.3600,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_DeepSpace_M_Dust": {"albedo": Color(0.000000, 0.000000, 0.000000), "metallic": 0.0000, "roughness": 0.5000,
		"emis": 2.4000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_DeepSpace_M_Nebula": {"albedo": Color(0.003000, 0.003600, 0.008600), "metallic": 0.5500, "roughness": 0.2000,
		"emis": 1.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_DeepSpace_M_Star": {"albedo": Color(0.000000, 0.000000, 0.000000), "metallic": 0.0000, "roughness": 0.5000,
		"emis": 7.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_DeepSpace_M_Void": {"albedo": Color(0.003000, 0.003600, 0.008600), "metallic": 0.5500, "roughness": 0.2000,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_HexFloor_M_LitSeam": {"albedo": Color(0.006000, 0.010000, 0.024000), "metallic": 0.0000, "roughness": 0.3000,
		"emis": 2.1000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_HexFloor_M_Panel": {"albedo": Color(0.007500, 0.007800, 0.009800), "metallic": 0.6200, "roughness": 0.3400,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_HexFloor_M_Seams": {"albedo": Color(0.002200, 0.002400, 0.003800), "metallic": 0.0000, "roughness": 0.5500,
		"emis": 1.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_NeonGrid_M_Floor": {"albedo": Color(0.004200, 0.005000, 0.011000), "metallic": 0.3000, "roughness": 0.3300,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_NeonGrid_M_GridAccent": {"albedo": Color(0.014000, 0.006000, 0.040000), "metallic": 0.0000, "roughness": 0.3500,
		"emis": 0.5500, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_NeonGrid_M_GridMajor": {"albedo": Color(0.006000, 0.016000, 0.040000), "metallic": 0.0000, "roughness": 0.3500,
		"emis": 0.5500, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_NeonGrid_M_GridMinor": {"albedo": Color(0.004000, 0.008000, 0.020000), "metallic": 0.0000, "roughness": 0.4000,
		"emis": 0.1600, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_NeonGrid_M_Horizon": {"albedo": Color(0.004200, 0.005000, 0.011000), "metallic": 0.3000, "roughness": 0.3300,
		"emis": 0.8500, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_NeonGrid_M_Pulse": {"albedo": Color(0.012000, 0.006000, 0.036000), "metallic": 0.0000, "roughness": 0.3500,
		"emis": 0.3400, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_NeonGrid_M_RingMetal": {"albedo": Color(0.016000, 0.017000, 0.028000), "metallic": 0.8500, "roughness": 0.3000,
		"emis": 0.0000, "glow": false, "alpha_vc": false, "coat": 0.0000, "blend": false},
	"BG_Volcanic_M_Basalt": {"albedo": Color(0.012500, 0.011600, 0.011000), "metallic": 0.0500, "roughness": 0.8000,
		"emis": 1.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_Volcanic_M_CrackWall": {"albedo": Color(0.011000, 0.006000, 0.003800), "metallic": 0.0500, "roughness": 0.6200,
		"emis": 2.6000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_Volcanic_M_Ember": {"albedo": Color(0.000000, 0.000000, 0.000000), "metallic": 0.0000, "roughness": 0.5000,
		"emis": 5.0000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
	"BG_Volcanic_M_Lava": {"albedo": Color(0.030000, 0.006000, 0.001000), "metallic": 0.0000, "roughness": 0.4200,
		"emis": 2.8000, "glow": true, "alpha_vc": true, "coat": 0.0000, "blend": false},
}

# Theme lights, per background, already converted into Godot space
# (Blender is Z-up, Godot Y-up: (x, y, z) -> (x, z, -y), basis included).
#
# 33 of the 47 are Blender AREA lights, which Godot has no equivalent for, so each
# is rebuilt as omnis strung along its long axis (see background_scenes.gd's
# _add_light). The data here stays the Blender description — the panel's size, its
# power in watts, its full orientation — so the translation lives in one readable
# place and can be re-tuned without regenerating this file.
const LIGHTS := {
	"BG_NeonGrid": [
		{"name": "BG_NeonGrid_Light_Blue", "type": "AREA", "energy": 13.0000,
			"color": Color(0.1000, 0.4200, 1.0000), "size": 6.0000, "size_y": 1.0000, "radius": 0.0000,
			"origin": Vector3(6.8000, 2.0000, -5.8000),
			"basis": Basis(Vector3(-0.829038, 0.000000, -0.559193), Vector3(0.502599, 0.438371, -0.745134), Vector3(0.245134, -0.898794, -0.363426))},
		{"name": "BG_NeonGrid_Light_Fill", "type": "AREA", "energy": 6.0000,
			"color": Color(0.2800, 0.3200, 0.7800), "size": 9.0000, "size_y": 3.0000, "radius": 0.0000,
			"origin": Vector3(0.0000, 2.6000, 4.8000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 0.788011, 0.615662), Vector3(0.000000, -0.615662, 0.788011))},
		{"name": "BG_NeonGrid_Light_Violet", "type": "AREA", "energy": 15.0000,
			"color": Color(0.4500, 0.1700, 1.0000), "size": 6.0000, "size_y": 1.0000, "radius": 0.0000,
			"origin": Vector3(-6.6000, 2.2000, -6.2000),
			"basis": Basis(Vector3(-0.829038, 0.000000, 0.559193), Vector3(-0.502599, 0.438371, -0.745134), Vector3(-0.245134, -0.898794, -0.363426))},
	],
	"BG_DeepSpace": [
		{"name": "BG_DeepSpace_Light_Blue", "type": "AREA", "energy": 9.0000,
			"color": Color(0.1400, 0.3000, 1.0000), "size": 7.0000, "size_y": 1.2000, "radius": 0.0000,
			"origin": Vector3(7.2000, 2.4000, -6.0000),
			"basis": Basis(Vector3(-0.848048, 0.000000, -0.529919), Vector3(0.484105, 0.406737, -0.774730), Vector3(0.215538, -0.913545, -0.344932))},
		{"name": "BG_DeepSpace_Light_Fill", "type": "AREA", "energy": 4.0000,
			"color": Color(0.2400, 0.2600, 0.6200), "size": 10.0000, "size_y": 3.0000, "radius": 0.0000,
			"origin": Vector3(0.0000, 3.0000, 5.4000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 0.809017, 0.587785), Vector3(0.000000, -0.587785, 0.809017))},
		{"name": "BG_DeepSpace_Light_Violet", "type": "AREA", "energy": 10.0000,
			"color": Color(0.3600, 0.2000, 1.0000), "size": 7.0000, "size_y": 1.2000, "radius": 0.0000,
			"origin": Vector3(-7.0000, 2.6000, -6.4000),
			"basis": Basis(Vector3(-0.848048, 0.000000, 0.529919), Vector3(-0.484105, 0.406737, -0.774730), Vector3(-0.215538, -0.913545, -0.344932))},
	],
	"BG_Aurora": [
		{"name": "BG_Aurora_Light_Aurora_C", "type": "AREA", "energy": 14.0000,
			"color": Color(0.1400, 0.9000, 1.0000), "size": 8.0000, "size_y": 1.0000, "radius": 0.0000,
			"origin": Vector3(4.5000, 1.5000, -5.0000),
			"basis": Basis(Vector3(-0.990268, 0.000000, -0.139173), Vector3(0.118026, 0.529919, -0.839795), Vector3(0.073751, -0.848048, -0.524762))},
		{"name": "BG_Aurora_Light_Aurora_G", "type": "AREA", "energy": 16.0000,
			"color": Color(0.2400, 1.0000, 0.5000), "size": 8.0000, "size_y": 1.0000, "radius": 0.0000,
			"origin": Vector3(-4.0000, 1.6000, -5.2000),
			"basis": Basis(Vector3(-0.990268, 0.000000, 0.139173), Vector3(-0.118026, 0.529919, -0.839795), Vector3(-0.073751, -0.848048, -0.524762))},
		{"name": "BG_Aurora_Light_Aurora_V", "type": "AREA", "energy": 9.0000,
			"color": Color(0.4500, 0.2200, 1.0000), "size": 9.0000, "size_y": 1.0000, "radius": 0.0000,
			"origin": Vector3(0.0000, 1.2000, -6.4000),
			"basis": Basis(Vector3(-1.000000, 0.000000, 0.000000), Vector3(-0.000000, 0.438371, -0.898794), Vector3(-0.000000, -0.898794, -0.438371))},
		{"name": "BG_Aurora_Light_Fill", "type": "AREA", "energy": 4.0000,
			"color": Color(0.3000, 0.4200, 0.6200), "size": 10.0000, "size_y": 3.0000, "radius": 0.0000,
			"origin": Vector3(0.0000, 2.8000, 5.2000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 0.809017, 0.587785), Vector3(0.000000, -0.587785, 0.809017))},
	],
	"BG_Circuit": [
		{"name": "BG_Circuit_Light_Cyan", "type": "AREA", "energy": 16.0000,
			"color": Color(0.1200, 0.6800, 1.0000), "size": 6.0000, "size_y": 1.0000, "radius": 0.0000,
			"origin": Vector3(-6.4000, 2.2000, -6.0000),
			"basis": Basis(Vector3(-0.829038, 0.000000, 0.559193), Vector3(-0.502599, 0.438371, -0.745134), Vector3(-0.245134, -0.898794, -0.363426))},
		{"name": "BG_Circuit_Light_Fill", "type": "AREA", "energy": 7.0000,
			"color": Color(0.2400, 0.3400, 0.7200), "size": 9.0000, "size_y": 3.0000, "radius": 0.0000,
			"origin": Vector3(0.0000, 2.8000, 5.0000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 0.788011, 0.615662), Vector3(0.000000, -0.615662, 0.788011))},
		{"name": "BG_Circuit_Light_Violet", "type": "AREA", "energy": 13.0000,
			"color": Color(0.4200, 0.1600, 1.0000), "size": 6.0000, "size_y": 1.0000, "radius": 0.0000,
			"origin": Vector3(6.6000, 2.0000, -5.6000),
			"basis": Basis(Vector3(-0.829038, 0.000000, -0.559193), Vector3(0.502599, 0.438371, -0.745134), Vector3(0.245134, -0.898794, -0.363426))},
	],
	"BG_HexFloor": [
		{"name": "BG_HexFloor_Light_Cyan", "type": "AREA", "energy": 15.0000,
			"color": Color(0.0800, 0.6200, 1.0000), "size": 6.5000, "size_y": 1.0000, "radius": 0.0000,
			"origin": Vector3(6.8000, 2.2000, -5.4000),
			"basis": Basis(Vector3(-0.829038, 0.000000, -0.559193), Vector3(0.502599, 0.438371, -0.745134), Vector3(0.245134, -0.898794, -0.363426))},
		{"name": "BG_HexFloor_Light_Fill", "type": "AREA", "energy": 9.0000,
			"color": Color(0.2800, 0.3200, 0.6600), "size": 9.0000, "size_y": 3.0000, "radius": 0.0000,
			"origin": Vector3(0.0000, 2.9000, 5.0000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 0.788011, 0.615662), Vector3(0.000000, -0.615662, 0.788011))},
		{"name": "BG_HexFloor_Light_Violet", "type": "AREA", "energy": 18.0000,
			"color": Color(0.4200, 0.1600, 1.0000), "size": 6.5000, "size_y": 1.0000, "radius": 0.0000,
			"origin": Vector3(-6.6000, 2.4000, -5.8000),
			"basis": Basis(Vector3(-0.829038, 0.000000, 0.559193), Vector3(-0.502599, 0.438371, -0.745134), Vector3(-0.245134, -0.898794, -0.363426))},
	],
	"BG_DarkMetal": [
		{"name": "BG_DarkMetal_Light_Amber", "type": "AREA", "energy": 22.0000,
			"color": Color(1.0000, 0.5800, 0.1800), "size": 5.0000, "size_y": 1.0000, "radius": 0.0000,
			"origin": Vector3(7.0000, 2.2000, -2.6000),
			"basis": Basis(Vector3(-0.374607, 0.000000, -0.927184), Vector3(0.818655, 0.469472, -0.330758), Vector3(0.435286, -0.882948, -0.175867))},
		{"name": "BG_DarkMetal_Light_Cyan", "type": "AREA", "energy": 17.0000,
			"color": Color(0.1000, 0.6200, 1.0000), "size": 5.0000, "size_y": 1.0000, "radius": 0.0000,
			"origin": Vector3(-7.2000, 2.0000, 1.2000),
			"basis": Basis(Vector3(0.309017, 0.000000, 0.951057), Vector3(-0.868833, 0.406737, 0.282301), Vector3(-0.386830, -0.913545, 0.125689))},
		{"name": "BG_DarkMetal_Light_Far", "type": "AREA", "energy": 32.0000,
			"color": Color(0.6000, 0.7000, 0.9500), "size": 15.0000, "size_y": 5.5000, "radius": 0.0000,
			"origin": Vector3(0.0000, 3.2000, -5.4000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_DarkMetal_Light_Key", "type": "AREA", "energy": 66.0000,
			"color": Color(0.5500, 0.7200, 1.0000), "size": 7.0000, "size_y": 1.4000, "radius": 0.0000,
			"origin": Vector3(-6.0000, 3.4000, -5.4000),
			"basis": Basis(Vector3(-0.788011, 0.000000, 0.615661), Vector3(-0.522111, 0.529919, -0.668271), Vector3(-0.326251, -0.848048, -0.417582))},
		{"name": "BG_DarkMetal_Light_Sweep", "type": "AREA", "energy": 30.0000,
			"color": Color(0.7200, 0.7800, 0.9200), "size": 11.0000, "size_y": 3.0000, "radius": 0.0000,
			"origin": Vector3(0.0000, 3.4000, 5.6000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 0.809017, 0.587785), Vector3(0.000000, -0.587785, 0.809017))},
		{"name": "BG_DarkMetal_Light_Wing_L", "type": "AREA", "energy": 9.0000,
			"color": Color(0.3500, 0.5500, 0.9500), "size": 5.0000, "size_y": 7.0000, "radius": 0.0000,
			"origin": Vector3(-6.6000, 2.4000, -1.2000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_DarkMetal_Light_Wing_R", "type": "AREA", "energy": 9.0000,
			"color": Color(0.9500, 0.6200, 0.2800), "size": 5.0000, "size_y": 7.0000, "radius": 0.0000,
			"origin": Vector3(6.6000, 2.4000, -1.0000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
	],
	"BG_CrystalCave": [
		{"name": "BG_CrystalCave_Light_Ambient", "type": "AREA", "energy": 5.0000,
			"color": Color(0.2000, 0.4200, 0.9000), "size": 12.0000, "size_y": 5.0000, "radius": 0.0000,
			"origin": Vector3(0.0000, 3.0000, -4.6000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_CrystalCave_Light_Fill", "type": "AREA", "energy": 4.0000,
			"color": Color(0.2800, 0.3400, 0.7000), "size": 9.0000, "size_y": 3.0000, "radius": 0.0000,
			"origin": Vector3(0.0000, 2.8000, 5.2000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 0.788011, 0.615662), Vector3(0.000000, -0.615662, 0.788011))},
		{"name": "BG_CrystalCave_Light_Xtal_01", "type": "POINT", "energy": 2.0000,
			"color": Color(0.4500, 0.1300, 1.0000), "size": 0.0000, "size_y": 0.0000, "radius": 0.2800,
			"origin": Vector3(-5.5010, 0.4091, -4.1982),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_CrystalCave_Light_Xtal_02", "type": "POINT", "energy": 2.0000,
			"color": Color(0.0500, 0.8000, 1.0000), "size": 0.0000, "size_y": 0.0000, "radius": 0.2800,
			"origin": Vector3(-3.0953, 0.3144, -4.7671),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_CrystalCave_Light_Xtal_03", "type": "POINT", "energy": 2.0000,
			"color": Color(1.0000, 0.1400, 0.6200), "size": 0.0000, "size_y": 0.0000, "radius": 0.2800,
			"origin": Vector3(-2.8515, 0.2872, -4.9113),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_CrystalCave_Light_Xtal_04", "type": "POINT", "energy": 2.0000,
			"color": Color(0.0600, 0.2200, 1.0000), "size": 0.0000, "size_y": 0.0000, "radius": 0.2800,
			"origin": Vector3(0.2353, 0.2290, -5.2202),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_CrystalCave_Light_Xtal_05", "type": "POINT", "energy": 2.0000,
			"color": Color(0.0500, 0.8000, 1.0000), "size": 0.0000, "size_y": 0.0000, "radius": 0.2800,
			"origin": Vector3(-0.3410, 0.2790, -4.9549),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_CrystalCave_Light_Xtal_06", "type": "POINT", "energy": 2.0000,
			"color": Color(1.0000, 0.1400, 0.6200), "size": 0.0000, "size_y": 0.0000, "radius": 0.2800,
			"origin": Vector3(2.5115, 0.3087, -4.7693),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_CrystalCave_Light_Xtal_07", "type": "POINT", "energy": 2.0000,
			"color": Color(1.0000, 0.1400, 0.6200), "size": 0.0000, "size_y": 0.0000, "radius": 0.2800,
			"origin": Vector3(2.5171, 0.3120, -4.7800),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
	],
	"BG_Volcanic": [
		{"name": "BG_Volcanic_Light_Ambient", "type": "AREA", "energy": 6.0000,
			"color": Color(0.5500, 0.2400, 0.1000), "size": 12.0000, "size_y": 5.0000, "radius": 0.0000,
			"origin": Vector3(0.0000, 3.0000, -4.4000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_Volcanic_Light_Fill", "type": "AREA", "energy": 4.0000,
			"color": Color(0.4200, 0.3000, 0.3400), "size": 9.0000, "size_y": 3.0000, "radius": 0.0000,
			"origin": Vector3(0.0000, 2.8000, 5.2000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 0.788011, 0.615662), Vector3(0.000000, -0.615662, 0.788011))},
		{"name": "BG_Volcanic_Light_Vent_01", "type": "POINT", "energy": 1.8000,
			"color": Color(1.0000, 0.3400, 0.0600), "size": 0.0000, "size_y": 0.0000, "radius": 0.4500,
			"origin": Vector3(-5.4000, 0.1000, -4.9000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_Volcanic_Light_Vent_02", "type": "POINT", "energy": 1.8000,
			"color": Color(1.0000, 0.3400, 0.0600), "size": 0.0000, "size_y": 0.0000, "radius": 0.4500,
			"origin": Vector3(3.9000, 0.1000, -5.3000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_Volcanic_Light_Vent_03", "type": "POINT", "energy": 1.8000,
			"color": Color(1.0000, 0.3400, 0.0600), "size": 0.0000, "size_y": 0.0000, "radius": 0.4500,
			"origin": Vector3(-4.2000, 0.1000, 0.4000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_Volcanic_Light_Vent_04", "type": "POINT", "energy": 1.8000,
			"color": Color(1.0000, 0.3400, 0.0600), "size": 0.0000, "size_y": 0.0000, "radius": 0.4500,
			"origin": Vector3(5.2000, 0.1000, -1.2000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_Volcanic_Light_Vent_06", "type": "POINT", "energy": 1.8000,
			"color": Color(1.0000, 0.3400, 0.0600), "size": 0.0000, "size_y": 0.0000, "radius": 0.4500,
			"origin": Vector3(0.6000, 0.1000, -6.2000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_Volcanic_Light_Vent_07", "type": "POINT", "energy": 1.8000,
			"color": Color(1.0000, 0.3400, 0.0600), "size": 0.0000, "size_y": 0.0000, "radius": 0.4500,
			"origin": Vector3(-2.6000, 0.1000, 3.2000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_Volcanic_Light_Vent_08", "type": "POINT", "energy": 1.8000,
			"color": Color(1.0000, 0.3400, 0.0600), "size": 0.0000, "size_y": 0.0000, "radius": 0.4500,
			"origin": Vector3(3.4000, 0.1000, 3.4000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
	],
	"BG_ArcadeRoom": [
		{"name": "BG_ArcadeRoom_Light_Blue", "type": "AREA", "energy": 3.5000,
			"color": Color(0.1200, 0.2800, 1.0000), "size": 2.0000, "size_y": 0.6000, "radius": 0.0000,
			"origin": Vector3(2.0000, 0.8000, -4.1000),
			"basis": Basis(Vector3(-1.000000, 0.000000, 0.000000), Vector3(-0.000000, 0.309017, -0.951057), Vector3(-0.000000, -0.951057, -0.309017))},
		{"name": "BG_ArcadeRoom_Light_Cyan", "type": "AREA", "energy": 4.5000,
			"color": Color(0.0600, 0.7800, 1.0000), "size": 2.4000, "size_y": 0.7000, "radius": 0.0000,
			"origin": Vector3(4.6000, 0.9000, -4.0000),
			"basis": Basis(Vector3(-1.000000, 0.000000, 0.000000), Vector3(-0.000000, 0.309017, -0.951057), Vector3(-0.000000, -0.951057, -0.309017))},
		{"name": "BG_ArcadeRoom_Light_Fill", "type": "AREA", "energy": 3.0000,
			"color": Color(0.3400, 0.3000, 0.6000), "size": 9.0000, "size_y": 3.0000, "radius": 0.0000,
			"origin": Vector3(0.0000, 2.8000, 5.2000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 0.788011, 0.615662), Vector3(0.000000, -0.615662, 0.788011))},
		{"name": "BG_ArcadeRoom_Light_Magenta", "type": "AREA", "energy": 5.0000,
			"color": Color(1.0000, 0.1600, 0.6200), "size": 2.4000, "size_y": 0.7000, "radius": 0.0000,
			"origin": Vector3(-5.0000, 0.9000, -4.0000),
			"basis": Basis(Vector3(-1.000000, 0.000000, 0.000000), Vector3(-0.000000, 0.309017, -0.951057), Vector3(-0.000000, -0.951057, -0.309017))},
		{"name": "BG_ArcadeRoom_Light_Sweep", "type": "AREA", "energy": 5.0000,
			"color": Color(0.3000, 0.3400, 0.7200), "size": 13.0000, "size_y": 7.0000, "radius": 0.0000,
			"origin": Vector3(0.0000, 3.2000, -0.6000),
			"basis": Basis(Vector3(1.000000, 0.000000, 0.000000), Vector3(0.000000, 1.000000, 0.000000), Vector3(0.000000, 0.000000, 1.000000))},
		{"name": "BG_ArcadeRoom_Light_Violet", "type": "AREA", "energy": 3.5000,
			"color": Color(0.5000, 0.1400, 1.0000), "size": 2.0000, "size_y": 0.6000, "radius": 0.0000,
			"origin": Vector3(-1.8000, 0.8000, -4.1000),
			"basis": Basis(Vector3(-1.000000, 0.000000, 0.000000), Vector3(-0.000000, 0.309017, -0.951057), Vector3(-0.000000, -0.951057, -0.309017))},
	],
}

# Mesh objects per background, with the material in each slot and the
# `lume_anim` custom property the artist wrote on it. The anim string is the
# authoring INTENT — background_scenes.gd maps it onto one of its own motion
# kinds; anything it does not recognise stays still, which is always safe.
const OBJECTS := {
	"BG_NeonGrid": [
		{"name": "BG_EnergyPulse", "slots": ["BG_NeonGrid_M_RingMetal", "BG_NeonGrid_M_Pulse"],
			"anim": "radial_pulse | scale 1.0->1.06 + emission 0.7->1.4, 3.2s"},
		{"name": "BG_GridLines", "slots": ["BG_NeonGrid_M_GridMajor"],
			"anim": "emission_scroll_v  | slow energy travelling along the grid"},
		{"name": "BG_GridLines_Accent", "slots": ["BG_NeonGrid_M_GridAccent"],
			"anim": "emission_pulse | 4s offset from majors"},
		{"name": "BG_NeonGrid_Floor", "slots": ["BG_NeonGrid_M_Floor"],
			"anim": "static"},
		{"name": "BG_NeonGrid_GridLines_Minor", "slots": ["BG_NeonGrid_M_GridMinor"],
			"anim": "emission_breathe | 0.85x-1.15x, 6s"},
		{"name": "BG_NeonGrid_Horizon", "slots": ["BG_NeonGrid_M_Horizon"],
			"anim": "emission_breathe | 9s, very subtle"},
	],
	"BG_DeepSpace": [
		{"name": "BG_CosmicDust", "slots": ["BG_DeepSpace_M_Dust"],
			"anim": "drift_translate | +X 0.02 u/s, wrap"},
		{"name": "BG_DeepSpace_Void", "slots": ["BG_DeepSpace_M_Void"],
			"anim": "static"},
		{"name": "BG_Nebula", "slots": ["BG_DeepSpace_M_Nebula"],
			"anim": "emission_breathe | 12s, hue drift +-4deg"},
		{"name": "BG_Stars", "slots": ["BG_DeepSpace_M_Star"],
			"anim": "uv_parallax_drift + per-star twinkle | extremely slow"},
	],
	"BG_Aurora": [
		{"name": "BG_Aurora_Ground", "slots": ["BG_Aurora_M_Ground"],
			"anim": "emission_breathe follows ribbons | 14s"},
		{"name": "BG_Aurora_Motes", "slots": ["BG_Aurora_M_Motes"],
			"anim": "drift_translate | slow upward"},
		{"name": "BG_Aurora_Ribbon_01", "slots": ["BG_Aurora_M_Ribbon"],
			"anim": "wave_offset along X + alpha breathe | 14s, phase = index * 2.8s"},
		{"name": "BG_Aurora_Ribbon_02", "slots": ["BG_Aurora_M_Ribbon"],
			"anim": "wave_offset along X + alpha breathe | 14s, phase = index * 2.8s"},
		{"name": "BG_Aurora_Ribbon_03", "slots": ["BG_Aurora_M_Ribbon"],
			"anim": "wave_offset along X + alpha breathe | 14s, phase = index * 2.8s"},
		{"name": "BG_Aurora_Ribbon_04", "slots": ["BG_Aurora_M_Ribbon"],
			"anim": "wave_offset along X + alpha breathe | 14s, phase = index * 2.8s"},
		{"name": "BG_Aurora_Ribbon_05", "slots": ["BG_Aurora_M_Ribbon"],
			"anim": "wave_offset along X + alpha breathe | 14s, phase = index * 2.8s"},
		{"name": "BG_Aurora_Ridge_Far", "slots": ["BG_Aurora_M_Ridge"],
			"anim": "static"},
		{"name": "BG_Aurora_Ridge_Mid", "slots": ["BG_Aurora_M_Ridge"],
			"anim": "static"},
		{"name": "BG_Aurora_Ridge_Near", "slots": ["BG_Aurora_M_Ridge"],
			"anim": "static"},
	],
	"BG_Circuit": [
		{"name": "BG_Circuit_ChipLEDs", "slots": ["BG_Circuit_M_ChipLED"],
			"anim": "blink | 1-3s random"},
		{"name": "BG_Circuit_Chips", "slots": ["BG_Circuit_M_Chip"],
			"anim": "static"},
		{"name": "BG_Circuit_HubBezel", "slots": ["BG_Circuit_M_Bezel", "BG_Circuit_M_HubGlow"],
			"anim": "emission_breathe | 4s"},
		{"name": "BG_Circuit_Panels", "slots": ["BG_Circuit_M_Panel"],
			"anim": "static"},
		{"name": "BG_Circuit_Substrate", "slots": ["BG_Circuit_M_Substrate"],
			"anim": "static"},
		{"name": "BG_Circuit_Vias", "slots": ["BG_Circuit_M_Via"],
			"anim": "blink | random 0.2s flashes on pulse arrival"},
		{"name": "BG_CircuitPulse", "slots": ["BG_Circuit_M_Pulse"],
			"anim": "trace_pulse | bright head travelling outward from the hub, 2.6s, staggered"},
		{"name": "BG_CircuitTraces", "slots": ["BG_Circuit_M_Trace"],
			"anim": "static"},
	],
	"BG_HexFloor": [
		{"name": "BG_HexFloor_Lit", "slots": ["BG_HexFloor_M_LitSeam"],
			"anim": "hex_wave | illumination sweeping outward, 5s, per-hex delay = radius"},
		{"name": "BG_HexFloor_Panels", "slots": ["BG_HexFloor_M_Panel"],
			"anim": "static"},
		{"name": "BG_HexFloor_Seams", "slots": ["BG_HexFloor_M_Seams"],
			"anim": "emission_breathe | 8s, +-12%"},
	],
	"BG_DarkMetal": [
		{"name": "BG_DarkMetal_Accent_Amber", "slots": ["BG_DarkMetal_M_AccentAmber"],
			"anim": "emission_breathe | 6s, 3s offset"},
		{"name": "BG_DarkMetal_Accent_Cyan", "slots": ["BG_DarkMetal_M_AccentCyan"],
			"anim": "emission_breathe | 6s"},
		{"name": "BG_DarkMetal_Bolts", "slots": ["BG_DarkMetal_M_Bolt"],
			"anim": "static"},
		{"name": "BG_DarkMetal_Floor", "slots": ["BG_DarkMetal_M_Gunmetal"],
			"anim": "static"},
		{"name": "BG_DarkMetal_Grooves", "slots": ["BG_DarkMetal_M_Groove"],
			"anim": "static"},
		{"name": "BG_DarkMetal_Plates", "slots": ["BG_DarkMetal_M_Gunmetal"],
			"anim": "static"},
		{"name": "BG_DarkMetal_Turning", "slots": ["BG_DarkMetal_M_TurnedA", "BG_DarkMetal_M_TurnedB"],
			"anim": "static"},
	],
	"BG_CrystalCave": [
		{"name": "BG_CrystalCave_Cores", "slots": ["BG_CrystalCave_M_Core"],
			"anim": "emission_breathe | 5s, per-crystal phase offset"},
		{"name": "BG_CrystalCave_Crystals", "slots": ["BG_CrystalCave_M_Crystal"],
			"anim": "emission_breathe | 5s, 40% depth"},
		{"name": "BG_CrystalCave_Ground", "slots": ["BG_CrystalCave_M_Rock"],
			"anim": "static"},
		{"name": "BG_CrystalCave_Particles", "slots": ["BG_CrystalCave_M_Motes"],
			"anim": "drift_translate | slow rise + fade"},
	],
	"BG_Volcanic": [
		{"name": "BG_LavaCracks", "slots": ["BG_Volcanic_M_Lava"],
			"anim": "emission_breathe + slow flow | 7s"},
		{"name": "BG_Volcanic_Crust", "slots": ["BG_Volcanic_M_Basalt", "BG_Volcanic_M_CrackWall"],
			"anim": "crack_edge_breathe (slot 1 only) | 7s, in phase with lava"},
		{"name": "BG_Volcanic_Embers", "slots": ["BG_Volcanic_M_Ember"],
			"anim": "drift_translate | slow rise, fade out at top"},
	],
	"BG_ArcadeRoom": [
		{"name": "BG_ArcadeMachines", "slots": ["BG_ArcadeRoom_M_Cabinet", "BG_ArcadeRoom_M_CabinetTrim"],
			"anim": "static"},
		{"name": "BG_ArcadeNeonSigns", "slots": ["BG_ArcadeRoom_M_Neon"],
			"anim": "neon_pulse | 2-5s per sign, occasional 1-frame dropout"},
		{"name": "BG_ArcadeRoom_Floor", "slots": ["BG_ArcadeRoom_M_Floor"],
			"anim": "static"},
		{"name": "BG_ArcadeRoom_Marquees", "slots": ["BG_ArcadeRoom_M_Marquee"],
			"anim": "emission_breathe | 3s"},
		{"name": "BG_ArcadeScreens", "slots": ["BG_ArcadeRoom_M_Screen"],
			"anim": "screen_flicker | per-screen random 0.05-0.4s, +-25%"},
	],
}

# The radius at which SOLID geometry taller than z = 0.10 first appears, per
# background — measured over every vertex in the .blend. `INF` means the scene is
# a pure floor with nothing standing on it at all, which is true of five of the
# nine.
#
# This is what decides how far a background may be slid toward the camera to
# recover the Blender framing (see BackgroundScenes.SEAT and
# MemoryGameUI._seat_background): the outermost button must stay inside it, so a
# scene with nothing standing in it can be seated freely and one with a cabinet
# row cannot.
#
# Drifting particle fields (motes, stars, embers, cosmic dust) are deliberately
# excluded — they are specks of light with no silhouette, and a button passing
# near one reads as nothing.
const TALL_RADIUS := {
	"BG_NeonGrid": INF,
	"BG_DeepSpace": INF,
	"BG_Aurora": 3.8540,   # BG_Aurora_Ribbon_03
	"BG_Circuit": INF,
	"BG_HexFloor": INF,
	"BG_DarkMetal": INF,
	"BG_CrystalCave": 3.7516,   # BG_CrystalCave_Crystals
	"BG_Volcanic": 4.9132,   # BG_Volcanic_Crust
	"BG_ArcadeRoom": 3.9401,   # BG_ArcadeNeonSigns
}

# How far out each background's STANDING furniture reaches, in Blender y — the
# largest y of any mesh more than 0.35 tall. `INF` means the scene has none: it is
# a floor, and there is nothing out there to be cut off by the top of the frame.
#
# 0.35 is not arbitrary. It sits above the tallest floor RELIEF in the set (the
# volcanic crust's plates at 0.27, Crystal Cave's displaced ground at 0.30) and
# below the shortest real standing object (an aurora ribbon at 0.38), so the two
# separate cleanly with nothing near the boundary.
#
# This is what decides whether a background is seated at all — see
# MemoryGameUI._seat_background. A floor needs no correction: its far edge running
# off the top of the frame is what a floor is supposed to do, and sliding it
# forward only drags the horizon band into view. A cabinet row does need one.
const FURNITURE_FAR_Y := {
	"BG_NeonGrid": INF,
	"BG_DeepSpace": INF,
	"BG_Aurora": 5.9792,   # BG_Aurora_Ribbon_05
	"BG_Circuit": INF,
	"BG_HexFloor": INF,
	"BG_DarkMetal": INF,
	"BG_CrystalCave": 5.4590,   # BG_CrystalCave_Crystals
	"BG_Volcanic": INF,
	"BG_ArcadeRoom": 5.7347,   # BG_ArcadeMachines
}

# The Blender world: a vertical gradient on the generated-Z coordinate, i.e. a
# very dark blue-grey ambient that lifts towards the top of the dome. Godot's
# board viewport already owns its Environment (tuned for the buttons and NOT ours
# to change), so this is applied as the backdrop dome's own gradient instead.
const WORLD_RAMP := [
	Color(0.003500, 0.004200, 0.006000),   # ramp stop at 0.30
	Color(0.023000, 0.029000, 0.042000),   # ramp stop at 0.62
	Color(0.062000, 0.076000, 0.105000),   # ramp stop at 0.86
]
const WORLD_RAMP_POS := [0.3000, 0.6200, 0.8600]
