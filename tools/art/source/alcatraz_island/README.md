# SGODOT-424 · Alcatraz Island · B 白模

作者：马可波罗。此轮只交体块、布局、道路、碰撞和镜头，等待上官婉儿技术审与不知火舞画面审；细节和正式配色留到白模通过之后。

原始参考保存在 `reference/`：用户提供的三联说明 `landmark_concept_v1.jpg` 和方案 B 大图 `c_alc.png`。哈希见 `reference/provenance.json`。原图是设定示意，不是实测建筑或精确地理位置。

## 源文件与坐标

- `alcatraz_blockout.blend`：可编辑命名构件、模块 collection 和实际布局的 collection instances。
- `build.py`：确定性建模／布局／GLB 导出。复用仓库 `landmark_kit.py` 的 Y-up、顶点色与法线导出规则；全量运行会重建源文件。
- `assets/landmarks/alcatraz_island/`：独立模块、`layout.json` 与面数／字节清单 `manifest.json`。
- `scenes/landmark/alcatraz_island.tscn`：独立可走场景，使用已有 Avatar 和 ScenePan。只新增此地标文件，不修改共享玩法或地图入口注册。

单位为米；Godot Y 向上、北方 -Z；Blender 映射 `(x, -z, y)`。独立建筑／道具以落地中心为局部原点；岛体层、铺装、三段台阶和路沿以岛体原点为共同地形基准。布局中的 yaw 为弧度，正 Y 轴旋转。

## 白模约定

主楼为游客中心／博物馆，门窗无铁栏；灯塔、水塔和废墟保留。岛体由五层地形组成，可走铺装比不可走花园明亮。三段台阶各升 1.6 m、10 级、每级 0.16 m；可走导航使用连续坡面，实际台阶与平台有三角网碰撞。导航从铺装外缘内收 0.25 m，排除长椅及收缩后孤立的小角落。

码头 `spawn` / `exit` 和 `cam0` 写入布局并生成 Marker3D。出口是门图标钮与 `Map` 名字条，只发退出请求；在现有 AppRouter 中打开时调用返回。渡轮、静态海鸟和远景没有碰撞交互，不发放奖励，不读写网络玩法状态。

镜头使用格里菲斯的 45° 正交、7 m 宽、0.8–1.4 缩放与手势。按本任务明确要求增加此场景内的走路跟随；拖动进入自由查看，下一次走路或 Follow 恢复跟随，保留当前缩放。Overview 查看全岛。镜头与海面范围有界，512 m 海面覆盖可走位置和自由查看边界；诊断背景为洋红色，以便捕捉任何露底。

橙红金门大桥是为码头开场构图压缩比例的离岸远景模型，非真实地理比例。除辨识桥的必要橙红和灰蓝海面外，当前均为灰阶分区；不代表正式材质／颜色已批准。

## 重建与复核

在仓库根目录运行；所有 Blender／Godot 工作均使用同一共享锁：

```sh
flock ~/gs66-render.lock blender --background --factory-startup --threads 3 --python-exit-code 1 --python "$PWD/tools/art/source/alcatraz_island/build.py"
bash tools/art/source/alcatraz_island/review.sh
```

实渲需要当前桌面的有效 `DISPLAY` 和 `XAUTHORITY`，可从 `systemctl --user show-environment` 查询；不要复制过期鉴权路径。所有进程完成后自动退出，脚本设有超时。源目录的 `.gdignore` 防止 Blender 源和参考图进入游戏自动导入。

`prepare.py` 复制最小隔离项目到 `output/alcatraz-424/project`，只启用 Avatar autoload，独立用户目录，无 Net、生产地址或地图自动登录。Godot 自动生成新增 `.import` 与脚本 UID，`--sync-imports` 仅回收本资产／场景导入元数据。

`review.gd` 运行真实场景，沿 NavigationServer 路径逐段走到半山和主楼前，再拍三张 360×800 图、1000×1200 俯视图及全岛补图。它检查跟随、实际碰撞高度、装饰物不交互、缩放／拖拽和返回请求。程序模拟步进与事件仅是桌面回归证据，不是 Android 真机操作或性能结论。审阅图和最终验证记录从 `output/alcatraz-424/review/` 归档至对应设计审阅目录。
