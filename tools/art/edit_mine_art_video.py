#!/usr/bin/env python3
from pathlib import Path
import json,subprocess,math,textwrap
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'output/mine-art-video-2026-09-16';FINAL=OUT/'交付';FINAL.mkdir(exist_ok=True)
clips=json.loads((OUT/'timeline.json').read_text());assert json.loads((OUT/'recording-result.json').read_text())['passed']
def run(args):subprocess.run(args,check=True,stdout=subprocess.DEVNULL,stderr=open(OUT/'private/ffmpeg.log','ab'))
def probe(path):return json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-show_streams','-of','json',str(path)]))
def stamp(t):
 cent=max(0,round(t*100));h,rest=divmod(cent,360000);m,rest=divmod(rest,6000);s,cs=divmod(rest,100);return f'{h}:{m:02}:{s:02}.{cs:02}'
def wrap(text):
 lines=[];line='';n=0
 for ch in text:
  weight=1 if ord(ch)<128 else 2
  if n+weight>44:lines.append(line);line='';n=0
  line+=ch;n+=weight
 if line:lines.append(line)
 return '\\N'.join(lines)
concat=OUT/'private/concat.txt';concat.write_text(''.join("file '"+str((ROOT/c['file']).resolve()).replace("'","'\\''")+"'\n" for c in clips))
raw=FINAL/'矿井演示-无字幕原片.mp4'
run(['ffmpeg','-y','-hide_banner','-f','concat','-safe','0','-i',str(concat),'-vf','fps=30','-an','-c:v','libx264','-preset','fast','-crf','21','-pix_fmt','yuv420p','-movflags','+faststart',str(raw)])
ass='''[Script Info]
ScriptType: v4.00+
PlayResX: 720
PlayResY: 1800
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Header,Arial Unicode MS,29,&H00F5FAF7,&H00FFFFFF,&H001D3329,&H001D3329,-1,0,0,0,100,100,0,0,1,0,0,8,20,20,20,1
Style: Detail,Arial Unicode MS,17,&H00CCDCCF,&H00FFFFFF,&H001D3329,&H001D3329,0,0,0,0,100,100,0,0,1,0,0,8,20,20,70,1
Style: Caption,Arial Unicode MS,27,&H00FFFFFF,&H00FFFFFF,&H001D3329,&H001D3329,0,0,0,0,100,100,0,0,1,0,0,2,26,26,25,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
'''
segments=[];offset=0
for idx,clip in enumerate(clips):
 duration=float(probe(ROOT/clip['file'])['format']['duration']);end=offset+duration
 title=clip['label'].replace(' ',' / ',1)
 ass+=f'Dialogue: 0,{stamp(offset)},{stamp(end)},Header,,0,0,0,,{title}\n'
 ass+=f'Dialogue: 0,{stamp(offset)},{stamp(end)},Detail,,0,0,0,,当前版本 0.11.0 · Android 模拟器 · 实际运行画面\n'
 events=clip['events'];merged=[]
 for e in events:
  if not merged or merged[-1]['text']!=e['text']:merged.append(e)
 for n,e in enumerate(merged):
  start=offset+max(0,e['time']-.3);until=offset+min(duration,merged[n+1]['time']-.3 if n+1<len(merged) else duration)
  if until<=start:continue
  text=e['text']
  if n==0:text='从农场进入矿井，观察场景、角色与操作反馈' if idx==0 else '第三、四层：普通史莱姆与战斗操作' if idx==1 else '第五层：精英冲撞与战败返回' if idx==2 else '战败后恢复生命，再次挑战并解锁电梯'
  if idx>=2 and text.startswith('击败怪物'):text='精英击败后结算掉落，电梯永久解锁'
  ass+=f'Dialogue: 1,{stamp(start)},{stamp(until)},Caption,,0,0,0,,{wrap(text)}\n'
  segments.append({'start':round(start,2),'end':round(until,2),'text':text})
 clip['duration']=duration;clip['start']=offset;offset=end
asspath=OUT/'private/captions.ass';asspath.write_text(ass)
annotated=FINAL/'矿井演示-美术说明版.mp4'
filter_text=f'pad=720:1800:0:110:color=0x233E33,ass={asspath.as_posix()}'
run(['ffmpeg','-y','-hide_banner','-i',str(raw),'-vf',filter_text,'-an','-c:v','libx264','-preset','fast','-crf','21','-pix_fmt','yuv420p','-movflags','+faststart',str(annotated)])
cover_at=clips[2]['start']+5
run(['ffmpeg','-y','-hide_banner','-ss',str(cover_at),'-i',str(annotated),'-frames:v','1',str(FINAL/'矿井演示-封面.png')])
# Playback reference and SRT for editing without burning captions into the source.
def srt(t):return stamp(t).replace('.',',').zfill(11)+'0'
(FINAL/'矿井演示-字幕.srt').write_text('\n\n'.join(f"{i+1}\n{srt(s['start'])} --> {srt(s['end'])}\n{s['text']}" for i,s in enumerate(segments)))
notes='''# 矿井功能录屏 · 美术说明

基线：Journey 0.11.0，2026-09-16 当前矿井和多人战斗逻辑。

- 美术说明版：原始手机画面完整保留，画面外加阶段标题和操作说明，无配音。
- 无字幕原片：720×1560，可直接取帧或重新剪辑；四个实际操作章节之间有剪接，包含一次战败后再战。
- Android 模拟器连接独立的真实游戏后端。测试账号预置铜剑、铜镐、探矿靴及料理；怪物血量、伤害、碰撞、掉落与通行条件未修改。
- 当前录制为一名玩家操作，不是多人拥挤场景压测。没有改动线上账号或存档。

## 观看顺序

'''
for c in clips:notes+=f"- {int(c['start'])//60:02}:{int(c['start'])%60:02}　{c['label']}\n"
notes+='''
## 给美术的观察点

1. 农场矿洞入口：入口模型、可点击识别与场景切换。
2. 矿层空间：地面/岩壁、照明、矿石、上下层梯子、锁定与解锁电梯。
3. 采矿：角色走近、劳作动作、进度条、矿石消失与材料反馈。
4. 普通怪：待机/追击、蓄力预警、冲撞、受击、击退、生命条和击败后的资源反馈。
5. 武器：平时收起，每次挥剑时显示；观察动作衔接和攻击范围提示。
6. 精英怪：更大的体型、300 生命、冲撞预警和抗打断表现；与普通怪区分轮廓、材质和特效。
7. 操作 UI：左侧摇杆，右侧采矿/上下层/攻击；顶部楼层、生命、在线状态与背包。
8. 结果：料理恢复、战败回农场、休息恢复、通行条件完成、电梯永久解锁和返回农场。

这是当前实现的视觉参考。新 UI、场景材质、角色动作和特效方案可基于这些状态设计。
'''
(FINAL/'给美术的说明.md').write_text(notes)
report={'passed':True,'duration_seconds':float(probe(annotated)['format']['duration']),'clips':clips,'captions':segments,'files':[]}
for file in [raw,annotated]:
 p=probe(file);v=next(s for s in p['streams'] if s['codec_type']=='video');assert v['codec_name']=='h264' and v['pix_fmt']=='yuv420p'
 report['files'].append({'name':file.name,'bytes':file.stat().st_size,'width':v['width'],'height':v['height'],'duration':p['format']['duration']})
(OUT/'edit-result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps({'duration':report['duration_seconds'],'files':report['files']},ensure_ascii=False))
