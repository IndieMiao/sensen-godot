# SGODOT-440 制作与复拍

`homestead_lv15.blend` 保留两个独立集合、命名主楼部件和 porch / kitchen_wing 组件。`build_homestead_lv15.py` 生成主楼，四个挂件固定取自439 / #858头262533a7，来源与原GLB在 `reference/439/`。每栋只导出一个合并 mesh/surface，GLB没有文字、灯、相机或贴图。详见 [接口合同](contract.md) 与 [审阅说明](../../../../docs/design/homestead-440/README.md)。

固定原设定、原屋资产与程序版本见 `reference/provenance.json`。结构颜色从未改动的 `house_cottage.glb` 的实际 COLOR_0 取最近样本，花叶沿用农场套件色板；目标色与实际线性样本分别记录在 `manifest.json`。各GLB的 hash、预算、组件包围盒及烟口也在该文件。

从仓库根执行（Blender参数必须为脚本绝对路径）：

```sh
blender --background --factory-startup --python /absolute/repo/tools/art/build_homestead_lv15.py
python3 tools/art/source/homestead_440/verify.py
python3 tools/art/source/homestead_440/prepare.py
SENSEN_OFFLINE=1 P0_SERVER_URL=http://127.0.0.1:9/v1 flock /home/deck/gs66-render.lock godot --headless --path output/homestead-440/project --editor --import
SENSEN_OFFLINE=1 P0_SERVER_URL=http://127.0.0.1:9/v1 flock /home/deck/gs66-render.lock godot --path output/homestead-440/project --fixed-fps 30 --disable-vsync
python3 tools/art/source/homestead_440/cold_import.py
```

桌面实渲需使用已验证的 DISPLAY/XAUTHORITY。`prepare.py` 只在 output 下展开固定farm-dev实际场景；关闭网络、替换fixture传输，使用私有用户目录。不会读写真实玩家状态。`review.gd` 用360×800 SubViewport绕过Deck桌面高度限制，所有默认图用同一开场相机；近景后恢复包括near/far在内的相机状态；默认保留完整人物，近景临时隐藏远处人物避免下沿截头。为并排可比只冻结了本地烟雾材质副本的TIME。

原来额外显示的门廊/扩建占位在fixture明确关闭；Lv15整栋已含这些几何。只在隔离预览演示Bench向-X移1.3m、左灌木向-X移1.5m，以及隐藏两枚被439地坪替换的踏石；Lv8/Lv15两边处理相同。验收数值分开记录模型最高点和整个原烟雾周期的保守投影上界。

Android小验证：

```sh
python3 tools/art/source/homestead_440/prepare_android.py
SENSEN_OFFLINE=1 flock /home/deck/gs66-render.lock godot --headless --path output/homestead-440/android-project --export-debug 'Android Homestead QA' ../homestead-qa.apk
flock /home/deck/gs66-render.lock python3 tools/art/source/homestead_440/android_smoke.py
```

该脚本默认已有 `emulator-5592` / 私有ADB 5071，可用环境变量ADB/JOURNEY_SERIAL/ADB_SERVER_SOCKET覆盖；使用包 `com.sensen.homestead440qa`，恢复原wm尺寸密度，结束后停掉该QA应用。验证3次真实点击切换、完整人物与GLB渲染、当前PID日志、安装包完整读回。它是独立资产场景，不是完整农场Android玩法或真机性能结论。

最后用带Pillow的Python运行 `package.py`，把实拍与记录放入 `docs/design/homestead-440/`。图片标题区可加说明，原始360×800像素不缩放、不修饰；原始图也一起保留。

## 四立面与同款组件 v1.2

主楼的侧后绿窗、封闭后勤门、木框和石砌保留；439左右翼自身已有完整侧后窗。a二层两只花箱抬高.17m避开原件门廊顶，不改439几何。

四个GLB作为锁定源依赖：`source_component()`读它们的网格建立Blender组件预览；`export_mesh.py`先导主楼，再由 `merge_components.py` 直接拼接源GLB的float32位置、法线和颜色，形成一个mesh/surface。这样绕开Blender自定义法线内部压缩，不改变439的任何三角面/颜色；不加纹理或pass。`verify.py`独立解码GLB逐值比较每个组件的三角面多重集，检查四件原SHA、预算、净空和同款Lv8包络。

不要在440的.blend里改动锁定组件后期待覆盖源件：这四件的可编辑命名源仍由赵云维护，固定版本链接记录在 `reference/439/provenance.json`。要升级它们，应先取得439的新版本，再同步源GLB/.import/manifest和来源hash并重新核同款。主楼部件仍由本生成器完整重建。

`review.gd`用同一场地循环Lv8（现房+439原件）/Lv15整栋，拍默认14.5°、水平45°默认尺度/近景和225°背面左侧；俯角始终43°。45°同尺度图保持房屋屏幕位置，不代表未来全农场正式构图。只对正面机位做三牌遮挡断言，背面视角自然会被房体挡住。`package.py`输出四列Lv8/Lv15对照，不缩放原始360×800图。
