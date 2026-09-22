"""Bake rounded sediment, mineral and optical caustic maps for real-time water.

Run with NumPy and Pillow. Caustics are light-density maps from refracted rays,
not a Voronoi edge diagram. All maps wrap periodically.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parents[2] / 'assets/farm/art/water'
N = 1024
y, x = np.mgrid[:N, :N].astype(np.float32)
u, v = x / N, y / N
rng = np.random.default_rng(190924)

def noise(size, seed):
    gen = np.random.default_rng(seed)
    base = gen.normal(size=(N, N))
    ky = np.fft.fftfreq(N) * N
    filt = np.exp(-(ky[:, None] ** 2 + ky[None, :] ** 2) / size**2)
    field = np.fft.ifft2(np.fft.fft2(base) * filt).real
    return (field - field.min()) / (field.max() - field.min())

def smooth(a, b, value):
    t = np.clip((value - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)

def save(name, rgb):
    Image.fromarray(np.uint8(np.clip(rgb, 0, 1) * 255)).save(OUT / name)

fine, veins, broad = noise(160, 1), noise(36, 2), noise(7, 3)
sand = np.array([.36, .40, .32])[None, None, :] * (.78 + fine[..., None] * .35)
bed = sand.copy()
# Scattered rounded stones in several sizes, with sand between them and buried overlap.
for index in range(210):
    cx, cy = rng.random(2)
    rx = rng.uniform(.018, .063) if index < 140 else rng.uniform(.013, .036)
    ry, angle = rx * rng.uniform(.65, 1.2), rng.uniform(0, np.pi)
    dx, dy = (u - cx + .5) % 1 - .5, (v - cy + .5) % 1 - .5
    sx, sy = dx * np.cos(angle) + dy * np.sin(angle), -dx * np.sin(angle) + dy * np.cos(angle)
    radial = np.sqrt((sx / rx) ** 2 + (sy / ry) ** 2)
    radial *= 1 + (veins - .5) * .13
    mask = 1 - smooth(.84, 1, radial)
    height = np.sqrt(np.maximum(0, 1 - np.minimum(radial, 1) ** 2))
    tone = np.array([.52, .55, .45]) * rng.uniform(.74, 1.28)
    tone += rng.uniform(-.045, .045, 3)
    shade = .65 + height * .26 + np.clip(-sx / rx * .16 - sy / ry * .19, -.22, .22)
    mineral = .85 + fine * .12 + veins * .09
    streak = smooth(.63, .68, veins) * .03
    stone = tone[None, None, :] * shade[..., None] * mineral[..., None] + streak[..., None]
    bed = bed * (1 - mask[..., None]) + stone * mask[..., None]
save('sediment.png', bed)
# Rough mineral surface, triplanar sampled by bank stones.
rock = np.array([.57, .59, .52])[None, None, :] * (.74 + broad[..., None] * .24 + veins[..., None] * .14)
rock += (fine[..., None] - .5) * .15
rock -= smooth(.72, .81, veins)[..., None] * .14
save('shore_stone.png', rock)
# Light rays bent by a sum of periodic low waves and accumulated on the bed.
M = 2048
ry, rx = np.mgrid[:M, :M].astype(np.float32)
a, b = rx / M, ry / M
shift_x, shift_y = np.zeros_like(a), np.zeros_like(a)
waves = np.random.default_rng(15924)
for index in range(24):
    kx, ky = waves.integers(-7, 8, 2)
    if kx == 0 and ky == 0:
        continue
    amplitude, phase = waves.uniform(.007, .014), waves.uniform(0, 2*np.pi)
    wave = np.sin((a * kx + b * ky) * 2 * np.pi + phase)
    length = np.hypot(kx, ky)
    shift_x += wave * amplitude * kx / length
    shift_y += wave * amplitude * ky / length
ix, iy = (np.mod(a + shift_x, 1) * N).astype(int), (np.mod(b + shift_y, 1) * N).astype(int)
density = np.bincount((iy * N + ix).ravel(), minlength=N*N).reshape(N,N) / 4
light = np.clip((density - 1.25) / 5.5, 0, 1) ** .65
im = Image.fromarray(np.uint8(light * 255)).filter(ImageFilter.GaussianBlur(.65))
im.save(OUT / 'caustic_light.png')
# Finer soil/grass color detail, used only close to the bank.
grass = np.array([.37,.51,.18])[None,None,:]*(.7+broad[...,None]*.5+fine[...,None]*.24)
for _ in range(1200):
    cx,cy=rng.random(2);length=rng.uniform(.006,.025);angle=rng.uniform(0,6.28)
    dx,dy=(u-cx+.5)%1-.5,(v-cy+.5)%1-.5
    along,across=dx*np.cos(angle)+dy*np.sin(angle),-dx*np.sin(angle)+dy*np.cos(angle)
    mask=(1-smooth(.0008,.0022,np.abs(across)))*(1-smooth(length*.4,length,np.abs(along)))
    color=np.array([.52,.65,.24])*rng.uniform(.78,1.22)
    grass=grass*(1-mask[...,None])+color[None,None,:]*mask[...,None]
save('bank_grass.png',grass)
print('Baked sediment, mineral stone, refracted light and bank grass.')
