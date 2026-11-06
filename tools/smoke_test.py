"""Compile GLSL 1.20 and exercise the actual render passes on headless OpenGL.

Requires: python3 -m pip install -r tools/test-requirements.txt
This is a synthetic GPU test, not an Iris/Minecraft integration test.
"""
import os
os.environ.setdefault('PYOPENGL_PLATFORM', 'egl')
from pathlib import Path
from shader_sources import expand_shader, shader_files
import numpy as np
import moderngl
from OpenGL import GL

ROOT = Path(__file__).resolve().parents[1] / 'shaders'
shader_files(ROOT)
W, H = 128, 64
ctx = moderngl.create_standalone_context(backend='egl', require=210)
print('OpenGL:', ctx.info['GL_VERSION'], '/', ctx.info['GL_RENDERER'])

def expand(path, settings=None):
    return expand_shader(path, ROOT, settings)

def program(name, settings=None):
    return ctx.program(vertex_shader=expand(ROOT / (name + '.vsh'), settings),
                       fragment_shader=expand(ROOT / (name + '.fsh'), settings))

def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print('PASS', message)

for steps in (16, 32, 64):
    for path in sorted(ROOT.glob('*.vsh')):
        p = program(path.stem, {'REFLECTION_STEPS': steps})
        p.release()
    print('PASS all', len(list(ROOT.glob('*.vsh'))), 'programs compile/link, REFLECTION_STEPS =', steps)

def texture(data):
    a = np.asarray(data, dtype='f4')
    if a.ndim == 1:
        a = np.broadcast_to(a, (H, W, len(a))).copy()
    if a.ndim == 2:
        a = a[:, :, None]
    t = ctx.texture((W, H), a.shape[2], a.tobytes(), dtype='f4')
    t.filter = (moderngl.LINEAR, moderngl.LINEAR)
    t.repeat_x = t.repeat_y = False
    return t

near, far_plane = 0.05, 512.0
projection = np.array([[0.5, 0, 0, 0], [0, 1, 0, 0],
                       [0, 0, -(far_plane+near)/(far_plane-near), -2*far_plane*near/(far_plane-near)],
                       [0, 0, -1, 0]], dtype='f4')
identity = np.eye(4, dtype='f4')

def depth_at(distance):
    return ((-projection[2, 2] * distance + projection[2, 3]) / distance + 1) / 2

DEFAULTS = {
    'gbufferProjection': projection, 'gbufferProjectionInverse': np.linalg.inv(projection),
    'gbufferModelViewInverse': identity, 'gbufferPreviousProjection': projection,
    'gbufferPreviousModelView': identity, 'far': 256.0, 'viewWidth': float(W),
    'viewHeight': float(H), 'fogColor': (0.5, 0.7, 0.8), 'skyColor': (0.3, 0.5, 0.8),
    'isEyeInWater': 0, 'cameraPosition': (0., 0., 0.), 'previousCameraPosition': (0., 0., 0.),
    'frameTime': 1/60,
}

def draw(p, textures, uniforms=None, count=1):
    attachments = [ctx.texture((W, H), 4, dtype='f4') for _ in range(count)]
    fbo = ctx.framebuffer(attachments)
    fbo.use()
    ctx.viewport = (0, 0, W, H)
    GL.glUseProgram(p.glo)
    owned = []
    for unit, (name, data) in enumerate(textures.items()):
        t = data if isinstance(data, moderngl.Texture) else texture(data)
        if t is not data:
            owned.append(t)
        t.use(unit)
        if name in p:
            p[name].value = unit
    for name, value in (DEFAULTS | (uniforms or {})).items():
        if name not in p:
            continue
        if isinstance(value, np.ndarray):
            p[name].write(value.astype('f4').T.tobytes())
        else:
            p[name].value = value
    GL.glMatrixMode(GL.GL_PROJECTION)
    GL.glLoadIdentity()
    GL.glMatrixMode(GL.GL_MODELVIEW)
    GL.glLoadIdentity()
    GL.glBegin(GL.GL_QUADS)
    for x,y,u,v in [(-1,-1,0,0),(1,-1,1,0),(1,1,1,1),(-1,1,0,1)]:
        GL.glTexCoord2f(u,v)
        GL.glVertex2f(x,y)
    GL.glEnd()
    GL.glFinish()
    results = [np.frombuffer(t.read(), dtype='f4').reshape(H,W,4).copy() for t in attachments]
    for result in results:
        check(np.isfinite(result).all(), 'finite render output')
    fbo.release()
    for t in attachments + owned:
        t.release()
    return results

composite = program('composite')
base = {'colortex0': [0.8,0.3,0.1,1], 'colortex1': [0.5,0.5,1,0],
        'colortex2': [0,0,0,0], 'colortex5': [0.6,0.4,0.2,1]}
