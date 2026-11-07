# SGODOT-440 制作与复拍

`homestead_lv15.blend` 保留两个独立集合，以及命名 main / porch / kitchen_wing 可编辑件；`build_homestead_lv15.py` 是几何来源。每栋只导出一个合并 mesh/surface，GLB没有文字、灯、相机或贴图。详见 [接口合同](contract.md) 与 [审阅说明](../../../../docs/design/homestead-440/README.md)。

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

桌面实渲需使用已验证的 DISPLAY/XAUTHORITY。`prepare.py` 只在 output 下展开固定farm-dev实际场景；关闭网络、替换fixture传输，使用私有用户目录。不会读写真实玩家状态。`review.gd` 用360×800 SubViewport绕过Deck桌面高度限制，所有默认图用同一开场相机；近景后恢复包括near/far在内的相机状态。为并排可比只冻结了本地烟雾材质副本的TIME。

原来额外显示的门廊/扩建占位在fixture明确关闭；Lv15整栋已含这些几何。只在隔离预览演示已确认的长凳/灌木移位。验收数值分开记录模型最高点和整个原烟雾周期的保守投影上界。

Android小验证：

```sh
python3 tools/art/source/homestead_440/prepare_android.py
SENSEN_OFFLINE=1 flock /home/deck/gs66-render.lock godot --headless --path output/homestead-440/android-project --export-debug 'Android Homestead QA' ../homestead-qa.apk
flock /home/deck/gs66-render.lock python3 tools/art/source/homestead_440/android_smoke.py
```

该脚本默认已有 `emulator-5592` / 私有ADB 5071，可用环境变量ADB/JOURNEY_SERIAL/ADB_SERVER_SOCKET覆盖；使用包 `com.sensen.homestead440qa`，恢复原wm尺寸密度，结束后停掉该QA应用。验证3次真实点击切换、完整人物与GLB渲染、当前PID日志、安装包完整读回。它是独立资产场景，不是完整农场Android玩法或真机性能结论。

最后用带Pillow的Python运行 `package.py`，把实拍与记录放入 `docs/design/homestead-440/`。图片标题区可加说明，原始360×800像素不缩放、不修饰；原始图也一起保留。

## 45° 补图 / 四立面 v1.1

`secondary_window()` / `rear_facade()` / `wing_back_and_side()` 只补侧后立面，绿窗和木石取色仍来自原屋。前门和外轮廓不变；后门是封闭的静态细节。瓦片仅省掉被实心底板挡住的下面，石块仅省掉埋在实心墙里的背面；不删除完整房体的墙或屋顶。

`review.gd` 额外拍水平45°默认尺度及近景，再拍225°背面与左侧。所有机位俯仰仍43°；45°默认图为检查立面而保留原房屋屏幕位置，不能当成未来全农场最终取景方案。相机参数只改在隔离审阅脚本。反向机位不做前方门牌遮挡断言；两个正面45°机位照常检查三牌。
