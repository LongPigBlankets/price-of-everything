"""Goods lettering: Arial Bold, native aspect, explicit chemical subscript runs."""
import re,hashlib
from pathlib import Path
import bpy,bmesh
FONT_PATH='/System/Library/Fonts/Supplemental/Arial Bold.ttf'
SUBSCRIPT_SCALE=.68
SUBSCRIPT_DROP=.13

def formula_mesh(collection,name,text,material,width,height,chemical=True):
    """Return one centred mesh in local XY; caller maps it to the actual surface.
    Width/height are bounds, not separate stretch factors. Unicode subscript digits
    normalize to ASCII and are deliberately smaller/lowered with the same font.
    """
    font_path=Path(FONT_PATH);assert font_path.exists(),FONT_PATH
    text=text.translate(str.maketrans('₀₁₂₃₄₅₆₇₈₉','0123456789'))
    font=bpy.data.fonts.load(str(font_path));runs=re.findall(r'\d+|\D+',text) if chemical else [text]
    vertices=[];faces=[];pen=0.
    for run in runs:
        sub=chemical and run.isdigit();size=SUBSCRIPT_SCALE if sub else 1.;drop=-SUBSCRIPT_DROP if sub else 0.
        cu=bpy.data.curves.new(name+'_run','FONT');cu.font=font;cu.body=run;cu.size=size;cu.align_x='LEFT';cu.align_y='BOTTOM_BASELINE';cu.resolution_u=16
        ob=bpy.data.objects.new(name+'_run',cu);collection.objects.link(ob);bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob;bpy.ops.object.convert(target='MESH');ob=bpy.context.object
        xs=[v.co.x for v in ob.data.vertices];xmin=min(xs);xmax=max(xs);offset=len(vertices)
        vertices.extend((pen+v.co.x-xmin,v.co.y+drop,0.) for v in ob.data.vertices);faces.extend(tuple(offset+i for i in f.vertices) for f in ob.data.polygons)
        pen+=xmax-xmin+.035;bpy.data.objects.remove(ob,do_unlink=True)
    xmin=min(v[0] for v in vertices);xmax=max(v[0] for v in vertices);ymin=min(v[1] for v in vertices);ymax=max(v[1] for v in vertices);factor=min(width/(xmax-xmin),height/(ymax-ymin));cx=(xmin+xmax)/2;cy=(ymin+ymax)/2
    vertices=[((x-cx)*factor,(y-cy)*factor,z) for x,y,z in vertices]
    me=bpy.data.meshes.new(name);me.from_pydata(vertices,[],faces);me.update();ob=bpy.data.objects.new(name,me);collection.objects.link(ob);me.materials.append(material)
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.triangulate(bm,faces=bm.faces[:]);bmesh.ops.subdivide_edges(bm,edges=bm.edges[:],cuts=3,use_grid_fill=True);bm.to_mesh(me);bm.free()
    ob['font_family']='Arial';ob['font_style']='Bold';ob['font_sha256']=hashlib.sha256(font_path.read_bytes()).hexdigest();ob['formula']=text;ob['subscript_scale']=SUBSCRIPT_SCALE;ob['subscript_drop_em']=SUBSCRIPT_DROP;ob['native_glyph_aspect']=True;ob.pass_index=73
    return ob
