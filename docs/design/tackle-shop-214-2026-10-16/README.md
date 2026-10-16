# SGODOT-214 · Tackle Shop · v1

本目录保留 v1 与 spawn 补图的历史证据。当前套件、装配和审阅以
[v1.1 交付目录](../tackle-shop-214-v1.1-2026-10-16/README.md) 为准。

【赵云】2026-10-16。新建独立渔具铺套件，依据 Stark `2681:135486`、
不知火舞标注、制作清单 v1.1 和已通过的鱼竿架设定。
交上官婉儿技术检查、不知火舞画面验收；合并由用户批准。

## 资产与尺寸

| 项目 | 交付值 |
| --- | --- |
| 运行时套件 | `assets/rooms/tackle_shop/` |
| 可编辑源文件 | `tools/art/source/tackle_shop/tackle_shop.blend` |
| 可复现脚本 | `tools/art/build_tackle_shop.py` |
| 独立运行时场景 | `scenes/tackle_shop/tackle_shop_art.tscn` |
| 主地面 | 6.80 × 6.40 m；顶面 Y=0.08 m |
| 开放前沿 | 1.40 m 宽出口；额外 0.60 m 支撑落脚面供出口往返检查 |
| 墙体 | 两面切开，最高约 3.30 m；圆舷窗是真开孔 |
| 弧柜 | 台面约 2.04 × 0.83 m，离地 1.12 m；三件台上物留间隙 |
| 中央圆毯 | 主体直径 1.90 m；短流苏外径约 2.03 m |
| 鱼竿架 | 木架宽 0.90、深 0.35 m；四竿总高约 1.63 m |
| Kai 圆凳 | 座面离地 0.62 m，处于 Basic Room 基线 ±15% 内 |
| 静态场景 | 61,352 三角面 / 37 surface；36 个 GLB，37 个摆放实例 |
| 鱼竿架独立预算 | 1,196 三角面 / ≤1,200；包含架旁浮漂桶 |
| 贴图 | 一张 2048² `room_albedo_ao.png`；mipmap / VRAM 压缩 |
| 材质 | 哑光图集 + 鱼缸透明材质，specular 均为 0.28 |

预算以 [asset_stats.json](../../../assets/rooms/tackle_shop/asset_stats.json)
和本目录验证 JSON 的实际导入结果为准。鱼竿架的独立预算包括架子、4 根鱼竿、
架旁木桶和桶内 3 只浮漂；另一只桶属于整屋预算。没有额外第三只浮漂桶；Kai
旁边是船桨桶。竿身上的导线环用凸点表示，卷线轮保持哑光。

房间含浅粉白墙、灰蓝护墙板、橘棕框架、弧柜船舵、小灯、鱼缸中的两条鱼、
灰色方形器具、三层开放架、蓝底地图、画鱼渔情板、两顶挂帽、帆船、黄靴、
罐子、木盒、鱼牌、彩旗、吊灯、两个居民渔网角落及盆栽。

## 取景与审阅图

上官婉儿已确认两张分别验收：保留房间尺寸，交 360×800、43°俯角、
45°方位、6.72 m 正交宽的游戏取景；另交不裁切的 43°完整全景。
游戏取景会裁掉房间边角，没有偷偷缩小房间或改变 6.72 m 参数。

**2026-10-16 补图口径**：进门第一眼以
[13_spawn_follow_360](SGODOT-214_TACKLE_v1_13_spawn_follow_360.png) 为准。
玩家脚下位于 layout 的 `spawn = (0, 0.08, 0.83)`，镜头直接跟随此点；
原始视口 360×800、俯角 43°、套件方位 45°、正交宽 6.72 m。
已看图确认柜台与 Finn 在画面内。Finn 使用 `farm-dev` 固定提交
`f8c3391c8c0606ae664fb8e06ad85068aa199f69` 的既有造型
`hairhat51 / cloth12_npc_finn / shoes4`，只在隔离审阅工程中读入。
玩家为现有默认尺规人偶；名字是审阅标记。本图用于按派活口径审视第一眼，
不代表玩法房间的完整 HUD / 自动取景接入。原 `01_game_360` 是固定房间构图，
保留作历史对照，不再作为进门画面的验收图；`02_whole_43deg` 仍为完整全景。

补图命令（复用已搭好的隔离工程）：

```sh
python3 tools/art/prepare_tackle_spawn_review.py
godot --headless --editor --path output/tackle-214/project --import --quit
godot --path output/tackle-214/project --rendering-method mobile \
  --rendering-driver vulkan res://spawn_review.tscn
python3 tools/art/package_tackle_review.py --spawn-only
```

镜头、站位、Finn 部件来源及实际投影记录见 `spawn-follow-validation.json`。

