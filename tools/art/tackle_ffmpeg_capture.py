#!/usr/bin/env python3
"""Task-local FFmpeg bridge: capture only the benchmark's verified X11 window.

Wayland's XWayland root image is black. The shared runner stays unchanged;
the recording reads the actual window belonging to its PID instead.
"""
import os,sys,json,subprocess,re
from pathlib import Path
args=sys.argv[1:]
if 'x11grab' in args:
    state=json.loads(Path(os.environ['TACKLE_BENCH_STATE']).read_text())
    pid=int(state['pid'])
    command=Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0',b' ').decode()
    assert 'tackle-214/project' in command and '--record-route' in command
    tree=subprocess.check_output(['xwininfo','-root','-tree'],text=True)
    ids=[]
    for line in tree.splitlines():
        if 'Scene Benchmark' not in line:continue
        match=re.search(r'0x[0-9a-fA-F]+',line)
        if not match:continue
        identity=subprocess.run(['xprop','-id',match[0],'_NET_WM_PID'],capture_output=True,text=True,check=True).stdout
        if re.search(r'=\s*'+str(pid)+r'\s*$',identity):ids.append(match[0])
    assert len(ids)==1, ('Expected one owned benchmark window',ids)
    idx=args.index('-i');args[idx:idx]=['-window_id',str(int(ids[0],16))]
    args[args.index('-i')+1]=os.environ['DISPLAY']
    Path(os.environ['TACKLE_CAPTURE_RECEIPT']).write_text(json.dumps({'pid':pid,'window_id':ids[0],
        'capture':'Actual X11 window, verified against benchmark PID; no desktop crop or speed change'},indent=2)+'\n')
os.execv(os.environ['TACKLE_FFMPEG'],[os.environ['TACKLE_FFMPEG'],*args])
