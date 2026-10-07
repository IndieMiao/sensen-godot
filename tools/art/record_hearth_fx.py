"""Capture eight real seconds of the shared fire in its consuming room."""
from pathlib import Path
import sys,os,subprocess,json,time,math,shutil
ROOT=Path(__file__).resolve().parents[2];slug=sys.argv[1];out=Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=True);project=ROOT/'output'/(slug+'-2026-10-07')/'godot-project';shutil.copy2(ROOT/'tools/art/record_hearth_fx.gd',project/'tools/art/record_hearth_fx.gd')
go=out/'fx-go'
if go.exists():go.unlink()
log=(out/'fire-record.log').open('w');app=subprocess.Popen(['godot','--path',str(project),'--resolution','960x720','--position','0,0','--borderless','--script','res://tools/art/record_hearth_fx.gd','--',slug,str(out)],stdout=log,stderr=subprocess.STDOUT);recorder=None
try:
 deadline=time.monotonic()+45
 while time.monotonic()<deadline:
  if app.poll() is not None:raise RuntimeError('Fire viewport exited; inspect log')
  try:
   state=json.loads((out/'fx-state.json').read_text())
   if state['pid']==app.pid and state['phase']=='record-ready':break
  except (OSError,ValueError):pass
  time.sleep(.05)
 else:raise RuntimeError('Fire recorder handshake timeout')
 recorder=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','x11grab','-draw_mouse','0','-framerate','30','-video_size','960x720','-i',os.environ['DISPLAY']+'+0,0','-t','8','-c:v','libx264','-preset','veryfast','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(out/'hearth-8s.mp4')])
 time.sleep(.25);go.write_text(str(app.pid));assert recorder.wait(timeout=20)==0;assert app.wait(timeout=30)==0
 result=json.loads((out/'fire-runtime.json').read_text());assert result['passed']
 metadata=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration:stream=codec_name,width,height','-of','json',str(out/'hearth-8s.mp4')],text=True));assert 7.8<float(metadata['format']['duration'])<8.2
 for i,t in enumerate((.5,4,7.5)):
  subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-ss',str(t),'-i',str(out/'hearth-8s.mp4'),'-frames:v','1',str(out/f'clip-{i}.png')],check=True)
 metadata['real_time']=True;(out/'fire-video-metadata.json').write_text(json.dumps(metadata,indent=2)+'\n');print('FIRE_VIDEO_VERIFIED',slug)
finally:
 if recorder and recorder.poll() is None:recorder.terminate();recorder.wait(timeout=5)
 if app.poll() is None:app.terminate();app.wait(timeout=10)
 log.close()
