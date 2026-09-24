"""Griffith Observatory reference rebuild: measured layout, rebuilt architecture and layered planting.

Design: docs/design/landmark-scenes-2026-09-23/griffith_observatory_scene_v1.png (1536 x 1024).
Run: /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/build_griffith_observatory.py

Every layout coordinate below is a design pixel (u, v) converted through the review camera
(orthographic, pitch 45 deg, yaw 0, 58 px/m, screen centre = world origin): x = (u-768)/58 and,
for a point at height y, z = (v-512)/41 + y. The observatory sits on a hilltop; everything past
the ridge falls away to a hazy valley, so the far band of the frame reads as distant scenery.
World frame = Godot: x east, y up, z south (toward the camera), meters.
"""

import json
import math
import random
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from landmark_kit import Kit, reset_scene, hex_rgb  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/landmarks/griffith_observatory"
random.seed(20260923)
reset_scene()

C = {
    "__paint__": "ffffff",
    "cream": "f0e4c9", "cream_shade": "d7cbb1", "cream_light": "fff4db", "stone": "d6cdbd",
    "dome": "60768b", "dome_rib": "54697c", "dome_light": "8195a7", "glass": "629ba9",
    "teal": "5aaeb2", "teal_light": "93d6d2", "door": "9a6a3e", "door_dark": "74502e",
    "pave": "e8dcc3", "sand_pave": "e9d3a0", "plaza": "d4cfc7", "plaza_ring": "c3bdb4", "star": "eee3cc",
    "leaf": "84ad56", "leaf_light": "a2c56c", "leaf_dark": "628b48", "cypress": "659849", "cypress_light": "7ba755",
    "olive": "8aa34a", "olive_light": "a9bd62",
    "bush": "87b753", "bush_light": "a4c769", "trunk": "7a5a3a",
    "rock": "b9b6ac", "rock_dark": "9e9b92", "iron": "3b4046", "globe": "fff6dc",
    "bench": "a8733f", "rope": "efe8d8", "post": "8a6a45",
    "flower": "fffaf0", "flower_heart": "f2cf4f", "roof_green": "5b9a7e", "roof_green_light": "79b597",
    "awning_w": "f7f3ea", "awning_g": "7db39a", "umbrella": "f3e7cc", "table": "a8733f",
    "city1": "b8cbd7", "city2": "b1bed0", "city3": "c8d8de", "city_roof": "dbe4e8", "city_road": "ced8dc", "city_park": "b4cbab",
    "water_basin": "cfc6b6", "planter": "d9cfbd",
}
kit = Kit(OUT, C)
S = 58.0          # design px per meter
K = S * math.sqrt(0.5)  # px per (z - y) meter at 45 deg


def P(u, v, y=0.0):
    """Design pixel on a surface at height y -> world (x, z)."""
    return ((u - 768) / S, (v - 512) / K + y)


def Ps(pts, y=0.0):
    return [P(u, v, y) for u, v in pts]


# --------------------------------------------------------------------------------------------
# geometry helpers
# --------------------------------------------------------------------------------------------
def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def seg_dist(px, pz, a, b):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz)))
    return math.hypot(px - ax - t * dx, pz - az - t * dz)


def poly_dist(px, pz, pts):
    return min(seg_dist(px, pz, pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def inside_poly(px, pz, pts):
    c = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, zi = pts[i]
        xj, zj = pts[j]
        if (zi > pz) != (zj > pz) and px < (xj - xi) * (pz - zi) / (zj - zi) + xi:
            c = not c
        j = i
    return c


def poly_sdf(px, pz, pts):
    d = poly_dist(px, pz, pts + [pts[0]])
    return -d if inside_poly(px, pz, pts) else d


def chaikin(pts, rounds=3):
    for _ in range(rounds):
        out = []
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            out.append((a[0] * 0.75 + b[0] * 0.25, a[1] * 0.75 + b[1] * 0.25))
            out.append((a[0] * 0.25 + b[0] * 0.75, a[1] * 0.25 + b[1] * 0.75))
        pts = out
    return pts


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


# --------------------------------------------------------------------------------------------
# traced layout
# --------------------------------------------------------------------------------------------
TERRACE_Y = 0.5
LAWN_Y = 0.03

# Building: side observatories traced at design (540, 355) and (1040, 410) base fronts, r 1.3.
BUILDING_ORIGIN = (0.38, -3.96)
BUILDING_YAW = 8.8   # right wing nearer the camera
TOWER_X = 4.36
TOWER_R = 1.3

FORECOURT = Ps([(480, 300), (600, 190), (1000, 230), (1150, 330), (1150, 400), (1090, 460), (1000, 478),
                (835, 455), (640, 440), (440, 470), (440, 395)], TERRACE_Y)
WEST_TERRACE = chaikin(Ps([(130, 335), (400, 330), (440, 395), (430, 405), (300, 405), (180, 402),
                           (140, 390)], TERRACE_Y), 2)
CAFE = (*P(1300, 545, TERRACE_Y), 3.2)
CAFE_LINK = [(4.55, -2.4), (8.3, -2.4), (8.3, 0.9), (4.55, 0.9)]

# Stairs (x0, x1, z_top, z_bottom, y_top, y_bottom).
STAIRS = [(-2.2, 1.15, -1.15, -0.05, TERRACE_Y, 0.0),      # forecourt -> garden (design 640-835 px)
          (-8.05, -6.75, -2.15, -1.3, TERRACE_Y, 0.0),      # west terrace -> sand walk (design 310-385 px)
          (4.65, 5.85, 0.85, 1.65, TERRACE_Y, 0.0),           # cafe terrace -> east garden
          (7.8, 8.85, 6.55, 7.45, 0.0, -0.6)]               # garden -> lower right path

# Hilltop garden (y = 0): lawn islands + sand ring path, bounded by the fences.
PLATEAU = Ps([(430, 505), (440, 420), (170, 420), (150, 470), (215, 600), (300, 720), (335, 747), (330, 790), (560, 850),
              (700, 880), (1000, 815), (1100, 780), (1060, 700), (1060, 620), (1050, 560), (1000, 530),
              (840, 515)])
PLAZA = (*P(690, 615), 2.0)
LAWNS = [chaikin(Ps(p)) for p in [
    [(390, 528), (470, 512), (560, 522), (578, 600), (570, 690), (520, 745), (420, 745), (386, 700), (386, 600)],
    [(582, 702), (758, 702), (765, 760), (750, 810), (602, 812), (578, 760)],
    [(840, 535), (900, 527), (990, 542), (1000, 640), (985, 760), (850, 765), (800, 722), (810, 640)],
    [(250, 552), (370, 546), (376, 620), (262, 626)],
    [(1030, 642), (1098, 652), (1104, 744), (1036, 740)],
    [(455, 466), (636, 466), (636, 503), (455, 503)],
    [(842, 478), (998, 497), (998, 522), (842, 516)],
]]

# Paths leaving the hilltop (centerline design px with surface heights, half width m).
TRAIL_SPECS = [
    ([(330, 800, 0.0), (180, 802, -0.5), (20, 808, -1.0)], 0.75),            # west, off the left edge
    ([(520, 872, 0.0), (360, 930, -1.2), (200, 1000, -2.4)], 0.8),            # down-left toward the camera
    ([(1060, 760, 0.0), (1250, 775, -0.3), (1400, 830, -0.8), (1530, 880, -1.3)], 0.7),  # east rim path
    ([(1250, 850, -0.65), (1400, 882, -1.2), (1530, 902, -1.6)], 0.75),       # below stair D
    ([(330, 245, 0.35), (200, 172, 1.0), (60, 122, 1.6), (0, 98, 1.8)], 0.7),  # up the western hill
]
TRAILS = [([(*P(u, v, y), y) for u, v, y in pts], w) for pts, w in TRAIL_SPECS]
TRAIL_END = 0.8

PLAY = (-12.8, 12.8, -8.2, 10.5)
EXTENT = (-22.0, 22.0, -34.0, 20.0)


def terrace_sdf(x, z):
    d = poly_sdf(x, z, FORECOURT)
    d = min(d, poly_sdf(x, z, WEST_TERRACE))
    d = min(d, poly_sdf(x, z, CAFE_LINK))
    d = min(d, math.hypot(x - CAFE[0], z - CAFE[1]) - CAFE[2])
    return d


def plateau_sdf(x, z):
    return min(poly_sdf(x, z, PLATEAU), poly_sdf(x, z, [(4.0,0.4),(6.1,0.4),(6.35,3.2),(5.2,4.15),(4.3,2.5)]))


def summit_sdf(x, z):
    return min(plateau_sdf(x, z), terrace_sdf(x, z))


def lawn_sdf(x, z):
    return min(poly_sdf(x, z, p) for p in LAWNS)


def trail_info(x, z):
    """(distance to nearest trail edge, trail surface height)."""
    best, height = 1e9, 0.0
    for pts, w in TRAILS:
        for i in range(len(pts) - 1):
            ax, az, ay = pts[i]
            bx, bz, by = pts[i + 1]
            dx, dz = bx - ax, bz - az
            t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz)))
            d = math.hypot(x - ax - t * dx, z - az - t * dz) - w
            if d < best:
                best, height = d, ay + (by - ay) * t
    return best, height


