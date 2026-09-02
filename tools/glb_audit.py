# ---------------------------------------------------------------------------
# glb_audit -- what is actually inside a shipped .glb, without opening anything
# ---------------------------------------------------------------------------
# Reads the container directly (no bpy, no Godot, no import step) and prints the
# handful of facts that decide whether a "the model looks broken in engine" report
# is about the ASSET or about something downstream of it.
#
#   python3 tools/glb_audit.py models/buttons/Ice_Snowflake_*.glb
#
# Why this exists: twice now a skin has come in looking flat and jagged in Godot,
# and both times the mesh turned out to be correct and the cause was a material
# flag, a light rig or a viewport setting (see the shading-pipeline notes on
# lily_buttons.gd and ice_buttons.gd). Measuring the asset FIRST is what stops a
# day going into normals that were never wrong.
#
# What each column means, and what a bad value looks like:
#
#   attrs             POSITION/NORMAL/COLOR_0/TEXCOORD_0. A skin whose shading is
#                     painted into COLOR_0 renders as one flat slab if the engine
#                     drops it -- which Godot's glTF importer does by default
#                     (`vertex_color_use_as_albedo` comes in FALSE).
#   splitPos          how many vertex POSITIONS appear more than once. This is the
#                     sharp-edge test: a mesh with hard creases must split its
#                     vertices to carry two normals at them, so a near-zero count
#                     on a mesh that has folds means the shading data never left
#                     Blender. Near 900 of 2700 is a mesh whose creases survived.
#   maxSplit          the widest angle between two normals sharing one position,
#                     which is the size of the sharpest crease that did export.
#   degenerate        zero-area triangles.
#   non-unit          normals that are not normalised.
#   nonManifold       edges used by other than exactly two triangles, pooled ACROSS
#                     a mesh's primitives -- pooling matters: a two-material solid
#                     looks wide open if each material island is counted alone.
#   dupDir            edges traversed the same way twice, i.e. inconsistent face
#                     orientation. Zero is what a correctly wound solid gives.
#   nodes             every node at an identity transform, which is what a button
#                     that will be swapped onto a board's own node has to be.
import json, math, struct, sys
from collections import defaultdict


def load(path):
    d=open(path,'rb').read(); n=struct.unpack('<I',d[12:16])[0]
    js=json.loads(d[20:20+n]); off=20+n; b=b''
    while off<len(d):
        ln,ty=struct.unpack('<II',d[off:off+8])
        if ty==0x004E4942: b=d[off+8:off+8+ln]
        off+=8+ln
    return js,b
CT={5120:('b',1),5121:('B',1),5122:('h',2),5123:('H',2),5125:('I',4),5126:('f',4)}
NC={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}
def acc(js,bins,i):
    a=js['accessors'][i]; bv=js['bufferViews'][a['bufferView']]
    fmt,sz=CT[a['componentType']]; nc=NC[a['type']]
    base=bv.get('byteOffset',0)+a.get('byteOffset',0); stride=bv.get('byteStride') or sz*nc
    return [struct.unpack_from('<'+fmt*nc,bins,base+k*stride) for k in range(a['count'])]
for path in sys.argv[1:]:
    js,bins=load(path); name=path.split('/')[-1]
    tot_deg=tot_tri=0; bad_n=0; nonman=0; flipped=0; nodes_ok=True
    for nd in js.get('nodes',[]):
        t=nd.get('translation',[0,0,0]); r=nd.get('rotation',[0,0,0,1]); s=nd.get('scale',[1,1,1])
        if any(abs(v)>1e-6 for v in t) or abs(r[3]-1)>1e-6 or any(abs(v-1)>1e-6 for v in s):
            nodes_ok=False
        if 'matrix' in nd: nodes_ok=False
    for m in js['meshes']:
        ec=defaultdict(int); dirs=defaultdict(int)
        for p in m['primitives']:
            pos=acc(js,bins,p['attributes']['POSITION'])
            nrm=acc(js,bins,p['attributes']['NORMAL'])
            idx=[i[0] for i in acc(js,bins,p['indices'])]
            for v in nrm:
                if abs(math.sqrt(sum(c*c for c in v))-1.0)>0.02: bad_n+=1
            for k in range(0,len(idx),3):
                a,b,c=idx[k],idx[k+1],idx[k+2]; tot_tri+=1
                pa,pb,pc=pos[a],pos[b],pos[c]
                u=[pb[i]-pa[i] for i in range(3)]; w=[pc[i]-pa[i] for i in range(3)]
                cr=[u[1]*w[2]-u[2]*w[1],u[2]*w[0]-u[0]*w[2],u[0]*w[1]-u[1]*w[0]]
                if math.sqrt(sum(x*x for x in cr))<1e-12: tot_deg+=1
                # weld by position so shading splits don't look like holes
                key=lambda i:(round(pos[i][0],6),round(pos[i][1],6),round(pos[i][2],6))
                ka,kb,kc=key(a),key(b),key(c)
                for e in ((ka,kb),(kb,kc),(kc,ka)):
                    ec[frozenset(e)]+=1; dirs[e]+=1
        for e,n in ec.items():
            if n!=2: nonman+=1
        for e,n in dirs.items():
            if n>1: flipped+=1
    attrs=set(); dup=0; maxsplit=0.0
    for m in js['meshes']:
        for p in m['primitives']:
            attrs|=set(p['attributes'].keys())
            pos=acc(js,bins,p['attributes']['POSITION'])
            nrm=acc(js,bins,p['attributes'].get('NORMAL',p['attributes']['POSITION']))
            byp={}
            for v,nv in zip(pos,nrm):
                byp.setdefault(tuple(round(c,6) for c in v),[]).append(nv)
            for k,l in byp.items():
                if len(l)>1:
                    dup+=1
                    for i in range(len(l)):
                        for j in range(i+1,len(l)):
                            d=sum(a*b for a,b in zip(l[i],l[j]))
                            maxsplit=max(maxsplit,math.degrees(math.acos(max(-1,min(1,d)))))
            break     # the primitives of one mesh share their vertex arrays
    print("%-28s tris %5d  splitPos %4d  maxSplit %5.1fdeg  degenerate %d  non-unit %d  nonManifold %d  dupDir %d  nodes %s  [%s]"
          % (name, tot_tri, dup, maxsplit, tot_deg, bad_n, nonman, flipped,
             "identity" if nodes_ok else "MOVED", ",".join(sorted(attrs))))
