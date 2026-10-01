"""Weld the downloaded monobloc (Poly Haven "Plastic Monobloc Chair 01" by Kuutti Siitonen, CC0; glTF 2.0 from the
owner's plastic+chair.zip, textures left out) into the one closed solid the kit loads.
    Blender --background --factory-startup --python weld_monobloc.py -- <folder with untitled.gltf> <out.npz>
The importer splits vertices at UV seams (3271 of them); welded at 1e-5 the chair is one closed island of 1660
vertices and 3356 triangles, facing -Y, Z up, 2.03 tall. The kit (CHAIR_MESH) turns and places it."""
import bpy, bmesh, sys
import numpy as np
src, out = sys.argv[sys.argv.index('--') + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src + '/untitled.gltf')
ob = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
bm = bmesh.new(); bm.from_mesh(ob.data); bm.transform(ob.matrix_world)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bad = sum(not e.is_manifold for e in bm.edges)
co = np.array([v.co[:] for v in bm.verts]); faces = np.array([[v.index for v in f.verts] for f in bm.faces])
print('welded: %d vertices, %d faces, %d non-manifold edges' % (len(co), len(faces), bad))
np.savez(out, co=co, faces=faces)
