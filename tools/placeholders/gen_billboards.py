#!/usr/bin/env python3
"""Valley placeholder billboards — procedural, in the concept paintings' language.
Flat shapes, paper grain, segmented bulbs, starbursts, laminated mounds."""
import os, json, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = "/home/claude/valley-placeholders/assets/paintings"
CARDS = []

P = {  # palette sampled from the three concept paintings
 'teal_dark':(29,78,74),'teal_deep':(20,56,54),'teal_hi':(56,112,102),
 'pine':(126,200,154),'pine_d':(88,168,122),
 'gold':(168,144,64),'gold_d':(128,110,40),'olive':(122,124,62),
 'pink':(224,85,154),'pink_soft':(240,178,182),'coral':(238,102,85),
 'sun_red':(230,70,40),
 'sky_pink':(243,205,203),'cream':(246,239,226),'pale':(238,238,242),
 'ochre':(214,164,90),'ochre_d':(196,146,70),
 'grayb':(152,162,176),'grayp':(188,194,206),
 'brown':(120,96,70),'brown_d':(102,80,58),
 'purple':(184,160,209),'purple_p':(203,182,222),
 'wpink':(240,138,138),'wpink_d':(224,108,108),
 'navy':(28,42,76),'navy_d':(20,30,58),'starp':(172,184,218),
 'moss':(110,122,58),'moss_d':(88,100,46),
 'agave':(38,74,68),'sage':(160,164,140),'sage_d':(132,138,112),
 'sand':(224,202,164),'sand_d':(200,176,136),
 'ash':(96,94,100),'ash_d':(72,70,78),'lichen':(198,206,172),
 'mint':(150,214,184),'white':(248,248,246),'sulfur':(206,186,88),
 'red_stripe':(206,72,48),
}

def V(c, dv):  # value-shift a color
    return tuple(max(0, min(255, x + dv)) for x in c)

def new(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))

