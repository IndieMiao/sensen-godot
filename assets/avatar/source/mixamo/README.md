# Mixamo 动作接入（B 路线：本机离线重定向）

把 Mixamo 上下载的 **Y Bot 版**动作 FBX 放进本目录，写一份 `clips.json`，跑一条命令，
动作就重定向到本项目的 dt 62 骨骨架并进入 `assets/avatar/base/animations.res`。
不改 base_rig 的骨骼名与 rest，30 个部件 .res 与 socket 挂点原样可用。

## 一、下载（唯一需要人手的步骤，登录一次即可）

1. 打开 <https://www.mixamo.com/> ，用 Adobe ID 登录（免费账号即可）。
2. 左侧 Characters 保持默认的 **Y Bot**（不要换成自定义角色）。
3. Animations 页搜动作。建议搜索词：`dig` `shovel` `pick` `gather` `crouch` `kneel`
   `throw` `sweep` `hammer` `chop` `water` `plant` `wave` `greeting`。
4. 右侧参数：动作若原地不动就勾 **In Place**（有这个选项时）。
5. Download 面板：
   - Format：**FBX Binary (.fbx)**
   - Skin：**Without Skin**（只要骨骼动画，文件小十倍）
   - Frames per Second：**30**
   - Keyframe Reduction：**none**
6. 文件名保持 Mixamo 给的即可（如 `Digging.fbx`），全部放到本目录。

授权：Mixamo 动作可免版税用于商业游戏，无需署名；不能把原始动画文件当资产包对外分发，
团队内部共享（含入库）允许。所以源 FBX 可以直接提交进仓库。

## 二、写清单

复制 `clips.example.json` 为 `clips.json`，按实际文件名改 `file`。字段：

| 字段 | 含义 | 默认 |
|---|---|---|
| `file` | 相对本目录的 FBX/GLB 文件名 | 必填 |
| `animation` | 文件内动画名；Mixamo FBX 只有一条，可省略 | 第一条 |
| `loop` | 循环播放。劳作动作 true；挥手等一次性动作 false | true |
| `in_place` | 去掉髋部水平位移，角色不漂移 | true |
| `start` / `end` | 裁剪源片段（秒） | 全长 |
| `speed` | 播放速度倍率 | 1.0 |

clip 的 key（`labour_till`、`emote_wave` …）必须与 `assets/avatar/base/anim_placeholders.json`
里占位条目的 `clip_id` 一致，管线才会把该动作从占位转正。

## 三、跑管线

```bash
godot --headless --path . --import        # 新放进来的 FBX 先导入一次
godot --headless --path . --script res://tools/pipeline/gen_mixamo_clips.gd
```

输出每条 clip 的映射骨数（Mixamo 全骨应为 46）、帧数、髋高比与朝向修正角。成功后会：

- 把 clip 写进 `assets/avatar/base/animations.res`（同名覆盖，idle/walk/run 不动）；
- 把 clip key 登记进 `anim_placeholders.json` 的 `real_clips`，占位条目 `status` 标成 `real`。

`tools/pipeline/gen_base_rig.gd` 全量重生成时也会跑同一步，不会丢。

## 四、目视验收

```bash
godot --path . --script res://tools/dev/anim_visual_probe.gd -- --clips=labour_till,emote_wave --frames=5
```

带窗口运行，联系表 PNG 输出到 `output/anim-probe/`。看三件事：胳膊没反、脚没穿地、
动作幅度和 idle/walk 风格一致。数字全对但胳膊反了的情况只有看图才能发现。

然后跑守卫测试：`tools/run_tests.sh res://tests/farm` 与 `tools/run_tests.sh res://tests/pipeline`。

## 五、原理与边界

- 算法：世界空间旋转差分。两边都是 T-pose，源骨相对 rest 的世界旋转增量原样叠到目标骨的
  世界 rest 上，再折回局部旋转；髋部位移按髋高比缩放；未映射骨（Cup_*、shoesTongue_*、
  眼、颌）钉在 rest。实现在 `tools/pipeline/mixamo_retarget.gd`，映射表 `BONE_MAP` 也在那里。
- 命名陷阱：dt 骨架是 Maya AdvancedSkeleton 命名，`Shoulder_*` 是上臂、`Scapula_*` 才是肩，
  `Hip_*` 是大腿。改映射表前先看清。
- 不适合的动作：需要手脚精确接触的（爬梯、双手扶物）——比例不同会穿模；带大位移的
  跑跳要关 `in_place` 并另行处理根运动。
- 不用 Blender 做 FBX 往返：Blender 导出会重写关节朝向，与 base_rig 的 rest 对不上。
- Mixamo 网站的"上传自定义角色"路线（A 路线）不需要本目录，但每条动作都得手点，
  且已知会多出根骨，不推荐。
