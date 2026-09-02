"""Blender half of the AgX transfer measurement (see tools/agx_probe.gd).

    blender -b -P tools/agx_blender_ramp.py -- <out.png>

Renders a ramp of known linear emissive values through Blender's AgX view
transform with the "AgX - Punchy" look — the exact transform Themes2.blend renders
the six worlds with — into a strip of 16 px cells. tools/agx_probe.gd renders the
same ramp through Godot's TONE_MAPPER_AGX and prints the two side by side; the
difference between them is what WorldScenes.AGX_FIT corrects for.

The scene is built from factory settings so nothing in any .blend can influence it.
"""
import bpy, math, json, sys, os
OUT = sys.argv[sys.argv.index("--")+1]
VALS = [0.002, 0.002245, 0.00252, 0.002828, 0.003175, 0.003564, 0.004, 0.00449, 0.00504, 0.005657, 0.00635, 0.007127, 0.008, 0.00898, 0.010079, 0.011314, 0.012699, 0.014254, 0.016, 0.017959, 0.020159, 0.022627, 0.025398, 0.028509, 0.032, 0.035919, 0.040317, 0.045255, 0.050797, 0.057018, 0.064, 0.071838, 0.080635, 0.09051, 0.101594, 0.114035, 0.128, 0.143675, 0.16127, 0.181019, 0.203187, 0.22807, 0.256, 0.28735, 0.32254, 0.362039, 0.406375, 0.45614, 0.512, 0.574701, 0.64508, 0.724077, 0.812749, 0.91228, 1.024, 1.149401, 1.290159, 1.448155, 1.625499, 1.824561, 2.048, 2.298802, 2.580318, 2.896309, 3.250997, 3.649121, 4.096, 4.597605, 5.160637, 5.792619, 6.501995, 7.298242, 8.192, 9.195209, 10.321273, 11.585238, 13.003989, 14.596485, 16.384, 18.390418, 20.642546, 23.170475, 26.007979, 29.192969, 32.768, 36.780836]
# Also a saturated-hue ramp, to see how each transform desaturates.
HUES = []

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = len(VALS)*16
sc.render.resolution_y = (1+len(HUES))*16
sc.render.film_transparent = False
sc.view_settings.view_transform = 'AgX'
sc.view_settings.look = 'AgX - Punchy'
sc.view_settings.exposure = 0.0
sc.render.image_settings.file_format = 'PNG'
sc.render.image_settings.color_depth = '16'

cam_data = bpy.data.cameras.new("C"); cam = bpy.data.objects.new("C", cam_data)
sc.collection.objects.link(cam); sc.camera = cam
cam_data.type = 'ORTHO'; cam_data.ortho_scale = len(VALS)
cam.location = (len(VALS)/2.0, (1+len(HUES))/2.0, 10.0)

rows = [[(v,v,v) for v in VALS]] + [[(h[0]*v,h[1]*v,h[2]*v) for v in VALS] for h in HUES]
for r, row in enumerate(rows):
    for i, c in enumerate(row):
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=(i+0.5, r+0.5, 0))
        ob = bpy.context.object
        m = bpy.data.materials.new("m%d_%d" % (r, i)); m.use_nodes = True
        nt = m.node_tree
        for n in list(nt.nodes): nt.nodes.remove(n)
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        em = nt.nodes.new('ShaderNodeEmission')
        em.inputs['Color'].default_value = (c[0], c[1], c[2], 1.0)
        em.inputs['Strength'].default_value = 1.0
        nt.links.new(em.outputs[0], out.inputs['Surface'])
        ob.data.materials.append(m)

sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
json.dump({"vals": VALS, "hues": HUES}, open(OUT + ".json", "w"))
print("###OK###")
