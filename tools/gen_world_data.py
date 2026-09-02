"""Generate world_scenes_data.gd from the Blender truth dump.

    blender -b Themes2.blend -P tools/dump_world_truth.py -- tools/lume_world_truth.json
    python3 tools/gen_world_data.py tools/lume_world_truth.json world_scenes_data.gd

See world_scenes.gd's header for why the .glb alone is not enough.
"""
import json, sys

d = json.load(open(sys.argv[1]))
dest = sys.argv[2] if len(sys.argv) > 2 else "world_scenes_data.gd"
ORDER = ["Ice", "Forest"]

out = []
W = out.append

W('''# GENERATED - do not hand-edit. Regenerate with:
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
''')

W('''# Per-material Principled values.
#   base / emis    linear colour; `vc_*` says the "Col" attribute multiplies it
#   emis_strength  Blender's Emission Strength (already folded through nothing —
#                  world_scenes.gd applies the exposure match itself)
#   vc_alpha       Alpha is driven by the attribute's own alpha channel
#   blend          real alpha blending; the rest are Blender's dithered mode,
#                  which at alpha 1.0 is indistinguishable from opaque
const MATERIALS := {''')
seen = {}
for w in ORDER:
    for name in sorted(d["worlds"][w]["materials"]):
        if name in seen:
            continue
        seen[name] = True
        m = d["worlds"][w]["materials"][name]
        W('\t"%s": {' % name)
        W('\t\t"base": Color(%.6f, %.6f, %.6f), "base_a": %.4f, "vc_base": %s,'
          % (m["base"][0], m["base"][1], m["base"][2], m["base_a"],
             "true" if m["vc_base"] else "false"))
        W('\t\t"emis": Color(%.6f, %.6f, %.6f), "emis_strength": %.6f, "vc_emis": %s,'
          % (m["emis"][0], m["emis"][1], m["emis"][2], m["emis_strength"],
             "true" if m["vc_emis"] else "false"))
        W('\t\t"alpha": %.4f, "vc_alpha": %s, "blend": %s,'
          % (m["alpha"], "true" if m["vc_alpha"] else "false",
             "true" if m["blend"] else "false"))
        W('\t\t"metallic": %.4f, "roughness": %.4f, "specular": %.4f, "ior": %.4f},'
          % (m["metallic"], m["roughness"], m["specular"], m["ior"]))
W('}\n')

W('''# Every light that shapes a world, in Godot space. The first block of each list
# is the world's own rig; entries marked `shared` are the six LUME presentation
# panels at the multiplier and tint this theme scales them to (see the .blend's
# `lume_lights` / `activate_theme`) — untouched originals that only this theme's
# activation re-weights, which is why they are captured per world rather than once.
const LIGHTS := {''')
for w in ORDER:
    W('\t"%s": [' % w)
    for L in d["worlds"][w]["lights"]:
        b = L["basis"]
        c = L["color"]
        o = L["origin"]
        W('\t\t{"name": "%s", "type": "%s", "energy": %.4f, "shared": %s,'
          % (L["name"], L["type"], L["energy"], "true" if L.get("shared") else "false"))
        W('\t\t\t"color": Color(%.5f, %.5f, %.5f), "size": %.4f, "size_y": %.4f, "radius": %.4f,'
          % (c[0], c[1], c[2], L["size"], L["size_y"], L["radius"]))
        W('\t\t\t"origin": Vector3(%.5f, %.5f, %.5f),' % (o[0], o[1], o[2]))
        W('\t\t\t"basis": Basis(Vector3(%.6f, %.6f, %.6f), Vector3(%.6f, %.6f, %.6f), Vector3(%.6f, %.6f, %.6f))},'
          % (b[0][0], b[1][0], b[2][0], b[0][1], b[1][1], b[2][1], b[0][2], b[1][2], b[2][2]))
    W('\t],')
W('}\n')

W('''# Mesh objects per world, with the material in each slot, in the order the
# exporter wrote the primitives. `vcol` is whether the mesh actually carries the
# "Col" attribute: a material may ask for it on a mesh that has none, and Godot
# hands the shader white in that case, which is the same thing Blender's own
# exporter concluded when it wrote the flat factor into the .glb.
const OBJECTS := {''')
for w in ORDER:
    W('\t"%s": [' % w)
    for o in d["worlds"][w]["objects"]:
        slots = ", ".join('"%s"' % s for s in o["slots"])
        W('\t\t{"name": "%s", "slots": [%s], "vcol": %s},'
          % (o["name"], slots, "true" if o["vcol"] else "false"))
    W('\t],')
W('}\n')

W('''# Blender's view-transform exposure for each world, as `activate_theme` sets it.
# world_scenes.gd turns this into the linear pre-scale that makes the same light
# reach AgX in both engines (see EXPOSURE_MATCH).
const EXPOSURE := {''')
for w in ORDER:
    W('\t"%s": %.4f,' % (w, d["worlds"][w]["exposure"]))
W('}\n')

W("""# The island's own silhouette, measured through the reference camera.
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
const DECK := {""")
for w in ORDER:
    k = d["worlds"][w]["deck"]
    sk = k["skyline"]
    W('\t"%s": {"far": %.4f, "radius": %.4f, "top": %.4f, "skyline_v": %.6f,'
      % (w, k["far"], k["radius"], k["top"], sk["v"]))
    W('\t\t"skyline": Vector3(%.5f, %.5f, %.5f)},'
      % (sk["point"][0], sk["point"][1], sk["point"][2]))
W('}\n')

cam = d["camera"]
W('''# The camera both were composed against: LUME_Gameplay_Camera, unmoved, at a
# %.2f deg horizontal lens on a %dx%d frame. The shop preview uses exactly this
# pose so a card frames a world the way its author did.
const REF_CAM_ORIGIN := Vector3(%.4f, %.4f, %.4f)
const REF_CAM_FOV := %.4f
''' % (cam["fov_x_deg"], cam["res"][0], cam["res"][1],
       cam["origin"][0], cam["origin"][1], cam["origin"][2], cam["fov_x_deg"]))

W('''# The authored loop: %d frames at %d fps, with frame %d keyed identical to frame 1,
# so the clip is exactly %.4f s long and the last key sits one frame before the repeat.
const LOOP_FPS := %d
const LOOP_FRAMES := %d
const LOOP_SECONDS := %.6f
''' % (d["frame_range"][1], d["fps"], d["frame_range"][1] + 1,
       d["frame_range"][1] / float(d["fps"]), d["fps"], d["frame_range"][1],
       d["frame_range"][1] / float(d["fps"])))

open(dest, "w").write("\n".join(out) + "\n")
print("wrote %s (%d lines)" % (dest, len(out)))
