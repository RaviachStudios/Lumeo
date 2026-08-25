import json, sys, os
d = json.load(open(sys.argv[1]))
out = []
W = out.append

W('''# GENERATED — do not hand-edit. Regenerate with tools/gen_bg_data.py against
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
''')

# ---- materials ----
W('# Material name -> the Principled BSDF values as authored in Blender.')
W('#   albedo    Base Color (linear). The .glb says (1,1,1,1) for every emissive one.')
W('#   emis      Emission Strength; the emission COLOUR is the per-vertex Glow attribute.')
W('#   glow      true when Emission Color is driven by the Glow vertex attribute.')
W('#   alpha_vc  true when Alpha is driven by Glow.Alpha.')
W('#   blend     true for real alpha blending; the rest are opaque (Blender dithers them,')
W('#             which at alpha 1.0 is indistinguishable from opaque).')
W('const MATERIALS := {')
for k in sorted(d["materials"]):
    m = d["materials"][k]
    a = m["albedo"]
    blend = "true" if m["render_method"] == "BLENDED" else "false"
    W('\t"%s": {"albedo": Color(%.6f, %.6f, %.6f), "metallic": %.4f, "roughness": %.4f,'
      % (k, a[0], a[1], a[2], m["metallic"], m["roughness"]))
    W('\t\t"emis": %.4f, "glow": %s, "alpha_vc": %s, "coat": %.4f, "blend": %s},'
      % (m["emission_strength"], "true" if m["glow"] else "false",
         "true" if m["alpha_vc"] else "false", m["coat"], blend))
W('}\n')

# ---- lights ----
W('''# Theme lights, per background, already converted into Godot space
# (Blender is Z-up, Godot Y-up: (x, y, z) -> (x, z, -y), basis included).
#
# 33 of the 47 are Blender AREA lights, which Godot has no equivalent for, so each
# is rebuilt as omnis strung along its long axis (see background_scenes.gd's
# _add_light). The data here stays the Blender description — the panel's size, its
# power in watts, its full orientation — so the translation lives in one readable
# place and can be re-tuned without regenerating this file.
const LIGHTS := {''')
for bg in ["BG_NeonGrid","BG_DeepSpace","BG_Circuit","BG_HexFloor",
           "BG_DarkMetal","BG_CrystalCave","BG_Volcanic","BG_ArcadeRoom"]:
    W('\t"%s": [' % bg)
    for L in d["lights"][bg]:
        o = L["origin"]; b = L["basis"]; c = L["color"]
        W('\t\t{"name": "%s", "type": "%s", "energy": %.4f,' % (L["name"], L["type"], L["energy"]))
        W('\t\t\t"color": Color(%.4f, %.4f, %.4f), "size": %.4f, "size_y": %.4f, "radius": %.4f,'
          % (c[0], c[1], c[2], L["size"], L["size_y"], L["radius"]))
        W('\t\t\t"origin": Vector3(%.4f, %.4f, %.4f),' % (o[0], o[1], o[2]))
        W('\t\t\t"basis": Basis(Vector3(%.6f, %.6f, %.6f), Vector3(%.6f, %.6f, %.6f), Vector3(%.6f, %.6f, %.6f))},'
          % (b[0][0], b[1][0], b[2][0], b[0][1], b[1][1], b[2][1], b[0][2], b[1][2], b[2][2]))
    W('\t],')
W('}\n')

# ---- objects ----
W('''# Mesh objects per background, with the material in each slot and the
# `lume_anim` custom property the artist wrote on it. The anim string is the
# authoring INTENT — background_scenes.gd maps it onto one of its own motion
# kinds; anything it does not recognise stays still, which is always safe.
const OBJECTS := {''')
for bg in ["BG_NeonGrid","BG_DeepSpace","BG_Circuit","BG_HexFloor",
           "BG_DarkMetal","BG_CrystalCave","BG_Volcanic","BG_ArcadeRoom"]:
    W('\t"%s": [' % bg)
    for o in d["objects"][bg]:
        slots = ", ".join('"%s"' % s for s in o["slots"])
        anim = o["anim"].replace('"', "'")
        W('\t\t{"name": "%s", "slots": [%s],' % (o["name"], slots))
        W('\t\t\t"anim": "%s"},' % anim)
    W('\t],')
W('}\n')

W("""# The radius at which SOLID geometry taller than z = 0.10 first appears, per
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
const TALL_RADIUS := {""")
for bg in ["BG_NeonGrid","BG_DeepSpace","BG_Circuit","BG_HexFloor",
           "BG_DarkMetal","BG_CrystalCave","BG_Volcanic","BG_ArcadeRoom"]:
    r = d.get("tall_radius", {}).get(bg)
    who = d.get("tall_object", {}).get(bg, "")
    if r is None:
        W('\t"%s": INF,' % bg)
    else:
        W('\t"%s": %.4f,   # %s' % (bg, r, who))
W('}\n')

W("""# How far out each background's STANDING furniture reaches, in Blender y — the
# largest y of any mesh more than 0.35 tall. `INF` means the scene has none: it is
# a floor, and there is nothing out there to be cut off by the top of the frame.
#
# 0.35 is not arbitrary. It sits above the tallest floor RELIEF in the set (the
# volcanic crust's plates at 0.27, Crystal Cave's displaced ground at 0.30) and
# below the shortest real standing object in it, so the two separate cleanly with
# nothing near the boundary.
#
# This is what decides whether a background is seated at all — see
# MemoryGameUI._seat_background. A floor needs no correction: its far edge running
# off the top of the frame is what a floor is supposed to do, and sliding it
# forward only drags the horizon band into view. A cabinet row does need one.
const FURNITURE_FAR_Y := {""")
for bg in ["BG_NeonGrid","BG_DeepSpace","BG_Circuit","BG_HexFloor",
           "BG_DarkMetal","BG_CrystalCave","BG_Volcanic","BG_ArcadeRoom"]:
    v = d.get("furniture_far_y", {}).get(bg)
    o = d.get("furniture_object", {}).get(bg, "")
    if v is None:
        W('\t"%s": INF,' % bg)
    else:
        W('\t"%s": %.4f,   # %s' % (bg, v, o))
W('}\n')

r = d["world"]["ramp"]
W('''# The Blender world: a vertical gradient on the generated-Z coordinate, i.e. a
# very dark blue-grey ambient that lifts towards the top of the dome. Godot's
# board viewport already owns its Environment (tuned for the buttons and NOT ours
# to change), so this is applied as the backdrop dome's own gradient instead.''')
W('const WORLD_RAMP := [')
for pos, col in r:
    W('\tColor(%.6f, %.6f, %.6f),   # ramp stop at %.2f' % (col[0], col[1], col[2], pos))
W(']')
W('const WORLD_RAMP_POS := [%s]' % ", ".join("%.4f" % p for p, _ in r))

open(sys.argv[2], "w").write("\n".join(out) + "\n")
print("wrote", sys.argv[2], len(out), "lines")
