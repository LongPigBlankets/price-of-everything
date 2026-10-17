#!/usr/bin/env python3
"""Read-only Stoneshore road alternatives from compare_stoneshore's numeric plan.
No roads, gameplay data, or bakes are modified. Pillow is only used for the plan.
"""
import argparse
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def distance(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def closest(p, a, b):
    v = (b[0] - a[0], b[1] - a[1])
    length = v[0] ** 2 + v[1] ** 2
    t = max(0, min(1, ((p[0]-a[0])*v[0] + (p[1]-a[1])*v[1]) / length)) if length else 0
    return [a[0]+v[0]*t, a[1]+v[1]*t]


def inside(p, poly):
    result = False
    for a, b in zip(poly, poly[1:]+poly[:1]):
        if (a[1]>p[1]) != (b[1]>p[1]) and p[0] < (b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]:
            result = not result
    return result


def poly_distance(p, poly):
    if inside(p, poly):
        return 0
    return min(distance(p, closest(p,a,b)) for a,b in zip(poly,poly[1:]+poly[:1]))


def samples(path, step=2):
    for a,b in zip(path,path[1:]):
        count = max(1, math.ceil(distance(a,b)/step))
        for i in range(count):
            yield [a[0]+(b[0]-a[0])*i/count, a[1]+(b[1]-a[1])*i/count]
    yield path[-1]


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument('plan', type=Path)
    args.add_argument('output', type=Path)
    args = args.parse_args()
    data = json.loads(args.plan.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    roads = data['roads']
    def road_point(p, sources):
        candidates=[closest(p,r['a'],r['b']) for r in roads if r['source'] in sources]
        return min(candidates, key=lambda q:distance(p,q))
    coast_end = [2900.43359375,5637.9482421875]
    def yard_point(x,y):
        yaw=data['depots'][0]['yaw']
        return [2790+x*math.cos(yaw)-y*math.sin(yaw),5550+x*math.sin(yaw)+y*math.cos(yaw)]
    routes = [
        {'name':'A · Around the closed end', 'color':'#b47830', 'path':[
            coast_end,[2860,5660],[2815,5676],yard_point(165,-65),yard_point(165,40),
            road_point([2665,5653],['r:untitled:66'])]},
        {'name':'B · East-side access', 'color':'#078279', 'path':[
            coast_end,[2875,5590],[2887,5510],[2910,5450],[2924,5400],[2938,5345],
            road_point([2940,5290],['r:procedural:159','r:procedural:48'])]},
    ]
    rail = [t for t in data['rails'] if not t['hidden']]
    half_width = 6.8  # 8.4u two-lane carriageway, casing + urban sidewalks.
    yard = []
    for depot in data['depots']:
        c,s=math.cos(depot['yaw']),math.sin(depot['yaw'])
        yard.append([[depot['pos'][0]+x*c-y*s,depot['pos'][1]+x*s+y*c]
                     for x,y in [(-145,-47),(145,-47),(145,57),(-145,57)]])
    for route in routes:
        pts=list(samples(route['path']))
        overlaps={}
        water=0
        for p in pts:
            if not all(any(inside(q,land) for land in data['land']) for q in [p,[p[0]+half_width,p[1]],[p[0]-half_width,p[1]],[p[0],p[1]+half_width],[p[0],p[1]-half_width]]):
                water+=1
            for building in data['buildings']:
                if any(poly_distance(p,poly)<half_width+1 for poly in building['polygons']):
                    overlaps[building['iid']]=building['kind']
        route.update(length=sum(distance(a,b) for a,b in zip(route['path'],route['path'][1:])),
                     minimum_rail_center_distance=min(distance(p,closest(p,t['a'],t['b'])) for p in pts for t in rail),
                     minimum_yard_edge_distance=min(poly_distance(p,poly) for p in pts for poly in yard),
                     water_shoulder_samples=water, building_conflicts=overlaps,
                     road_half_width=half_width, samples=len(pts))
    report={'scope':'Five-tile Stoneshore; read-only 2D routing concepts, not engineered roads',
            'limitations':'Heights, smooth bends, sidewalks, junction grades and final re-placement require a follow-up 3D engineering pass.',
            'routes':routes}
    (args.output/'routes.json').write_text(json.dumps(report,indent=2))
    render(data, routes, args.output/'depot-options.png')
    print(json.dumps(report,indent=2))


def render(data, routes, path):
    # Draw vector-plan data, not a modification of a game screenshot.
    scale=2.0
    origin=(2530,5180)
    im=Image.new('RGB',(1400,1320),'#f5f4ef');d=ImageDraw.Draw(im)
    font_path='/System/Library/Fonts/Supplemental/Arial.ttf'
    def face(size):
        try:
            return ImageFont.truetype(font_path,size)
        except OSError:
            return ImageFont.load_default()
    font=face(20);small=face(17);title=face(29)
    def xy(p):return ((p[0]-origin[0])*scale+40,(p[1]-origin[1])*scale+90)
    d.rectangle((40,90,1090,1290),fill='#dceaf0')
    for poly in data['land']:
        if max(p[0] for p in poly)>2530 and min(p[0] for p in poly)<3055 and max(p[1] for p in poly)>5180 and min(p[1] for p in poly)<5780:
            d.polygon([xy(p) for p in poly],fill='#dedfc3')
    for building in data['buildings']:
        for poly in building['polygons']:
            if not all(2530<p[0]<3055 and 5180<p[1]<5780 for p in poly):continue
            d.polygon([xy(p) for p in poly],fill='#b5b3aa' if building['kind']=='house' else '#8e9aab',outline='#888b8d')
    for road in data['roads']:
        if not 2500<road['a'][0]<3100 or not 5100<road['a'][1]<5800:continue
        d.line([xy(road['a']),xy(road['b'])],fill='#737c83',width=max(2,round(road['half']*2*scale)))
    for rail in data['rails']:
        if 2500<rail['a'][0]<3100 and 5100<rail['a'][1]<5800:
            d.line([xy(rail['a']),xy(rail['b'])],fill='#c4b6ab' if rail['hidden'] else '#614d3f',width=3)
    for depot in data['depots']:
        c,s=math.cos(depot['yaw']),math.sin(depot['yaw'])
        shed=[[depot['pos'][0]+x*c-y*s,depot['pos'][1]+x*s+y*c] for x,y in [(43,-27),(112,-27),(112,27),(43,27)]]
        d.polygon([xy(p) for p in shed],fill='#52776b',outline='#355c50')
        d.text(xy([2750,5600]),'DEPOT',font=small,fill='#213f35')
    for road in data['roads']:
        if road['source']=='r:untitled:65':d.line([xy(road['a']),xy(road['b'])],fill='#c8544e',width=9)
    for route in routes:
        d.line([xy(p) for p in route['path']],fill=route['color'],width=8,joint='curve')
        for p in [route['path'][0],route['path'][-1]]:
            x,y=xy(p);d.ellipse((x-6,y-6,x+6,y+6),fill=route['color'])
    # Mask excess polygons outside the framed plan.
    d.rectangle((0,0,1400,87),fill='#f5f4ef');d.rectangle((1092,88,1400,1320),fill='#f5f4ef')
    d.rectangle((0,1292,1400,1320),fill='#f5f4ef');d.rectangle((0,88,37,1320),fill='#f5f4ef')
    d.text((40,20),'Stoneshore depot · road alternatives',font=title,fill='#26384a')
    d.text((40,57),'Plan view · concepts only · existing rail and buildings retained in grey/brown',font=small,fill='#53616a')
    labels=[('Existing spur','#c8544e'),('A · Closed end',routes[0]['color']),('B · East side',routes[1]['color']),('Surface railway','#614d3f')]
    for i,(name,color) in enumerate(labels):
        y=110+i*65;d.line((1120,y+10,1160,y+10),fill=color,width=7);d.text((1120,y+26),name,font=small,fill='#26384a')
    y=430
    for r in routes:
        d.text((1120,y),r['name'].split(' · ')[0],font=title,fill=r['color'])
        lines=[f"{r['length']:.0f}u road",f"{r['minimum_rail_center_distance']:.1f}u to rail",f"{len(r['building_conflicts'])} footprint hits",f"{r['water_shoulder_samples']} wet samples"]
        for i,line in enumerate(lines):d.text((1120,y+40+i*28),line,font=small,fill='#53616a')
        y+=200
    d.line((70,1240,270,1240),fill='#26384a',width=3);d.text((70,1250),'100u',font=small,fill='#26384a')
    im.save(path)


if __name__=='__main__':main()
