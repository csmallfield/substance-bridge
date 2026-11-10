"""Industrial canister for the mesh-adaptive painted metal test: a lathed body (foot ring, ribs, shoulder, neck), a
valve with side outlet and handwheel, a protective collar on three posts, bolts. One mesh, one non-overlapping UV map.
blender -b -P canister_blender.py -- <out_dir>     -> canister.glb, canister.obj
"""
import bpy, bmesh, math, sys, os

out_dir = sys.argv[sys.argv.index('--') + 1] if '--' in sys.argv else os.path.dirname(__file__)
bpy.ops.wm.read_factory_settings(use_empty=True)
SEG = 64


def lathe(profile, name, seg=SEG):
    bm = bmesh.new()
    rings = []
    for k in range(seg):
        a = 2 * math.pi * k / seg
        ring = []
        for r, z in profile:
            if r < 1e-6:
                ring.append(None)
            else:
                ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    poles = {}
    for j, (r, z) in enumerate(profile):
        if r < 1e-6:
            poles[j] = bm.verts.new((0, 0, z))
    for k in range(seg):
        A, B = rings[k], rings[(k + 1) % seg]
        for j in range(len(profile) - 1):
            a0, a1, b0, b1 = A[j], A[j + 1], B[j], B[j + 1]
            if a0 is None:
                bm.faces.new((poles[j], b1, a1))
            elif a1 is None:
                bm.faces.new((a0, b0, poles[j + 1]))
            else:
                bm.faces.new((a0, b0, b1, a1))
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def add(op, **kw):
    op(**kw)
    return bpy.context.active_object


def bevel(ob, width, seg=2, angle=40):
    m = ob.modifiers.new('bevel', 'BEVEL')
    m.width, m.segments, m.limit_method, m.angle_limit = width, seg, 'ANGLE', math.radians(angle)
    m.harden_normals = False


# --- body (lathe), radii and heights in metres, z up ---------------------------------------------------------------
P = [(0.0, 0.03), (0.17, 0.026), (0.198, 0.004), (0.205, 0.0), (0.244, 0.0), (0.25, 0.006), (0.25, 0.05),
     (0.244, 0.056), (0.236, 0.062), (0.24, 0.07),
     (0.24, 0.235), (0.244, 0.24), (0.252, 0.246), (0.252, 0.274), (0.244, 0.28), (0.24, 0.285),
     (0.24, 0.605), (0.244, 0.61), (0.252, 0.616), (0.252, 0.644), (0.244, 0.65), (0.24, 0.655),
     (0.24, 0.79)]
for k in range(1, 13):                                       # shoulder: quarter ellipse from r 0.24 to the neck
    t = k / 12 * math.pi / 2
    P.append((0.062 + 0.178 * math.cos(t), 0.79 + 0.16 * math.sin(t)))
P += [(0.062, 0.965), (0.066, 0.97), (0.078, 0.972), (0.08, 0.976), (0.08, 0.996), (0.076, 1.0), (0.0, 1.0)]
body = lathe(P, 'body')
bevel(body, 0.0025, 2, 30)

parts = [body]
# --- valve ------------------------------------------------------------------------------------------------------------
v = add(bpy.ops.mesh.primitive_cylinder_add, vertices=32, radius=0.036, depth=0.075, location=(0, 0, 1.0375)); bevel(v, 0.003)
parts.append(v)
v = add(bpy.ops.mesh.primitive_cylinder_add, vertices=6, radius=0.046, depth=0.018, location=(0, 0, 1.009)); bevel(v, 0.002)
parts.append(v)                                              # hex collar nut at the neck
o = add(bpy.ops.mesh.primitive_cylinder_add, vertices=24, radius=0.016, depth=0.07, location=(0.06, 0, 1.04),
        rotation=(0, math.pi / 2, 0)); bevel(o, 0.002)
parts.append(o)
o = add(bpy.ops.mesh.primitive_cylinder_add, vertices=6, radius=0.024, depth=0.022, location=(0.1, 0, 1.04),
        rotation=(0, math.pi / 2, 0)); bevel(o, 0.002)
parts.append(o)
o = add(bpy.ops.mesh.primitive_cylinder_add, vertices=16, radius=0.009, depth=0.04, location=(0, 0, 1.09))
parts.append(o)                                              # stem
w = add(bpy.ops.mesh.primitive_torus_add, major_radius=0.055, minor_radius=0.0075, major_segments=48, minor_segments=12,
        location=(0, 0, 1.11))
