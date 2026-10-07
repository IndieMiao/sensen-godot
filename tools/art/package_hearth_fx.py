"""Package the actual shared-FX integration evidence without replacing old art reviews."""
from pathlib import Path
import sys,json,hashlib,shutil
from PIL import Image,ImageDraw,ImageFont
import numpy as np
ROOT=Path(__file__).resolve().parents[2];slug=sys.argv[1];BASE=ROOT/'output/zhaoyun-shared-fire-2026-10-08';OUT=BASE/slug;DOC=ROOT/'docs/design'/(slug+'-fire-2026-10-08');DOC.mkdir(exist_ok=True)
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf',20)
def sheet(items,name,width=720,height=540):
 canvas=Image.new('RGB',(len(items)*width,height+48),'#f5f0df');d=ImageDraw.Draw(canvas)
 for i,(label,im) in enumerate(items):canvas.paste(im.convert('RGB').resize((width,height),Image.Resampling.LANCZOS),(i*width,48));d.text((i*width+14,12),label,font=font,fill='#4a4032')
 canvas.save(DOC/name)
for name in ('godot.png','fire-runtime.json','fire-video-metadata.json'):shutil.copy2(OUT/name,DOC/name)
shutil.copy2(OUT/'clip-1.png',DOC/'fire-close.png')
sheet([('Whole scene / Godot Mobile',Image.open(OUT/'godot.png')),('Shared GPU fire / actual viewport',Image.open(OUT/'clip-1.png'))],'whole-and-fire.png')
frames=[Image.open(OUT/f'clip-{i}.png').convert('RGB') for i in range(3)]
sheet(list(zip(['8s clip / 0.5s','8s clip / 4s','8s clip / 7.5s'],frames)),'fire-timeline.png',640,480)
arrays=[np.array(im,dtype=np.int16) for im in frames]
assert all(a.mean()>8 and a.std()>8 for a in arrays)
diffs=[float(np.abs(arrays[i+1]-arrays[i]).mean()) for i in range(2)];assert min(diffs)>.1
for name in ('spawn.png','main.png','door.png','collisions.png','result.json','record-result.json','scale-measurements.json','video-metadata.json'):shutil.copy2(OUT/'bench'/name,DOC/('bench-'+name))
shutil.copy2(BASE/(slug+'-preservation.json'),DOC/'preservation.json');shutil.copy2(BASE/(slug+'-render-preservation.json'),DOC/'render-preservation.json')
sheet([('Old material / flames hidden',Image.open(OUT/'control-before/godot.png')),('New adapter / particles and ember glow off',Image.open(OUT/'control-after/godot.png'))],'preservation-control.png')
layout=json.loads((ROOT/'assets/rooms'/slug/'layout.json').read_text());stats=json.loads((ROOT/'assets/rooms'/slug/'asset_stats.json').read_text());render=json.loads((OUT/'godot-validation.json').read_text());bench=json.loads((OUT/'bench/result.json').read_text());motion=json.loads((OUT/'fire-runtime.json').read_text());preserve=json.loads((DOC/'preservation.json').read_text());control=json.loads((DOC/'render-preservation.json').read_text())
assert bench['passed'] and motion['passed'] and preserve['passed'] and control['passed'];assert stats['scene_triangles']==render['triangles'] and stats['static_draw_surfaces']==render['surfaces'];assert render['particle_capacity']==stats['particles']['capacity']<=40
for rel,expected in preserve['original_files'].items():assert hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()==expected
files=[ROOT/'assets/rooms'/slug/'layout.json',ROOT/'assets/rooms'/slug/'asset_stats.json',ROOT/'tools/art/source'/slug/(slug+'.blend'),ROOT/'scenes'/slug/(slug+'_art.gd'),*list((ROOT/'scenes/room_effects').glob('*')),*[p for p in (ROOT/'assets/rooms/_shared/fx').iterdir() if p.suffix in ('.png','.gd','.tscn')]]
result={'scene':slug,'scope':'Only shared particle flame integration, existing hearth light flicker and masked ember emission. No atlas rebake or physical-device claim.','shared_library_commit':'5e5bf6af','renderer':render,'asset_stats':stats,'effects':layout['effects'],'ember_surfaces':layout['ember_surfaces'],'character_checks':len(bench['checks']),'character_passed':True,'motion':motion,'particle_frames_nonblank_and_different':True,'sample_mean_rgb_change_255':diffs,'hearth_video_sha256':hashlib.sha256((OUT/'hearth-8s.mp4').read_bytes()).hexdigest(),'hearth_video_seconds':8,'preservation_passed':True,'render_control_mean_rgb_255':control['mean_rgb_255'],'hashes':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
(DOC/'verification-summary.json').write_text(json.dumps(result,indent=2)+'\n')
checks=len(bench['checks']);fx=layout['effects'][0];light=fx['light'];bounds=fx['emission_box'];card={'standard_room_5':172,'deluxe_room_10':173,'bakery':175}[slug]
(DOC/'README.md').write_text(f'''# SGODOT-{card} · shared particle hearth fire

赵云 · Review candidate, 2026-10-08. Consumes Liu Bei's **fx_hearth_fire** from shared-library commit **5e5bf6af** without changing that library.

![Actual whole scene and hearth](whole-and-fire.png)

Static `fire` mesh is removed from runtime `assets`; its file and named Blender source remain archived/hidden for provenance. Hearth body, logs, wood niche and all other editable mesh geometry, transforms, materials and source UVs are preserved. **Every existing room GLB and PNG is byte-identical; no atlas rebake.** [File and editable-source preservation](preservation.json).

Two GPU emitters provide **{fx['flame_count']} flames + {fx['spark_count']} sparks = {render['particle_capacity']} particles / 40 limit**. Emission half-extents `{bounds}`, root `{fx['position']}`, flame-height parameter **{fx['flame_height']}m**. The emitter is placed inside the arched mouth; the oven fire sits behind the loaves. Existing charcoal/low firebox surfaces receive masked low emission through their existing atlas and unchanged mesh. Other material response is retained.

The existing hearth OmniLight moves under the art adapter at the same `{light['position']}` position, colour `{light['color']}`, range `{light['range']}m`, base energy `{light['energy']}`. The shared effect alone writes its bounded smooth flicker; the former review-light entry is removed to avoid a duplicate. Measured energy spans **{motion['light_min']:.4f}–{motion['light_max']:.4f}**, within ±10%. No smoke was added to these indoor hearths.

![First, middle and last recorded fire frames](fire-timeline.png)

**8-second real-time desktop clip**, recorded at 960×720/30fps; first/middle/last frames were visually inspected and decoded nonblank/different. Actual adapter: Godot4.7.2 Mobile/Vulkan, RADV VANGOGH. Close-view draw samples: `{motion['frame_draw_calls']}`; these include the visible room and effect, not physical-phone GPU timing. `hearth-8s.mp4` and the separately recorded 15-second character route are delivered as card attachments.

Budget: **{stats['scene_triangles']:,} static mesh triangles**, **{stats['plant_budget_triangles']:,} botanical-budget triangles**, **{stats['static_draw_surfaces']} static surfaces**, plus **2 GPU particle draws** and at most **{render['particle_capacity']*2} dynamic sprite triangles**. The original static fire's 944 triangles/1surface are no longer placed. **{checks}/{checks} actual rendered character checks pass**, with unchanged room geometry/colliders/anchors and a fresh15-second route recording. [Full evidence/hashes](verification-summary.json).

For preservation control, both flame forms were hidden, the new ember emission disabled, and the original light fixed to its old base. Same camera/light presets then differ by **{control['mean_rgb_255']:.7f} RGB/255 mean** across the whole image (maximum channel delta {control['maximum_channel_difference']} at a small set of raster edges). This is a controlled material/scene comparison, not reference-art similarity. [Control pair](preservation-control.png) · [Numbers](render-preservation.json).

Configuration: `tools/art/source/{slug}/shared-hearth-fx.json`. `apply_shared_hearth_fx.py` is a post-export migration that edits layout/stats and source visibility without rebaking. The normal builder now runs it automatically after export. The adapter lives in `scenes/room_effects/`; the reusable FX remains entirely in `assets/rooms/_shared/fx/`. `record_hearth_fx.py {slug} <output>` records the close view; `scene_bench` records the actual route. Basic Room and production/gameplay saves are untouched.
''')
print('FX_PACKAGE',card,stats['scene_triangles'],render['particle_capacity'],checks)
