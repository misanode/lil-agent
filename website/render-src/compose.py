# Composite the multilayer EXR onto the site's paper colour (#faf8f5) with the
# coloured shadow-catcher pass, plus a transparent version. Run inside Blender's python:
# Blender -b --python compose.py -- <prefix>
import os, sys, numpy as np, OpenImageIO as oiio
prefix = sys.argv[sys.argv.index('--') + 1]

inp = oiio.ImageInput.open(prefix + '.exr')
layers = {}
sub = 0
while inp.seek_subimage(sub, 0):
    spec = inp.spec()
    px = inp.read_image(sub, 0, 0, spec.nchannels, 'float')
    for i, name in enumerate(spec.channelnames):
        layers[name] = px[..., i]
    sub += 1
inp.close()
names = list(layers)
def find(suffix):
    for k in names:
        if k.endswith(suffix): return layers[k]
    raise KeyError(suffix + ' in ' + str(names))

comb = np.stack([find('Combined.R'), find('Combined.G'), find('Combined.B')], -1)
alpha = find('Combined.A')[..., None]
sc = np.stack([find('Shadow Catcher.R'), find('Shadow Catcher.G'), find('Shadow Catcher.B')], -1)

def to_lin(h):
    c = np.array([int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)])
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
def to_srgb(x):
    x = np.clip(x, 0, 1)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * x ** (1 / 2.4) - 0.055)

paper = to_lin(os.environ.get('PAPER', '#faf8f5'))
sc = np.clip(sc, 0, 1)
# soften/lift shadow a bit so it stays airy like the reference
shade = (1 - sc.mean(-1, keepdims=True)) * float(os.environ.get('SHADOW_STRENGTH', '1.0'))
tint = to_lin(os.environ.get('SHADOW_TINT', '#a8875f'))                 # bronze-tinted shadow, like the reference's blue one
bgc = paper * (1 - shade * (1 - tint * 0.55))
sc = 1 - shade
out = comb + bgc * (1 - alpha)          # Combined is premultiplied
img = (to_srgb(out) * 255 + 0.5).astype(np.uint8)

def write(path, arr):
    h, w, ch = arr.shape
    o = oiio.ImageOutput.create(path)
    o.open(path, oiio.ImageSpec(w, h, ch, 'uint8'))
    o.write_image(arr[::-1] if False else arr)
    o.close()
ys, xs = np.where(alpha[..., 0] > 0.02)            # frame around the tile itself
ext = max(ys.max() - ys.min(), xs.max() - xs.min())
cy = (ys.min() + ys.max()) // 2 + int(ext * 0.06)     # nudge down a bit to leave room for the shadow
cx = (xs.min() + xs.max()) // 2 + int(ext * 0.03)
half = int(ext * float(os.environ.get('PAD', '0.78')))
H, Wd = img.shape[:2]
y0, x0 = max(0, cy - half), max(0, cx - half)
y1, x1 = min(H, cy + half), min(Wd, cx + half)
img = img[y0:y1, x0:x1]
write(prefix + '-on-paper.png', img)

# Transparent version: shadow becomes alpha (luminance), tinted by shadow colour
shadow_a = 1 - sc.mean(-1, keepdims=True)
tint = np.where(shadow_a > 1e-4, (1 - (1 - sc) / np.maximum(1 - sc.mean(-1, keepdims=True), 1e-4) * 0) , 1)
a_total = alpha + shadow_a * (1 - alpha)
shadow_col = np.clip(sc / np.maximum(sc.mean(-1, keepdims=True), 1e-4), 0, 2) * 0.35
rgb = (comb + shadow_col * shadow_a * (1 - alpha)) / np.maximum(a_total, 1e-5)
rgba = np.concatenate([to_srgb(rgb), np.clip(a_total, 0, 1)], -1)
write(prefix + '.png', (rgba[y0:y1, x0:x1] * 255 + 0.5).astype(np.uint8))
print('composited', prefix)
