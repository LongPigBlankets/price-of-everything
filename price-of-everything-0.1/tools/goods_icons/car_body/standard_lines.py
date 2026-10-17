"""Two fixed image-space ink weights for Blender-rendered goods.
Uses solid ownership and visibility passes, then Euclidean strokes of one combined
interior centreline. Shading/highlights never participate in the ink mask.
"""
import json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt,binary_fill_holes


def stroke_projected(paths,feature,labels,box,scale,pos,size,width):
    """Stroke Blender's exact projected paths; raster data gates visibility only."""
    from PIL import ImageDraw
    factor=4;layer=Image.new('L',(size*factor,size*factor));draw=ImageDraw.Draw(layer)
    h,w=feature.shape
    for entry in paths:
        samples=np.asarray(entry['points'],float);visible=np.asarray(entry['visible'],bool)
        cumulative=np.r_[0,np.cumsum(np.linalg.norm(np.diff(samples,axis=0),axis=1))];fraction=cumulative/max(cumulative[-1],1e-9)
        closed_path=np.linalg.norm(samples[0]-samples[-1])<.01
        changes=np.diff(np.r_[False,visible,False].astype(int));starts=np.where(changes==1)[0];ends=np.where(changes==-1)[0]
        for start,end in zip(starts,ends):
            p=samples[start:end]
            if len(p)<2:continue
            length=float(np.linalg.norm(np.diff(p,axis=0),axis=1).sum())*scale
            touches_end=start==0 or end==len(samples)
            if length<1:continue
            # Tiny glimpses of a channel behind lugs read as detached dots.
            # Preserve designed open ends; suppress only short occluded fragments.
            if length<width*1.5 and (closed_path or not touches_end):continue
            transformed=[(((x-box[0])*scale+pos[0])*factor,((y-box[1])*scale+pos[1])*factor) for x,y in p]
            if entry.get('ink_width',0):
                # Port coal/iron ALONG_STROKE profiles to exact projected paths.
                # Evaluate on the entire path so an occlusion does not restart taper.
                # One joined polygon keeps kinks clean; pointed tips replace round caps.
                q=np.asarray(transformed);tangent=np.gradient(q,axis=0)
                tangent/=np.maximum(np.linalg.norm(tangent,axis=1)[:,None],1e-8)
                normal=np.column_stack((-tangent[:,1],tangent[:,0]))
                u=fraction[start:end];hump=1-np.abs(2*u-1)
                profile=entry['ink_tip']+(entry['ink_centre']-entry['ink_tip'])*hump
                radius=entry['ink_width']*(size/800)*factor*.5*profile
                left=q+normal*radius[:,None];right=q-normal*radius[:,None]
                draw.polygon([tuple(x) for x in np.concatenate((left,right[::-1]))],fill=255)
                continue
            # Butt ends at occlusion boundaries do not protrude into the upper solid.
            draw.line(transformed,fill=255,width=round(width*factor),joint='curve')
            for endpoint,real_end in [(transformed[0],start==0),(transformed[-1],end==len(samples))]:
                if real_end:
                    x,y=endpoint;r=width*factor/2
                    draw.ellipse((x-r,y-r,x+r,y+r),fill=255)
    return np.array(layer.resize((size,size),Image.Resampling.LANCZOS)).astype(float)/255