本目录的 `SGODOT-214_TACKLE_v1_*` 图均来自 Godot 4.7.2 实际渲染。
正交图同样来自交付模型。图片署名为外部审阅标注，不烘入房间。
站位图用同一现有 1.745 m 默认角色验证空间，不代表 Finn / Kai / Rafa 的角色美术。
设计图与运行时的并排图用于看构图与配色，不是像素配准相似度评分。

## 建议挂点

坐标为 Godot 米，Y-up。NPC 朝向按现有挂点约定记录；实际 NPC 与点击、寻路、
名称条由程序接入。`assets/p0/outposts/tackle.anchors.json` 未修改。

| 挂点 | 位置 X / Y / Z | 用途 |
| --- | --- | --- |
| `npc_keeper` | -0.36 / 0.08 / -2.35 | Finn 柜台后 |
| `badge_keeper` | -0.36 / 1.98 / -2.35 | 掌柜标记建议位 |
| `use_counter` | -0.36 / 1.20 / -0.85 | 柜台点击建议位 |
| `stand_counter` | -0.36 / 0.08 / -0.02 | 玩家柜台前 |
| `stand_keeper` | -0.36 / 0.08 / -0.02 | 与掌柜交谈 |
| `npc_kai` | -1.85 / 0.08 / 1.55 | 左前渔网、圆凳角 |
| `stand_kai` | -1.10 / 0.08 / 1.10 | Kai 对话位置 |
| `npc_rafa` | 1.85 / 0.08 / -1.55 | 右侧墙端浮漂桶旁，与 Kai 对应 |
| `stand_rafa` | 1.30 / 0.08 / -0.85 | Rafa 对话位置 |
| `use_fish_board` | 0.69 / 1.99 / -2.86 | 画鱼的小黑板 |
| `stand_fish_board` | 0.96 / 0.08 / -2.07 | 黑板前侧通道 |
| `spawn` | 0 / 0.08 / 0.83 | 中央锚纹毯 |
| `exit` | 0 / 0.08 / 3.40 | 开放前沿出口 |
| `badge_exit` | 0 / 0.30 / 3.20 | 出口标记 |
| `sign_name` | -3.02 / 2.07 / 1.29 | 鱼牌下方 0.72 × 0.12 m 空白区，运行时可替换 |

## 验证与复现

`glb-validation.json` 独立读取二进制 GLB，核预算、局部坐标、图集 UV、两桶数量、
竿架不挡舷窗、NPC/玩家位置净空，并以实际三角网格检查跨模块穿插。
地板承托、墙角木作、舷窗装配和鱼缸内部接合会明确分类；未将它们伪报为零接触。
负例把鱼板放进柜台，验证交叠检测能失败。

`godot-validation.json` 记录实际导入的面数、surface、2048 贴图、材质、挂点、
渲染器、显卡及每张截图的镜头参数。`scene-bench-result.json` 与尺寸报告记录
完整角色路线、柜台/货架/墙边阻挡、1.36 m 掌柜通道、出口往返、滑墙、输入释放、
失焦停止和动画切换。碰撞图显示实际物理形状；视频为 15 秒原速桌面路线。

```sh
source ~/.codex-zhaoyun/env.sh
blender --background --factory-startup --threads 6 --python-exit-code 1 \
  --python "$PWD/tools/art/build_tackle_shop.py"
python3 tools/art/prepare_tackle_shop_review.py
blender --background --factory-startup --python-exit-code 1 \
  --python "$PWD/tools/art/verify_tackle_shop.py"
godot --headless --editor --path output/tackle-214/project --import --quit
godot --path output/tackle-214/project --rendering-method mobile \
  --rendering-driver vulkan res://review.tscn
python3 tools/art/run_tackle_bench.py --ffmpeg /path/to/ffmpeg --ffprobe /path/to/ffprobe
```

最后两步需要真实桌面显示；录屏需要 FFmpeg/FFprobe。gs66 的本次隔离测试
使用 RTX 2060 / Vulkan Mobile，私有 ADB 端口 5099。没有安卓、真机性能、
玩法接入或发布结论。项目和工具下载均在忽略的 `output/tackle-214/`。
gs66 的 Wayland 桌面抓 X11 根窗口会得到黑图；任务适配器核对测试进程 PID 后
直接捕获它的 X11 窗口。公共 scene_bench 未修改，原速与黑帧检查继续有效。

## 制作中的修正

实际渲染的关阴影对照定位并消除了大面斜纹；灯光偏移与能量保留在 layout 中。
地毯密集编织转为烘焙细节；细网绳、竿身等改用同一图集内带保护边的源颜色块；
地图单面朝向修正。独立碰撞检查驱动了竿架离墙、
货架柱脚退让、箱盖高度、渔网离地及绿萝下垂方向的修正。原图精细编绳、
柔软渔网褶皱和远景云层已简化；按清单物理尺寸落地后，柜台和圆毯相对于地面的占比小于插图；最终画面仍待不知火舞验收。

附件上传、身份署名和下载哈希回读记录保存在 `delivery-verification.json`。
