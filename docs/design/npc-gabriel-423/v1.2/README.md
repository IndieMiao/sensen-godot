# Gabriel v1.2 · 前领片 / 前襟贴图

刘备，2026-11-07。基于已验收 v1.1 `ccd6e7f0`，领口阶段更新两张游戏资源图：

- `assets/avatar/source/cloth36_npc_gabriel/T_gabriel_cloth_D.png`
- `assets/p0/art/residents/gabriel_card.jpg`（按新贴图开窗口重烘）

衣服原 UV 上的领带、衬衫和背心分色改为统一近黑 #2B2A2E，三粒扣的颜色也并入前襟，
不再另画扣面。喉咙正前方补约 2.5 cm 宽的白色罗马领片 #F4F1E8，连接已有白色颈圈。
原袖口、下摆、长袖长裤、白发、眼镜、鞋不变。

**纹理范围的实际限制：原模型的领结、领带和扣子是凸起几何。**本次消掉它们的贴图分色，
不能消除几何投下的边缘阴影；放大和侧光下仍看得到原有浮起形状。
按“只动贴图、不动网格”保留，见下方同机位放大对照，未把它称为删除了几何。

- [360×800 同机位前后](before-after.png)
- [领口 3 倍像素裁切对照](collar-comparison.png)：来自同镜头、同光照的原图，最近邻放大。
- [正面](gabriel-front.png)、[3/4](gabriel-three-quarter.png)、[背面](gabriel-back.png)
- [原光照近景](collar-front.png)、[3/4 近景](collar-three-quarter.png)：只收紧相机取景。
- [新头像 / 邮票 / 脸框](portrait-review.png)、[300×660 原卡](gabriel_card.jpg)
- [验证记录](validation.json)

slots 不变：

```json
{"hairHat":"hairhat0_npc_gabriel","cloth":"cloth36_npc_gabriel","shoes":"shoes3","glass":"glass0"}
```

网格、UV、FBX、.res、材质参数、shader、.import、注册表及 crop 表与 v1.1 字节相同。
PNG 仍为 1024²、运行时无损 512²、mipmaps，alpha 原样；不增加纹理、采样或 pass。
头像按既有居民 baker 开窗口生成到 `assets/p0/art/residents/`，临时 baker 仍仅有 v1.1
记录的 P0Logic 延迟加载适配。裁切未变：stamp `[68,47,170,213]`，face `[70,51,165,165]`；
原 11 条与整个 crop 文件保持原字节。

验证包含空缓存冷导入（15 个交付文件字节稳定、0 错误），以及原独立 Android SwiftShader
夹具的完整显示、3 次真实点按、walk 与 APK/资源回读。模拟器的原皮肤、眼镜、鞋偏亮仍是
v1.1 已记录的限制；没有新的实体手机性能结论。

整合以本次两张图覆盖 v1.1 对应路径即可；若尚未接入 v1.1，仍按上级说明向运行时现有
manifest / npc_only 追加两条 Gabriel，保留其他 NPC。


## 掌柜头像路径补齐

程序按掌柜路径读图，因此另加以下两张及各自 `.import`：

- `assets/p0/art/keepers/gabriel_card.jpg`：300×660，与 residents 下 v1.2 卡图字节一致。
- `assets/p0/art/keepers/gabriel_head.jpg`：按 `[70,51,165,165]` 脸部方框裁切，LANCZOS 缩至 132×132，JPEG quality 95、无色度抽样。

[卡图与 132×132 / 44×44 头像预览](keepers-review.png)，[验证与 UID](keepers-validation.json)。
两份导入参数完整照 farm-dev `c6d490f7a7` 的 `lou_card.jpg.import` / `lou_head.jpg.import`：
`compress/mode=0`、`mipmaps/generate=false`、`process/size_limit=0`。UID 由 Godot 在新
keepers 路径生成，未复制 Lou 或 residents 的 UID。空缓存冷导入四文件字节稳定、0 错误；
Godot 实际加载两张纹理的尺寸、无 mipmap 与合法 UID 均通过。原 residents 图和 crop 条目保留。
本补件没有再次改衣服贴图、网格或头像内容。

## 贴图复现

在仓库根目录先用既有 `tools/art/inspect_gabriel_423.py` 读取 cloth36 UV，
再运行本目录的 `paint_collar.py`。它以 v1.1 贴图为底，不更改 FBX 或材质；使用原几何坐标
定位领片，通过独立 UV 岛抹掉前襟分色。原始网格连通分量索引随本版 donor 固定。
