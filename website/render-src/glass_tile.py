# Lil Agent — frosted glass app tile (reference: soft glassy tile, bright white logo,
# darker saturated rim, lighter hazy centre, thin bright edge highlight, tinted soft shadow).
# Run: Blender -b -P glass_tile.py -- <out_prefix> [samples] [res]
import bpy, bmesh, math, sys, os
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
OUT = argv[0] if argv else '/tmp/tile'
SAMPLES = int(argv[1]) if len(argv) > 1 else 128
RES = int(argv[2]) if len(argv) > 2 else 900
SVG = os.environ['LOGO_SVG']

def srgb(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

RIM = srgb(os.environ.get('RIM', '#7a4a20'))      # deep, saturated colour (rim / thick paths)
FACE = srgb(os.environ.get('FACE', '#e3c49d'))    # light, hazy face tint

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ---------------- Slab: squircle outline, flat face, side walls bulge like a lens ----------------
W, T = 2.0, float(os.environ.get('THICK', '0.3'))
N = float(os.environ.get('SQUIRCLE', '4.2'))       # superellipse exponent: 2 = circle, higher = squarer
BULGE = float(os.environ.get('BULGE', '0.02'))     # how far the side walls swell outward
SEG = 192
def ring(z, scale=1.0):
    pts = []
    for k in range(SEG):
        a = 2 * math.pi * k / SEG
        c, s_ = math.cos(a), math.sin(a)
        x = math.copysign(abs(c) ** (2 / N), c) * W / 2 * scale
        y = math.copysign(abs(s_) ** (2 / N), s_) * W / 2 * scale
        pts.append((x, y, z))
    return pts
rings = [ring(0, 1 - BULGE * 0.5), ring(T * 0.18, 1 + BULGE * 0.6), ring(T * 0.5, 1 + BULGE), ring(T * 0.82, 1 + BULGE * 0.6), ring(T, 1 - BULGE * 0.5)]
verts = [v for r in rings for v in r]
faces = []
for r in range(len(rings) - 1):
    for k in range(SEG):
        a, b2 = r * SEG + k, r * SEG + (k + 1) % SEG
        faces.append((a, b2, b2 + SEG, a + SEG))
faces.append(tuple(reversed(range(SEG))))
faces.append(tuple(range((len(rings) - 1) * SEG, len(rings) * SEG)))
me = bpy.data.meshes.new('Slab'); me.from_pydata(verts, [], faces); me.update()
bm = bmesh.new(); bm.from_mesh(me)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(me); bm.free()
if os.environ.get('DISH', '1') == '1':   # shallow dished face with a raised lip, like a keycap
    bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
    top = max(bm.faces, key=lambda f: f.calc_center_median().z)
    res = bmesh.ops.inset_region(bm, faces=[top], thickness=float(os.environ.get('DISH_INSET', '0.16')), depth=0)
    bmesh.ops.translate(bm, verts=list(top.verts), vec=(0, 0, -float(os.environ.get('DISH_DEPTH', '0.06'))))
    bm.to_mesh(me); bm.free()
slab = bpy.data.objects.new('Slab', me)
scene.collection.objects.link(slab)
for p in me.polygons: p.use_smooth = True
b = slab.modifiers.new('Bevel', 'BEVEL')                 # soft rounded lip where face meets wall
b.width, b.segments, b.limit_method, b.angle_limit, b.profile = 0.07, 12, 'ANGLE', math.radians(25), 0.55
slab.modifiers.new('WN', 'WEIGHTED_NORMAL')

glass = bpy.data.materials.new('Glass'); glass.use_nodes = True
nt = glass.node_tree; n = nt.nodes
bsdf = n['Principled BSDF']
bsdf.inputs['Base Color'].default_value = (*FACE, 1)
bsdf.inputs['Roughness'].default_value = float(os.environ.get('GLOSS_ROUGH', '0.08'))
bsdf.inputs['IOR'].default_value = 1.47
bsdf.inputs['Transmission Weight'].default_value = 1.0
bsdf.inputs['Coat Weight'].default_value = 1.0
bsdf.inputs['Coat Roughness'].default_value = 0.06
bsdf.inputs['Coat IOR'].default_value = 1.5
absorb = n.new('ShaderNodeVolumeAbsorption')
absorb.inputs['Color'].default_value = (*RIM, 1)
absorb.inputs['Density'].default_value = float(os.environ.get('ABSORB', '1.5'))
scat = n.new('ShaderNodeVolumeScatter')
scat.inputs['Color'].default_value = (*FACE, 1)
scat.inputs['Density'].default_value = float(os.environ.get('HAZE', '3.6'))
addv = n.new('ShaderNodeAddShader')
nt.links.new(absorb.outputs[0], addv.inputs[0])
nt.links.new(scat.outputs[0], addv.inputs[1])
nt.links.new(addv.outputs[0], n['Material Output'].inputs['Volume'])
# Razor-thin fresnel glow on the outer ridge: emission where the surface turns away from view
lw = n.new('ShaderNodeLayerWeight'); lw.inputs['Blend'].default_value = 0.08
ramp = n.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].position = 0.86; ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
ramp.color_ramp.elements[1].position = 0.97; ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
nt.links.new(lw.outputs['Facing'], ramp.inputs['Fac'])
glow = n.new('ShaderNodeEmission'); glow.inputs['Color'].default_value = (1, 0.97, 0.92, 1)
glow.inputs['Strength'].default_value = float(os.environ.get('RIM_GLOW', '3.0'))
mix = n.new('ShaderNodeMixShader')
nt.links.new(ramp.outputs['Color'], mix.inputs['Fac'])
nt.links.new(bsdf.outputs[0], mix.inputs[1])
nt.links.new(glow.outputs[0], mix.inputs[2])
nt.links.new(mix.outputs[0], n['Material Output'].inputs['Surface'])
slab.data.materials.append(glass)

