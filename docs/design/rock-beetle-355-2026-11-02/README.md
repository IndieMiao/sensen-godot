# SGODOT-355 岩甲虫正式版 v1

赵云，2026-11-02。灰模 bf5279c3 已通过上官婉儿技术检查（355 5a8606d9）；本版按她的三处意见及不知火舞 6a4c6bba 的补充调整，交正式首版技术检查、画面验收。未批准合并，355 状态仍由奕星管理。

## 本版变化

| 项目 | 正式 v1 |
|---|---|
| 壳 | 深、偏冷的岩棕 685B59；含橙边宽 0.82 m、前后长 0.98 m |
| 整体 | 含头和脚约 0.931 × 1.104 × 0.494 m（宽×深×高），横向低于 1.1 m |
| 体量取值 | 主壳取“约 0.9 × 0.75 m”的上沿，并增加厚度，让体量来自壳而非外伸长腿；三视图给出全部轮廓供复核 |
| 橙边 | F2A13C，截面加宽并在脸上方拱起，正面可见环绕边 |
| 腿 | 缩短、加粗，膝部向下弯；保留六腿、每腿一骨 |
| 触角 | 保留 ant_l/r，杆及端球加粗，默认镜头仍可见；不删骨 |
| stunned | 身体下沉约 4.4–4.9 cm，壳左右摇约 ±15°，六腿朝上交替乱蹬；触角下垂、头左右晃 |
| hit | 增强身体与头部顿挫，加小幅抬身、后缩；闪白及击退位移仍归程序 |
| radius | 0.45 → **0.58 m**；静止网格最大水平径距约 0.5743 m，向上取厘米 |
| 接口 | 11 根骨骼的名称和层级、8 个动作名称/时长、hit_at=0.18 均保持 |

壳尺寸最终取 0.98 × 0.82 m，是在同镜头与史莱姆并排比较后对原“约”尺寸的小幅放大；并未缩小史莱姆、单独放大截图或改变 6.72 m 视宽。11 骨层级不改，头、触角、腿的绑定支点随新形体调整。

## 文件与分支

运行时仍只推 `art/monsters-355`，本件位于 `assets/monsters/mob_rock_beetle/`，包括 GLB、同名 JSON、GLB 的 .import；不为运行时分支开 PR。保留黄忠的目录，复用他的 `assets/monsters/material_import.gd`，没有新增共享脚本或材质文件。

美术源和审阅分支为 `wp-3d-scene-zhaoyun-monsters-355`，正式版开草稿 PR 到 wp-3d-scene。具名 Blender 源、生成/验证/拍摄脚本、beetle_v3 与现有史莱姆参考图位于 `tools/art/source/monsters/mob_rock_beetle/`。不做战斗 AI 接入、发包或主线合并。

## 模型与接口

**1470 三角形 / 1 mesh / 1 surface / 11 bones**。米制、Y 上、+Z 正面，根在脚底中心；全部平滑法线，每个顶点严格绑定单骨、权重 1。壳的三个圆鼓包按壳面射线定位。UV2.x=1 为壳/躯体/腿，脸、眼、高光、腮红、独角和橙边为 0；没有位图贴图或黑描边。

骨骼为 root、body、head、ant_l/r、leg_l_1..3、leg_r_1..3。基础材质实测 roughness=0.78、Godot specular=0.5；共享导入脚本启用顶点色并关闭真实投影，比较工位使用程序的 BlobShadow。

客户端字段按周瑜接口：`radius=0.58`、`hit_point=[0,0.28,0.04]`、顶层 `durations` 和 `hit_at=0.18`。其余 height、badge_point、anims、palette 等只是补充说明；旧 hurt_point 已删除。

| 动作 | 秒 | 循环 |
|---|---:|---|
| idle | 1.60 | 是 |
| move | 0.80 | 是 |
| windup | 0.60 | 否 |
| attack | 0.40 | 否 |
| recover | 0.50 | 否 |
| hit | 0.25 | 否 |
| die | 0.80 | 否 |
| stunned | 1.00 | 是 |

全部原地、root 不动。stunned 由程序持续循环 2 秒；冲撞、击退和闪白由程序控制，循环按动作名设置。recover 从晕眩姿势收回；die 保留翻倒，并修正翻倒前段的脚穿地。视频为原地动作演示，不是 AI 打斗或玩家实操。

## 导入修复

优先修复已单独推到运行时 cfb05265。45 行 .import 保留 `uid://crslv7oobgd44`，照蝙蝠模板设置：