def base_height(x, z):
    d = summit_sdf(x, z)
    y = 0.0 if d <= 0 else -min(9.0, 0.5 * d ** 1.15)
    # Nearby western hill rising behind the telescope terrace (design top-left).
    y += 4.4 * math.exp(-(((x + 12.5) ** 2) / 34 + ((z + 8.5) ** 2) / 14)) * smooth(-2.0, -5.5, z)
    # Ridge continuing behind the building's west half (design: near wooded hills above the left dome).
    y += 2.1 * math.exp(-(((x + 5.0) ** 2) / 40 + ((z + 11.0) ** 2) / 10))
    if d > 0:
        y += smooth(0.0,2.0,d)*(.35*math.sin(x*.62+z*.34)+.24*math.sin(z*.9-x*.36))
    # Past the ridge everything drops to a far valley; flatten it for the city.
    drop = smooth(-11.5, -17.5, z) * smooth(-3.0, 2.5, x)
    drop = max(drop, smooth(-2.0, -12.0, z) * smooth(7.5, 13.0, x))
    y = y + (-9.0 - y) * drop
    return y


def terrain_height(x, z):
    y = base_height(x, z)
    t, th = trail_info(x, z)
    if summit_sdf(x, z) > 0 and t < 0.6:
        # Trails are graded shelves cut into the slope.
        y = th + (y - th) * smooth(-0.1, 0.6, t)
    return y


def stair_height(x, z):
    for x0, x1, zt, zb, yt, yb in STAIRS:
        if x0 + 0.08 <= x <= x1 - 0.08 and zt - 0.5 <= z <= zb + 0.5:
            return yt + (yb - yt) * max(0.0, min(1.0, (z - zt) / (zb - zt)))
    return None


def walk_surface(x, z):
    s = stair_height(x, z)
    if s is not None:
        return s
    td = terrace_sdf(x, z)
    if td < -0.3:
        return TERRACE_Y
    if td < 0.3:
        return None
    if plateau_sdf(x, z) < -0.35:
        return LAWN_Y if lawn_sdf(x, z) < 0 else 0.0
    for pts, w in TRAILS:
        end = pts[-1]
        if poly_dist(x, z, [(p[0], p[1]) for p in pts]) < w - 0.1 and math.hypot(x - end[0], z - end[1]) > TRAIL_END:
            if PLAY[0] + 0.6 < x < PLAY[1] - 0.6 and PLAY[2] < z < PLAY[3]:
                return terrain_height(x, z)
    return None


# --------------------------------------------------------------------------------------------
# terrain + lawns
# --------------------------------------------------------------------------------------------
GRASS = hex_rgb("a4c977")
GRASS_LIGHT = hex_rgb("b3d77e")
SLOPE = hex_rgb("91b963")
DRY = hex_rgb("d9c283")
DRY_DARK = hex_rgb("c7ab6a")
SAND = hex_rgb("efd9a5")
SAND_EDGE = hex_rgb("dcc187")
VALLEY = hex_rgb("c9d6cf")


def noise(x, z):
    return (math.sin(x * 0.9 + z * 0.37) * 0.5 + math.sin(x * 0.31 - z * 0.83 + 1.7) * 0.35
            + math.sin(x * 2.3 + z * 1.9) * 0.15)


def terrain_color(x, z, y):
    n = noise(x, z)
    if plateau_sdf(x, z) < 0:
        col = mix(SAND, SAND_EDGE, 0.2 + 0.15 * n)
    else:
        d = summit_sdf(x, z)
        dry = smooth(0.8, 3.0, d + n * 1.3) * (0.3 + 0.55 * smooth(-0.3, 0.7, n))
        col = mix(mix(SLOPE, GRASS, 0.4 + 0.3 * n), mix(DRY, DRY_DARK, 0.5 + 0.5 * n), dry)
    t, _ = trail_info(x, z)
    col = mix(col, SAND, smooth(0.12, -0.15, t))
    return mix(col, VALLEY, smooth(-6.5, -8.8, y))


def build_terrain():
    kit.begin("terrain", ao=False)
    x0, x1, z0, z1 = EXTENT
    step = 0.3
    nx = int((x1 - x0) / step) + 1
    nz = int((z1 - z0) / step) + 1
    verts, cols, faces = [], [], []
    for j in range(nz):
        for i in range(nx):
            x, z = x0 + i * step, z0 + j * step
            y = terrain_height(x, z)
            verts.append((x, y, z))
            cols.append(terrain_color(x, z, y))
    for j in range(nz - 1):
        for i in range(nx - 1):
            a = j * nx + i
            faces.append((a, a + nx, a + nx + 1, a + 1))
    kit.mesh("Hilltop terrain", verts, faces, "__paint__", True, cols)


def build_lawns():
    kit.begin("lawns", ao=False)
    for k, ring in enumerate(LAWNS):
        n = len(ring)
        cx = sum(p[0] for p in ring) / n
        cz = sum(p[1] for p in ring) / n
        verts, cols, faces = [(cx, LAWN_Y, cz)], [GRASS_LIGHT], []
        for x, z in ring:
            verts.append((x, LAWN_Y, z))
            cols.append(mix(GRASS, GRASS_LIGHT, 0.45))
        for x, z in ring:
            dx, dz = x - cx, z - cz
            l = math.hypot(dx, dz) or 1
            verts.append((x + dx / l * 0.05, -0.02, z + dz / l * 0.05))
            cols.append(mix(GRASS, SAND_EDGE, 0.3))
        for i in range(n):
            j = (i + 1) % n
            faces.append((0, j + 1, i + 1))
            faces.append((i + 1, j + 1, n + j + 1, n + i + 1))
        kit.mesh("Lawn %d" % k, verts, faces, "__paint__", True, cols)


# --------------------------------------------------------------------------------------------
# observatory (modeled in its own frame, then rotated onto the traced footprint)
# --------------------------------------------------------------------------------------------
def windows_ring(cx, cz, radius, y, h, w, count, a0, a1):
    for k in range(count):
        a = a0 + (a1 - a0) * (k + 0.5) / count
        x = cx + math.cos(a) * (radius - 0.005)
        z = cz + math.sin(a) * (radius - 0.005)
        kit.box("Arched window", (x, y, z), (w, h, 0.04), "glass", 0.0, rot_y=-(a - math.pi / 2))
        top = kit.cylinder("Window arch", (x, y + h / 2, z), w / 2, 0.04, "glass", seg=12)
        top.rotation_euler.x = math.pi / 2
        top.rotation_euler.z = -(a - math.pi / 2)