def grain(img, amt=9):
    a = np.array(img).astype(np.int16)
    n = np.random.default_rng(7).integers(-amt, amt+1, a.shape[:2])
    for c in range(3):
        a[:, :, c] = np.clip(a[:, :, c] + n, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")

def blob_pts(cx, cy, rx, ry, rng, wob=0.16, n=26):
    pts = []
    for i in range(n):
        t = 2*math.pi*i/n
        w = 1 + rng.uniform(-wob, wob)
        pts.append((cx + math.cos(t)*rx*w, cy + math.sin(t)*ry*w))
    return pts

def hatch_mask(layer, mask, color, spacing=10, angle=0, width=3, alpha=255):
    w, h = layer.size
    tmp = new(w, h); d = ImageDraw.Draw(tmp)
    L = int(math.hypot(w, h))
    ca, sa = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    for k in range(-L, L, spacing):
        x0, y0 = w/2 + k*(-sa) - ca*L, h/2 + k*ca - sa*L
        x1, y1 = w/2 + k*(-sa) + ca*L, h/2 + k*ca + sa*L
        d.line([x0, y0, x1, y1], fill=color+(alpha,), width=width)
    layer.paste(tmp, (0, 0), Image.composite(tmp.split()[3], Image.new("L", (w, h), 0), mask))

def taper_poly(d, x0, y0, x1, y1, w0, w1, color):
    dx, dy = x1-x0, y1-y0
    L = math.hypot(dx, dy) or 1
    nx, ny = -dy/L, dx/L
    d.polygon([(x0+nx*w0, y0+ny*w0), (x0-nx*w0, y0-ny*w0),
               (x1-nx*w1, y1-ny*w1), (x1+nx*w1, y1+ny*w1)], fill=color)

def blade(d, x0, y0, x1, y1, bend, w0, color, segs=10):
    mx, my = (x0+x1)/2 + bend, (y0+y1)/2
    prev = (x0, y0)
    for i in range(1, segs+1):
        t = i/segs
        bx = (1-t)**2*x0 + 2*(1-t)*t*mx + t*t*x1
        by = (1-t)**2*y0 + 2*(1-t)*t*my + t*t*y1
        taper_poly(d, prev[0], prev[1], bx, by, w0*(1-t*0.92)+0.6, w0*(1-(t+0.05)*0.92)+0.5, color)
        prev = (bx, by)

def starburst(img, cx, cy, r, rng, spike_c=None, core_c=None, n=None):
    d = ImageDraw.Draw(img)
    spike_c = spike_c or P['gold']; core_c = core_c or P['pink']
    n = n or rng.randint(11, 15)
    for i in range(n):
        t = 2*math.pi*i/n + rng.uniform(-.06, .06)
        rr = r * (1.0 if i % 2 == 0 else rng.uniform(.55, .7))
        tip = (cx+math.cos(t)*rr, cy+math.sin(t)*rr)
        bw = r*0.10
        nx, ny = -math.sin(t)*bw, math.cos(t)*bw
        d.polygon([(cx+nx, cy+ny), (cx-nx, cy-ny), tip], fill=V(spike_c, rng.randint(-14, 10)))
        d.line([ (cx+tip[0])/2, (cy+tip[1])/2, tip[0], tip[1]], fill=V(spike_c, -30), width=max(1, int(r*0.02)))
    d.ellipse([cx-r*.30, cy-r*.30, cx+r*.30, cy+r*.30], fill=core_c)
    d.ellipse([cx-r*.30, cy-r*.30, cx+r*.30, cy+r*.30], outline=V(core_c, -46), width=max(2, int(r*.035)))

def seg_stalk(img, base, top, w0, rng, col=None, bulbs=None, burst=True, burst_r=None):
    """Chain of overlapping bulbs along a bent path — the signature flora form."""
    d = ImageDraw.Draw(img)
    col = col or P['teal_dark']
    x0, y0 = base; x1, y1 = top
    bend = rng.uniform(-.5, .5) * abs(y0-y1) * 0.45
    mx, my = (x0+x1)/2 + bend, (y0+y1)/2
    n = bulbs or max(4, int(abs(y0-y1)/(w0*1.15)))
    pts = []
    for i in range(n+1):
        t = i/n
        bx = (1-t)**2*x0 + 2*(1-t)*t*mx + t*t*x1
        by = (1-t)**2*y0 + 2*(1-t)*t*my + t*t*y1
        pts.append((bx, by, w0*(1-0.55*t)))
    for (bx, by, r) in pts:
        c = V(col, rng.randint(-10, 10))
        d.ellipse([bx-r, by-r*0.92, bx+r, by+r*0.92], fill=c)
        # dark striations on lower half of each bulb
        for k in range(int(r/4)):
            a = rng.uniform(math.pi*0.15, math.pi*0.85)
            sx = bx - math.cos(a)*r*0.8
            d.line([sx, by+r*0.15, sx+rng.uniform(-2,2), by+r*0.75],
                   fill=V(col, -38), width=max(1, int(r*0.09)))
        d.arc([bx-r, by-r*0.92, bx+r, by+r*0.92], 200, 340, fill=V(col, 26), width=max(1,int(r*0.10)))
    if burst:
        bx, by, r = pts[-1]
        starburst(img, bx, by - r*0.6, burst_r or w0*2.2, rng)
    return pts

def ground_shadow(img, cx, cy, rx, alpha=42):
    d = ImageDraw.Draw(img)
    d.ellipse([cx-rx, cy-rx*0.18, cx+rx, cy+rx*0.18], fill=(40, 40, 40, alpha))

def save(img, slot, name, i, meta):
    path = os.path.join(ROOT, os.path.dirname(slot))
    os.makedirs(path, exist_ok=True)
    f = os.path.join(path, f"{os.path.basename(slot)}_{i:02d}.png")
    grain(img).save(f)
    return os.path.relpath(f, ROOT)

# ---------------- generators ----------------
def g_tuft(rng, col, h=520, w=560, nb=None, thin=False, sparse=False, base_w=None):
    img = new(w, h); d = ImageDraw.Draw(img)
    cx, cy = w//2, h-30
    ground_shadow(img, cx, cy, w*0.32)
    n = nb or (rng.randint(7, 10) if sparse else rng.randint(14, 22))
    for _ in range(n):
        a = rng.uniform(-1.15, 1.15)
        L = h * rng.uniform(0.45, 0.86)
        tipx = cx + math.sin(a)*L*0.75 + rng.uniform(-14, 14)
        tipy = cy - L*abs(math.cos(a))*rng.uniform(0.8, 1.0)
        blade(d, cx+rng.uniform(-w*0.07, w*0.07), cy, tipx, tipy,
              rng.uniform(-60, 60), (base_w or (5 if thin else 10))*rng.uniform(.8, 1.25),
              V(col, rng.randint(-22, 22)))
    return img

def g_starflower(rng, spike, core, h=520, stem=True, r=None, w=460):
    img = new(w, h); d = ImageDraw.Draw(img)
    cx = w//2; r = r or w*0.28
    if stem:
        blade(d, cx, h-24, cx+rng.uniform(-30, 30), int(r*1.2)+10, rng.uniform(-40, 40), 9, P['teal_deep'])
        ground_shadow(img, cx, h-24, w*0.2)
    starburst(img, cx, int(r*1.1), r, rng, spike, core)
    return img

def g_rosette(rng, col, h=440, w=560, spikes=None, fat=False):
    img = new(w, h); d = ImageDraw.Draw(img)
    cx, cy = w//2, h-26
    ground_shadow(img, cx, cy, w*0.3)
    n = spikes or rng.randint(9, 13)
    for i in range(n):
        t = math.pi*(0.06 + 0.88*i/(n-1)) + rng.uniform(-.04, .04)
        L = h*rng.uniform(.55, .9)
        tip = (cx - math.cos(t)*L*0.72, cy - math.sin(t)*L)
        bw = (26 if fat else 15)*rng.uniform(.8, 1.2)
        nx, ny = math.sin(t)*bw, -math.cos(t)*bw  # perpendicular
        c = V(col, rng.randint(-16, 16))
        d.polygon([(cx+nx, cy+ny), (cx-nx, cy-ny), tip], fill=c)
        d.line([cx, cy, tip[0], tip[1]], fill=V(col, -30), width=3)
    return img

def g_segment_rosette(rng, col, h=380, w=520):
    img = new(w, h); d = ImageDraw.Draw(img)
    cx, cy = w//2, h-40; ground_shadow(img, cx, cy+14, w*0.3)
    for ring in range(3, 0, -1):
        rr = ring*w*0.11
        n = 5 + ring*2
        for i in range(n):
            t = 2*math.pi*i/n + ring*.3
            bx, by = cx+math.cos(t)*rr, cy - 6*ring + math.sin(t)*rr*0.42
            r = w*0.075*(1+0.14*ring)
            c = V(col, rng.randint(-14, 14) + ring*8)
            d.ellipse([bx-r, by-r, bx+r, by+r], fill=c, outline=V(col, -34), width=3)
    return img

def g_fern(rng, col, h=560, w=520, curl=False, broad=False):
    img = new(w, h); d = ImageDraw.Draw(img)
    cx, cy = w//2, h-26; ground_shadow(img, cx, cy, w*0.26)
    for _ in range(rng.randint(3, 5)):
        a = rng.uniform(-.7, .7)
        L = h*rng.uniform(.6, .9)
        tip = (cx + math.sin(a)*L*.6, cy - L*.92)
        segs = 14; prev = (cx, cy)
        for i in range(1, segs+1):
            t = i/segs
            bx = (1-t)**2*cx + 2*(1-t)*t*(cx+math.sin(a)*L*.7) + t*t*tip[0]
            by = (1-t)**2*cy + 2*(1-t)*t*(cy-L*.5) + t*t*tip[1]
            d.line([prev, (bx, by)], fill=V(col, -20), width=5)
            if i > 2:
                lw = (1-t)*(w*0.10 if broad else w*0.055)
                for s in (-1, 1):
                    d.ellipse([bx+s*lw-lw*.9, by-lw*.5, bx+s*lw+lw*.9, by+lw*.5],
                              fill=V(col, rng.randint(-14, 18)))
            prev = (bx, by)
        if curl:
            r = L*0.07
            for k in range(10):
                t = k/10*math.pi*1.6
                d.ellipse([tip[0]+math.cos(t)*r*(1-k*.07)-4, tip[1]-r+math.sin(t)*r*(1-k*.07)-4,
                           tip[0]+math.cos(t)*r*(1-k*.07)+4, tip[1]-r+math.sin(t)*r*(1-k*.07)+4], fill=V(col, -10))
    return img

def g_mat(rng, col, h=300, w=680, disc=False, hatchit=True):
    img = new(w, h); d = ImageDraw.Draw(img)
    pts = blob_pts(w/2, h*0.62, w*0.42, h*0.3, rng, .12)
    d.polygon(pts, fill=col)
    mask = Image.new("L", (w, h), 0); ImageDraw.Draw(mask).polygon(pts, fill=255)
    if hatchit:
        hatch_mask(img, mask, V(col, -34), spacing=9, angle=rng.choice([28, -28, 12]), width=3)
    if disc:
        for _ in range(rng.randint(8, 14)):
            bx, by = w/2+rng.uniform(-w*.3, w*.3), h*0.62+rng.uniform(-h*.18, h*.18)
            r = rng.uniform(10, 22)
            d.ellipse([bx-r, by-r*.5, bx+r, by+r*.5], fill=V(col, 26), outline=V(col, -30), width=2)
    d.line([w*.1, h*.62, w*.9, h*.62], fill=(0,0,0,0))
    return img

def g_pebbles(rng, cols, h=260, w=640, n=None, single=False):
    img = new(w, h); d = ImageDraw.Draw(img)
    n = 1 if single else (n or rng.randint(6, 11))
    for _ in range(n):
        bx = w/2 + (0 if single else rng.uniform(-w*.36, w*.36))
        by = h*0.62 + (0 if single else rng.uniform(-h*.14, h*.2))
        r = rng.uniform(h*.16, h*.3) if not single else h*0.34
        col = rng.choice(cols)
        pts = blob_pts(bx, by, r, r*.72, rng, .12, 16)
        d.polygon(pts, fill=V(col, rng.randint(-16, 16)))
        d.arc([bx-r, by-r*.72, bx+r, by+r*.72], 190, 330, fill=V(col, 26), width=3)
        ground_shadow(img, bx, by+r*.6, r*.9, 34)
    return img

def g_twigs(rng, col, h=220, w=640):
    img = new(w, h); d = ImageDraw.Draw(img)
    for _ in range(rng.randint(5, 8)):
        x0, y0 = rng.uniform(40, w-40), rng.uniform(h*.4, h*.85)
        a = rng.uniform(0, math.pi)
        L = rng.uniform(60, 150)
        x1, y1 = x0+math.cos(a)*L, y0-math.sin(a)*L*0.25
        # tiny segment chain (fallen stalk litter)
        n = int(L/16)
        for i in range(n):
            t = i/max(1, n-1)
            bx, by = x0+(x1-x0)*t, y0+(y1-y0)*t
            r = 8*(1-t*.4)
            d.ellipse([bx-r, by-r, bx+r, by+r], fill=V(col, rng.randint(-14, 14)))
    return img

def g_bells(rng, col, h=560, w=480):
    img = new(w, h); d = ImageDraw.Draw(img)
    cx, cy = w//2, h-26; ground_shadow(img, cx, cy, w*0.22)
    for _ in range(rng.randint(2, 3)):
        a = rng.uniform(-.5, .5)
        tipx, tipy = cx+math.sin(a)*w*.4, h*0.2+rng.uniform(-20, 30)
        blade(d, cx, cy, tipx, tipy, rng.uniform(-70, 70), 7, P['teal_deep'])
        for k in range(rng.randint(3, 5)):
            t = 0.45+0.14*k
            bx = (1-t)**2*cx + 2*(1-t)*t*(cx+math.sin(a)*w*.5) + t*t*tipx
            by = (1-t)**2*cy + 2*(1-t)*t*(cy-h*.45) + t*t*tipy
            bw = 20*rng.uniform(.85, 1.15)
            d.polygon([(bx-bw*.5, by), (bx+bw*.5, by), (bx+bw*.75, by+bw*1.5), (bx-bw*.75, by+bw*1.5)],
                      fill=V(col, rng.randint(-16, 16)))
            d.ellipse([bx-bw*.2, by+bw*1.3, bx+bw*.2, by+bw*1.7], fill=P['pink'])
    return img

def g_reed(rng, col, h=1000, w=560, cattail=False):
    img = new(w, h); d = ImageDraw.Draw(img)
    cx, cy = w//2, h-26; ground_shadow(img, cx, cy, w*0.24)
    for _ in range(rng.randint(5, 8) if not cattail else rng.randint(2, 3)):
        sway = rng.uniform(-90, 90)
        tipx = cx+rng.uniform(-w*.28, w*.28)+sway*.5
        tipy = rng.uniform(h*.06, h*.3)
        blade(d, cx+rng.uniform(-24, 24), cy, tipx, tipy, sway, 8, V(col, rng.randint(-20, 20)), segs=14)
        if cattail:
            for k in range(rng.randint(3, 4)):
                r = 26-k*4
                d.ellipse([tipx-r, tipy-40*k-r, tipx+r, tipy-40*k+r], fill=V(P['brown'], rng.randint(-10, 20)),
                          outline=V(P['brown'], -34), width=3)
    return img

def g_kelp(rng, col, h=900, w=420):
    img = new(w, h); d = ImageDraw.Draw(img)
    for _ in range(rng.randint(2, 3)):
        x = w*rng.uniform(.3, .7); amp = rng.uniform(28, 60); ph = rng.uniform(0, 6)
        prev = (x, h-14)
        for i in range(1, 26):
            t = i/25
            bx = x + math.sin(ph+t*5.5)*amp*(1-t*.3)
            by = h-14 - t*(h-40)
            wdt = 20*(1-t*.85)+2
            taper_poly(d, prev[0], prev[1], bx, by, wdt+3, wdt, V(col, rng.randint(-16, 16)))
            if i % 3 == 0:
                d.ellipse([bx-5, by-5, bx+5, by+5], fill=V(col, 30))
            prev = (bx, by)
    return img

def g_lilydisc(rng, col, h=360, w=560, big=False):
    img = new(w, h); d = ImageDraw.Draw(img)
    cx, cy = w/2, h/2
    rx, ry = w*0.42, h*0.36
    d.ellipse([cx-rx, cy-ry, cx+rx, cy+ry], fill=col, outline=V(col, -36), width=5)
    a0 = rng.uniform(0, 360)
    d.pieslice([cx-rx, cy-ry, cx+rx, cy+ry], a0, a0+rng.uniform(22, 40), fill=(0, 0, 0, 0))
    for _ in range(rng.randint(6, 10)):
        t = rng.uniform(0, 2*math.pi)
        d.ellipse([cx+math.cos(t)*rx*.8-4, cy+math.sin(t)*ry*.8-4,
                   cx+math.cos(t)*rx*.8+4, cy+math.sin(t)*ry*.8+4], fill=V(col, 30))
    if big:
        d.ellipse([cx-14, cy-14, cx+14, cy+14], fill=P['pink_soft'])
    return img

def g_driftwood(rng, h=420, w=680):
    img = new(w, h); d = ImageDraw.Draw(img)
    tuft = g_tuft(rng, P['sage'], h=int(h*.9), w=w, sparse=True)
    img.alpha_composite(tuft, (0, 0))
    y = h-70
    pts = blob_pts(w/2, y, w*0.3, 30, rng, .2, 18)
    d.polygon(pts, fill=P['grayp'])
    hatchm = Image.new("L", img.size, 0); ImageDraw.Draw(hatchm).polygon(pts, fill=255)
    hatch_mask(img, hatchm, V(P['grayp'], -40), spacing=12, angle=4, width=3)
    return img

def g_crust(rng, col, base=None, h=300, w=640, rings=False):
    img = new(w, h); d = ImageDraw.Draw(img)
    for _ in range(rng.randint(5, 9)):
        bx, by = rng.uniform(60, w-60), rng.uniform(h*.35, h*.8)
        r = rng.uniform(24, 66)
        pts = blob_pts(bx, by, r, r*.6, rng, .3, 14)
        d.polygon(pts, fill=V(col, rng.randint(-14, 20)))
        if rings:
            d.ellipse([bx-r*.5, by-r*.3, bx+r*.5, by+r*.3], outline=V(col, -44), width=3)
        else:
            for _ in range(int(r/6)):
                px, py = bx+rng.uniform(-r*.6, r*.6), by+rng.uniform(-r*.4, r*.4)
                d.ellipse([px-2, py-2, px+2, py+2], fill=V(col, -40))
    return img

def g_cushion(rng, col, h=340, w=520, dotted=True):
    img = new(w, h); d = ImageDraw.Draw(img)
    cx, cy = w/2, h-40; ground_shadow(img, cx, cy+10, w*.32)
    pts = blob_pts(cx, cy-h*.18, w*.4, h*.36, rng, .1)
    d.polygon(pts, fill=col)
    mask = Image.new("L", (w, h), 0); ImageDraw.Draw(mask).polygon(pts, fill=255)
    hatch_mask(img, mask, V(col, -30), spacing=8, angle=rng.choice([20, -20]), width=2)
    if dotted:
        for _ in range(rng.randint(10, 18)):
            t = rng.uniform(0, 2*math.pi); rr = rng.uniform(0, w*.33)
            px, py = cx+math.cos(t)*rr, cy-h*.18+math.sin(t)*rr*.8
            d.ellipse([px-4, py-4, px+4, py+4], fill=V(col, 42))
    return img

def g_bulbflower(rng, h=1300, w=760):
    img = new(w, h); rngr = rng
    ground_shadow(img, w//2, h-26, w*.22)
    seg_stalk(img, (w//2, h-30), (w//2+rng.uniform(-120, 120), h*0.18), w*0.085, rng,
              col=P['teal_dark'], burst=True, burst_r=w*0.22)
    return img

def g_spirebloom(rng, col, core, h=1200, w=520):
    img = new(w, h); d = ImageDraw.Draw(img)
    cx = w//2; ground_shadow(img, cx, h-26, w*.2)
    blade(d, cx, h-26, cx+rng.uniform(-40, 40), h*.14, rng.uniform(-50, 50), 10, P['olive'], segs=14)
    for k in range(rng.randint(5, 8)):
        t = k/8
        by = h*.16 + t*h*.34
        r = 16+18*t
        d.ellipse([cx-r+rng.uniform(-8, 8), by-r*.6, cx+r+rng.uniform(-8, 8), by+r*.6],
                  fill=V(col, rng.randint(-16, 16)))
    starburst(img, cx, int(h*.12), w*.2, rng, col, core)
    return img

def g_horizon_mound(rng, cols, h=900, w=1600, peaked=False, mesa=False, cone=False, treeline=False, dunes=False):
    img = new(w, h); d = ImageDraw.Draw(img)
    col = rng.choice(cols)
    if treeline:
        for i in range(rng.randint(14, 20)):
            bx = w*i/16 + rng.uniform(-30, 30)
            r = rng.uniform(60, 130)
            d.ellipse([bx-r, h-r*2.2, bx+r, h], fill=V(col, rng.randint(-20, 12)))
        return img
    base = h-8
    if mesa:
        topw, topy = w*rng.uniform(.4, .6), h*rng.uniform(.28, .42)
        pts = [(w*.06, base), (w*.5-topw/2, topy), (w*.5+topw/2, topy), (w*.94, base)]
    elif cone:
        pts = [(w*.1, base), (w*.46, h*.14), (w*.5, h*.16), (w*.54, h*.14), (w*.9, base)]
    elif dunes:
        pts = [(0, base)]
        x = 0
        while x < w:
            x += rng.uniform(w*.2, w*.4)
            pts.append((x, h*rng.uniform(.45, .7)))
            pts.append((min(w, x+rng.uniform(w*.1, w*.2)), base*rng.uniform(.9, 1)))
        pts.append((w, base))
    else:
        pts = []
        n = 40
        for i in range(n+1):
            t = i/n
            y = base - math.sin(t*math.pi)**(0.7 if peaked else 1.4) * h*rng.uniform(.78, .9)
            pts.append((w*.04 + t*w*.92, y))
        pts = [(w*.04, base)] + pts + [(w*.96, base)]
    d.polygon(pts, fill=col)
    mask = Image.new("L", (w, h), 0); ImageDraw.Draw(mask).polygon(pts, fill=255)
    # vertical wavy striations — the paintings' laminated look
    tmp = new(w, h); td = ImageDraw.Draw(tmp)
    for x in range(0, w, rng.randint(26, 40)):
        pts2 = []
        for yy in range(0, h, 24):
            pts2.append((x + math.sin(yy*.02 + x)*10, yy))
        td.line(pts2, fill=V(col, -28)+(255,), width=6)
    img.paste(tmp, (0, 0), Image.composite(tmp.split()[3], Image.new("L", (w, h), 0), mask))
    # top light rim
    d.line(pts[1:-1], fill=V(col, 30), width=8)
    if cone:
        for k in range(6):
            d.ellipse([w*.5-30+k*8, h*.16-40-k*26, w*.5+30+k*10, h*.16-k*26], fill=(200, 200, 205, 90))
    return img

def g_sky(name, w=512, h=1536):
    stops = {
      'sky_dawn':  [(246, 205, 205), (247, 233, 220), (238, 238, 242)],
      'sky_day':   [(233, 240, 244), (243, 243, 238), (247, 242, 230)],
      'sky_dusk':  [(242, 188, 178), (246, 224, 196), (240, 235, 228)],
      'sky_night': [(40, 46, 88), (74, 70, 110), (128, 108, 132)],
      'sky_storm': [(148, 152, 162), (176, 178, 184), (205, 205, 208)],
    }[name]
    a = np.zeros((h, w, 4), np.uint8); a[:, :, 3] = 255
    for y in range(h):
        t = y/(h-1)
        if t < .5:
            c0, c1, tt = stops[0], stops[1], t*2
        else:
            c0, c1, tt = stops[1], stops[2], (t-.5)*2
        col = [int(c0[i]+(c1[i]-c0[i])*tt) for i in range(3)]
        a[y, :, :3] = col
    img = Image.fromarray(a, "RGBA")
    d = ImageDraw.Draw(img)
    if name == 'sky_night':
        rng = random.Random(5)
        for _ in range(160):
            x, y = rng.uniform(0, w), rng.uniform(0, h*.75)
            r = rng.uniform(1, 2.6)
            d.ellipse([x-r, y-r, x+r, y+r], fill=P['starp'])
        for _ in range(14):  # mint day-stars like painting 3
            x, y = rng.uniform(0, w), rng.uniform(0, h*.5)
            starburst(img, x, y, rng.uniform(6, 11), rng, P['mint'], P['mint'], n=8)
    if name == 'sky_dusk':
        d.ellipse([w*.62, h*.08, w*.62+90, h*.08+90], fill=P['sun_red'])
    return img

def g_cloudband(rng, w=1600, h=360):
    img = new(w, h); d = ImageDraw.Draw(img)
    y = h*.55
    pts = [(0, h)]
    x = 0
    while x < w:
        r = rng.uniform(60, 150)
        d.ellipse([x-r, y-r*.8+rng.uniform(-20, 20), x+r, y+r*.6], fill=(247, 244, 238, 235))
        x += r*rng.uniform(.7, 1.1)
    d.rectangle([0, y+30, w, h], fill=(247, 244, 238, 235))
    d.line([0, y+90, w, y+90], fill=(214, 206, 200, 120), width=10)
    return img

def g_crack(rng, w=800, h=800):
    img = new(w, h); d = ImageDraw.Draw(img)
    def walk(x, y, a, L, wd):
        while L > 0 and wd > 0.7:
            nx, ny = x+math.cos(a)*14, y+math.sin(a)*14
            d.line([x, y, nx, ny], fill=(60, 48, 40, 200), width=int(wd))
            if rng.random() < .16:
                walk(x, y, a+rng.uniform(.5, 1.1)*rng.choice([-1, 1]), L*.5, wd*.6)
            a += rng.uniform(-.3, .3); x, y = nx, ny; L -= 14; wd *= .985
    for _ in range(rng.randint(2, 3)):
        walk(rng.uniform(w*.2, w*.8), rng.uniform(h*.2, h*.8), rng.uniform(0, 6.3), rng.uniform(260, 420), 9)
    return img

def g_stain(rng, col, w=800, h=420, bands=True):
    img = new(w, h); d = ImageDraw.Draw(img)
    for k in range(rng.randint(3, 5)):
        y = h*.3 + k*h*.14
        pts = [(x, y+math.sin(x*.02+k)*10+rng.uniform(-4, 4)) for x in range(0, w, 20)]
        d.line(pts, fill=col+(90+k*20,), width=int(16-k*2))
    return img

def g_scorch(rng, w=700, h=700):
    img = new(w, h)
    a = np.zeros((h, w, 4), np.uint8)
    cy, cx = h/2, w/2
    yy, xx = np.mgrid[0:h, 0:w]
    rr = np.hypot(xx-cx, yy-cy)/(w*.45)
    n = np.random.default_rng(rng.randint(0, 9999)).random((h, w))
    alpha = np.clip((1-rr)*220*(0.75+0.5*n), 0, 220)
    a[:, :, 3] = alpha.astype(np.uint8)
    a[:, :, 0] = 42; a[:, :, 1] = 36; a[:, :, 2] = 38
    return Image.fromarray(a, "RGBA")

def g_pathwear(rng, w=1200, h=460):
    img = new(w, h); d = ImageDraw.Draw(img)
    pts = blob_pts(w/2, h/2, w*.44, h*.3, rng, .18)
    d.polygon(pts, fill=(206, 188, 156, 130))
    for _ in range(60):
        x, y = rng.uniform(w*.1, w*.9), rng.uniform(h*.25, h*.75)
        d.ellipse([x-3, y-2, x+3, y+2], fill=(180, 160, 130, 120))
    return img

def g_swarm(rng, kind, w=420, h=420):
    img = new(w, h); d = ImageDraw.Draw(img)
    if kind == 'butterfly':
        c = rng.choice([P['pink'], P['gold'], P['mint'], P['coral']])
        cx, cy = w/2, h/2
        for s in (-1, 1):
            d.ellipse([cx+s*8-46*(s==1), cy-40, cx+s*8+46*(s==-1)+ (92 if s==1 else 0), cy+6], fill=V(c, 10))
            d.ellipse([cx+s*6-32*(s==1), cy+2, cx+s*6+32*(s==-1)+(64 if s==1 else 0), cy+40], fill=V(c, -14))
        d.line([cx, cy-34, cx, cy+34], fill=(40, 34, 30, 255), width=6)
        d.ellipse([cx-16, cy-16, cx+16, cy+16], fill=(0,0,0,0))
        d.ellipse([cx+18, cy-20, cx+30, cy-8], fill=V(c, 60))
    elif kind == 'gnat_column':
        for _ in range(rng.randint(26, 40)):
            x = w/2+rng.gauss(0, w*.09); y = rng.uniform(h*.06, h*.94)
            d.ellipse([x-2.5, y-2.5, x+2.5, y+2.5], fill=(50, 46, 50, 190))
    elif kind == 'shore_birds':
        for _ in range(rng.randint(7, 12)):
            x, y = rng.uniform(30, w-30), rng.uniform(30, h-30)
            s = rng.uniform(8, 22)
            d.arc([x-s, y-s*.6, x, y+s*.6], 200, 340, fill=(30, 28, 34, 255), width=4)
            d.arc([x, y-s*.6, x+s, y+s*.6], 200, 340, fill=(30, 28, 34, 255), width=4)
    elif kind == 'pollen_drift':
        for _ in range(rng.randint(18, 30)):
            x, y, r = rng.uniform(0, w), rng.uniform(0, h), rng.uniform(2, 6)
            d.ellipse([x-r, y-r, x+r, y+r], fill=(246, 226, 170, rng.randint(90, 200)))
    elif kind == 'glow_mote':
        for _ in range(rng.randint(6, 10)):
            x, y, r = rng.uniform(40, w-40), rng.uniform(40, h-40), rng.uniform(6, 14)
            for k in range(4, 0, -1):
                d.ellipse([x-r*k/2, y-r*k/2, x+r*k/2, y+r*k/2], fill=P['mint']+(30*k,))
    elif kind == 'ash_ember':
        for _ in range(rng.randint(10, 18)):
            x, y, r = rng.uniform(0, w), rng.uniform(0, h), rng.uniform(2.5, 5)
            d.ellipse([x-r, y-r, x+r, y+r], fill=rng.choice([(238, 120, 60), (222, 80, 44)])+(rng.randint(150, 230),))
            d.line([x, y, x+rng.uniform(-8, 8), y+rng.uniform(10, 24)], fill=(238, 120, 60, 70), width=2)
    return img

def g_branches(rng, w=1200, h=1200):
    img = new(w, h); d = ImageDraw.Draw(img)
    col = P['brown_d']
    def br(x, y, a, L, wd, depth):
        if depth == 0 or L < 20: return
        nx, ny = x+math.cos(a)*L, y-math.sin(a)*L
        taper_poly(d, x, y, nx, ny, wd, wd*.6, V(col, rng.randint(-10, 10)))
        for _ in range(rng.randint(2, 3)):
            br(nx, ny, a+rng.uniform(-.7, .7), L*rng.uniform(.6, .78), wd*.6, depth-1)
    br(w/2, h-20, math.pi/2+rng.uniform(-.15, .15), h*.3, 26, 5)
    return img

def foliage_sheet(rng, kind, w=1600, h=1600):
    """2x2 clump sheet — camera-facing leaf cards for hybrid trees."""
    img = new(w, h)
    for (qx, qy) in [(0, 0), (1, 0), (0, 1), (1, 1)]:
        cx, cy = int(w*.25+qx*w*.5), int(h*.28+qy*h*.5)
        cl = new(w//2, h//2); d = ImageDraw.Draw(cl)
        ccx, ccy = w//4, h//4
        if kind in ('canopy_bulb', 'broadleaf_bulb'):
            col = P['pine'] if kind == 'canopy_bulb' else P['teal_hi']
            for _ in range(rng.randint(9, 13)):
                t = rng.uniform(0, 2*math.pi); rr = rng.uniform(0, w*.11)
                bx, by = ccx+math.cos(t)*rr, ccy+math.sin(t)*rr*.7
                r = rng.uniform(w*.035, w*.06)
                c = V(col, rng.randint(-22, 18))
                d.ellipse([bx-r, by-r, bx+r, by+r], fill=c, outline=V(col, -36), width=4)
                for _ in range(5):
                    px, py = bx+rng.uniform(-r*.5, r*.5), by+rng.uniform(-r*.5, r*.5)
                    d.ellipse([px-3, py-3, px+3, py+3], fill=V(P['pink_soft'], rng.randint(-20, 10)))
        elif kind in ('weeping_frond', 'swamp_arch'):
            col = P['teal_dark'] if kind == 'swamp_arch' else P['pine_d']
            for _ in range(rng.randint(10, 14)):
                a = rng.uniform(-math.pi, 0)
                L = rng.uniform(w*.09, w*.16)
                tip = (ccx+math.cos(a)*L, ccy-math.sin(a)*L*(-1)+L*.6)
                blade(d, ccx, ccy, tip[0], min(tip[1], h/2-8), rng.uniform(-40, 40), 12, V(col, rng.randint(-18, 18)))
        elif kind in ('scrub_palm', 'wind_palm'):
            col = P['navy'] if kind == 'wind_palm' else P['olive']
            lean = w*.03 if kind == 'wind_palm' else 0
            for i in range(rng.randint(8, 11)):
                a = math.pi*(0.05+0.9*i/10)
                L = rng.uniform(w*.1, w*.16)
                tip = (ccx+lean-math.cos(a)*L, ccy-math.sin(a)*L*.8)
                blade(d, ccx, ccy+10, tip[0], tip[1], rng.uniform(-30, 30), 10, V(col, rng.randint(-16, 20)))
        elif kind == 'thorn_arch':
            col = P['brown']
            for _ in range(rng.randint(12, 16)):
                a = rng.uniform(0, 2*math.pi); L = rng.uniform(w*.05, w*.12)
                tip = (ccx+math.cos(a)*L, ccy+math.sin(a)*L*.8)
                d.line([ccx, ccy, tip[0], tip[1]], fill=V(col, rng.randint(-16, 12)), width=7)
                d.ellipse([tip[0]-5, tip[1]-5, tip[0]+5, tip[1]+5], fill=V(P['gold_d'], 10))
        elif kind == 'ash_snag':
            col = P['ash']
            for _ in range(rng.randint(4, 6)):
                a = rng.uniform(0, 2*math.pi); L = rng.uniform(w*.06, w*.11)
                d.line([ccx, ccy, ccx+math.cos(a)*L, ccy+math.sin(a)*L*.7], fill=V(col, rng.randint(-14, 14)), width=9)
        elif kind == 'lone_spire':
            col = P['teal_dark']
            for k in range(4):
                r = w*.05*(1-k*.16)
                d.ellipse([ccx-r, ccy-k*r*1.5-r, ccx+r, ccy-k*r*1.5+r], fill=V(col, rng.randint(-10, 10)),
                          outline=V(col, -34), width=4)
            starburst(cl, ccx, ccy-4*w*.05*1.4, w*.05, rng)
        img.alpha_composite(cl, (qx*w//2, qy*h//2))
    return img

# ---------------- manifest ----------------
def n_rng(seed): return random.Random(seed)

ASSETS = []
def A(slot, n, fn, gated=False, note=""):
    ASSETS.append((slot, n, fn, gated, note))

# A1 filler
A("ground/filler/dry_tuft", 4, lambda r: g_tuft(r, P['sage'], thin=True), note="retires the ⚠ SVG")
A("ground/filler/small_stone", 4, lambda r: g_pebbles(r, [P['grayb'], P['grayp'], P['brown']], single=True))
A("ground/filler/twig_litter", 3, lambda r: g_twigs(r, P['teal_deep']))
A("ground/filler/dust_clump", 3, lambda r: g_pebbles(r, [P['sand'], P['sand_d']], n=5))
# A1 oasis
A("ground/oasis/teal_grass", 4, lambda r: g_tuft(r, P['teal_dark']))
A("ground/oasis/clover_mat", 3, lambda r: g_mat(r, P['moss'], disc=True))
A("ground/oasis/violet_bells", 3, lambda r: g_bells(r, P['purple']))
A("ground/oasis/curl_fern", 3, lambda r: g_fern(r, P['pine_d'], curl=True))
A("ground/oasis/star_bloom", 4, lambda r: g_starflower(r, P['gold'], P['pink'], r=120))
A("ground/oasis/moss_cushion", 3, lambda r: g_cushion(r, P['moss']))
# A1 scrub
A("ground/scrub/needle_grass", 4, lambda r: g_tuft(r, P['sage_d'], thin=True))
A("ground/scrub/ochre_bloom", 3, lambda r: g_starflower(r, P['ochre'], P['coral'], r=95, h=420))
A("ground/scrub/ground_succulent", 4, lambda r: g_segment_rosette(r, P['teal_hi']))
A("ground/scrub/thistle_star", 3, lambda r: g_starflower(r, P['brown'], P['gold_d'], r=100, h=460))
A("ground/scrub/gray_sage", 3, lambda r: g_cushion(r, P['sage_d'], dotted=False))
# A1 dune
A("ground/dune/dune_grass", 4, lambda r: g_tuft(r, V(P['sand_d'], -20), thin=True, sparse=True))
A("ground/dune/sand_bloom", 3, lambda r: g_starflower(r, P['pink_soft'], P['pink'], r=80, h=380))
A("ground/dune/spine_cluster", 3, lambda r: g_rosette(r, P['agave'], h=340))
A("ground/dune/dry_scatter", 3, lambda r: g_twigs(r, P['sand_d']))
# A1 wetland
A("ground/wetland/sedge_tuft", 4, lambda r: g_tuft(r, P['teal_hi'], nb=26))
A("ground/wetland/marsh_fern", 3, lambda r: g_fern(r, P['pine_d'], broad=True))
A("ground/wetland/water_bloom", 3, lambda r: g_starflower(r, P['pink'], P['gold'], r=105, h=460))
A("ground/wetland/moss_mat", 3, lambda r: g_mat(r, P['moss_d']))
A("ground/wetland/floating_disc", 3, lambda r: g_lilydisc(r, P['pine_d']))
# A1 strand
A("ground/strand/beach_grass", 4, lambda r: g_tuft(r, P['sand_d'], nb=18))
A("ground/strand/shore_bloom", 3, lambda r: g_starflower(r, P['coral'], P['cream'], r=90, h=420))
A("ground/strand/sea_holly", 3, lambda r: g_rosette(r, P['teal_hi'], h=400))
A("ground/strand/driftwood_tuft", 3, lambda r: g_driftwood(r))
A("ground/strand/kelp_ribbon", 4, lambda r: g_kelp(r, P['olive'], h=520, w=520))
# A1 volcanic
A("ground/volcanic/lichen_crust", 4, lambda r: g_crust(r, P['lichen']))
A("ground/volcanic/ash_grass", 3, lambda r: g_tuft(r, P['ash'], thin=True, sparse=True))
A("ground/volcanic/pioneer_bloom", 3, lambda r: g_starflower(r, P['coral'], P['gold'], r=85, h=400))
A("ground/volcanic/sulfur_tuft", 3, lambda r: g_tuft(r, P['sulfur'], sparse=True))
A("ground/volcanic/cinder_moss", 3, lambda r: g_mat(r, V(P['moss_d'], -30)))
# A1 peak
A("ground/peak/rock_lichen", 4, lambda r: g_crust(r, P['lichen'], rings=True))
A("ground/peak/peak_cushion", 3, lambda r: g_cushion(r, P['terre'] if 'terre' in P else P['sage'], dotted=True))
A("ground/peak/alpine_star", 3, lambda r: g_starflower(r, P['white'], P['pink'], r=85, h=380))
A("ground/peak/snow_tuft", 2, lambda r: g_tuft(r, P['sage'], sparse=True, thin=True))
# A2 blooms
A("blooms/starburst_gold", 4, lambda r: g_starflower(r, P['gold'], P['pink'], h=1300, w=1100, r=330))
A("blooms/pink_pool_lily", 3, lambda r: g_lilydisc(r, P['wpink'], big=True, h=520, w=820))
A("blooms/bulb_flower", 4, lambda r: g_bulbflower(r))
A("blooms/night_bloom", 3, lambda r: g_starflower(r, P['mint'], P['starp'], h=900, w=700, r=200))
A("blooms/spire_bloom", 3, lambda r: g_spirebloom(r, P['ochre'], P['pink']))
A("blooms/ember_bloom", 3, lambda r: g_starflower(r, P['sun_red'], P['gold'], h=900, w=700, r=210))
A("blooms/tide_flower", 3, lambda r: g_starflower(r, P['coral'], P['cream'], h=800, w=640, r=180))
A("blooms/glow_bloom", 4, lambda r: g_starflower(r, P['mint'], P['mint'], h=900, w=700, r=210), gated=True,
  note="UND — gated on glow fiction; placeholder only")
# A3 water margin
A("water/reed_tall", 4, lambda r: g_reed(r, P['teal_hi']))
A("water/cattail_bulb", 3, lambda r: g_reed(r, P['olive'], cattail=True))
A("water/rush_clump", 3, lambda r: g_reed(r, P['pine_d'], h=760, w=520))
A("water/lily_disc_big", 3, lambda r: g_lilydisc(r, P['pine_d'], big=True, h=460, w=760))
A("water/kelp_frond", 4, lambda r: g_kelp(r, P['moss']))
A("water/pool_moss", 3, lambda r: g_mat(r, P['moss'], h=380, w=760))
# A4 foliage sheets
for k, n in [("canopy_bulb", 3), ("weeping_frond", 2), ("thorn_arch", 3), ("scrub_palm", 2),
             ("broadleaf_bulb", 3), ("swamp_arch", 2), ("wind_palm", 2), ("ash_snag", 2), ("lone_spire", 2)]:
    A(f"foliage/{k}_cards", n, (lambda kk: (lambda r: foliage_sheet(r, kk)))(k))
A("foliage/bare_winter", 4, lambda r: g_branches(r))
# A5 swarms
for k, n in [("butterfly", 3), ("gnat_column", 2), ("pollen_drift", 2), ("ash_ember", 2)]:
    A(f"swarms/{k}", n, (lambda kk: (lambda r: g_swarm(r, kk)))(k))
A("swarms/shore_wheel", 3, lambda r: g_swarm(r, "shore_birds", w=900, h=520))
A("swarms/glow_mote", 2, lambda r: g_swarm(r, "glow_mote"), gated=True, note="UND gated")
# A6 horizon
A("horizon/mountain_striped", 4, lambda r: g_horizon_mound(r, [P['ochre'], P['grayb'], P['brown'], P['purple']]))
A("horizon/mesa_far", 3, lambda r: g_horizon_mound(r, [P['ochre_d'], P['brown']], mesa=True))
A("horizon/sea_stack", 3, lambda r: g_horizon_mound(r, [P['grayb'], P['ash']], peaked=True, w=700))
A("horizon/volcano_cone", 2, lambda r: g_horizon_mound(r, [P['ash_d']], cone=True))
A("horizon/dune_ridge", 2, lambda r: g_horizon_mound(r, [P['sand'], P['sand_d']], dunes=True))
A("horizon/tree_line", 3, lambda r: g_horizon_mound(r, [P['teal_dark'], P['pine_d']], treeline=True, h=420))
# A7 sky
for k in ["sky_dawn", "sky_day", "sky_dusk", "sky_night", "sky_storm"]:
    A(f"sky/{k.split('_')[1]}", 1, (lambda kk: (lambda r: g_sky(kk)))(k))
A("sky/cloud_bands", 4, lambda r: g_cloudband(r))
# A8 decals
A("decals/crack", 4, lambda r: g_crack(r))
A("decals/lichen_splash", 4, lambda r: g_crust(r, P['lichen'], w=800, h=800))
A("decals/moss_patch", 3, lambda r: g_mat(r, P['moss'], w=800, h=520))
A("decals/tide_stain", 3, lambda r: g_stain(r, P['grayb']))
A("decals/scorch", 3, lambda r: g_scorch(r))
A("decals/path_wear", 4, lambda r: g_pathwear(r))

# fix: peak_cushion palette key
P['terre'] = (107, 130, 102)

def main():
    total = 0
    for (slot, n, fn, gated, note) in ASSETS:
        files = []
        for i in range(1, n+1):
            rng = n_rng(hash(slot) % 100000 + i*17)
            img = fn(rng)
            files.append(save(img, slot, os.path.basename(slot), i, None))
            total += 1
        card = {"slot": slot, "class": "billboard_png", "variants": n, "files": files,
                "status": "placeholder-synth", "generator": "gen_billboards.py",
                "gated": gated}
        if note: card["note"] = note
        cpath = os.path.join(ROOT, slot + ".card.json")
        os.makedirs(os.path.dirname(cpath), exist_ok=True)
        json.dump(card, open(cpath, "w"), indent=1)
        CARDS.append(card)
    print(f"billboards: {total} PNGs across {len(ASSETS)} slots")

if __name__ == "__main__":
    main()