- animation/remove_immutable_tracks=false
- nodes/use_name_suffixes=true
- meshes/ensure_tangents=false
- meshes/create_shadow_meshes=false
- import_script/path="res://assets/monsters/material_import.gd"
- _subresources={}，gltf/texture_map_mode=1

configure.gd 按同一模板生成，保留本件 UID 和路径，不写高级导入里的默认项。check_transition.gd 在两动作之间不 reset、不 seek，用 play/advance 对照独立起播目标动作；正式版 56 组切换通过，move → hit 六腿无残姿。灰模追补证据另保留在 import-transition-check.json。

## 验证与媒体

最新记录：`validation-v1.json`、`media-manifest-v1.json`。

- 40 项独立 GLB 检查通过：预算、刚性权重、平滑法线、UV2、尺寸、按实测取半径、客户端字段、全部时长、root 静止和循环首尾。
- 88 项 Godot Mobile/Vulkan 实渲检查通过；动作抽样还核了蒙皮后落地位置（12 mm 接触容差）、身体下沉和脚抬高，另有 56 组实际连续动作切换检查。
- stunned 四个相位实测壳摇约 ±14.9°，脚端最低位置约 0.110–0.235 m；不是只比较动作名存在。
- 相同材质参数换色测试中，身体像素改变，受保护眼睛像素误差为 0。
- 两种矿使用现有 MineArt 第 1 层红岩、第 3 层紫灰岩壁、普通史莱姆 r=.4 和实际 Avatar。43°、6.72 m 不变，三者在画面里横排比大小，无 NPC 标签或游戏 HUD。
- 360 宽图片中取壳与邻近地面的 3×3 像素中位数：红岩矿壳 L*=44.86、地面 72.80，差 27.95；紫灰矿壳 L*=44.86、地面 68.77，差 23.92。是指定采样点的明度证据，不是全图配准分数。
- 交三视图、8 动作与 stunned 四相位拼图、两种矿各 360/720 宽截图，以及 6.125 秒、24 FPS、720×1600 动作视频，共 7 份。前缀 `SGODOT-355_mob_rock_beetle_v1_`，署名上传 Plane 355，并下载回读校验。
- 视频首、中、尾已解码抽帧查看；这是桌面原地动画审阅，不是手机性能或战斗接入验收。

G0 图片、media-manifest-graybox.json 和 validation-graybox.json 保留为历史版本，不覆盖。当前正式版仍待上官婉儿和不知火舞复核。

## 复现

Blender 5.2.2、Godot 4.7.2、NumPy/Pillow、ffmpeg。运行时 checkout 需包含共享怪物导入脚本。每次 Godot 先加载私有 ADB 5099 环境，渲染前查看 nvidia-smi，仅关闭自己的 PID。隔离工位使用独立用户目录和 localhost:9，不读取生产账号或存档。

```bash
source ~/.codex-zhaoyun/env.sh
BEETLE_RUNTIME=/absolute/path/to/private/monsters-checkout
BEETLE_SOURCE="$PWD/tools/art/source/monsters/mob_rock_beetle"
blender --background --factory-startup --threads 2 --python "$BEETLE_SOURCE/build.py" -- --runtime "$BEETLE_RUNTIME"
python3 "$BEETLE_SOURCE/prepare.py" --runtime "$BEETLE_RUNTIME"
godot --headless --path output/rock-beetle-355/project --editor --import
godot --headless --path output/rock-beetle-355/project --script res://configure.gd
godot --headless --path output/rock-beetle-355/project --editor --import
godot --headless --path output/rock-beetle-355/project --script "$BEETLE_SOURCE/check_transition.gd" -- "$PWD/output/rock-beetle-355/transition-formal-v1.json"
nvidia-smi
godot --path output/rock-beetle-355/project --display-driver wayland --rendering-method mobile --rendering-driver vulkan --max-fps 30 -- --video
cp output/rock-beetle-355/project/assets/monsters/mob_rock_beetle/*.import "$BEETLE_RUNTIME/assets/monsters/mob_rock_beetle/"
output/art-setup/venv/bin/python "$BEETLE_SOURCE/verify.py" --runtime "$BEETLE_RUNTIME"
output/art-setup/venv/bin/python "$BEETLE_SOURCE/package.py" --runtime "$BEETLE_RUNTIME"
```

生成器保留具名施工部件和单 mesh 导出副本。手工编辑需同步生成脚本，避免重建覆盖；共享分支推前 fetch，保留其他作者目录，只做快进推送。
