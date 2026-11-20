import pathlib,subprocess,json,time,re,datetime,os,sys
R=pathlib.Path(__file__).resolve().parents[1];python=str(R.parent/'parcel-r2/.venv/bin/python');procs={};rows=[];logs=[];restart=[]
def resources():
 s=subprocess.check_output(['vm_stat'],text=True);page=int(re.search(r'page size of (\d+) bytes',s)[1]);avail=sum(int(re.search(r'Pages '+n+r':\s+(\d+)',s)[1]) for n in ['free','inactive','speculative'])*page/1024**2
 swap=float(re.search(r'used\s*=\s*([0-9.]+)M',subprocess.check_output(['sysctl','vm.swapusage'],text=True))[1]);return avail,swap
avail,initial_swap=resources()
if avail<3072 or initial_swap>=7500:raise SystemExit('resource_gate_not_met')
def start(shard):
 log=open(R/'evidence'/f'source-audit-shard-{shard}.log','w');logs.append(log)
 p=subprocess.Popen(['nice','-n','10',python,str(R/'tools/audit_source_geometry.py'),'--shard',str(shard),'--shards','2'],stdout=log,stderr=subprocess.STDOUT)
 row={'shard':shard,'pid':p.pid,'start':datetime.datetime.now(datetime.timezone.utc).isoformat(),'peak_rss_mib':0};rows.append(row);procs[shard]=(p,row)
for shard in [0,1]:start(shard)
while procs:
 avail,swap=resources()
 if len(procs)>1 and (avail<3072 or swap>initial_swap+300 or swap>=7500):
  p,row=procs.pop(1);p.terminate();p.wait(timeout=20);row.update(exit_code=p.returncode,resource_downgrade=True,end=datetime.datetime.now(datetime.timezone.utc).isoformat());restart.append(1)
 for shard,(p,row) in list(procs.items()):
  if p.poll() is not None:
   row.update(exit_code=p.returncode,end=datetime.datetime.now(datetime.timezone.utc).isoformat());del procs[shard]
   if p.returncode:print('FAILED',row,flush=True)
  else:
   try:row['peak_rss_mib']=max(row['peak_rss_mib'],int(subprocess.check_output(['ps','-o','rss=','-p',str(p.pid)],text=True).strip())/1024)
   except (ValueError,subprocess.CalledProcessError):pass
 (R/'evidence/source-audit-runtime.json').write_text(json.dumps({'initial_swap_mib':initial_swap,'available_mib':avail,'swap_mib':swap,'processes':rows,'pending_restart':restart},indent=2)+'\n')
 if not procs and restart:
  if avail>=3072:start(restart.pop())
  else:print('restart_requires_resource_window',restart,flush=True)
 if procs:time.sleep(5)
for l in logs:l.close()
print(json.dumps(rows),flush=True)
if any(r.get('exit_code')!=0 and not r.get('resource_downgrade') for r in rows) or restart:raise SystemExit(1)
