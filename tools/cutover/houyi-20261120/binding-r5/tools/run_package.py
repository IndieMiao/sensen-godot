from pathlib import Path
import subprocess,json,time,datetime,sys
R=Path(__file__).resolve().parents[1];py=str(R.parent/'parcel-r2/.venv/bin/python');start=datetime.datetime.fromisoformat('2026-11-18T22:56:00+08:00');deadline=datetime.datetime.fromisoformat('2026-11-18T23:06:00+08:00');assert start<=datetime.datetime.now(datetime.timezone.utc)<deadline
records=[]
for name in ['export_validate_tiles.py','finalize_city.py','archive_static.py','write_data_report.py','archive_review.py']:
 assert datetime.datetime.now(datetime.timezone.utc)<deadline
 log=(R/'evidence'/(name+'.log')).open('w');p=subprocess.Popen(['nice','-n','10',py,str(R/'tools'/name)],stdout=log,stderr=subprocess.STDOUT);row={'step':name,'pid':p.pid,'start':datetime.datetime.now(datetime.timezone.utc).isoformat(),'peak_rss_mib':0};records.append(row);print('START',name,p.pid,flush=True)
 try:
  while p.poll() is None:
   try:row['peak_rss_mib']=max(row['peak_rss_mib'],int(subprocess.check_output(['ps','-o','rss=','-p',str(p.pid)],text=True).strip())/1024)
   except (ValueError,subprocess.CalledProcessError):pass
   if datetime.datetime.now(datetime.timezone.utc)>=deadline:p.terminate();p.wait(timeout=20);row['hard_deadline_stopped']=True;break
   (R/'evidence/package-runtime.json').write_text(json.dumps({'window':'Q1117-46','deadline':deadline.isoformat(),'steps':records},indent=2)+'\n');time.sleep(2)
 finally:
  if p.poll() is None:p.terminate();p.wait(timeout=20)
  row.update(exit_code=p.returncode,end=datetime.datetime.now(datetime.timezone.utc).isoformat());(R/'evidence/package-runtime.json').write_text(json.dumps({'window':'Q1117-46','deadline':deadline.isoformat(),'steps':records},indent=2)+'\n');log.close()
 print('END',name,p.returncode,flush=True)
 if p.returncode:raise SystemExit(p.returncode)
print('PACKAGE_COMPLETE',flush=True)
