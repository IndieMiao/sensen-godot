"""Three actual 8s Godot viewport clips with monotonic PTS; no time acceleration."""
from pathlib import Path
import sys,json,subprocess,shutil
ROOT=Path(__file__).resolve().parents[4];revision=sys.argv[1] if len(sys.argv)>1 else 'r22';out=ROOT/'output/blacksmith_shop'/revision;stage=out/'godot-project'
s=(ROOT/'tools/art/source/coffee_shop/render_r1.gd').read_text()
a=s.index('\tvar views := [');b=s.index('\tfor view in views:',a)
s=s[:a]+'''\tvar views := [
 ["whole-motion",_vec(layout.camera.position),_vec(layout.camera.target),float(layout.camera.size)],
 ["fire-motion",Vector3(3.7,3.7,5.5),Vector3(-1.48,1.6,-2.03),3.1],
 ["smoke-motion",Vector3(4.4,7.6,6.0),Vector3(-.35,5.95,-2.29),5.1]]
'''+s[b:]
if revision=='r23':
 a=s.index(' ["whole-motion"');b=s.index(' ["smoke-motion"',a);s=s[:a]+s[b:]
s=s.replace('viewport.size = Vector2i(1400,1400)','viewport.size = Vector2i(960,960)')
a=s.index('\t\tfor i in range(8):');b=s.index('\tvar result :=',a)
s=s[:a]+'''\t\tfor i in range(8): await process_frame
  var frames: Array = []
  var energies: Array = []
  var started := Time.get_ticks_usec()
  var previous := -1.0
  while float(Time.get_ticks_usec()-started)/1000000.0 < 8.0:
   await process_frame
   var elapsed := float(Time.get_ticks_usec()-started)/1000000.0
   energies.append(room.get_node("LocalLight_forge_fire").light_energy)
   if elapsed-previous < .05: continue
   await RenderingServer.frame_post_draw
   var path := output_dir+"/"+str(view[0])+"-%04d.jpg" % frames.size()
   viewport.get_texture().get_image().save_jpg(path,.93)
   frames.append({"file":path,"seconds":elapsed})
   previous = elapsed
  var f := FileAccess.open(output_dir+"/"+str(view[0])+"-frames.json",FileAccess.WRITE)
  f.store_string(JSON.stringify({"frames":frames,"light_energy_min":energies.min(),"light_energy_max":energies.max(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)},"  "))
''' +s[b:]
# Existing renderer is tab-indented; expand uniformly before mixing our snippets.
s=s.replace('godot-verification.json','particle-record-verification.json').replace('[1400,1400]','[960,960]');s=s.expandtabs(1);(stage/'record_particles.gd').write_text(s)
with (out/'particle-record.log').open('w') as log:
 subprocess.run(['godot','--path',str(stage),'--disable-vsync','--max-fps','60','--rendering-method','mobile','--rendering-driver','vulkan','--script','res://record_particles.gd','--','blacksmith_shop',str(out)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=90)
records=[]
for name in (['smoke-motion'] if revision=='r23' else ['whole-motion','fire-motion','smoke-motion']):
 d=json.loads((out/(name+'-frames.json')).read_text());fs=d.pop('frames');seq=['ffconcat version 1.0'];assert len(fs)>50
 for i,f in enumerate(fs):
  nxt=fs[i+1]['seconds'] if i+1<len(fs) else 8.0
  seq += ["file '"+f['file']+"'",f'duration {max(.001,nxt-f["seconds"]):.6f}']
 seq+=["file '"+fs[-1]['file']+"'"];(out/(name+'.ffconcat')).write_text('\n'.join(seq)+'\n')
 subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-f','concat','-safe','0','-i',str(out/(name+'.ffconcat')),'-vf','fps=30','-t','8','-c:v','libx264','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(out/(name+'.mp4'))],check=True)
 d.update(clip=name+'.mp4',frames=len(fs),duration_seconds=8,accelerated=False,renderer='Godot Mobile/Vulkan',capture='Wall-clock viewport samples at up to 20 Hz, resampled to 30fps; not a GPU timing benchmark.')
 records.append(d)
(out/'particle-clips.json').write_text(json.dumps(records,indent=2)+'\n')
print(records)