parts.append(w)
o = add(bpy.ops.mesh.primitive_cylinder_add, vertices=20, radius=0.014, depth=0.018, location=(0, 0, 1.11)); bevel(o, 0.002)
parts.append(o)                                              # hub
for k in range(3):
    a = 2 * math.pi * k / 3
    s = add(bpy.ops.mesh.primitive_cylinder_add, vertices=10, radius=0.005, depth=0.05,
            location=(0.031 * math.cos(a), 0.031 * math.sin(a), 1.11), rotation=(0, math.pi / 2, a))
    parts.append(s)

# --- collar: ring on three flat posts, bolted at the shoulder ------------------------------------------------------------
RC = 0.165
ring = add(bpy.ops.mesh.primitive_torus_add, major_radius=RC, minor_radius=0.013, major_segments=64, minor_segments=14,
           location=(0, 0, 1.075))
parts.append(ring)


def shoulder_z(r):
    t = math.acos(min(1.0, (r - 0.062) / 0.178))
    return 0.79 + 0.16 * math.sin(t)


for k in range(3):
    a = 2 * math.pi * k / 3 + math.pi / 6
    z0 = shoulder_z(RC) - 0.01
    h = 1.075 - z0
    post = add(bpy.ops.mesh.primitive_cube_add, size=1, location=(RC * math.cos(a), RC * math.sin(a), z0 + h / 2),
               rotation=(0, 0, a))
    post.scale = (0.014, 0.034, h)
    bpy.ops.object.transform_apply(scale=True)
    bevel(post, 0.003)
    parts.append(post)
    foot = add(bpy.ops.mesh.primitive_cube_add, size=1, location=(RC * math.cos(a), RC * math.sin(a), z0 + 0.004),
               rotation=(0, -0.0, a))
    foot.scale = (0.05, 0.05, 0.012)
    bpy.ops.object.transform_apply(scale=True)
    bevel(foot, 0.003)
    parts.append(foot)
    for s in (-1, 1):                                        # two bolts per foot
        bx = RC * math.cos(a) + s * 0.015 * -math.sin(a)
        by = RC * math.sin(a) + s * 0.015 * math.cos(a)
        b = add(bpy.ops.mesh.primitive_cylinder_add, vertices=6, radius=0.007, depth=0.008,
                location=(bx, by, z0 + 0.012)); bevel(b, 0.0012)
        parts.append(b)

# --- a bolted name plate band on the body ------------------------------------------------------------------------------
plate = add(bpy.ops.mesh.primitive_cylinder_add, vertices=96, radius=0.2445, depth=0.16, location=(0, 0, 0.445),
            end_fill_type='NOTHING')
bm = bmesh.new(); bm.from_mesh(plate.data)
kill = [f for f in bm.faces if not (-0.45 < math.atan2(f.calc_center_median().y, f.calc_center_median().x) < 0.45)]
bmesh.ops.delete(bm, geom=kill, context='FACES')
bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=-0.006)
bm.to_mesh(plate.data); bm.free()
bevel(plate, 0.0015, 2, 30)
parts.append(plate)
for zz in (0.38, 0.51):
    for aa in (-0.38, 0.38):
        b = add(bpy.ops.mesh.primitive_cylinder_add, vertices=12, radius=0.006, depth=0.008,
                location=(0.2505 * math.cos(aa), 0.2505 * math.sin(aa), zz), rotation=(0, math.pi / 2, aa)); bevel(b, 0.0015)
        parts.append(b)

# --- join, apply modifiers, smooth by angle, UV unwrap ---------------------------------------------------------------------
bpy.ops.object.select_all(action='DESELECT')
for p_ in parts:
    p_.select_set(True)
    bpy.context.view_layer.objects.active = p_
    for m in list(p_.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
ob = bpy.context.active_object
ob.name = 'canister'
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=1e-5)
bpy.ops.mesh.normals_make_consistent(inside=False)          # the solidified name plate came out inside-out
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, scale_to_bounds=False)
bpy.ops.uv.select_all(action='SELECT')
bpy.ops.uv.average_islands_scale()                           # even texel density across parts
bpy.ops.uv.pack_islands(rotate=True, margin=0.004)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
for m in list(ob.modifiers):
    bpy.ops.object.modifier_apply(modifier=m.name)
print('canister: %d verts, %d faces' % (len(ob.data.vertices), len(ob.data.polygons)))
os.makedirs(out_dir, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, 'canister.glb'), export_format='GLB', use_selection=True,
                          export_yup=True, export_apply=True)
bpy.ops.wm.obj_export(filepath=os.path.join(out_dir, 'canister.obj'), export_selected_objects=True,
                      forward_axis='NEGATIVE_Z', up_axis='Y', export_materials=False)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, 'canister.blend'))
