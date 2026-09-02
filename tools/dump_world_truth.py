# Blender-side half of the Themes2 world import pipeline.
#
#   blender -b Themes2.blend -P tools/dump_world_truth.py -- <out.json>
#   python3 tools/gen_world_data.py <out.json> world_scenes_data.gd
#
# Writes the ground truth the .glb cannot carry: the Principled values behind each
# material (the .glb folds the vertex-colour scale into its factors and drops the
# "vertex colour also multiplies EMISSION" link entirely), and the AREA lights,
# which glTF has no representation for at all.
#
# Everything geometric is emitted in GODOT space already — Blender is Z-up and
# Godot is Y-up, so (x, y, z) -> (x, z, -y) — because that conversion is easy to
# get subtly wrong twice and there is no reason for the engine side to redo it.
import bpy, json, sys, math

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else "/tmp/lume_world_truth.json"

g = {}
for t in ['lume_lib', 'lume_stage', 'lume_sil', 'lume_bg', 'lume_lights',
          'lume_world', 'lume_anim', 'lume_kit', 'lume_themes']:
    exec(bpy.data.texts[t].as_string(), g)

THEMES = g['LUME_THEMES']
ORDER = g['LUME_ORDER']


def v3(v):
    """Blender world position -> Godot."""
    return [round(v[0], 5), round(v[2], 5), round(-v[1], 5)]


def basis(m):
    """Blender world basis -> Godot, row-major so the generator can read columns.

    A Blender area/sun light emits along its own -Z and so does a Godot
    DirectionalLight3D, so converting the frame is all that is needed for the
    orientation to carry across untouched.
    """
    # The object's three local axes, as Blender world vectors, re-expressed in
    # Godot world coordinates. The conversion is a proper rotation (det +1), so the
    # re-expressed axes are the Godot basis directly — no axis is swapped or
    # negated on top, because the light is the same physical object pointing the
    # same physical way.
    cols = [[m[r][c] for r in range(3)] for c in range(3)]
    gx, gy, gz = (v3(c) for c in cols)
    return [[gx[r], gy[r], gz[r]] for r in range(3)]


def light(o):
    L = o.data
    m = o.matrix_world
    return {
        "name": o.name, "type": L.type,
        "color": [round(c, 5) for c in L.color], "energy": round(L.energy, 4),
        "size": round(getattr(L, 'size', 0.0), 4),
        "size_y": round(getattr(L, 'size_y', 0.0), 4),
        "radius": round(getattr(L, 'shadow_soft_size', 0.0), 4),
        "origin": v3(m.translation), "basis": basis(m),
    }


def deck_bounds(o):
    """The play SURFACE's extent, in Blender x/y, ignoring the underside flare.

    Slot 0 of every `*_Platform` is the deck top; slots 1 and 2 are the rim wall and
    the rock mass hanging below it, both of which are wider than the surface the
    buttons actually stand on. `far` is how far out the deck reaches away from the
    camera (the tapered edge that opens the reveal band), `radius` how close its
    nearest boundary comes in the other three directions — which is what limits how
    far the world may be scaled down before a button overhangs the edge, and `top`
    is how high the surface itself stands (Blender z, which is Godot y). `top` is
    not decoration: an island deck is 55-78 mm ABOVE the origin the boards are built
    around, so anything the engine wants to lay ON the play surface has to be put
    there rather than at y = 0 — see MemoryGameUI's ground pools.
    """
    me = o.data
    xs, ys, zs = [], [], []
    for poly in me.polygons:
        if poly.material_index != 0:
            continue
        for vi in poly.vertices:
            v = o.matrix_world @ me.vertices[vi].co
            xs.append(v[0])
            ys.append(v[1])
            zs.append(v[2])
    if not xs:
        return None
    return {"far": round(max(ys), 4),
            "radius": round(min(max(xs), -min(xs), -min(ys)), 4),
            "top": round(max(zs), 4)}


def skyline(o, cam, scene):
    """Where this world's island stands highest in the REFERENCE frame.

    Returns the platform vertex with the smallest normalised v through
    LUME_Gameplay_Camera (v = 0 is the top of frame), and that v. Every game board
    looks at the island from a slightly different seat, and this is the one measured
    fact that lets the engine put the island's silhouette back where its author
    framed it: scale the world until this point lands on this v again, and the
    reveal band above the rim comes back at the size the composition was designed
    around. See WorldScenes.fit_scale.
    """
    from bpy_extras.object_utils import world_to_camera_view
    best_v, best_p = 2.0, None
    me = o.data
    for vtx in me.vertices:
        w = o.matrix_world @ vtx.co
        c = world_to_camera_view(scene, cam, w)
        if c.z <= 0.0:
            continue
        v = 1.0 - c.y          # Blender's y is up from the bottom; ours is down from the top
        if v < best_v:
            best_v, best_p = v, w
    if best_p is None:
        return None
    return {"v": round(best_v, 6), "point": v3(best_p)}