for distance in (100., 240., 248., 256.):
    inputs = base | {'depthtex0': [depth_at(distance)], 'depthtex1': [depth_at(distance)]}
    result = draw(composite, inputs, count=2)[0]
    # Actual position at the central pixel, including its half-pixel horizontal displacement.
    xz = distance * np.sqrt(1 + (2/W)**2)
    f = np.clip((xz - 240) / 16, 0, 1)
    f = f*f*(3-2*f)
    expected = np.array([0.8,0.3,0.1])*(1-f) + np.array([0.5,0.7,0.8])**2.2*f
    check(np.allclose(result[H//2,W//2,:3], expected, atol=0.003), f'fog ramp at {distance:g} blocks')

inputs = base | {'depthtex0': [depth_at(256)], 'depthtex1': [depth_at(256)]}
biome_fog = (0.2,0.45,0.25)
result = draw(composite, inputs, {'fogColor':biome_fog}, count=2)[0]
check(np.allclose(result[H//2,W//2,:3],np.array(biome_fog)**2.2,atol=0.001), 'fog follows engine biome colour')
# Hand tags must bypass world fog even at the far plane.
result = draw(composite, inputs | {'colortex2':[0,0,0,0.5]}, count=2)[0]
check(np.allclose(result[H//2,W//2,:3],base['colortex0'][:3],atol=0.001), 'hand is excluded from fog')

# Bloom is sourced only from the emission buffer, and spreads in both axes.
black = np.zeros((H,W,4),dtype='f4')
emission = black.copy()
emission[H//2-2:H//2+2,W//2-2:W//2+2,:3] = 3
horizontal = program('composite1'); vertical = program('composite2')
h = draw(horizontal, {'colortex2':emission})[0]
b = draw(vertical, {'colortex3':h})[0]
check(b[H//2+4,W//2+4,0] > 0.001, 'emissive bloom spreads horizontally and vertically')
zero = draw(horizontal, {'colortex2':black,'colortex0':[10,10,10,1]})[0]
check(np.max(zero[:,:,:3]) == 0, 'bright nonemissive pixels cannot produce bloom')

# Reprojection: stationary view is exact, movement softens a high-frequency pattern.
pattern = np.zeros((H,W,4),dtype='f4'); pattern[:,:,3] = 1
pattern[:,:,0:3] = (np.arange(W)%2)[None,:,None]*0.8
final = program('final'); no_blur = program('final', {'MOTION_BLUR':0.0})
inputs = {'colortex0':pattern,'colortex2':black,'colortex4':black,'depthtex0':[depth_at(3)]}
reference = draw(no_blur,inputs)[0]
stationary = draw(final,inputs)[0]
check(np.allclose(stationary,reference,atol=0.00001), 'stationary camera has no motion blur')
moving = draw(final,inputs,{'previousCameraPosition':(0.5,0,0)})[0]
check(np.mean(abs(moving[:,:,0]-reference[:,:,0])) > 0.05, 'camera motion produces blur')
hand = draw(final,inputs | {'colortex2':[0,0,0,0.5]}, {'previousCameraPosition':(0.5,0,0)})[0]
check(np.allclose(hand,reference,atol=0.00001), 'held item stays sharp during camera movement')
cut = draw(final,inputs,{'previousCameraPosition':(100,0,0)})[0]
check(np.allclose(cut,reference,atol=0.00001), 'teleport disables motion blur')

# Both sides of the interface must face the viewer, including grazing incidence.
for underwater in (0,1):
    for normal in ([0.5,1,0.5,0.95],[0.5,0,0.5,0.95],[0.5,0.5,1,0.95]):
        draw(composite,base | {'colortex1':normal,'colortex2':[0,0,0,1],
             'depthtex0':[depth_at(3)],'depthtex1':[depth_at(8)]}, {'isEyeInWater':underwater},count=2)
# A shallow underside angle must reflect the opaque bottom rather than transmit
# the blue colour directly behind the water. Reversing the mesh normal is harmless.
opaque = np.zeros((H,W,4),dtype='f4'); opaque[:,:,2] = 1; opaque[:,:,3] = 1
opaque[int(H*0.65):,:,:3] = (1,0,0)
n = np.array([0,0.9238795,0.3826834])
reflections = []
for sign in (1,-1):
    normal = list(n*sign*0.5+0.5) + [0.95]
    r = draw(composite,base | {'colortex1':normal,'colortex2':[0,0,0,1],
             'colortex5':opaque,'depthtex0':[depth_at(3)],'depthtex1':[depth_at(8)]},
             {'isEyeInWater':1},count=2)[0]
    reflections.append(r)
check(np.allclose(reflections[0],reflections[1],atol=0.00001), 'water normals work from either side')
pixel = reflections[0][H//2,W//2,:3]
check(pixel[0] > 0.7 and pixel[2] < 0.25, 'underwater total internal reflection hits opaque lake bed')
print('All synthetic OpenGL smoke tests passed.')
