"""Label actual Mobile captures, encode a real-speed 4 s excerpt, read it back."""
from pathlib import Path
import hashlib, json, shutil, subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'output/sea-backdrop-432'
CAP = OUT / 'captures'
DOC = ROOT / 'docs/design/sea-backdrop-432'
DOC.mkdir(parents=True, exist_ok=True)
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'

def label(im, preset, motion=False):
    im = im.convert('RGB')
    draw = ImageDraw.Draw(im)
    draw.rectangle((0, 0, 360, 57), fill='#f2f0e8')
    draw.text((10, 8), 'SGODOT-432 / ' + ('Bay' if preset == 'bay' else 'Lake'),
              font=ImageFont.truetype(FONT, 16), fill='#334646')
    draw.text((10, 32), '360 x 800 | Vulkan Mobile | ' + ('4 s excerpt' if motion else 'default camera'),
              font=ImageFont.truetype(FONT, 11), fill='#334646')
    draw.rectangle((0, 746, 360, 800), fill='#f2f0e8')
    lines = ['426 v1.1 + 430 foam / 0.25 m wet band',
             'Sea: 0 samples / 1 pass | Liu Bei']
    if motion:
        lines[1] = 'Real speed / 5.5 s foam cycle / clip restarts'
    for i, line in enumerate(lines):
        draw.text((10, 754 + i*21), line, font=ImageFont.truetype(FONT, 11), fill='#334646')
    return im

metrics = {}
for preset in ['bay', 'lake']:
    im = Image.open(CAP / (preset + '-default-review.png'))
    assert im.size == (360, 800)
    label(im, preset).save(DOC / (preset + '-default-review.png'))
    a = np.asarray(Image.open(CAP / (preset + '-sea-time-0.png'))).astype(float)[..., :3]
    b = np.asarray(Image.open(CAP / (preset + '-sea-time-4.png'))).astype(float)[..., :3]
    d = abs(a-b)
    changed = int((d.max(axis=2) > 0).sum())
    assert changed > 100
    metrics[preset] = {'sea_only_t0_vs_t4_changed_pixels': changed,
                       'whole_frame_mean_rgb_255': float(d.mean()),
                       'maximum_rgb_255': float(d.max())}

frames = []
for i in range(80):
    frame = Image.new('RGB', (720, 800))
    for j, preset in enumerate(['bay', 'lake']):
        frame.paste(label(Image.open(CAP / f'{preset}-motion/{i:03d}.png'), preset, True), (j*360, 0))
    frames.append(frame)
# Ordered, stationary dither retains the soft water gradient without temporal noise.
panels = OUT / 'motion-panels'
panels.mkdir(exist_ok=True)
for i, frame in enumerate(frames):
    frame.save(panels / f'{i:03d}.png')
subprocess.run(['ffmpeg', '-y', '-v', 'error', '-threads', '1', '-filter_complex_threads', '1',
                '-framerate', '20', '-i', str(panels/'%03d.png'),
                '-filter_complex', '[0:v]split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle',
                '-loop', '0', str(DOC/'motion-review.gif')], check=True)
gif = Image.open(DOC / 'motion-review.gif')
duration = 0
for i in range(gif.n_frames):
    gif.seek(i)
    duration += gif.info['duration']
    assert gif.size == (720, 800)
    if i in [0, gif.n_frames//2, gif.n_frames-1]:
        gif.convert('RGB').save(OUT / f'gif-decoded-{i:03d}.png')
assert duration == 4000
assert (DOC / 'motion-review.gif').stat().st_size < 5*1024*1024
report = {'passed': True, 'duration_ms': duration, 'decoded_frames': gif.n_frames,
          'clock': '80 actual Mobile frames at t=i/20s, TIME substituted only in desktop QA. Real-speed excerpt, not a seamless loop; foam period remains 5.5s.',
          'sea_motion_without_foam': metrics}
(DOC / 'motion-validation.json').write_text(json.dumps(report, indent=2) + '\n')
for source, target in [(CAP/'render-validation.json', 'render-validation.json'),
                       (OUT/'resource-validation.json', 'resource-validation.json')]:
    shutil.copy2(source, DOC/target)
names = ['bay-default-review.png', 'lake-default-review.png', 'motion-review.gif']
names += [name for name in ['android-bay.png', 'android-lake.png'] if (DOC/name).exists()]
manifest = {name: {'bytes': (DOC/name).stat().st_size,
                  'sha256': hashlib.sha256((DOC/name).read_bytes()).hexdigest()} for name in names}
(DOC / 'media-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
print(json.dumps({'media': manifest, 'motion': report}, indent=2))