def principled(m):
    b = None
    for n in m.node_tree.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            b = n
            break
    if b is None:
        return None

    def const(sock, default):
        if sock not in b.inputs:
            return default
        i = b.inputs[sock]
        return list(i.default_value) if hasattr(i.default_value, '__len__') else i.default_value

    def mix(sock):
        """(constant colour, driven-by-vertex-colour) behind a socket.

        Every material in these six worlds is authored as
        MULTIPLY(A = a flat colour, B = the "Col" vertex attribute) — or as the
        flat colour alone where the mesh carries no colour attribute. Both cases
        collapse to the same pair.
        """
        if sock not in b.inputs:
            return [0.0, 0.0, 0.0, 1.0], False
        i = b.inputs[sock]
        if not i.is_linked:
            return list(i.default_value), False
        n = i.links[0].from_node
        if n.bl_idname in ('ShaderNodeMix', 'ShaderNodeMixRGB'):
            # ShaderNodeMix colour inputs are sockets 6 (A) and 7 (B).
            a = n.inputs[6]
            vc = n.inputs[7].is_linked
            return list(a.default_value), vc
        if n.bl_idname == 'ShaderNodeVertexColor':
            return [1.0, 1.0, 1.0, 1.0], True
        return [1.0, 1.0, 1.0, 1.0], False

    base, vc_base = mix('Base Color')
    emis, vc_emis = mix('Emission Color')
    alpha_linked = 'Alpha' in b.inputs and b.inputs['Alpha'].is_linked
    method = getattr(m, 'surface_render_method', getattr(m, 'blend_method', ''))
    return {
        "base": [round(c, 6) for c in base[:3]],
        "base_a": round(base[3] if len(base) > 3 else 1.0, 6),
        "vc_base": vc_base,
        "emis": [round(c, 6) for c in emis[:3]],
        "emis_strength": round(const('Emission Strength', 0.0), 6),
        "vc_emis": vc_emis,
        "vc_alpha": alpha_linked,
        "alpha": round(const('Alpha', 1.0), 6),
        "metallic": round(const('Metallic', 0.0), 6),
        "roughness": round(const('Roughness', 0.5), 6),
        "specular": round(const('Specular IOR Level', 0.5), 6),
        "ior": round(const('IOR', 1.45), 6),
        "blend": method in ('BLENDED', 'BLEND'),
    }


out = {
    "camera": None, "shared_base": g['LUME_LIGHT_BASE'], "worlds": {},
    "fps": bpy.context.scene.render.fps,
    "frame_range": [bpy.context.scene.frame_start, bpy.context.scene.frame_end],
}

cam = bpy.data.objects.get("LUME_Gameplay_Camera")
if cam is not None:
    bpy.context.view_layer.update()
    out["camera"] = {
        "origin": v3(cam.matrix_world.translation),
        "fov_x_deg": round(math.degrees(cam.data.angle_x), 4),
        "res": [bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y],
    }

for key in ORDER:
    t = THEMES[key]
    g['activate_theme'](key)
    bpy.context.view_layer.update()
    coll = bpy.data.collections[t['coll']]

    lights = [light(o) for o in coll.all_objects if o.type == 'LIGHT']
    # The six shared presentation panels light the world too, at whatever this
    # theme scaled and tinted them to. They are not in the collection and not in
    # the .glb, so they have to be captured here or the worlds arrive a stop dark.
    shared = []
    for n in g['SHARED']:
        o = bpy.data.objects.get(n)
        if o is not None:
            d = light(o)
            d["shared"] = True
            shared.append(d)

    objects = []
    mats = {}
    deck = None
    for o in coll.all_objects:
        if o.type != 'MESH':
            continue
        if o.name.endswith("_Platform"):
            deck = deck_bounds(o)
            if cam is not None:
                deck["skyline"] = skyline(o, cam, bpy.context.scene)
        slots = []
        for ms in o.material_slots:
            if ms.material is None:
                slots.append("")
                continue
            slots.append(ms.material.name)
            if ms.material.name not in mats:
                p = principled(ms.material)
                if p is not None:
                    mats[ms.material.name] = p
        has_col = any(a.name == 'Col' for a in o.data.color_attributes)
        objects.append({"name": o.name, "slots": slots, "vcol": has_col})

    out["worlds"][key] = {
        "coll": t['coll'], "prefix": t['prefix'], "label": t['label'],
        "exposure": t['exposure'], "tint": list(t['tint']),
        "lights": lights + shared, "objects": objects, "materials": mats,
        "deck": deck,
    }

json.dump(out, open(OUT, "w"), indent=1)
print("###WROTE### %s  worlds=%d" % (OUT, len(out["worlds"])))
