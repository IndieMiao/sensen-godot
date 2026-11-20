"""Run ONLY after Daqiao's distinct MVT resource window is granted."""
from pathlib import Path
import subprocess,json,time,datetime,os,argparse,re
R=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--window',required=True);p.add_argument('--deadline',required=True);p.add_argument('--not-before',required=True);a=p.parse_args()
deadline=datetime.datetime.fromisoformat(a.deadline);not_before=datetime.datetime.fromisoformat(a.not_before);assert deadline.tzinfo and not_before.tzinfo and not_before<=datetime.datetime.now(datetime.timezone.utc)<deadline
def resources():
 text=subprocess.check_output(['vm_stat'],text=True);page=int(re.search(r'page size of (\d+) bytes',text)[1]);avail=sum(int(re.search(r'Pages '+n+r':\s+(\d+)',text)[1]) for n in ['free','inactive','speculative'])*page/1024**2
 swap=float(re.search(r'used\s*=\s*([0-9.]+)M',subprocess.check_output(['sysctl','vm.swapusage'],text=True))[1]);return avail,swap
avail,initial_swap=resources();assert avail>=3072,'resource_gate_not_met'
args=['nice','-n','10','tippecanoe','-o',str(R/'staging/parcels.mbtiles'),'-l','parcels','-Z15','-z18','-r1','--no-feature-limit','--no-tile-size-limit','--no-tiny-polygon-reduction','--full-detail=12','--low-detail=12','--simplification=1','--buffer=5','--name=Dynamic Farm SF parcels r4','--attribution=DataSF / SF Planning (PDDL / CC0)',str(R/'staging/parcels-0.ndjson'),str(R/'staging/parcels-1.ndjson')]
log=open(R/'evidence/tippecanoe.log','w');child=subprocess.Popen(args,stdout=log,stderr=subprocess.STDOUT,env=dict(os.environ,TIPPECANOE_MAX_THREADS='2'));record={'window':a.window,'pid':child.pid,'started':datetime.datetime.now(datetime.timezone.utc).isoformat(),'command':args,'threads':2,'deadline':deadline.isoformat()};start=time.monotonic();maxrss=0
try:
 while child.poll() is None:
  try:maxrss=max(maxrss,int(subprocess.check_output(['ps','-o','rss=','-p',str(child.pid)],text=True).strip())/1024)
  except (ValueError,subprocess.CalledProcessError):pass
  avail,swap=resources();record.update(available_mib=avail,swap_mib=swap,initial_swap_mib=initial_swap)
  if avail<3072 or swap>initial_swap+300:
   child.terminate();child.wait(timeout=20);record['resource_pressure_stopped']=True;break
  if datetime.datetime.now(datetime.timezone.utc)>=deadline:
   child.terminate();child.wait(timeout=20);record['hard_deadline_stopped']=True;break
  record.update(elapsed_s=time.monotonic()-start,peak_sampled_rss_mib=maxrss);(R/'evidence/mvt-runtime.json').write_text(json.dumps(record,indent=2)+'\n');time.sleep(2)
finally:
 if child.poll() is None:child.terminate();child.wait(timeout=20)
 record.update(exit_code=child.returncode,elapsed_s=time.monotonic()-start,peak_sampled_rss_mib=maxrss);(R/'evidence/mvt-runtime.json').write_text(json.dumps(record,indent=2)+'\n');log.close()
print(json.dumps(record),flush=True)
if child.returncode:raise SystemExit(child.returncode)
