import math
import os

import bpy
import bmesh

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "LilAgent", "Resources", "bed.glb")

MATTRESS_TOP = 0.62
PILLOW_TOP = 0.97


bpy.ops.wm.read_factory_settings(use_empty=True)


def gl(x, y, z):
    return (x, -z, y)


def material(name, rgb, rough=0.6, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = 0
    if coat:
        p.inputs["Coat Weight"].default_value = coat
        p.inputs["Coat Roughness"].default_value = 0.3
    return m


def srgb(h):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return tuple(lin(int(h[i:i + 2], 16)) for i in (1, 3, 5))


NAVY = material("BedFrame", srgb("#2B3A8C"), rough=0.45, coat=0.3)
WHITE = material("BedLinen", srgb("#F7F5F0"), rough=0.85)
PILLOW = material("BedPillow", srgb("#D6E3FF"), rough=0.85)
STRIPE = material("BedStripe", srgb("#4F72E8"), rough=0.8)


def block(name, lo, hi, bevel, mat, parent, segments=4, subdiv=1, cuts=0):
    cx, cy, cz = ((a + b) / 2 for a, b in zip(lo, hi))
    sx, sy, sz = ((b - a) for a, b in zip(lo, hi))
    bpy.ops.mesh.primitive_cube_add(size=1, location=gl(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (sx, sz, sy)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    if cuts:
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.subdivide(number_cuts=cuts)
        bpy.ops.object.mode_set(mode="OBJECT")
    b = o.modifiers.new("bevel", "BEVEL")
    b.width = bevel
    b.segments = segments
    b.limit_method = "ANGLE" if cuts else "NONE"
    if subdiv:
        s = o.modifiers.new("smooth", "SUBSURF")
        s.levels = subdiv
        s.render_levels = subdiv
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    o.parent = parent
    return o


def apply_modifiers(o):
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


root = bpy.data.objects.new("bed", None)
bpy.context.scene.collection.objects.link(root)

block("bed_rail", (-3.05, 0.14, -1.8), (1.6, 0.44, 1.8), 0.12, NAVY, root)
for x in (-2.85, 1.4):
    for z in (-1.55, 1.55):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.16, depth=0.2, location=gl(x, 0.1, z), vertices=24)
        f = bpy.context.active_object
        f.name = "bed_foot"
        f.data.materials.append(NAVY)
        bpy.ops.object.shade_smooth()
        f.parent = root
block("bed_headboard", (-3.4, 0.0, -1.85), (-3.0, 2.9, 1.85), 0.19, NAVY, root, segments=6)
block("bed_footboard", (1.5, 0.0, -1.85), (1.85, 1.75, 1.85), 0.16, NAVY, root, segments=6)
for x, y in ((-3.2, 2.9), (1.675, 1.75)):
    for z in (-1.7, 1.7):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2, location=gl(x, y + 0.08, z), segments=24, ring_count=12)
        k = bpy.context.active_object
        k.name = "bed_knob"
        k.data.materials.append(NAVY)
        bpy.ops.object.shade_smooth()
        k.parent = root

block("bed_mattress", (-3.0, 0.36, -1.75), (1.55, MATTRESS_TOP, 1.75), 0.12, WHITE, root, subdiv=1, cuts=22)
pillow = block("bed_pillow", (-2.9, MATTRESS_TOP - 0.06, -1.6), (-0.55, PILLOW_TOP, 1.6), 0.16, PILLOW, root, subdiv=1, cuts=20)
apply_modifiers(pillow)
for v in pillow.data.vertices:
    x, z, y = v.co.x, -v.co.y, v.co.z
    u = (x - (-1.725)) / 1.175
    w = z / 1.6
    puff = max(0.0, 1 - u * u) * max(0.0, 1 - w * w)
    if y > (MATTRESS_TOP + PILLOW_TOP) / 2:
        y += 0.1 * puff
    v.co = gl(x, y, z)

HEAD_EDGE, FOOT = 0.14, 1.55
DRAPE = 2.05

bm = bmesh.new()
NX, NZ = 48, 80
grid = []
for i in range(NX + 1):
    x = HEAD_EDGE + (FOOT - HEAD_EDGE) * i / NX
    grid.append([bm.verts.new(gl(x, MATTRESS_TOP, -DRAPE + 2 * DRAPE * j / NZ)) for j in range(NZ + 1)])
for i in range(NX):
    for j in range(NZ):
        bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
mesh = bpy.data.meshes.new("bed_blanket")
bm.to_mesh(mesh)
bm.free()
blanket_obj = bpy.data.objects.new("bed_blanket", mesh)
bpy.context.scene.collection.objects.link(blanket_obj)
blanket_obj.parent = root
mesh.materials.append(WHITE)
mesh.materials.append(STRIPE)
for poly in mesh.polygons:
    cx = poly.center.x
    poly.material_index = 1 if any(abs(cx - c) < 0.09 for c in (0.2, 0.62, 1.04)) else 0
    poly.use_smooth = True
if sum(p.normal.z for p in mesh.polygons) < 0:
    for p in mesh.polygons:
        p.flip()
sol = blanket_obj.modifiers.new("thick", "SOLIDIFY")
sol.thickness = 0.07
sol.offset = -1
apply_modifiers(blanket_obj)

bm = bmesh.new()
RINGS, SIDES, R = 80, 16, 0.12
rings = []
for i in range(RINGS + 1):
    z = -DRAPE + 2 * DRAPE * i / RINGS
    rings.append([bm.verts.new(gl(HEAD_EDGE + 0.05 + R * math.cos(2 * math.pi * k / SIDES), MATTRESS_TOP + 0.05 + R * math.sin(2 * math.pi * k / SIDES), z))
                  for k in range(SIDES)])
for i in range(RINGS):
    for k in range(SIDES):
        bm.faces.new((rings[i][k], rings[i][(k + 1) % SIDES], rings[i + 1][(k + 1) % SIDES], rings[i + 1][k]))
hem_mesh = bpy.data.meshes.new("bed_blanket_hem")
bm.to_mesh(hem_mesh)
bm.free()
hem = bpy.data.objects.new("bed_blanket_hem", hem_mesh)
bpy.context.scene.collection.objects.link(hem)
hem_mesh.materials.append(STRIPE)
for poly in hem_mesh.polygons:
    poly.use_smooth = True
c = gl(HEAD_EDGE + 0.05, MATTRESS_TOP + 0.05, 0)
if sum((p.center.x - c[0]) * p.normal.x + (p.center.z - c[2]) * p.normal.z for p in hem_mesh.polygons) < 0:
    for p in hem_mesh.polygons:
        p.flip()
hem.parent = blanket_obj

for o in (blanket_obj,):
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.scene.cursor.location = gl(FOOT, MATTRESS_TOP, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

for o in list(root.children):
    if o.modifiers:
        apply_modifiers(o)

bpy.ops.export_scene.gltf(filepath=os.path.normpath(OUT), export_format="GLB", export_apply=True, export_yup=True,
                          export_animations=False, export_cameras=False, export_lights=False)
print("wrote", os.path.normpath(OUT))