# ---------------- Logo: each SVG path filled flat → mesh, joined, thin solid ----------------
before = set(bpy.data.objects)
bpy.ops.import_curve.svg(filepath=SVG)
curves = [o for o in bpy.data.objects if o not in before and o.type == 'CURVE']
for c in curves:
    c.data.dimensions = '2D'
    c.data.fill_mode = 'BOTH'
    c.data.extrude = 0
    c.data.resolution_u = 32
bpy.ops.object.select_all(action='DESELECT')
for c in curves: c.select_set(True)
bpy.context.view_layer.objects.active = curves[0]
bpy.ops.object.convert(target='MESH')
bpy.ops.object.join()
logo = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
logo.location = (0, 0, 0)
s_ = (W * float(os.environ.get('LOGO_SCALE', '0.62'))) / max(logo.dimensions.x, logo.dimensions.y)
logo.scale = (s_, s_, s_)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0001)
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.object.mode_set(mode='OBJECT')
sol = logo.modifiers.new('Solid', 'SOLIDIFY')
sol.thickness, sol.offset, sol.use_even_offset = 0.012, 1, True
lb = logo.modifiers.new('Bevel', 'BEVEL'); lb.width, lb.segments, lb.limit_method = 0.006, 4, 'ANGLE'
white = bpy.data.materials.new('White'); white.use_nodes = True
wb = white.node_tree.nodes['Principled BSDF']
wb.inputs['Base Color'].default_value = (*srgb(os.environ.get('LOGO_COLOR', '#fbf8f3')), 1)
wb.inputs['Roughness'].default_value = 0.6
wb.inputs['Emission Color'].default_value = wb.inputs['Base Color'].default_value[:]
wb.inputs['Emission Strength'].default_value = 0.55
logo.data.materials.clear(); logo.data.materials.append(white)
# sits inside the glass, just under the dished face
logo.location = (0, 0, T - float(os.environ.get('DISH_DEPTH', '0.06')) - float(os.environ.get('EMBED', '0.006')))
logo.parent = slab

# ---------------- Pose ----------------
pivot = bpy.data.objects.new('Pivot', None); scene.collection.objects.link(pivot)
slab.parent = pivot
slab.location = (0, 0, -T / 2)
pivot.location = (0, 0, float(os.environ.get('LIFT', '0.2')))
pivot.rotation_euler = (math.radians(float(os.environ.get('TILT_X', '0'))), math.radians(float(os.environ.get('TILT_Y', '0'))), math.radians(float(os.environ.get('SPIN', '0'))))

# ---------------- Softbox reflection (replaces the hard diagonal stripe) ----------------
# A rounded emissive panel above the top-left, seen only in reflections. Its brightness fades
# out radially, so the reflection wraps softly over the top-left rim instead of cutting a line.
REFL = float(os.environ.get('REFL', '3.0'))
bpy.ops.mesh.primitive_plane_add(size=1)
card = bpy.context.active_object; card.name = 'Softbox'
card.scale = (float(os.environ.get('SOFTBOX_W', '5.0')), float(os.environ.get('SOFTBOX_H', '3.0')), 1)
card.location = (float(os.environ.get('REFL_X', '1.7')), float(os.environ.get('REFL_Y', '1.6')), 2.6)
card.rotation_euler = (math.radians(-20), math.radians(-24), math.radians(float(os.environ.get('REFL_ANGLE', '-35'))))
cm = bpy.data.materials.new('Softbox'); cm.use_nodes = True
cn = cm.node_tree.nodes; cl = cm.node_tree.links
cn.remove(cn['Principled BSDF'])
tc = cn.new('ShaderNodeTexCoord'); grad = cn.new('ShaderNodeTexGradient'); grad.gradient_type = 'SPHERICAL'
mp = cn.new('ShaderNodeMapping'); mp.inputs['Scale'].default_value = (1.9, 1.9, 1)
cramp = cn.new('ShaderNodeValToRGB')
cramp.color_ramp.elements[0].position = 0.0; cramp.color_ramp.elements[0].color = (0, 0, 0, 1)
cramp.color_ramp.elements[1].position = 0.75; cramp.color_ramp.elements[1].color = (1, 1, 1, 1)
em = cn.new('ShaderNodeEmission'); em.inputs['Strength'].default_value = REFL
cl.new(tc.outputs['Object'], mp.inputs['Vector']); cl.new(mp.outputs[0], grad.inputs['Vector'])
cl.new(grad.outputs['Fac'], cramp.inputs['Fac']); cl.new(cramp.outputs['Color'], em.inputs['Strength'])
emm = cn.new('ShaderNodeMath'); emm.operation = 'MULTIPLY'; emm.inputs[1].default_value = REFL
cl.new(cramp.outputs['Color'], emm.inputs[0]); cl.new(emm.outputs[0], em.inputs['Strength'])
cl.new(em.outputs[0], cn['Material Output'].inputs['Surface'])
card.data.materials.append(cm)
card.visible_camera = card.visible_shadow = card.visible_diffuse = False
card.visible_transmission = card.visible_volume_scatter = False

