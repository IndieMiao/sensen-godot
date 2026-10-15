#!/usr/bin/env python3
"""Run the unchanged scene_bench with gs66's X11 window capture correction."""
from pathlib import Path
import argparse,os,shutil,subprocess,sys,shlex
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--ffmpeg',default=shutil.which('ffmpeg'))
p.add_argument('--ffprobe',default=shutil.which('ffprobe'));a=p.parse_args()
assert a.ffmpeg and a.ffprobe,'Supply existing FFmpeg and FFprobe paths'
bin_dir=ROOT/'output/tackle-214/bench-bin';bin_dir.mkdir(parents=True,exist_ok=True)
for name,target in [('ffmpeg',ROOT/'tools/art/tackle_ffmpeg_capture.py'),('ffprobe',Path(a.ffprobe).resolve())]:
    link=bin_dir/name
    if link.is_symlink():link.unlink()
    link.symlink_to(target)
engine=Path(shutil.which('godot')).resolve()
wrapper=bin_dir/'godot'
wrapper.write_text('#!/bin/sh\nexec '+shlex.quote(str(engine))+' --display-driver x11 --rendering-method mobile --rendering-driver vulkan "$@"\n')
wrapper.chmod(0o755)
(ROOT/'tools/art/tackle_ffmpeg_capture.py').chmod(0o755)
env=os.environ.copy();env['PATH']=str(bin_dir)+os.pathsep+env['PATH']
env['TACKLE_BENCH_STATE']=str(ROOT/'output/tackle-214/bench/state.json')
env['TACKLE_CAPTURE_RECEIPT']=str(ROOT/'output/tackle-214/bench/window-capture.json')
env['TACKLE_FFMPEG']=str(Path(a.ffmpeg).resolve())
subprocess.run([sys.executable,str(ROOT/'tools/dev/scene_bench/run.py'),'tackle_shop','--record',
    '--project','output/tackle-214/project','--output','output/tackle-214/bench'],cwd=ROOT,env=env,check=True)
