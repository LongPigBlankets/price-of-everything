"""Offline, periodic capsule puffs. Executed in the capsule kit namespace."""
from mathutils import Matrix


class LoadingSmokeLoop:
    FRAMES = 12
    SECONDS = 1.5

    def __init__(self, stacks):
        self.col = bpy.data.collections.new('LoadingSmokeLoop')
        bpy.context.scene.collection.children.link(self.col)
        kit = Kit(self.col)
        kit._fine_mode = True
        wx, wy = map_to_world(WIND_MAP[0], WIND_MAP[1], PLATE_YAW)
        ox, oy = map_to_world(0, 0, PLATE_YAW)
        self.wind = Vector((wx-ox, wy-oy, 0)).normalized()
        self.plumes = []
        for stack, (kind, rise, drift, r_end) in stacks.items():
            mouth, r0 = _mouth(bpy.data.objects[stack])
            cloud = _puff_spheres(random.Random(stack))
            mats = (kit.mat(kind+'_puff'), kit.mat(kind+'_patch'))
            groups = []
            # Identical source puffs vary continuously with age, rather than slot
            # identity: phase 1 is exactly phase 0 with the slots permuted.
            for slot in range(7):
                groups.append([_sphere(kit, f'Loop.{stack}.{slot}.{i}', c, r,
                    mats[1 if patch else 0]) for i, (c, r, patch) in enumerate(cloud)])
            anchor = [_sphere(kit, f'Mouth.{stack}.{i}', c, r,
                mats[1 if patch else 0]) for i, (c, r, patch) in enumerate(cloud)]
            anchor_matrix = Matrix.Translation(mouth+Vector((0,0,r0*.25))) @ Matrix.Scale(r0*.52, 4)
            for ob in anchor:
                ob.matrix_world = anchor_matrix
            self.plumes.append((mouth, r0, rise, drift, r_end, groups))
        self.set_phase(0)
        start = self.pose()
        self.set_phase(1)
        assert self.pose() == start, 'Smoke loop does not close under slot permutation'
        self.set_phase(0)

    def pose(self):
        return sorted(tuple(float(v) for row in group[0].matrix_world for v in row)
            for *_, groups in self.plumes for group in groups)

    @staticmethod
    def smooth(a, b, x):
        t = max(0, min(1, (x-a)/(b-a)))
        return t*t*(3-2*t)

    def set_phase(self, phase):
        for mouth, r0, rise, drift, r_end, groups in self.plumes:
            for slot, group in enumerate(groups):
                age = ((slot+phase)/len(groups)) % 1
                # Start slowly just above the mouth, then rise and bend downwind.
                # The first live puff overlaps the mouth cluster instead of leaving a gap.
                centre = mouth + self.wind*(drift*age**2) + Vector((0,0,rise*self.smooth(0,1,age)))
                radius = r0*1.4 + (r_end-r0*1.4)*min(1, age/BREAK_UP)**.8
                birth = self.smooth(0, .10, age)
                death = 1-self.smooth(.72, 1, age)
                radius *= birth*death
                centre.z += radius*.55
                matrix = Matrix.Translation(centre) @ Matrix.Rotation(age*1.7,4,'Z') @ Matrix.Scale(max(.0001,radius/1.6),4)
                for ob in group:
                    ob.matrix_world = matrix
                    ob.hide_render = radius < .002

    def hide(self):
        for ob in self.col.objects:
            ob.hide_render = True
