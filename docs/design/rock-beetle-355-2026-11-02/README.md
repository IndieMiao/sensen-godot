# SGODOT-355 岩甲虫正式版 v1.1

赵云，2026-11-02。v1 技术检查通过（355 fe3a6d67）；v1.1 按不知火舞 236f9afe 和上官婉儿派活调整，交复核。源与审阅更新草稿 PR #682；运行时仍只推 art/monsters-355，不开 PR、不合并，355 状态由奕星管理。

运行时 v1.1 提交 **5c043e4c**（基于共享分支 b4a8d3ea），仅改岩甲虫 GLB、JSON 两个文件。

## v1.1 本次返修

- 整体以静态骨架变换等比放大 **1.25 倍**；脚底原点、朝向保持。壳含橙边实测 **长 1.225 × 宽 1.025 m**，整体含头为 **宽 1.025 × 深 1.3802 × 高 0.6171 m**。按实际 v1 的 0.98 m 壳长乘 1.25，未单独压缩前后轴去凑 1.1 m。
- 六腿中心线长变为 v1 的 **66.76%–67.12%**，粗细保持，横向收进壳下。保留支点高度和脚底平面，使旧 stunned 动作仍能翘腿；只调整腿网格，不修改动作曲线。
- 只把头的底色 A18B7D 恢复为浅暖棕 **C9A087**；壳 685B59、橙边、眼睛、腮红和触角不改。非腿几何在除去整体缩放后与 v1 逐顶点一致。
- **radius=0.58×1.25=0.725**，**hit_point=[0,0.28,0.04]×1.25=[0,0.35,0.05]**；height=0.6171，badge_point=[0,0.8125,0]。按要求保留缩放后的半径，不因腿收短再缩碰撞圈。
- **1470 三角形 / 1 mesh / 1 surface / 11 bones** 不变。8 个动作的名称、时长、逐轨道采样值（相对静止支点）、源文件 pose/animations 函数均与 v1 一致；整体缩放会同步放大动作的空间幅度。
- `.import` 与 v1 逐字节相同，保留 **uid://crslv7oobgd44**、remove_immutable_tracks=false 和共享导入脚本；本轮仅在隔离工程重新导入，不覆盖运行时导入文件。

最新证据为 `validation-v1.1.json`、`media-manifest-v1.1.json`。独立 GLB 55 项、Godot 实渲 89 项、连续动作切换 56 组通过；检查器按实际蒙皮变换计算缩放后的包围盒，脚端仅从腿骨绑定顶点采样。stunned 全周期 61 帧核查：脚端最低离地 **14.7 mm**，全模型最低 **-3.8 mm**（原接触容差 12 mm 内）。腿收短后低侧脚端抬升小于 v1，故离地检查改按 10 mm 留量，旧的 100 mm 不是本轮规格；动作曲线没有为此调整。玩家及普通史莱姆大小、镜头和矿场景保持原样。

交付三张署名图，前缀 `SGODOT-355_mob_rock_beetle_v1.1_`：红岩矿、紫灰岩壁矿各一张 43° / 6.72 m 图（720×1600，360×800 的 2 倍），以及一张 stunned 近景。沿用现有 MineArt、MineCombat 史莱姆和 Avatar；这是桌面 Mobile/Vulkan 美术工位，不是 AI 打斗或真机性能验收。v1 与 G0 图、视频、验证文件保留。

## v1 制作记录（历史）

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

## v1 模型与接口（历史）

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

## v1 验证与媒体（历史）

v1 记录：`validation-v1.json`、`media-manifest-v1.json`。

- 40 项独立 GLB 检查通过：预算、刚性权重、平滑法线、UV2、尺寸、按实测取半径、客户端字段、全部时长、root 静止和循环首尾。
- 88 项 Godot Mobile/Vulkan 实渲检查通过；动作抽样还核了蒙皮后落地位置（12 mm 接触容差）、身体下沉和脚抬高，另有 56 组实际连续动作切换检查。
- stunned 四个相位实测壳摇约 ±14.9°，脚端最低位置约 0.110–0.235 m；不是只比较动作名存在。
- 相同材质参数换色测试中，身体像素改变，受保护眼睛像素误差为 0。
- 两种矿使用现有 MineArt 第 1 层红岩、第 3 层紫灰岩壁、普通史莱姆 r=.4 和实际 Avatar。43°、6.72 m 不变，三者在画面里横排比大小，无 NPC 标签或游戏 HUD。
- 360 宽图片中取壳与邻近地面的 3×3 像素中位数：红岩矿壳 L*=44.86、地面 72.80，差 27.95；紫灰矿壳 L*=44.86、地面 68.77，差 23.92。是指定采样点的明度证据，不是全图配准分数。
- 交三视图、8 动作与 stunned 四相位拼图、两种矿各 360/720 宽截图，以及 6.125 秒、24 FPS、720×1600 动作视频，共 7 份。前缀 `SGODOT-355_mob_rock_beetle_v1_`，署名上传 Plane 355，并下载回读校验。
- 视频首、中、尾已解码抽帧查看；这是桌面原地动画审阅，不是手机性能或战斗接入验收。

G0 图片、media-manifest-graybox.json 和 validation-graybox.json 保留为历史版本，不覆盖。v1 技术复核通过，画面返修已进入上方 v1.1。

## 复现

Blender 5.2.2、Godot 4.7.2、NumPy/Pillow、ffmpeg。运行时 checkout 需包含共享怪物导入脚本。每次 Godot 先加载私有 ADB 5099 环境，渲染前查看 nvidia-smi，仅关闭自己的 PID。隔离工位使用独立用户目录和 localhost:9，不读取生产账号或存档。

```bash
source ~/.codex-zhaoyun/env.sh
BEETLE_RUNTIME=/absolute/path/to/private/monsters-checkout
BEETLE_SOURCE="$PWD/tools/art/source/monsters/mob_rock_beetle"
blender --background --factory-startup --threads 2 --python "$BEETLE_SOURCE/build.py" -- --runtime "$BEETLE_RUNTIME"
python3 "$BEETLE_SOURCE/prepare.py" --runtime "$BEETLE_RUNTIME"
godot --headless --path output/rock-beetle-355/project --editor --import
godot --headless --path output/rock-beetle-355/project --script "$BEETLE_SOURCE/check_transition.gd" -- "$PWD/output/rock-beetle-355/transition-formal-v1.1.json"
nvidia-smi
godot --path output/rock-beetle-355/project --display-driver wayland --rendering-method mobile --rendering-driver vulkan --max-fps 30
output/art-setup/venv/bin/python "$BEETLE_SOURCE/verify.py" --runtime "$BEETLE_RUNTIME"
output/art-setup/venv/bin/python "$BEETLE_SOURCE/package.py" --runtime "$BEETLE_RUNTIME"
```

生成器保留具名施工部件和单 mesh 导出副本。手工编辑需同步生成脚本，避免重建覆盖；共享分支推前 fetch，保留其他作者目录，只做快进推送。