def standard_export(raw,out,size,margin,vib,outline,stipple_fn,vibrance_fn):
    prefix=raw[:-4];fill=np.array(Image.open(prefix+'_contour.png').convert('RGBA'))
    solid=fill[...,3]>120
    visible=np.array(Image.open(prefix+'_ink.png').convert('RGBA'))
    feature=(visible[...,0]>128)&(visible[...,3]>120)&solid
    labels=None
    source_feature=feature.copy()
    if outline.get('host_ownership'):
        host=np.array(Image.open(prefix+'_host_id.png').convert('RGBA'))
        ids=np.array(Image.open(prefix+'_id.png').convert('RGBA'))
        labels=np.rint(host[...,0].astype(float)/outline.get('id_step',32)).astype(int);labels[~solid]=0
        ink_labels=np.rint(ids[...,0].astype(float)/outline.get('id_step',32)).astype(int)
        feature &= labels==ink_labels
        source_feature=feature.copy()
    ys,xs=np.where(solid);box=(xs.min(),ys.min(),xs.max()+1,ys.max()+1)
    x0,y0,x1,y1=box
    pad=24
    def crop(a):
        p=[(pad,pad),(pad,pad)]+([(0,0)] if a.ndim==3 else [])
        return np.pad(a[y0:y1,x0:x1],p)
    rgba=crop(fill);lab=crop(labels) if labels is not None else None
    lighting=np.array(Image.open(prefix+'_mask.png').convert('RGBA'))[...,0]/255
    lit=crop(lighting**2.2)
    profile=Path(prefix+'_stipple.json');config=json.loads(profile.read_text()) if profile.exists() else None
    long_side=max(rgba.shape[:2])
    rgba=stipple_fn(rgba,lit,long_side*(config['spacing_fraction'] if config else .015),long_side*(config['dot_radius_fraction'] if config else .0036),config['strength'] if config else .42,lab,config)
    rgba=vibrance_fn(rgba,vib)
    rgba=rgba[pad:-pad,pad:-pad]
    weights=outline['standard_weights'];outer=weights['outer']*size/800;inner=weights['inner']*size/800
    target=int(round(size*(1-2*margin)-outer))
    scale=target/max(x1-x0,y1-y0);dims=(round((x1-x0)*scale),round((y1-y0)*scale));pos=((size-dims[0])//2,(size-dims[1])//2)
    canvas=Image.new('RGBA',(size,size));resized=Image.fromarray(rgba).resize(dims,Image.Resampling.LANCZOS);canvas.paste(resized,pos)
    a=np.array(canvas).astype(float)/255;body=a[...,3]>.5
    paths=json.loads(Path(prefix+'_paths.json').read_text())
    interior=stroke_projected(paths,source_feature,labels,box,scale,pos,size,inner)*body
    # Optional per-part weights (fertilisers, 2026-09-29, owner: "thinner linework on the leaves esp. the
    # outside"): outline['outer_by_label'] and outline['component_weight_by_label'] map a part label to
    # px at 800. Without them every weight below is exactly the set's, and exports are unchanged.
    outer_by=outline.get('outer_by_label') or {};component_by=outline.get('component_weight_by_label') or {}
    owned=None
    if labels is not None and (outline.get('component_boundaries') or outer_by):
        label_img=Image.fromarray(labels[y0:y1,x0:x1].astype('uint8')).resize(dims,Image.Resampling.NEAREST)
        full=Image.new('L',(size,size));full.paste(label_img,pos);owned=np.array(full)
    if outline.get('component_boundaries') and owned is not None:
        boundaries=np.zeros((size,size),float)
        for label in np.unique(owned):
            if label==0:continue
            mask=owned==label
            dist=distance_transform_edt(mask)-.5
            weight=component_by.get(str(label),outline.get('component_weight',weights['inner']))
            boundaries=np.maximum(boundaries,np.where(mask,np.clip(weight*size/800/2+.5-dist,0,1),0))
        interior=np.maximum(interior,boundaries*body)
    # Enclosed openings are interior boundaries: use6px there,12px on outer silhouette.
    filled=binary_fill_holes(body);holes=filled&~body
    inside=distance_transform_edt(filled)-.5;outside=distance_transform_edt(~filled)-.5
    signed=np.where(filled,inside,-outside)
    if outer_by and owned is not None:
        # Each silhouette pixel takes the outer weight of the part it belongs to (outside the body: the
        # part of the nearest body pixel).
        _,(iy,ix)=distance_transform_edt(~filled,return_indices=True)
        near=np.where(filled,owned,owned[iy,ix])
        width=np.full(near.shape,float(outer))
        for key,px in outer_by.items():width[near==int(key)]=px*size/800
        exterior=np.clip(width/2+.5-np.abs(signed),0,1)
    else:
        exterior=np.clip(outer/2+.5-np.abs(signed),0,1)
    if holes.any():
        signed_holes=np.where(holes,distance_transform_edt(holes)-.5,-distance_transform_edt(~holes)+.5)
        interior=np.maximum(interior,np.clip(inner/2+.5-np.abs(signed_holes),0,1))
    coverage=np.maximum(interior,exterior)
    ink=np.array([20,30,60])/255
    old_alpha=a[...,3];alpha=coverage+old_alpha*(1-coverage)
    rgb=(ink*coverage[...,None]+a[...,:3]*old_alpha[...,None]*(1-coverage[...,None]))/np.maximum(alpha[...,None],1e-8)
    result=np.dstack((rgb,alpha));Image.fromarray(np.rint(np.clip(result,0,1)*255).astype('uint8'),'RGBA').save(out)
    stem=str(Path(out).with_suffix(''))
    Image.fromarray(np.rint(interior*255).astype('uint8')).save(stem+'_interior_ink.png')
    Image.fromarray(np.rint(exterior*255).astype('uint8')).save(stem+'_exterior_ink.png')
    Path(stem+'_line_weights.json').write_text(json.dumps({'outer_px':outer,'inner_px':inner,'ore_taper':outline.get('ore_taper'),'metric':'Exact Blender projected paths; supersampled ore wedge profiles and Euclidean exterior band','solid_frame':list(map(int,box)),'scale':scale},indent=2))
    return out