def ribbed_dome(cx, base_y, cz, r, ribs=18, rings=5, height_scale=1.05):
    previous=set(kit.current.objects)
    kit.dome("Navy dome", (cx, base_y, cz), r, "dome", seg=64, rings=20)
    for k in range(ribs):
        a = k * math.tau / ribs
        prev = None
        for t in range(13):
            ang = t / 12 * math.pi / 2
            p = (cx + math.cos(a) * r * math.cos(ang) * 1.012, base_y + r * math.sin(ang) * 1.012,
                 cz + math.sin(a) * r * math.cos(ang) * 1.012)
            if prev is not None and t < 12:
                kit.beam("Dome rib", prev, p, r * 0.009, "dome_rib")
            prev = p
    for k in range(1, rings):
        ang = k / rings * math.pi / 2
        rr = r * math.cos(ang) * 1.012
        yy = base_y + r * math.sin(ang) * 1.012
        kit.lathe("Dome ring", [(rr, yy - 0.006), (rr, yy + 0.006)], "dome_rib", 40, False, (cx, 0, cz))
    kit.lathe("Sculpted dome cap", [(r*.21,0),(r*.22,.035),(r*.15,.065),(r*.07,.19),(.004,.31)], "dome_light", 32, True, (cx,base_y+r-.035,cz))
    kit.cylinder("Dome drum band", (cx, base_y - 0.08, cz), r * 1.005, 0.10, "dome_rib", seg=40)
    from mathutils import Matrix
    pivot=kit.v((cx,base_y,cz))
    deform=Matrix.Translation(pivot) @ Matrix.Diagonal((1.0,.90,height_scale,1.0)) @ Matrix.Translation(-pivot)
    for obj in set(kit.current.objects)-previous:
        obj.matrix_world=deform @ obj.matrix_world



def shrub_ring(cx, y, cz, r, count, size=0.46, front_gap=False):
    for k in range(count):
        a = k * math.tau / count
        if front_gap and math.sin(a) > .45: continue
        kit.ellipsoid("Roof shrub", (cx + math.cos(a) * r, y, cz + math.sin(a) * r), (size, size * 0.9, size),
                      "bush_light" if k % 3 == 0 else "bush", 12, 8)


def arch_window(name, cx, cy, cz, width, height, angle=0.0):
    # Recessed blue glass with a cream arched reveal. Cylindrical pieces are rotated
    # around the actual tangent, so windows remain mounted on curved walls.
    def pane(w,h,depth,color,offset):
        outline=[(-w/2,-h/2),(w/2,-h/2),(w/2,h/2-w/2)]
        for k in range(13):
            t=k*math.pi/12
            outline.append((math.cos(t)*w/2,h/2-w/2+math.sin(t)*w/2))
        verts=[]
        for zz in [offset,offset+depth]:
            for xx,yy in outline:
                verts.append((cx+xx*math.cos(angle)+zz*math.sin(angle),cy+yy,
                              cz-xx*math.sin(angle)+zz*math.cos(angle)))
        n=len(outline)
        faces=[tuple(reversed(range(n))),tuple(range(n,n*2))]
        faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        return kit.mesh(name,verts,faces,color)
    pane(width+0.06,height+0.07,0.025,"cream_shade",0)
    pane(width,height,0.015,"glass",0.03)
    kit.box(name+" sill",(cx,cy-height/2-0.02,cz+0.04),(width+0.10,0.04,0.08),"cream_light",0.015,rot_y=angle)


def round_windows(cx,cz,r,y,h,w,count):
    for k in range(count):
        a=0.25+(math.pi-0.5)*(k+0.5)/count
        arch_window("Arched rotunda window",cx+math.cos(a)*(r+0.02),y,
                    cz+math.sin(a)*(r+0.02),w,h,math.pi/2-a)


def ring_course(name,cx,cz,r,y,h,color="cream_light"):
    kit.lathe(name,[(r-0.07,0),(r,0.035),(r,h-0.025),(r-0.03,h)],color,64,True,(cx,y,cz))