# Secondary cool reflection on the top-left: warm-vs-cool contrast on the gloss
cool = card.copy(); cool.data = card.data.copy(); scene.collection.objects.link(cool)
cool.name = 'CoolFill'
cool.location = (-1.9, 1.4, 2.4)
cool.rotation_euler = (math.radians(-20), math.radians(24), math.radians(35))
cool.scale = (4.0, 2.6, 1)
cmc = cm.copy(); cool.data.materials.clear(); cool.data.materials.append(cmc)
for nd in cmc.node_tree.nodes:
    if nd.type == 'EMISSION': nd.inputs['Color'].default_value = (0.82, 0.9, 1.0, 1)
    if nd.type == 'MATH': nd.inputs[1].default_value = float(os.environ.get('COOL_REFL', '1.1'))

# ---------------- Floor (shadow catcher) ----------------
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
bpy.context.active_object.is_shadow_catcher = True

# ---------------- Lighting: high key, soft ----------------
def area(name, loc, size, energy, shape='SQUARE', size_y=None, color=(1, 1, 1)):
    d = bpy.data.lights.new(name, 'AREA')
    d.shape, d.size, d.energy, d.color = shape, size, energy, color
    if size_y: d.size_y = size_y
    o = bpy.data.objects.new(name, d); o.location = loc
    scene.collection.objects.link(o)
    o.rotation_euler = (Vector((0, 0, 0.35)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return o

area('Key', (-4.5, 4.5, 8.5), 9, 820)                        # big soft top-left
area('Strip', (3.2, 3.6, 6.0), 0.6, 260, 'RECTANGLE', 5.0)    # vertical streak reflection top-right
area('Fill', (2.5, -5.0, 5.0), 8, 120)
area('Back', (0, 6, 2.0), 6, 950)                             # stronger → edges glow                             # light through the glass

for o in scene.objects:
    if o.type == 'LIGHT': o.visible_glossy = False   # reflections come only from the feathered softbox cards
world = bpy.data.worlds.new('W'); scene.world = world; world.use_nodes = True
bg = world.node_tree.nodes['Background']
bg.inputs['Color'].default_value = (1, 1, 1, 1)
bg.inputs['Strength'].default_value = 1.0

# ---------------- Camera ----------------
cd_ = bpy.data.cameras.new('Cam'); cd_.lens = 110
cam = bpy.data.objects.new('Cam', cd_); scene.collection.objects.link(cam)
cam.location = (0, 0, 13.5)   # straight above the tile, no roll → the tile faces the viewer
cam.rotation_euler = (0, 0, 0)
scene.camera = cam

# ---------------- Render ----------------
scene.render.engine = 'CYCLES'
prefs = bpy.context.preferences.addons['cycles'].preferences
try:
    prefs.compute_device_type = 'METAL'; prefs.get_devices()
    for d in prefs.devices: d.use = True
    scene.cycles.device = 'GPU'
except Exception as e:
    print('CPU fallback', e)
c = scene.cycles
c.samples = SAMPLES
c.use_denoising = True
c.max_bounces, c.transmission_bounces, c.volume_bounces = 24, 24, 4
c.caustics_refractive = True
c.blur_glossy = 0.5
scene.render.film_transparent = True
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'
scene.view_settings.exposure = 0.0
scene.render.resolution_x = scene.render.resolution_y = RES
vl = scene.view_layers[0]
vl.cycles.use_pass_shadow_catcher = True
ims = scene.render.image_settings
if hasattr(ims, 'media_type'): ims.media_type = 'MULTI_LAYER_IMAGE'
ims.file_format = 'OPEN_EXR_MULTILAYER'
scene.render.image_settings.color_depth = '32'
scene.render.filepath = OUT + '.exr'
bpy.ops.render.render(write_still=True)
print('WROTE', OUT + '.exr')
