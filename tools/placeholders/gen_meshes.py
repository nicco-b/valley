#!/usr/bin/env python3
"""Valley placeholder meshes — low-poly glTF in the palette, with -col hull nodes.
+Y up, 1u=1m. Static only: no rigs, no clips (honest limit of synthesis)."""
import os, json, math, random, sys
import numpy as np
import trimesh
from trimesh.creation import icosphere, cylinder, box, cone

# Repo-relative by default (the original drop ran in a container at
# /home/claude); VALLEY_MODELS overrides for out-of-tree experiments.
ROOT = os.environ.get("VALLEY_MODELS", os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models")))
PAL = {
 'teal':(46,96,90),'teal_d':(29,70,66),'pine':(120,190,148),'olive':(122,124,62),
 'gold':(168,144,64),'pink':(224,85,154),'granite':(150,158,168),'basalt':(70,68,76),
 'coastal':(178,184,192),'sandstone':(206,166,108),'brown':(116,92,66),'wood':(134,104,72),
 'plaster':(233,224,206),'ochre':(214,164,90),'purple':(184,160,209),'ash':(96,94,100),
 'sand':(222,198,158),'cream':(244,236,222),'navy':(32,46,80),'moss':(110,122,58),
 'hide':(122,100,84),'slate':(90,100,110),'mint':(150,214,184),'red':(206,72,48),
}
def C(name, dv=0): return tuple(max(0,min(255,c+dv)) for c in PAL[name])+(255,)

def paint(m, col):
    m.visual.vertex_colors = np.tile(np.array(col, np.uint8), (len(m.vertices), 1))
    return m

def paint_pinned(m, col, pin_fn):
    """Paint RGB + a PIN weight in vertex alpha for fabric_wind.gdshader
    (PLAN_FABRIC F1): a=1 rigid (pole, stakes, hoist edge), a->0 free
    cloth. The shader reads freedom = 1 - a as the normalized distance
    from the pin, so paint it linear along the cloth. pin_fn(v) -> 0..1."""
    n = len(m.vertices)
    rgba = np.tile(np.array(col, np.uint8), (n, 1))
    a = np.clip([pin_fn(v) for v in m.vertices], 0.0, 1.0)
    rgba[:, 3] = np.round(a * 255).astype(np.uint8)
    m.visual.vertex_colors = rgba
    return m

def noise_displace(m, rng, amp=0.18, freq=2.2, flatten_floor=None):
    v = m.vertices.copy()
    ks = [rng.uniform(0.6,1.4)*freq*np.array([rng.uniform(-1,1) for _ in range(3)]) for _ in range(4)]
    ph = [rng.uniform(0, 6.28) for _ in range(4)]
    n = sum(np.sin(v @ k + p) for k, p in zip(ks, ph)) / 4.0
    ctr = v.mean(axis=0)
    dirs = v - ctr; L = np.linalg.norm(dirs, axis=1, keepdims=True); L[L==0]=1
    m.vertices = v + dirs/L * (n[:, None]*amp)
    if flatten_floor is not None:
        m.vertices[:,1] = np.maximum(m.vertices[:,1], flatten_floor) * (m.vertices[:,1] > flatten_floor) + \
                          flatten_floor * (m.vertices[:,1] <= flatten_floor)
    return m

def T(m, dx=0, dy=0, dz=0, s=1.0, sy=None, sz=None, rot=None):
    S = np.eye(4); S[0,0]=s; S[1,1]=sy if sy is not None else s; S[2,2]=sz if sz is not None else s
    m.apply_transform(S)
    if rot is not None:
        m.apply_transform(trimesh.transformations.rotation_matrix(rot[0], rot[1]))
    m.apply_translation([dx, dy, dz])
    return m

def yup_cyl(r, h, sections=10):
    c = cylinder(radius=r, height=h, sections=sections)
    c.apply_transform(trimesh.transformations.rotation_matrix(math.pi/2, [1,0,0]))
    return c

def export(parts, slot, name, i, cls, extra=None):
    mesh = trimesh.util.concatenate(parts) if len(parts) > 1 else parts[0]
    scene = trimesh.Scene()
    scene.add_geometry(mesh, node_name=name)
    hull = mesh.convex_hull; hull.visual.vertex_colors = np.tile(np.array((120,120,120,60),np.uint8),(len(hull.vertices),1))
    scene.add_geometry(hull, node_name=f"{name}-col")
    path = os.path.join(ROOT, os.path.dirname(slot)); os.makedirs(path, exist_ok=True)
    f = os.path.join(path, f"{os.path.basename(slot)}_{i:02d}.glb")
    scene.export(f)
    return os.path.relpath(f, ROOT)

# ---------- generators ----------
def seg_trunk(rng, h=4.0, r0=0.45, bend=0.9, col='teal_d', burst=False):
    parts = []
    n = max(5, int(h/(r0*1.1)))
    bx = rng.uniform(-bend, bend); bz = rng.uniform(-bend, bend)
    for i in range(n+1):
        t = i/n
        x = bx*math.sin(t*math.pi*0.5)*t; z = bz*math.sin(t*math.pi*0.5)*t
        y = t*h
        r = r0*(1-0.55*t)
        s = icosphere(subdivisions=1, radius=r)
        T(s, x, y, z, sy=0.92)
        parts.append(paint(s, C(col, rng.randint(-12, 12))))
    if burst:
        tip = parts[-1].vertices.mean(axis=0)
        for k in range(10):
            a = 2*math.pi*k/10
            sp = cone(radius=r0*0.16, height=r0*1.6, sections=5)
            sp.apply_transform(trimesh.transformations.rotation_matrix(math.pi/2,[1,0,0]))
            sp.apply_transform(trimesh.transformations.rotation_matrix(a,[0,0,1]))
            sp.apply_transform(trimesh.transformations.rotation_matrix(rng.uniform(-.2,.2),[0,1,0]))
            sp.apply_translation(tip + [math.cos(a)*r0*0.9, r0*0.4, math.sin(a)*r0*0.9])
            parts.append(paint(sp, C('gold')))
        core = icosphere(1, r0*0.35); core.apply_translation(tip+[0, r0*0.5, 0])
        parts.append(paint(core, C('pink')))
    return parts

def palm_trunk(rng, h=6.0, r=0.28, lean=0.35, col='brown', ring=None):
    parts = []
    n = 8
    for i in range(n):
        t = i/n
        c = yup_cyl(r*(1-0.35*t)*1.06, h/n*1.1, 8)
        T(c, lean*t*t*h*0.25, t*h + h/n/2, 0)
        parts.append(paint(c, C(col, (14 if (ring and i%2) else 0) + rng.randint(-8, 8))))
    return parts

def boulder(rng, family, s=1.0, amp=0.2):
    b = icosphere(2, 1.0)
    noise_displace(b, rng, amp=amp)
    T(b, 0, 0.72*s, 0, s=s, sy=s*rng.uniform(0.62, 0.85), sz=s*rng.uniform(0.8, 1.15))
    return [paint(b, C(family, rng.randint(-14, 14)))]

def slab(rng, w, h, d, col, amp=0.12):
    b = box(extents=[w, h, d])
    b = b.subdivide().subdivide()
    noise_displace(b, rng, amp=amp)
    b.apply_translation([0, h/2, 0])
    return [paint(b, C(col, rng.randint(-12, 12)))]

def arch(rng, span=4.0, col='sandstone'):
    parts = []
    n = 9
    for i in range(n):
        t = i/(n-1)
        a = math.pi*t
        x = -span/2*math.cos(a); y = math.sin(a)*span*0.5+0.2
        s = icosphere(1, span*0.14*(1-0.3*abs(t-0.5)))
        noise_displace(s, rng, amp=0.05)
        s.apply_translation([x, y, 0])
        parts.append(paint(s, C(col, rng.randint(-10, 10))))
    return parts

def humanoid(rng, col, scale=1.0):
    parts = []
    body = icosphere(2, 0.32); T(body, 0, 0.95*scale, 0, s=1, sy=1.6)
    parts.append(paint(body, col))
    head = icosphere(2, 0.19*scale); head.apply_translation([0, 1.62*scale, 0])
    parts.append(paint(head, C('cream', -10)))
    snout = cone(radius=0.07*scale, height=0.22*scale, sections=8)
    snout.apply_transform(trimesh.transformations.rotation_matrix(math.pi/2, [1, 0, 0]))
    snout.apply_translation([0, 1.58*scale, 0.2*scale])
    parts.append(paint(snout, C('pink', -30)))
    for sx in (-1, 1):
        leg = yup_cyl(0.075*scale, 0.62*scale, 8); leg.apply_translation([sx*0.13*scale, 0.31*scale, 0])
        parts.append(paint(leg, C('navy')))
        arm = yup_cyl(0.055*scale, 0.5*scale, 8); arm.apply_translation([sx*0.36*scale, 1.05*scale, 0])
        parts.append(paint(arm, col))
    return parts

def quadruped(rng, col, L=1.6, H=0.9, horn=False, bird=False, fish=False, crab=False):
    parts = []
    if fish:
        b = icosphere(2, 0.3); T(b, 0, 0.3, 0, sz=2.2, sy=0.8); parts.append(paint(b, col))
        tail = cone(radius=0.18, height=0.35, sections=6)
        tail.apply_transform(trimesh.transformations.rotation_matrix(-math.pi/2, [1,0,0]))
        tail.apply_translation([0, 0.3, -0.75]); parts.append(paint(tail, C('pink')))
        return parts
    if crab:
        b = icosphere(2, 0.3); T(b, 0, 0.24, 0, sy=0.5, s=1, sz=0.8); parts.append(paint(b, col))
        for sx in (-1, 1):
            for k in range(3):
                lg = yup_cyl(0.03, 0.3, 6)
                lg.apply_transform(trimesh.transformations.rotation_matrix(sx*0.9, [0, 0, 1]))
                lg.apply_translation([sx*0.3, 0.18, -0.15+k*0.15]); parts.append(paint(lg, col))
        return parts
    body = icosphere(2, 0.4); T(body, 0, H, 0, sz=L/0.8, sy=0.85)
    parts.append(paint(body, col))
    hd = icosphere(1, 0.22); hd.apply_translation([0, H+0.24, L*0.52]); parts.append(paint(hd, col))
    if horn:
        for sx in (-1, 1):
            hn = cone(radius=0.05, height=0.3, sections=6)
            hn.apply_transform(trimesh.transformations.rotation_matrix(sx*0.7, [0, 0, 1]))
            hn.apply_translation([sx*0.12, H+0.44, L*0.5]); parts.append(paint(hn, C('brown', -20)))
    if bird:
        for sx in (-1, 1):
            wing = box(extents=[0.9, 0.04, 0.4]); wing.apply_translation([sx*0.55, H+0.1, 0])
            parts.append(paint(wing, C('navy', -10)))
    nl = 2 if bird else 4
    for i in range(nl):
        sx = -1 if i % 2 == 0 else 1; sz = -1 if i < 2 else 1
        leg = yup_cyl(0.06, H, 6); leg.apply_translation([sx*0.2, H/2, sz*L*0.32])
        parts.append(paint(leg, C('navy', -14) if not bird else col))
    return parts

def wall_piece(rng, w=2, h=2.4, col='plaster', beams=True):
    parts = [paint(T(box(extents=[w, h, 0.24]), 0, h/2, 0), C(col, rng.randint(-8, 8)))]
    if beams:
        for x in (-w/2+0.1, w/2-0.1):
            parts.append(paint(T(box(extents=[0.14, h, 0.3]), x, h/2, 0), C('wood')))
    return parts

def roof_piece(rng, w=2.4, col='red'):
    r = box(extents=[w, 0.16, 2.6])
    r.apply_transform(trimesh.transformations.rotation_matrix(rng.choice([0.0, 0.32]), [1, 0, 0]))
    r.apply_translation([0, 2.6, 0])
    return [paint(r, C(col, rng.randint(-14, 14)))]

def stall(rng):
    parts = []
    parts += [paint(T(box(extents=[2, 0.1, 1]), 0, 0.9, 0), C('wood'))]
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(paint(T(yup_cyl(0.05, 1.9), sx*0.9, 0.95, sz*0.42), C('wood', -16)))
    aw = box(extents=[2.2, 0.06, 1.3]); aw.apply_transform(trimesh.transformations.rotation_matrix(0.25, [1,0,0]))
    aw.apply_translation([0, 2.0, 0.1])
    parts.append(paint(aw, C(random.choice(['red','ochre','teal']), 10)))
    return parts

def container(rng, kind):
    if kind == 'basket':
        c = cone(radius=0.4, height=0.5, sections=10); c.apply_transform(trimesh.transformations.rotation_matrix(math.pi,[1,0,0]))
        c.apply_translation([0, 0.5, 0]); return [paint(c, C('wood', 20))]
    if kind == 'crate': return [paint(T(box(extents=[0.6, 0.5, 0.6]), 0, 0.25, 0), C('wood'))]
    if kind == 'urn':
        u = icosphere(2, 0.32); T(u, 0, 0.4, 0, sy=1.2); return [paint(u, C('ochre', -10))]
    s = icosphere(2, 0.3); T(s, 0, 0.3, 0, sy=0.9); return [paint(s, C('sand', -10))]

def furniture(rng, kind):
    parts = []
    if kind in ('stool', 'seat'):
        parts.append(paint(T(yup_cyl(0.25, 0.08), 0, 0.45, 0), C('wood')))
        for k in range(3):
            a = 2*math.pi*k/3
            parts.append(paint(T(yup_cyl(0.04, 0.45), math.cos(a)*0.16, 0.22, math.sin(a)*0.16), C('wood', -14)))
    else:  # table/bench
        parts.append(paint(T(box(extents=[1.4, 0.08, 0.8]), 0, 0.75, 0), C('wood')))
        for sx in (-1, 1):
            for sz in (-1, 1):
                parts.append(paint(T(yup_cyl(0.05, 0.75), sx*0.6, 0.375, sz*0.32), C('wood', -14)))
    return parts

def tool(rng, kind):
    parts = [paint(T(yup_cyl(0.025, 1.3), 0, 0.65, 0), C('wood'))]
    hd = box(extents=[0.3, 0.08, 0.05]); hd.apply_translation([0.1, 1.3, 0])
    parts.append(paint(hd, C('slate')))
    return parts

def item(rng, kind):
    col = {'blooms':'pink','fruit':'coral' if 'coral' in PAL else 'pink','roots':'brown',
           'mineral':'slate','creature':'cream','crafted':'wood','hero':'mint'}.get(kind, 'gold')
    s = icosphere(1, 0.12); noise_displace(s, rng, amp=0.03); s.apply_translation([0, 0.12, 0])
    return [paint(s, C(col, rng.randint(-16, 16)))]

def banner(rng):
    """Pole + crossarm + hung pennant — the one placeholder that visibly
    HANGS (PLAN_FABRIC F1: today's textiles lie flat, something must hang).
    Wood is painted rigid (pin=1); the pennant frees linearly hoist->hem so
    fabric_wind.gdshader's freedom doubles as distance-along-cloth."""
    parts = []
    parts.append(paint(T(yup_cyl(0.05, 2.7, 8), 0, 1.35, 0), C('wood')))
    arm = yup_cyl(0.035, 1.1, 8)
    arm.apply_transform(trimesh.transformations.rotation_matrix(math.pi/2, [0, 0, 1]))
    arm.apply_translation([0.5, 2.6, 0])
    parts.append(paint(arm, C('wood', -14)))
    w = rng.uniform(0.7, 0.95); h = rng.uniform(1.0, 1.3); top = 2.55
    cloth = box(extents=[w, h, 0.015]).subdivide().subdivide().subdivide()
    cloth.apply_translation([0.5, top - h / 2, 0])
    parts.append(paint_pinned(cloth, C(rng.choice(['red', 'teal', 'purple', 'pink', 'gold']), 10),
        lambda v: (v[1] - (top - h)) / h))
    return parts

def tent(rng):
    """Cone tent, walls painted breathable: base ring staked (pin=1), apex
    pinned to the pole, mid-wall freed ~0.35. (Also rights the old recipe,
    which left the cone apex-down underground.)"""
    c = cone(radius=1.2, height=1.8, sections=7).subdivide().subdivide()
    c.apply_transform(trimesh.transformations.rotation_matrix(-math.pi / 2, [1, 0, 0]))
    return [paint_pinned(c, C('cream', -16),
        lambda v: 1.0 - 0.35 * math.sin(math.pi * min(1.0, max(0.0, v[1] / 1.8))))]

def ground_cloth(rng, w, d, col, free=0.55):
    """A flat sheet pinned at its center, edges freed — wind strains and
    ripples the rim while the middle stays weighted down."""
    m = T(box(extents=[w, 0.03, d]).subdivide().subdivide(), 0, 0.03, 0)
    return [paint_pinned(m, col,
        lambda v: 1.0 - free * min(1.0, math.hypot(v[0] / (w / 2), v[2] / (d / 2))))]

def crystal(rng, col='mint', h=1.2):
    parts = []
    for _ in range(rng.randint(3, 5)):
        c = cone(radius=rng.uniform(0.12, 0.25), height=rng.uniform(h*0.5, h), sections=6)
        c.apply_transform(trimesh.transformations.rotation_matrix(math.pi/2, [1, 0, 0]))
        c.apply_transform(trimesh.transformations.rotation_matrix(rng.uniform(-0.4, 0.4), [rng.uniform(-1,1), 0, rng.uniform(-1,1)]))
        c.apply_translation([rng.uniform(-0.3, 0.3), 0, rng.uniform(-0.3, 0.3)])
        parts.append(paint(c, C(col, rng.randint(-20, 20))))
    return parts

# ---------- manifest ----------
MESHES = []
def M(slot, n, fn, gated=False, note="", card_extra=None):
    MESHES.append((slot, n, fn, gated, note, card_extra))

# B1 trees/shrubs/cacti (skip ✅ low_shrub, dune_cactus)
M("trees/arch_tree", 2, lambda r: seg_trunk(r, h=r.uniform(4.5, 6), bend=2.2, burst=True))
M("trees/high_palm", 2, lambda r: palm_trunk(r, h=r.uniform(6, 8), col='brown', ring=True) )
M("trees/canopy_bulb_tree", 2, lambda r: seg_trunk(r, h=r.uniform(3.5, 4.5), r0=0.6, bend=0.5, col='pine'))
M("trees/weeping_frond", 1, lambda r: palm_trunk(r, h=5, lean=0.5, col='olive'))
M("trees/thorn_arch", 2, lambda r: seg_trunk(r, h=r.uniform(2.5, 3.5), r0=0.3, bend=2.6, col='brown'))
M("trees/scrub_palm", 2, lambda r: palm_trunk(r, h=r.uniform(2.5, 3.5), col='brown'))
M("trees/broadleaf_bulb", 2, lambda r: seg_trunk(r, h=4, r0=0.55, bend=0.8, col='teal'))
M("trees/swamp_arch", 2, lambda r: seg_trunk(r, h=3.5, r0=0.35, bend=2.2, col='teal_d'))
M("trees/wind_palm", 2, lambda r: palm_trunk(r, h=5.5, lean=0.9, col='brown'))
M("trees/ash_snag", 2, lambda r: palm_trunk(r, h=r.uniform(3, 4.5), col='ash'))
M("trees/lone_spire_cactus", 2, lambda r: seg_trunk(r, h=r.uniform(4, 5.5), r0=0.5, bend=0.3, burst=True))
M("shrubs/bulb_shrub", 2, lambda r: seg_trunk(r, h=1.2, r0=0.45, bend=0.2, col='pine'))
M("shrubs/fan_bush", 2, lambda r: seg_trunk(r, h=1.0, r0=0.35, bend=0.6, col='pine'))
M("shrubs/thorny_bush", 2, lambda r: seg_trunk(r, h=0.9, r0=0.3, bend=0.8, col='brown'))
M("shrubs/marsh_bush", 2, lambda r: seg_trunk(r, h=1.1, r0=0.4, bend=0.4, col='teal'))
M("cacti/ribbed_column", 2, lambda r: seg_trunk(r, h=2.4, r0=0.4, bend=0.2, col='teal_d'))
M("cacti/paddle_cactus", 2, lambda r: seg_trunk(r, h=1.6, r0=0.5, bend=1.0, col='teal'))
M("cacti/barrel_succulent", 2, lambda r: boulder(r, 'teal_d', s=0.5, amp=0.1))
# B2 rocks
for fam, key in [("granite_boulder", 'granite'), ("volcanic_boulder", 'basalt'),
                 ("coastal_boulder", 'coastal'), ("sandstone_boulder", 'sandstone')]:
    M(f"rocks/{fam}", 5, (lambda k: (lambda r: boulder(r, k, s=r.uniform(0.8, 2.2),
        amp=0.12 if k == 'coastal' else 0.22)))(key))
M("cliffs/rim_slab", 4, lambda r: slab(r, r.uniform(5, 8), r.uniform(2, 3), 3, 'granite'))
M("cliffs/face_wall", 4, lambda r: slab(r, r.uniform(6, 9), r.uniform(6, 9), 2.5, 'granite', amp=0.2))
M("cliffs/overhang", 3, lambda r: slab(r, 6, 3, 4, 'sandstone', amp=0.25))
M("cliffs/slide_wall", 3, lambda r: slab(r, 8, 5, 3, 'sand', amp=0.1))
M("cliffs/talus_slope", 3, lambda r: [p for k in range(9) for p in boulder(r, 'granite', s=r.uniform(0.3, 0.9))])
M("cliffs/cave_mouth", 3, lambda r: arch(r, span=r.uniform(4, 6), col='basalt'))
M("cliffs/step_terrace", 4, lambda r: [p for k in range(4) for p in
    [paint(T(box(extents=[6-k, 1, 4-k]), 0, k*1.0+0.5, 0), C('sandstone', r.randint(-10, 10)))]])
M("rocks/scree_clump", 5, lambda r: [p for k in range(r.randint(6, 10)) for p in boulder(r, 'granite', s=r.uniform(0.15, 0.4))])
M("rocks/pebble_cluster", 4, lambda r: [p for k in range(r.randint(8, 14)) for p in boulder(r, 'coastal', s=r.uniform(0.06, 0.18))])
M("rocks/flat_stone", 4, lambda r: slab(r, r.uniform(0.8, 1.4), 0.25, r.uniform(0.8, 1.2), 'coastal', amp=0.05))
M("landmarks/arch", 2, lambda r: arch(r, span=r.uniform(6, 9)))
M("landmarks/sea_stack", 3, lambda r: [T(p, 0, 0, 0, s=1, sy=r.uniform(2.5, 3.6)) for p in boulder(r, 'coastal', s=1.6)])
M("landmarks/spire", 2, lambda r: [T(p, 0, 0, 0, s=1, sy=r.uniform(3.5, 5)) for p in boulder(r, 'granite', s=1.2)])
M("landmarks/hoodoo", 3, lambda r: [p for k, s in enumerate([1.0, 0.7, 1.1]) for p in
    [T(boulder(r, 'sandstone', s=s)[0], 0, k*1.6, 0)]])
M("landmarks/gate_pillars", 1, lambda r: [T(p, x, 0, 0, s=1, sy=4) for x in (-4, 4) for p in boulder(r, 'basalt', s=1.4)])
M("landmarks/mesa_hero", 2, lambda r: slab(r, 14, 6, 10, 'sandstone', amp=0.3))
# B3 characters — static stand-ins, no rig
M("chars/humanoid_base", 1, lambda r: humanoid(r, C('cream', -20)), note="STATIC stand-in — the real rig cannot be synthesized")
for v, col in [("elder", 'purple'), ("keeper", 'teal'), ("wanderer", 'olive'), ("trader", 'ochre'),
               ("fisher", 'navy'), ("herder", 'moss'), ("smith", 'slate')]:
    M(f"chars/villager_{v}", 1, (lambda c: (lambda r: humanoid(r, C(c))))(col), note="reskin of humanoid_base; static")
M("chars/villager_child", 1, lambda r: humanoid(r, C('pink', 20), scale=0.62), note="scaled child; static")
# B4 wildlife — static primitives
M("wildlife/bulb_grazer", 1, lambda r: quadruped(r, C('mint', -20), horn=True))
M("wildlife/grazer_calf", 1, lambda r: [T(p, 0, 0, 0, s=0.55) for p in quadruped(r, C('mint', -10), horn=False)])
M("wildlife/ridge_stalker", 1, lambda r: quadruped(r, C('brown', -20), L=2.0, H=1.0))
M("wildlife/pack_strider", 1, lambda r: quadruped(r, C('hide'), L=2.6, H=1.6))
M("wildlife/sky_wheeler", 1, lambda r: quadruped(r, C('navy'), bird=True, L=1.0, H=0.6))
M("wildlife/shore_skitterer", 1, lambda r: quadruped(r, C('red', 20), crab=True))
M("wildlife/dune_hopper", 1, lambda r: [T(p, 0, 0, 0, s=0.4) for p in quadruped(r, C('sand', -20))])
M("wildlife/pool_fish", 1, lambda r: quadruped(r, C('pink'), fish=True))
M("wildlife/reef_dart", 1, lambda r: [T(p, 0, 0, 0, s=0.6) for p in quadruped(r, C('mint'), fish=True)])
M("wildlife/burrow_thing", 1, lambda r: seg_trunk(r, h=1.0, r0=0.2, bend=1.4, col='hide', burst=False))
M("wildlife/marsh_wader", 1, lambda r: quadruped(r, C('cream'), bird=True, H=1.2, L=0.8))
M("wildlife/cliff_climber", 1, lambda r: quadruped(r, C('slate', 30), horn=True, H=1.0, L=1.3))
M("wildlife/glow_swimmer", 1, lambda r: quadruped(r, C('mint'), fish=True), gated=True, note="UND gated")
M("wildlife/cave_crawler", 1, lambda r: quadruped(r, C('ash'), crab=True), gated=True, note="UND gated")
M("wildlife/blind_grazer", 1, lambda r: quadruped(r, C('cream', -30), horn=False), gated=True, note="UND gated")
# B5 architecture
M("arch/village/wall", 6, lambda r: wall_piece(r))
M("arch/village/roof", 5, lambda r: roof_piece(r, col=r.choice(['red', 'ochre', 'slate'])))
M("arch/village/door", 4, lambda r: [paint(T(box(extents=[1, 2.1, 0.1]), 0, 1.05, 0), C('wood', r.randint(-14, 14)))])
M("arch/village/window", 4, lambda r: [paint(T(box(extents=[0.8, 0.9, 0.1]), 0, 1.5, 0), C('teal', r.randint(-10, 20)))])
M("arch/village/awning", 4, lambda r: roof_piece(r, w=2.0, col=r.choice(['red', 'teal', 'gold'])))
M("arch/village/stall", 4, lambda r: stall(r))
M("arch/village/well", 1, lambda r: [paint(T(yup_cyl(0.9, 0.9, 12), 0, 0.45, 0), C('granite'))] +
   [paint(T(yup_cyl(0.08, 1.6), x, 0.8+0.6, 0), C('wood')) for x in (-0.7, 0.7)] +
   [paint(T(box(extents=[1.8, 0.08, 1.0]), 0, 2.3, 0), C('red'))])
M("arch/village/fence", 4, lambda r: [paint(T(yup_cyl(0.05, 1.0), x, 0.5, 0), C('wood', r.randint(-10, 10)))
   for x in np.linspace(-1, 1, 5)] + [paint(T(box(extents=[2.2, 0.08, 0.06]), 0, 0.8, 0), C('wood'))])
M("arch/village/lantern_post", 3, lambda r: [paint(T(yup_cyl(0.07, 2.4), 0, 1.2, 0), C('wood', -10)),
   paint(T(icosphere(1, 0.18), 0, 2.5, 0.2), C('mint'))], gated=True, note="glow-vessel gated")
M("arch/village/stairs", 4, lambda r: [paint(T(box(extents=[1.6, 0.22, 0.4]), 0, 0.11+k*0.22, k*0.4), C('granite', r.randint(-8, 8))) for k in range(5)])
M("arch/village/pillar", 4, lambda r: [paint(T(yup_cyl(0.16, 2.6, 10), 0, 1.3, 0), C('plaster', -10))])
M("arch/shrine/platform", 2, lambda r: [paint(T(yup_cyl(2.4-k*0.5, 0.4, 14), 0, 0.2+k*0.4, 0), C('granite', 10-k*8)) for k in range(3)])
M("arch/shrine/monolith", 3, lambda r: slab(r, 0.9, r.uniform(2.4, 3.2), 0.5, 'slate', amp=0.06), gated=True, note="glow-stone gated")
M("arch/shrine/arch", 2, lambda r: arch(r, span=3.2, col='granite'))
M("arch/ruins/broken_wall", 4, lambda r: slab(r, r.uniform(2, 3.5), r.uniform(0.8, 1.6), 0.5, 'granite', amp=0.15))
M("arch/ruins/toppled_column", 3, lambda r: [paint(T(yup_cyl(0.3, r.uniform(1.5, 2.5), 10).apply_transform(
    trimesh.transformations.rotation_matrix(math.pi/2*0.94, [0, 0, 1])) or yup_cyl(0.3, 2), 0, 0.32, 0), C('plaster', -30))])
M("arch/ruins/foundation", 3, lambda r: slab(r, 4, 0.4, 4, 'granite', amp=0.08))
M("arch/ruins/relief_panel", 3, lambda r: slab(r, 1.8, 2.2, 0.3, 'sandstone', amp=0.04))
M("arch/bridge/plank_span", 3, lambda r: [paint(T(box(extents=[0.4, 0.06, 4.4]), x, 0.5, 0), C('wood', r.randint(-12, 12))) for x in (-0.45, 0, 0.45)])
M("arch/bridge/stone_arch", 2, lambda r: arch(r, span=5, col='granite'))
M("arch/bridge/ford_stones", 3, lambda r: [T(p, k*0.9-1.8, 0, r.uniform(-0.3, 0.3)) for k in range(5) for p in boulder(r, 'coastal', s=0.4, amp=0.08)])
M("arch/bridge/causeway", 2, lambda r: slab(r, 1.8, 0.5, 6, 'granite', amp=0.05))
# B6 props
M("props/furniture/seat", 6, lambda r: furniture(r, 'stool'))
M("props/furniture/table", 5, lambda r: furniture(r, 'table'))
M("props/furniture/storage", 6, lambda r: [paint(T(box(extents=[1.0, 1.4, 0.4]), 0, 0.7, 0), C('wood', r.randint(-12, 12)))] +
  [paint(T(box(extents=[0.94, 0.05, 0.36]), 0, 0.35+k*0.4, 0), C('wood', -20)) for k in range(3)])
M("props/container/basket", 8, lambda r: container(r, r.choice(['basket', 'crate', 'urn', 'sack'])))
M("props/goods/market", 10, lambda r: [T(p, r.uniform(-0.2, 0.2), k*0.13, r.uniform(-0.2, 0.2), s=1) for k in range(r.randint(4, 7))
   for p in [paint(icosphere(1, 0.14), C(r.choice(['pink', 'gold', 'teal', 'ochre']), r.randint(-16, 16)))]])
M("props/tools/hand", 8, lambda r: tool(r, 'generic'))
M("props/signage", 5, lambda r: [paint(T(yup_cyl(0.05, 1.8), 0, 0.9, 0), C('wood')),
   paint(T(box(extents=[0.9, 0.5, 0.05]), 0, 1.6, 0.05), C('cream', -10))])
# Fabric slots (PLAN_FABRIC F1): "wind": "fabric" flags the card for the
# fabric_wind material override at placement; "wind_hang" = meters of
# cloth at freedom 1. Pin weights live in vertex alpha (paint_pinned).
M("props/textile", 5, lambda r: ground_cloth(r, 1.6, 1.0, C(r.choice(['red', 'teal', 'purple']), 10)),
  card_extra={"wind": "fabric", "wind_hang": 0.35})
M("props/textile/banner", 3, lambda r: banner(r),
  card_extra={"wind": "fabric", "wind_hang": 1.2})
M("props/lighting", 5, lambda r: [paint(T(icosphere(1, 0.16), 0, 0.2, 0), C('mint')),
   paint(T(yup_cyl(0.04, 0.3), 0, 0.42, 0), C('slate'))], gated=True, note="glow-vessel gated")
M("props/camp/bedroll", 3, lambda r: [paint(T(yup_cyl(0.18, 1.8, 10).apply_transform(
    trimesh.transformations.rotation_matrix(math.pi/2, [1, 0, 0])) or yup_cyl(0.18, 1.8), 0, 0.18, 0), C(r.choice(['red', 'teal', 'purple']), -6))])
M("props/camp/pack", 5, lambda r: [paint(T(icosphere(1, 0.3), 0, 0.3, 0, sy=1.2), C('hide', r.randint(-14, 14)))])
M("props/camp/tent", 3, lambda r: tent(r),
  card_extra={"wind": "fabric", "wind_hang": 0.6})
M("props/camp/cart", 2, lambda r: [paint(T(box(extents=[1.2, 0.3, 2.0]), 0, 0.6, 0), C('wood'))] +
  [paint(T(yup_cyl(0.35, 0.08, 12).apply_transform(trimesh.transformations.rotation_matrix(math.pi/2, [0, 0, 1])) or yup_cyl(0.3, 0.1), sx*0.68, 0.35, 0.6), C('wood', -22)) for sx in (-1, 1)])
M("props/nautical/raft", 2, lambda r: [paint(T(yup_cyl(0.14, 2.6, 8).apply_transform(
    trimesh.transformations.rotation_matrix(math.pi/2, [1, 0, 0])) or yup_cyl(0.14, 2.6), x, 0.14, 0), C('wood', r.randint(-10, 10))) for x in np.linspace(-0.7, 0.7, 5)])
M("props/nautical/net", 4, lambda r: ground_cloth(r, 1.2, 1.2, C('sand', -30), free=0.4),
  card_extra={"wind": "fabric", "wind_hang": 0.3})
M("props/nautical/dock", 4, lambda r: [paint(T(box(extents=[1.2, 0.14, 3.0]), 0, 0.7, 0), C('wood'))] +
  [paint(T(yup_cyl(0.09, 0.9), sx*0.5, 0.45, sz*1.3), C('wood', -20)) for sx in (-1, 1) for sz in (-1, 1)])
# B7 items
for grp, n in [("forage/blooms", 8), ("forage/fruit", 8), ("forage/roots", 6),
               ("mineral", 6), ("creature", 6), ("crafted", 8), ("hero", 5)]:
    key = grp.split('/')[-1]
    M(f"items/{grp}", n, (lambda k: (lambda r: item(r, k)))(key),
      gated=(grp == "hero"), note="hero props gated on decisions" if grp == "hero" else "")
# B8 underworld (gated)
M("arch/under/stalactite", 4, lambda r: [paint(cone(radius=r.uniform(0.2, 0.5), height=r.uniform(1.5, 3), sections=8).apply_transform(
    trimesh.transformations.rotation_matrix(-math.pi/2, [1, 0, 0])) or cone(radius=0.3, height=2), C('slate', -20))], gated=True)
M("arch/under/crystal_cluster", 4, lambda r: crystal(r), gated=True)
M("arch/under/sinkhole_rim", 2, lambda r: [T(p, math.cos(a)*3, 0, math.sin(a)*3, s=1) for a in np.linspace(0, 6.28, 9)[:-1]
   for p in boulder(r, 'basalt', s=0.7)], gated=True)
M("arch/under/glow_pool", 2, lambda r: [paint(T(yup_cyl(1.8, 0.15, 16), 0, 0.07, 0), C('mint'))], gated=True)
M("arch/under/spore_stalk", 3, lambda r: seg_trunk(r, h=r.uniform(3, 5), r0=0.4, bend=0.6, col='purple', burst=False), gated=True)

def main():
    # --only <slot> (repeatable): regenerate just those slots — the drop is
    # untracked binary cache, so partial refreshes must not churn the rest.
    only = []
    args = sys.argv[1:]
    while args:
        if args[0] == "--only" and len(args) > 1:
            only.append(args[1]); args = args[2:]
        else:
            print("usage: gen_meshes.py [--only slot ...]"); return
    total = 0; cards = []
    for (slot, n, fn, gated, note, card_extra) in MESHES:
        if only and slot not in only:
            continue
        files = []
        for i in range(1, n+1):
            rng = random.Random(hash(slot) % 100000 + i*31)
            try:
                parts = fn(rng)
                parts = [p for p in parts if p is not None]
                files.append(export(parts, slot, os.path.basename(slot), i, "mesh"))
                total += 1
            except Exception as e:
                print("FAIL", slot, i, repr(e))
        card = {"slot": slot, "class": "gltf_mesh", "variants": n, "files": files,
                "status": "placeholder-synth", "generator": "gen_meshes.py",
                "collision": "-col convex hull node included", "clips": "none — static placeholder",
                "gated": gated}
        if note: card["note"] = note
        if card_extra: card.update(card_extra)
        cpath = os.path.join(ROOT, slot + ".card.json")
        os.makedirs(os.path.dirname(cpath), exist_ok=True)
        json.dump(card, open(cpath, "w"), indent=1)
        cards.append(card)
    print(f"meshes: {total} GLBs across {len(cards)} slots")

if __name__ == "__main__":
    main()