def observatory():
    kit.begin("observatory")
    y0=TERRACE_Y
    # Main circular hall carries the raised observatory; stair-stepped limestone cornices.
    kit.cylinder("Lower rotunda",(0.1,y0+1.02,-1.05),2.36,2.04,"cream",seg=64)
    ring_course("Rotunda plinth",0.1,-1.05,2.43,y0,0.18,"cream_shade")
    ring_course("Rotunda belt",0.1,-1.05,2.4,y0+1.68,0.12)
    ring_course("Rotunda broad cornice",0.1,-1.05,2.47,y0+2.03,0.16)
    kit.cylinder("Roof garden",(0.1,y0+2.17,-1.05),2.29,0.055,"pave",seg=64)
    shrub_ring(0.1,y0+2.24,-1.05,2.12,20,0.38,True)
    kit.cylinder("Upper rotunda",(-0.18,y0+2.71,-1.28),1.60,1.02,"cream",seg=64)
    round_windows(-0.18,-1.28,1.60,y0+2.76,0.43,0.18,8)
    kit.box("Rotunda garden panel",(-.18,y0+2.62,.34),(.26,.42,.05),"leaf_light",.02)
    ring_course("Upper drum base",-0.18,-1.28,1.66,y0+2.19,0.13)
    ring_course("Dome base entablature",-0.18,-1.28,1.70,y0+3.15,0.14)
    ribbed_dome(-0.18,y0+3.35,-1.28,1.63,24,7,1.14)
    for side in [-1,1]:
        tx=side*TOWER_X
        wx=side*2.48
        kit.box("Connecting hall",(wx,y0+0.95,-0.17),(2.16,1.90,1.92),"cream",0.055)
        kit.box("Hall limestone plinth",(wx,y0+0.11,-0.16),(2.24,0.22,2.0),"cream_shade",0.035)
        kit.box("Hall cornice",(wx,y0+1.94,-0.17),(2.30,0.14,2.06),"cream_light",0.04)
        for k in range(2):
            arch_window("Tall hall arch",wx+(k-.5)*.87,y0+.94,.812,.24,.85)
        for k in range(3):
            kit.box("Hall pilaster",(wx+(k-1)*.90,y0+.92,.83),(.13,1.76,.10),"cream_light",.025)
        # Roof foliage is arranged in beds, leaving the parapet visible.
        kit.box("Hall roof bed",(wx,y0+2.02,-.30),(1.98,.08,1.40),"leaf_dark",.035)
        for k in range(6):
            kit.ellipsoid("Roof hedge",(wx+(k%3-1)*.55,y0+2.20,-.62+(k//3)*.55),(.63,.52,.59),"bush" if k%2 else "bush_light",16,10)
        kit.cylinder("Side tower",(tx,y0+1.05,0),TOWER_R,2.1,"cream",seg=64)
        ring_course("Tower plinth",tx,0,TOWER_R+.09,y0,.18,"cream_shade")
        ring_course("Tower mid band",tx,0,TOWER_R+.04,y0+1.88,.1)
        ring_course("Tower cornice",tx,0,TOWER_R+.09,y0+2.07,.17)
        round_windows(tx,0,TOWER_R,y0+1.05,.80,.19,5)
        kit.cylinder("Dome clerestory",(tx,y0+2.35,0),1.17,.21,"glass",seg=64)
        for k in range(28):
            a=k*math.tau/28
            kit.box("Clerestory mullion",(tx+math.cos(a)*1.18,y0+2.35,math.sin(a)*1.18),(.032,.23,.032),"dome_light",.005)
        ribbed_dome(tx,y0+2.49,0,1.08 if side < 0 else 1.17,18,6,1.05)
        kit.cylinder("Curved rear hall",(side*3.62,y0+.67,-1.48),1.65,1.34,"cream",seg=56)
        ring_course("Rear garden coping",side*3.62,-1.48,1.73,y0+1.32,.15)
        shrub_ring(side*3.62,y0+1.63,-1.48,1.39,14,.54)
    # Deep doorway, paired pilasters, a circular vestibule and teal roof lantern.
    kit.cylinder("Rounded entrance vestibule",(0,y0+.94,.31),1.23,1.88,"cream",seg=56)
    ring_course("Rounded vestibule cornice",0,.31,1.31,y0+1.84,.21)
    kit.box("Door recess",(0,y0+.78,1.49),(.85,1.51,.05),"door_dark",.025)
    kit.box("Double timber door",(0,y0+.71,1.535),(.71,1.35,.045),"door",.02)
    for dx in [-.25,.25]:
        kit.box("Door panel",(dx,y0+.73,1.57),(.18,.98,.015),"door_dark",.015)
    for dx in [-.55,.55]:
        kit.box("Door surround",(dx,y0+.79,1.52),(.16,1.58,.17),"cream_light",.035)
    kit.box("Door lintel",(0,y0+1.63,1.53),(1.32,.18,.20),"cream_light",.025)
    for dx in [-1.01,1.01]:
        kit.box("Fluted portico column",(dx,y0+.86,1.54),(.17,1.72,.20),"cream_light",.03)
        kit.box("Column foot",(dx,y0+.08,1.56),(.28,.16,.29),"cream_shade",.035)
    kit.cylinder("Lantern terrace",(0,y0+2.04,.68),.94,.14,"cream_light",seg=48)
    kit.cylinder("Lantern plinth",(0,y0+2.17,.68),.57,.21,"cream",seg=40)
    kit.lathe("Teal glass lantern",[(.51,0),(.48,.16),(.28,.34),(.19,.47),(.02,.66)],"teal",12,True,(0,y0+2.28,.68))
    for k in range(12):
        a=k*math.tau/12
        kit.beam("Lantern glazing bar",(.51*math.cos(a),y0+2.29,.68+.51*math.sin(a)),(.19*math.cos(a),y0+2.75,.68+.19*math.sin(a)),.018,"teal_light")
    kit.place_collection("observatory",-BUILDING_YAW,(BUILDING_ORIGIN[0],0,BUILDING_ORIGIN[1]))


def to_world(lx, lz):
    a = math.radians(BUILDING_YAW)
    return (BUILDING_ORIGIN[0] + lx * math.cos(a) - lz * math.sin(a), BUILDING_ORIGIN[1] + lx * math.sin(a) + lz * math.cos(a))


def in_building(x, z, pad=0.25):
    a = math.radians(BUILDING_YAW)
    dx, dz = x - BUILDING_ORIGIN[0], z - BUILDING_ORIGIN[1]
    lx = dx * math.cos(a) + dz * math.sin(a)
    lz = -dx * math.sin(a) + dz * math.cos(a)
    if abs(lx) < 1.5 + pad and -3.9 < lz < 1.35 + pad:
        return True
    if abs(lx) < 3.5 + pad and -3.9 < lz < 0.8 + pad:
        return True
    for s_ in (-1, 1):
        if math.hypot(lx - s_ * TOWER_X, lz) < TOWER_R + pad or math.hypot(lx - s_ * 3.7, lz + 1.5) < 1.7 + pad:
            return True
    return math.hypot(lx - 0.1, lz + 1.2) < 2.6 + pad


# --------------------------------------------------------------------------------------------
# terraces, plaza, fountains, cafe, city
# --------------------------------------------------------------------------------------------
def parapet(points, y, height=0.42):
    for a, b in zip(points, points[1:]):
        WALLS.append((a,b))
        kit.beam("Balustrade", (a[0], y + height / 2, a[1]), (b[0], y + height / 2, b[1]), 0.22, "cream", height)
        kit.beam("Balustrade cap", (a[0], y + height + 0.02, a[1]), (b[0], y + height + 0.02, b[1]), 0.28, "cream_light", 0.06)


def terraces():
    kit.begin("terrace")
    y = TERRACE_Y
    kit.slab("Forecourt", FORECOURT, -2.5, y, "cream_shade", "pave")
    kit.slab("West terrace", WEST_TERRACE, -2.5, y, "cream_shade", "sand_pave")
    kit.slab("Cafe link", CAFE_LINK, -2.5, y, "cream_shade", "pave")
    kit.cylinder("Cafe terrace", (CAFE[0], (y - 3.0) / 2, CAFE[1]), CAFE[2], y + 3.0, "cream_shade", seg=56)
    kit.cylinder("Cafe paving", (CAFE[0], y + 0.004, CAFE[1]), CAFE[2] - 0.03, 0.012, "pave", seg=56)
    # West terrace balustrade: north edge and the rounded western end (traced 130-400 px).
    wt = WEST_TERRACE
    north = [p for p in wt if p[1] < -3.3]
    north.sort(key=lambda p: p[0])
    parapet([(p[0], p[1] + 0.12) for p in north], y)
    west_end = [p for p in wt if p[0] < -9.6]
    west_end.sort(key=lambda p: p[1])
    parapet([(p[0] + 0.12, p[1]) for p in west_end], y)
    # Forecourt front wall on either side of the main stairs.
    parapet([(-5.6, -0.6), (-2.35, -1.2)], y)
    parapet([(1.3, -0.95), (4.0, -0.5), (5.3, -0.75)], y)
    ring = []
    for k in range(31):
        a = math.radians(-70 + k * 230 / 30)
        ring.append((CAFE[0] + math.cos(a) * (CAFE[2] - 0.12), CAFE[1] + math.sin(a) * (CAFE[2] - 0.12)))
    # Skip complete segments at the connecting promenade. Filtering vertices
    # would connect across the omitted opening and close it with a new wall.
    for a,b in zip(ring,ring[1:]):
        mx,mz=(a[0]+b[0])*.5,(a[1]+b[1])*.5
        if not (4.4 < mx < 8.5 and -2.6 < mz < 1.15):
            parapet([a,b],y)
    for x0, x1, zt, zb, yt, yb in STAIRS:
        n = 5
        for k in range(n):
            t0 = k / n
            z = zt + (zb - zt) * (t0 + 0.5 / n)
            h = yt + (yb - yt) * t0
            kit.box("Step", ((x0 + x1) / 2, (h + yb - 0.4) / 2, z), (x1 - x0, h - yb + 0.4, (zb - zt) / n + 0.02), "stone", 0.02)
        for xx in (x0 - 0.12, x1 + 0.12):
            kit.beam("Stair cheek", (xx, yt + 0.1, zt), (xx, yb + 0.12, zb), 0.2, "cream", 0.3)


def plaza():
    kit.begin("plaza")
    px, pz, r = PLAZA
    kit.cylinder("Plaza ring", (px, 0.02, pz), r, 0.05, "plaza_ring", seg=64)
    kit.cylinder("Plaza paving", (px, 0.035, pz), r - 0.16, 0.05, "plaza", seg=64)
    star = []
    for k in range(16):
        a = k * math.tau / 16 - math.pi / 2
        rr = r * 0.88 if k % 2 == 0 else r * 0.4
        star.append((px + math.cos(a) * rr, pz + math.sin(a) * rr))
    kit.slab("Compass star", star, 0.05, 0.066, "star", bevel=0)
    kit.cylinder("Planter ring", (px, 0.14, pz), 0.8, 0.22, "cream_light", seg=40)
    kit.cylinder("Planter soil", (px, 0.25, pz), 0.68, 0.02, "leaf_dark", seg=40)
    for k in range(10):
        a = k * math.tau / 10
        kit.ellipsoid("Planter shrub", (px + math.cos(a) * 0.52, 0.36, pz + math.sin(a) * 0.52), (0.3, 0.26, 0.3),
                      "bush" if k % 2 else "bush_light", 10, 6)
    kit.box("Monument base", (px, 0.36, pz), (0.66, 0.32, 0.66), "cream_shade", 0.04)
    v = [(-0.26, 0.52, -0.26), (0.26, 0.52, -0.26), (0.26, 0.52, 0.26), (-0.26, 0.52, 0.26),
         (-0.15, 3.3, -0.15), (0.15, 3.3, -0.15), (0.15, 3.3, 0.15), (-0.15, 3.3, 0.15), (0, 3.65, 0)]
    kit.mesh("Obelisk", [(px + a, b, pz + c) for a, b, c in v],
             [(4, 5, 1, 0), (5, 6, 2, 1), (6, 7, 3, 2), (7, 4, 0, 3), (8, 5, 4), (8, 6, 5), (8, 7, 6), (8, 4, 7)], "cream_light")


WATER = []
FOUNTAINS = [(*P(612, 372, 0.75), 0.55), (*P(752, 422, 0.75), 0.72), (*P(918, 412, 0.75), 0.6)]


def fountains():
    for i, (fx, fz, r) in enumerate(FOUNTAINS):
        kit.begin("fountain_%d" % i)
        y = TERRACE_Y
        # Hollow bowl: the former solid cap sat above the animated water disc.
        kit.lathe("Hollow basin",[(r,0),(r,.24),(r-.025,.27),(r-.09,.27),(r-.10,.08),(.001,.08)],
                  "cream_light",48,True,(fx,y,fz))
        kit.cylinder("Pedestal", (fx, y + 0.35, fz), r * 0.2, 0.5, "cream", top=r * 0.14, seg=20)
        kit.lathe("Hollow upper bowl",[(r*.42,0),(r*.5,.10),(r*.41,.10),(r*.32,.035),(.001,.035)],"cream_light",32,True,(fx,y+.57,fz))
        WATER.append({"kind": "basin", "pos": [fx, y + 0.235, fz], "radius": r - 0.1})
        WATER.append({"kind": "bowl", "pos": [fx, y + 0.645, fz], "radius": r * 0.39})
        WATER.append({"kind": "jet", "pos": [fx, y + 0.66, fz], "radius": r * 0.28, "height": 0.9})


KIOSK = (*P(1220, 585, TERRACE_Y), 2.6, 1.5)   # front-centre x, front z, width, depth
TABLES = [P(1128, 500, TERRACE_Y), P(1333, 590, TERRACE_Y)]


def cafe():
    kit.begin("cafe")
    kx, kf, w, d = KIOSK
    kz = kf - d / 2
    y = TERRACE_Y
    kit.box("Kiosk", (kx, y + 0.7, kz), (w, 1.4, d), "cream_light", 0.05)
    kit.box("Counter", (kx, y + 0.6, kf + 0.08), (w - 0.3, 0.12, 0.22), "bench", 0.03)
    kit.box("Kiosk window", (kx, y + 0.95, kf - 0.01), (w - 0.5, 0.5, 0.04), "glass", 0.02)
    for k in range(9):
        kit.box("Awning stripe", (kx - w / 2 + 0.15 + k * (w - 0.3) / 8, y + 1.45, kf + 0.2), ((w - 0.3) / 8 + 0.01, 0.05, 0.55),
                "awning_g" if k % 2 else "awning_w", 0.01)
    v = [(-w / 2 - 0.15, 0, -d / 2 - 0.15), (w / 2 + 0.15, 0, -d / 2 - 0.15), (w / 2 + 0.15, 0, d / 2 + 0.15),
         (-w / 2 - 0.15, 0, d / 2 + 0.15), (-w / 4, 0.6, 0), (w / 4, 0.6, 0)]
    kit.mesh("Hip roof", [(kx + a, y + 1.4 + b, kz + c) for a, b, c in v], [(4, 5, 1, 0), (5, 4, 3, 2), (5, 2, 1), (4, 0, 3)], "roof_green")
    for side in [-1,1]:
        for k in range(1,6):
            t=k/6
            zz=kz+side*t*(d/2+.15)
            yy=y+2.0-.60*t
            length=w*.5+(w*.5+.30)*t
            kit.box("Roof tile course",(kx,yy+.015,zz),(length,.035,.045),"roof_green_light",.01)
    for side in [-1,1]:
        kit.box("Kiosk corner post",(kx+side*(w/2-.10),y+.75,kf+.04),(.12,1.5,.13),"cream_light",.025)
    kit.box("Counter dark interior",(kx,y+.91,kf+.025),(w-.52,.53,.05),"door_dark",.02)
    for k in range(6):
        kit.cylinder("Counter cup",(kx-.86+k*.34,y+.74,kf+.14),.07,.15,"cream_light",seg=12)
    kit.box("Roof ridge", (kx, y + 2.02, kz), (w / 2 + 0.1, 0.06, 0.1), "roof_green_light", 0.01)
    from mathutils import Matrix
    pivot=kit.v((kx,0,kz))
    turn=Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(-22),4,"Z") @ Matrix.Translation(-pivot)
    for obj in kit.current.objects: obj.matrix_world=turn @ obj.matrix_world
    for tx, tz in TABLES:
        kit.cylinder("Table", (tx, y + 0.42, tz), 0.38, 0.05, "table", seg=20)
        kit.cylinder("Table leg", (tx, y + 0.2, tz), 0.04, 0.4, "iron", seg=8)
        kit.cylinder("Umbrella pole", (tx, y + 0.85, tz), 0.025, 1.3, "iron", seg=8)
        kit.lathe("Umbrella", [(0.85, 0), (0.58, 0.15), (0.001, 0.32)], "umbrella", 16, True, (tx, y + 1.4, tz))
        for k in range(3):
            a = k * math.tau / 3 + 0.4
            sx,sz=tx+math.cos(a)*.62,tz+math.sin(a)*.62
            kit.cylinder("Stool", (sx, y + 0.18, sz), 0.15, 0.06, "table", seg=16)
            for leg in range(3):
                b=leg*math.tau/3+a
                kit.cylinder("Stool leg",(sx+math.cos(b)*.085,y+.075,sz+math.sin(b)*.085),.022,.15,"bench",seg=8)
    px, pz = P(1348, 662, TERRACE_Y)
    kit.box("Stone planter", (px, y + 0.25, pz - 0.2), (1.2, 0.5, 0.7), "planter", 0.05)
    for flower in range(5):
        fx=px-.43+flower*.21
        fz=pz-.2+(.10 if flower%2 else -.06)
        fy=y+.83+(flower%2)*.06
        kit.cylinder("Planter flower stem",(fx,y+.65,fz),.012,.34,"leaf",seg=8)
        for petal in range(5):
            a=petal*math.tau/5
            kit.ellipsoid("Planter daisy petal",(fx+math.cos(a)*.07,fy,fz+math.sin(a)*.07),(.095,.025,.065),"flower",8,6)
        kit.ellipsoid("Planter daisy centre",(fx,fy+.015,fz),(.052,.032,.052),"flower_heart",10,6)
    for k in range(4):
        kit.ellipsoid("Planter bush", (px - 0.4 + k * 0.27, y + 0.62, pz - 0.2), (0.34, 0.3, 0.34), "bush_light" if k % 2 else "bush", 10, 6)


def city():
    kit.begin("city",ao=False)
    rnd=random.Random(51)
    # City sits in the valley. Tall narrow volumes silhouette against the upper frame.
    for gx in range(29):
        for gz in range(23):
            xx=gx*.86;zz=-gz*.83
            x=-1.5+xx*.92-zz*.39; z=-16.8+xx*.39+zz*.92
            base=terrain_height(x,z)+.04
            if base > -3.5: continue
            kit.box("Valley street parcel",(x,base-.025,z),(.88,.05,.86),"city_road",.0,rot_y=-.40)
            if gx%6==0 or gz%5==0: continue
            if (gx+gz)%9==0:
                kit.box("City garden",(x,base+.014,z),(.64,.025,.62),"city_park",.02,rot_y=-.40)
                continue
            h=rnd.uniform(.35,1.0)
            if rnd.random()<.24:h=rnd.uniform(1.3,2.6)
            w=rnd.uniform(.46,.64);dep=rnd.uniform(.43,.66)
            kit.box("Distant city facade",(x,base+h/2,z),(w,h,dep),rnd.choice(["city1","city2","city3"]),.04,rot_y=-.40)
            kit.box("Distant pale rooftop",(x,base+h+.025,z),(w+.03,.055,dep+.03),"city_roof",.02,rot_y=-.40)


# --------------------------------------------------------------------------------------------
# prop assets
# --------------------------------------------------------------------------------------------
def prop_assets():
    def crown(center,size,color,phase=0):
        obj=kit.ellipsoid("Sculpted foliage",center,size,color,20,12)
        for v in obj.data.vertices:
            co=v.co
            k=1+.045*math.sin(co.x*7.1+co.y*4.4+phase)*math.sin(co.z*6.3+phase)
            co*=k
        return obj
    for name,h,w,col in [("tree_round",2.15,1.65,"leaf"),("tree_big",3.15,2.30,"leaf"),("tree_olive",1.7,1.55,"olive")]:
        kit.begin(name)
        kit.cylinder("Tapered trunk",(0,h*.28,0),w*.065,h*.56,"trunk",top=w*.045,seg=12)
        for k in range(3):
            a=k*2.1
            kit.beam("Branches",(0,h*.36,0),(math.cos(a)*w*.24,h*.64,math.sin(a)*w*.24),w*.055,"trunk")
        crown((0,h*.73,0),(w,h*.73,w*.93),col)
        crown((-w*.29,h*.65,w*.08),(w*.57,h*.46,w*.62),col,1.8)
        crown((w*.29,h*.64,-w*.09),(w*.56,h*.45,w*.61),col,3.2)
        for k in range(7):
            a=k*2.4
            kit.ellipsoid("Root planting",(math.cos(a)*w*.14,.04,math.sin(a)*w*.14),(.18,.09,.18),"leaf_light",10,6)
    kit.begin("cypress")
    kit.cylinder("Trunk",(0,.28,0),.075,.56,"trunk",seg=10)
    kit.lathe("Tapered cypress",[(.001,.24),(.25,.32),(.33,.75),(.35,1.16),(.28,1.68),(.19,2.12),(.065,2.52),(.001,2.65)],"cypress",24,True)
    kit.begin("bush")
    for k in range(4):
        a = k * 2.3
        kit.ellipsoid("Shrub", (math.cos(a) * 0.14, 0.2 + (k % 2) * 0.06, math.sin(a) * 0.12), (0.4, 0.4, 0.4),
                      "bush_light" if k % 2 else "bush", 12, 8)
    kit.begin("bush_round")
    kit.ellipsoid("Round shrub", (0, 0.28, 0), (0.6, 0.56, 0.6), "bush", 16, 10)
    kit.ellipsoid("Shrub light", (-0.1, 0.36, 0.1), (0.35, 0.3, 0.35), "bush_light", 10, 6)
    kit.begin("grass_clump",ao=False)
    for k in range(9):
        a=k*2.4; dx,dz=math.cos(a),math.sin(a);w=.026
        h=.14+(k%4)*.045
        vs=[(-dz*w,0,dx*w),(dz*w,0,-dx*w),(dx*.11+dz*w,h*.65,dz*.11-dx*w),(dx*.20,h,dz*.20),(dx*.11-dz*w,h*.65,dz*.11+dx*w)]
        obj=kit.mesh("Grass blade",vs,[(0,1,2,4),(4,2,3)],"leaf_light" if k%3 else "bush")
        obj.modifiers.new("Leaf thickness","SOLIDIFY").thickness=.004
    kit.begin("rock")
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=(0, 0, 0.18))
    obj = kit._finish(bpy.context.object, "Boulder", "rock")
    obj.scale = (0.42, 0.34, 0.26)
    kit.begin("lamp")
    kit.cylinder("Lamp base", (0, 0.08, 0), 0.09, 0.16, "iron", seg=12)
    kit.cylinder("Lamp post", (0, 0.72, 0), 0.035, 1.34, "iron", seg=10)
    kit.cylinder("Lamp collar", (0, 1.4, 0), 0.07, 0.06, "iron", seg=12)
    kit.ellipsoid("Lamp globe", (0, 1.56, 0), (0.26, 0.28, 0.26), "globe", 14, 10)
    kit.begin("bench")
    for k in range(3):
        kit.box("Seat slat", (0, 0.36, -0.12 + k * 0.12), (1.0, 0.04, 0.1), "bench", 0.015)
    for k in range(2):
        kit.box("Back slat", (0, 0.55 + k * 0.13, -0.24), (1.0, 0.09, 0.03), "bench", 0.012)
    for s in (-1, 1):
        kit.box("Leg", (s * 0.42, 0.18, 0), (0.06, 0.36, 0.34), "iron", 0.01)
        kit.box("Back leg", (s * 0.42, 0.52, -0.25), (0.05, 0.4, 0.04), "iron", 0.01)
    kit.begin("fence_post")
    kit.cylinder("Rope post", (0, 0.32, 0), 0.06, 0.64, "post", seg=8, bevel=0.01)
    kit.begin("rope")
    for k in range(8):
        t0, t1 = k / 8, (k + 1) / 8
        sag = lambda t: 0.52 - 0.1 * math.sin(math.pi * t)
        kit.beam("Rope", (-0.5 + t0, sag(t0), 0), (-0.5 + t1, sag(t1), 0), 0.03, "rope")
    kit.begin("flowers")
    for k in range(5):
        x, z = math.cos(k * 2.4) * 0.13, math.sin(k * 2.4) * 0.11
        kit.ellipsoid("Leaves", (x, 0.05, z), (0.16, 0.08, 0.16), "bush", 8, 5)
        kit.ellipsoid("Petals", (x, 0.12, z), (0.1, 0.035, 0.1), "flower", 10, 5)
        kit.ellipsoid("Heart", (x, 0.14, z), (0.04, 0.02, 0.04), "flower_heart", 6, 4)
    kit.begin("telescope")
    kit.cylinder("Viewer post", (0, 0.4, 0), 0.05, 0.8, "iron", seg=10)
    kit.box("Viewer head", (0, 0.9, 0), (0.22, 0.18, 0.28), "rock_dark", 0.05)
    for s in (-1, 1):
        kit.cylinder("Eyepiece", (s * 0.06, 0.94, 0.16), 0.045, 0.08, "iron", seg=10).rotation_euler.x = math.pi / 2


# --------------------------------------------------------------------------------------------
# prop placement with footprint checks (nothing interpenetrates)
# --------------------------------------------------------------------------------------------
FOOT = {"tree_round": 0.85, "tree_big": 1.15, "tree_olive": 0.7, "cypress": 0.42, "bush": 0.34, "bush_round": 0.34,
        "rock": 0.45, "lamp": 0.22, "bench": 0.6, "flowers": 0.2, "telescope": 0.25, "fence_post": 0.1}
WALKER = {"lamp", "bench", "telescope", "bush", "bush_round", "tree_round", "tree_big", "tree_olive", "cypress", "rock"}
PROPS = {}
PLACED = []      # (x, z, radius)
OBSTACLES = []   # blocks navigation
WALLS = []       # exact parapet segments


def surface_y(x, z):
    w = walk_surface(x, z)
    return w if w is not None else terrain_height(x, z)


def from_pixel(u, v):
    """Intersect the reference camera ray with the height field.

    Fixed-point iteration diverges on steep hills (|dh/dz| >= 1) and displaced
    the original foreground trees by over a hundred pixels. Bisection keeps
    every traced base at its actual reference projection.
    """
    lo,hi=-14.0,12.0
    for _ in range(32):
        y=(lo+hi)*.5
        x,z=P(u,v,y)
        if y > surface_y(x,z): hi=y
        else: lo=y
    y=(lo+hi)*.5
    x,z=P(u,v,y)
    return x,y,z


def free(x, z, r):
    return all(math.hypot(x - a, z - b) >= r + c for a, b, c in PLACED)


def keep_off_paths(x, z, r):
    """Shrubs, trees and rocks never sit on sand paths, trails, stairs or terrace/building edges."""
    if stair_height(x, z) is not None or in_building(x, z, r):
        return False
    if abs(terrace_sdf(x, z)) < r + 0.15:
        return False
    if terrace_sdf(x, z) < 0:
        return False
    t, _ = trail_info(x, z)
    if t < r:
        return False
    if plateau_sdf(x, z) < 0 and lawn_sdf(x, z) > -r * 0.5:
        return False
    return math.hypot(x - PLAZA[0], z - PLAZA[1]) > PLAZA[2] + r


def put(asset, x, z, y=None, rot=None, scale=1.0, force=False, block=True):
    r = FOOT.get(asset, 0.3) * scale
    if not force and not free(x, z, r):
        return False
    if y is None:
        y = surface_y(x, z)
    PROPS.setdefault(asset, []).append([round(x, 3), round(y, 3), round(z, 3),
                                        round(rot if rot is not None else random.uniform(0, math.tau), 3), round(scale, 3)])
    PLACED.append((x, z, r))
    if block and asset in WALKER:
        OBSTACLES.append((x, z, r * (0.6 if asset.startswith("tree") else 1.0)))
    return True


def put_px(asset, u, v, **kw):
    x, y, z = from_pixel(u, v)
    return put(asset, x, z, y=y, **kw)


def fence_line(pixels):
    pts = [from_pixel(u, v) for u, v in pixels]
    posts = []
    for (ax, ay, az), (bx, by, bz) in zip(pts, pts[1:]):
        n = max(1, int(math.hypot(bx - ax, bz - az) / 1.3))
        for k in range(n):
            t = k / n
            x, z = ax + (bx - ax) * t, az + (bz - az) * t
            posts.append((x, surface_y(x, z) if walk_surface(x, z) is None else terrain_height(x, z), z))
    posts.append(pts[-1])
    for (ax, ay, az), (bx, by, bz) in zip(posts, posts[1:]):
        PROPS.setdefault("rope", []).append([round((ax + bx) / 2, 3), round((ay + by) / 2, 3), round((az + bz) / 2, 3),
                                             round(-math.atan2(bz - az, bx - ax), 3), round(math.hypot(bx - ax, bz - az), 3)])
    for x, y, z in posts:
        put("fence_post", x, z, y=y, rot=0, force=True)
        OBSTACLES.append((x, z, 0.12))


def scatter():
    # Traced design props first (they win every overlap test).
    for u, v in [(185, 340), (218, 340), (1413, 500)]:
        put_px("telescope", u, v, rot=math.pi, force=True)
    for u, v, r in [(335, 365, 0.05), (460, 697, 0.1), (856, 752, -0.25), (1128, 625, 0.35)]:
        put_px("bench", u, v, rot=r, force=True)
    for u, v in [(443, 482), (380, 657), (948, 766), (1003, 556), (315, 470)]:
        put_px("lamp", u, v, rot=0, force=True)
    fence_line([(210, 600), (230, 640), (260, 670), (290, 712), (335, 747)])
    fence_line([(575, 852), (635, 862), (700, 878)])
    fence_line([(1098, 662), (1148, 697), (1205, 732), (1268, 767), (1338, 792), (1393, 812), (1448, 847), (1493, 882)])
    fence_line([(100, 105), (175, 138), (225, 150), (272, 162)])
    trees = [
        ("tree_round", 130, 60, 1.0), ("tree_round", 230, 100, 0.9), ("tree_big", 40, 170, 1.0), ("cypress", 300, 152, 1.0),
        ("tree_round_dark", 375, 168, 1.1), ("cypress", 95, 305, 1.15), ("tree_round", 95, 378, 1.0), ("tree_big", 240, 432, 0.95),
        ("tree_round", 120, 482, 0.9), ("cypress", 410, 268, 0.9), ("cypress", 630, 172, 1.0), ("tree_round", 590, 78, 0.9),
        ("tree_round", 520, 58, 0.85), ("tree_round", 450, 62, 0.85), ("tree_round_dark", 400, 205, 1.0),
        ("cypress", 1000, 208, 1.0), ("tree_round", 1075, 162, 0.9), ("tree_big", 1215, 252, 1.0), ("cypress", 1265, 300, 1.0),
        ("cypress", 1332, 312, 1.1), ("cypress", 1410, 332, 1.0), ("tree_big", 1195, 412, 0.95), ("cypress", 1290, 447, 0.95),
        ("tree_round", 1470, 442, 0.9), ("tree_round", 1360, 452, 0.8),
        ("tree_big", 100, 706, 1.05), ("cypress", 172, 692, 1.15), ("tree_big", 110, 918, 1.25), ("tree_big", 385, 888, 1.05),
        ("cypress", 467, 906, 1.15), ("cypress", 540, 917, 1.0), ("tree_round", 300, 1012, 1.0), ("tree_big", 660, 1012, 1.05),
        ("cypress", 1080, 902, 1.2), ("cypress", 1118, 852, 1.0), ("tree_round", 1183, 852, 0.9), ("tree_big", 883, 952, 1.0),
        ("tree_round", 1043, 992, 0.9), ("cypress", 1175, 1024, 1.0), ("tree_round", 1260, 987, 0.85), ("tree_big", 1420, 1012, 1.1),
        ("cypress", 1423, 662, 1.1), ("cypress", 1483, 802, 1.1), ("tree_round", 1515, 772, 0.9),
    ]
    for asset, u, v, s in trees:
        asset = "tree_round" if asset == "tree_round_dark" else asset
        put_px(asset, u, v, scale=s, force=True)
    for u, v, s in [(185, 112, 1.0), (355, 285, 1.2), (95, 552, 1.2), (200, 737, 1.4), (165, 1010, 1.6), (1303, 702, 1.1),
                    (1338, 862, 1.2), (1433, 772, 1.0)]:
        put_px("rock", u, v, scale=s, force=True)
    # Shrub clusters traced from the design's lawns and slopes.
    for u, v, s_ in [(280, 597, 1.2), (300, 600, 1.0), (530, 602, 1.2), (560, 657, 1.1), (813, 577, 1.2), (948, 597, 1.0),
                     (813, 657, 1.1), (783, 692, 1.0), (1068, 672, 1.1), (1068, 722, 1.1), (1178, 622, 1.4), (1248, 692, 1.2),
                     (330, 230, 1.5), (100, 212, 1.3), (60, 245, 1.2), (420, 425, 1.3), (455, 420, 1.2), (570, 450, 1.3),
                     (610, 455, 1.2), (500, 432, 1.1), (160, 820, 1.2), (250, 870, 1.1), (560, 960, 1.3), (1270, 880, 1.2),
                     (1470, 940, 1.3), (1140, 985, 1.2), (740, 980, 1.2), (60, 640, 1.2)]:
        put_px(random.choice(["bush_round", "bush"]), u, v, scale=s_)
    for u, v in [(180, 215), (210, 212), (285, 277), (415, 292), (485, 447), (520, 447), (190, 407), (190, 497), (30, 527),
                 (60, 527), (480, 542), (425, 662), (220, 942), (430, 912), (938, 607), (1343, 713), (1373, 725), (1230, 480)]:
        put_px("flowers", u, v, scale=1.2)
    # Hedges under the forecourt wall and around the terraces (design: dense rounded shrubs).
    for strip in (LAWNS[5], LAWNS[6]):
        for i in range(0, len(strip), 3):
            x, z = strip[i]
            put(random.choice(["bush", "bush_round"]), x, z, y=LAWN_Y, scale=random.uniform(0.85, 1.1))
    # Hedge planting inside the forecourt/terrace walls (design: dense rows of rounded shrubs).
    for k in range(3000):
        x, z = random.uniform(-11.5, 12.5), random.uniform(-7.0, 5.0)
        td = terrace_sdf(x, z)
        if not (-0.95 < td < -0.35) or in_building(x, z, 0.35) or stair_height(x, z) is not None:
            continue
        if any(math.hypot(x - fx, z - fz) < r + 0.5 for fx, fz, r in FOUNTAINS):
            continue
        if -2.6 < x < 1.6 and z > -1.9:
            continue  # keep the main stair approach open
        if math.hypot(x - CAFE[0], z - CAFE[1]) < CAFE[2] - 0.2:
            continue  # cafe paving stays clear
        put("bush_round", x, z, y=TERRACE_Y, scale=random.uniform(1.25, 1.5))
    for k in range(1500):
        x, z = random.uniform(-11.5, 12.5), random.uniform(-4.5, 5.0)
        if 0.3 < terrace_sdf(x, z) < 1.0 and keep_off_paths(x, z, 0.33):
            put(random.choice(["bush", "bush_round", "bush"]), x, z, scale=random.uniform(0.9, 1.2))
    # Shrub clusters on the lawns, keeping the design's open lawn centres.
    for ring in LAWNS[:5]:
        for i in range(0, len(ring), 4):
            if random.random() < 0.6:
                x, z = ring[i]
                cx = sum(p[0] for p in ring) / len(ring)
                cz = sum(p[1] for p in ring) / len(ring)
                x, z = x + (cx - x) * 0.18, z + (cz - z) * 0.18
                if keep_off_paths(x, z, 0.34):
                    put(random.choice(["bush", "bush_round", "flowers"]), x, z, y=LAWN_Y, scale=random.uniform(0.8, 1.05))
    # Woodland on the slopes: clumps with dry open ground between, never on trails.
    for k in range(9000):
        x = random.uniform(EXTENT[0] + 1, EXTENT[1] - 1)
        z = random.uniform(-14.0, EXTENT[3] - 1)
        d = summit_sdf(x, z)
        if d < 0.5 or terrain_height(x, z) < -8.2:
            continue
        if not keep_off_paths(x, z, 0.9):
            continue
        if noise(x * 0.55 + 3.1, z * 0.55 - 1.7) < -0.45 and d > 3.5:
            continue
        # The design frames only a few big specimen trees in front; filler stays at the sides and beyond.
        if abs(x) < 12.5 and z > 5.0 and random.random() < 0.85:
            continue
        if terrain_height(x, z) < -3.0 and z < -6.0:
            continue  # the valley below the ridge is distant scenery
        kind = random.random()
        asset = ("cypress" if kind < 0.24 else "tree_olive" if kind < 0.36 else "tree_big" if d < 5 and kind < 0.6 else "tree_round")
        put(asset, x, z, y=terrain_height(x, z), scale=random.uniform(0.55, 0.85) if z < -5.5 else random.uniform(0.8, 1.05), block=False)
    for k in range(2500):
        x = random.uniform(EXTENT[0] + 1, EXTENT[1] - 1)
        z = random.uniform(-10.0, EXTENT[3] - 1)
        if summit_sdf(x, z) < 0.25 or terrain_height(x, z) < -8.2 or not keep_off_paths(x, z, 0.35):
            continue
        if terrain_height(x, z) < -3.0 and z < -6.0:
            continue
        put(random.choice(["bush", "bush_round", "bush", "flowers", "rock"]), x, z, y=terrain_height(x, z),
            scale=random.uniform(0.8, 1.3), block=False)
    rnd=random.Random(828)
    # Botanical detail has a lower footprint than trees, giving three visible planting layers.
    for k in range(2100):
        x=rnd.uniform(-15.0,16.0);z=rnd.uniform(-11,14)
        y=surface_y(x,z)
        if y < -5 or not keep_off_paths(x,z,.11):continue
        if plateau_sdf(x,z)<0 and lawn_sdf(x,z)<-.6 and rnd.random()<.90:continue
        asset="flowers" if rnd.random()<.025 else "grass_clump"
        PROPS.setdefault(asset,[]).append([round(x,3),round(y,3),round(z,3),round(rnd.uniform(0,math.tau),3),round(rnd.uniform(.7,1.5),3)])


def blocked(x, z):
    if in_building(x, z, 0.3):
        return True
    if math.hypot(x - PLAZA[0], z - PLAZA[1]) < 0.95:
        return True
    for fx, fz, r in FOUNTAINS:
        if math.hypot(x - fx, z - fz) < r + 0.25:
            return True
    kx, kf, w, d = KIOSK
    if abs(x - kx) < w / 2 + 0.3 and kf - d - 0.3 < z < kf + 0.45:
        return True
    for tx, tz in TABLES:
        if math.hypot(x - tx, z - tz) < 0.56:
            return True
        for seat in range(3):
            a=seat*math.tau/3+.4
            if math.hypot(x-tx-math.cos(a)*.62,z-tz-math.sin(a)*.62)<.29:
                return True
    # Bench footprints are rectangular; a circular 1.2m exclusion closed the
    # western stair landing even though the physical seat is only 0.4m deep.
    for bx,by,bz,angle,scale in PROPS.get("bench",[]):
        dx,dz=x-bx,z-bz
        lx,lz=math.cos(angle)*dx-math.sin(angle)*dz,math.sin(angle)*dx+math.cos(angle)*dz
        if abs(lx)<.5*scale+.15 and abs(lz)<.24*scale+.15:return True
    for a,b in WALLS:
        if seg_dist(x,z,a,b)<.27:return True
    for ox, oz, r in OBSTACLES:
        if math.hypot(x - ox, z - oz) < r:
            return True
    return False


def navigation():
    step = 0.25
    x0, x1, z0, z1 = PLAY[0], PLAY[1], PLAY[2], PLAY[3]
    nx = int((x1 - x0) / step) + 1
    nz = int((z1 - z0) / step) + 1
    heights = {}
    for j in range(nz):
        for i in range(nx):
            heights[(i, j)] = walk_surface(x0 + i * step, z0 + j * step)
    verts, index, polys = [], {}, []
    for j in range(nz - 1):
        for i in range(nx - 1):
            cs = [(i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j)]
            hs = [heights[c] for c in cs]
            if any(h is None for h in hs) or max(hs) - min(hs) > 0.2:
                continue
            if blocked(x0 + (i + 0.5) * step, z0 + (j + 0.5) * step):
                continue
            ids = []
            for c, h in zip(cs, hs):
                if c not in index:
                    index[c] = len(verts)
                    verts.append([round(x0 + c[0] * step, 3), round(h, 3), round(z0 + c[1] * step, 3)])
                ids.append(index[c])
            polys.append(list(reversed(ids)))
    return {"vertices": verts, "polygons": polys, "cell": step}


def static_obstacles(props):
    result=[]
    for name,items in props.items():
        if name == "bench" or (name not in WALKER and name != "fence_post"):continue
        for x,y,z,rot,scale in items:
            radius=FOOT.get(name,.1)*scale*(.6 if name.startswith("tree") else 1)
            result.append((x,z,radius))
    return result


def rebuild_navigation():
    layout=json.loads((OUT/"layout.json").read_text())
    for name,items in layout["props"].items():
        if name in ["bush","bush_round","flowers","grass_clump"]:
            layout["props"][name]=[p for p in items if stair_height(p[0],p[2]) is None and not (4.8<p[0]<8.3 and -.9<p[2]<2.15)]
    PROPS.update(layout["props"])
    OBSTACLES.extend(static_obstacles(PROPS))
    if "--skip-mesh" not in sys.argv: build_terrain()
    terraces()
    layout["navigation"]=navigation()
    layout["obstacles"]=OBSTACLES
    manifest=json.loads((OUT/"manifest.json").read_text())
    if "--skip-mesh" not in sys.argv:
        manifest["assets"]["terrace"]=kit.export("terrace")
        manifest["assets"]["terrain"]=kit.export("terrain")
    (OUT/"layout.json").write_text(json.dumps(layout,separators=(",",":")))
    (OUT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    print("LANDMARK_NAVIGATION",len(layout["navigation"]["polygons"]),flush=True)


def main():
    if "--water-only" in sys.argv:
        fountains()
        manifest=json.loads((OUT/"manifest.json").read_text())
        layout=json.loads((OUT/"layout.json").read_text())
        for name in kit.assets:manifest["assets"][name]=kit.export(name)
        layout["water"]=WATER
        (OUT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
        (OUT/"layout.json").write_text(json.dumps(layout,separators=(",",":")))
        return
    if "--architecture-only" in sys.argv:
        observatory()
        cafe()
        manifest=json.loads((OUT/"manifest.json").read_text())
        manifest["assets"]["observatory"]=kit.export("observatory")
        manifest["assets"]["cafe"]=kit.export("cafe")
        (OUT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
        return
    if "--navigation-only" in sys.argv:
        rebuild_navigation()
        return
    build_terrain()
    build_lawns()
    observatory()
    terraces()
    plaza()
    fountains()
    cafe()
    city()
    prop_assets()
    scatter()
    for name,items in PROPS.items():
        if name in ["bush","bush_round","flowers","grass_clump"]:
            PROPS[name]=[p for p in items if stair_height(p[0],p[2]) is None and not (4.8<p[0]<8.3 and -.9<p[2]<2.15)]
    OBSTACLES.clear()
    OBSTACLES.extend(static_obstacles(PROPS))
    nav = navigation()
    manifest = {"generator": "tools/art/build_griffith_observatory.py",
                "design": "docs/design/landmark-scenes-2026-09-23/griffith_observatory_scene_v1.png", "assets": {}}
    for name in list(kit.assets):
        manifest["assets"][name] = kit.export(name)
        print("LANDMARK_ASSET", name, manifest["assets"][name]["triangles"], flush=True)
    sx, sy, sz = from_pixel(690, 783)
    layout = {"props": PROPS, "water": WATER, "navigation": nav, "spawn": [round(sx, 2), round(sy, 2), round(sz, 2)],
              "camera_bounds": list(PLAY), "extent": list(EXTENT), "obstacles": OBSTACLES,
              "review_camera": {"pitch": 45, "yaw": 0, "px_per_m": S, "center": [0, 0, 0]},
              "unique": ["terrain", "lawns", "observatory", "terrace", "plaza", "fountain_0", "fountain_1", "fountain_2", "cafe", "city"]}
    for f in OUT.glob("*.glb"):
        if f.stem not in kit.assets:
            f.unlink()
    (OUT / "layout.json").write_text(json.dumps(layout, separators=(",", ":")))
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("LANDMARK_DONE nav_polys=%d props=%d" % (len(nav["polygons"]), sum(len(v) for v in PROPS.values())), flush=True)


if __name__ == "__main__":
    main()
