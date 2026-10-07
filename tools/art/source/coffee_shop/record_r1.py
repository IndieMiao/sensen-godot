"""Record the unchanged shared harness via real rendered viewport with wall-clock PTS."""
from pathlib import Path
import subprocess,json,shutil
ROOT=Path(__file__).resolve().parents[4];project=ROOT/'output/scene-bench/coffee_shop/project';out=ROOT/'output/scene-bench/coffee_shop/evidence'
shutil.copy2(Path(__file__).with_suffix('.gd'),project/'record_r1.gd')
(out/'record-go').unlink(missing_ok=True)
with (out/'record-viewport.log').open('w') as log:
    subprocess.run(['godot','--disable-vsync','--max-fps','60','--path',str(project),'--resolution','960x720','--position','0,0','--borderless','--script','res://record_r1.gd','--','--slug','coffee_shop','--output',str(out),'--record-route'],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=75)
result=json.loads((out/'record-result.json').read_text());assert result['passed']
frames=json.loads((out/'viewport-frames.json').read_text())['frames'];assert len(frames)>100 and frames[-1]['seconds']>14.8
# Use actual captured intervals; resample to 30fps without accelerating wall time.
sequence=[]
for i,f in enumerate(frames):
    end=frames[i+1]['seconds'] if i+1<len(frames) else 15.0
    duration=max(.001,end-f['seconds'])
    sequence += ["file '"+f['file']+"'",f'duration {duration:.6f}']
sequence += ["file '"+frames[-1]['file']+"'"]
(out/'viewport.ffconcat').write_text('ffconcat version 1.0\n'+'\n'.join(sequence)+'\n')
subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','concat','-safe','0','-i',str(out/'viewport.ffconcat'),'-vf','fps=30','-t','15','-c:v','libx264','-preset','veryfast','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart','-metadata','comment=Real-time Godot Mobile/Vulkan viewport; original monotonic timestamps; no acceleration',str(out/'walkthrough.mp4')],check=True)
for i,t in enumerate((.5,7.5,14)):
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',str(t),'-i',str(out/'walkthrough.mp4'),'-frames:v','1',str(out/f'video-{i}.png')],check=True)
probe=subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration:stream=codec_name,width,height','-of','json',str(out/'walkthrough.mp4')],text=True)
meta=json.loads(probe);meta['capture']='Godot rendered viewport; wall-clock frame timestamps';meta['accelerated']=False;meta['captured_frames']=len(frames);meta['capture_intervals_seconds']={'mean':(frames[-1]['seconds']-frames[0]['seconds'])/(len(frames)-1),'max':max(b['seconds']-a['seconds'] for a,b in zip(frames,frames[1:]))}
(out/'video-metadata.json').write_text(json.dumps(meta,indent=2)+'\n');print('VIEWPORT_VIDEO_READY',len(frames),meta['format']['duration'])
