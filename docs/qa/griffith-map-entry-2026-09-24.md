# Journey 0.16.33：格里菲斯卡片入口与农场同款手势

本地正式包已构建，使用原 `com.sensen.journeypreview` 与原签名，版本 `0.16.33 / 2026092401`。地图地标卡新增“进入场景”，可行走、自由拖拽、惯性、双指缩放、头像回位与返回地图；不包含种植。

- APK：`output/landmark-integration-2026-09-24/release/sensen-journey-landmark-0.16.33.apk`
- SHA256：`d9872f4363f8243ad6a4e31dcf3a6f3b8ea365a74c92ed70f4537138716eeaac`
- 字节数：178,303,532；相较 0.16.32 增加 7,333,575 字节。
- 原证书 SHA256：`38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`。

## 已验证

42 项独立原生检查通过：8 项新场景／入口／地图恢复／路径／手势测试，加 34 项已有农场手势、场景栈和城市地图交互回归。新场景检查发现导航地图的第一次同步可能早于区域网格同步，现检查区域已生效后才允许查询行走。各测试的最后结果及来源记录在 `output/landmark-integration-2026-09-24/native-verification.json`。

独立 `com.sensen.journeylandmarkqa` 在模拟器的 720×1560、720×1280、1080×2340 下共完成 29 次实际操作，保存 9 张截图。检查其他地标没有入口、格里菲斯详情卡进入、总览、短程与主台阶／西平台／咖啡露台行走、拖拽后惯性位移及衰减、系统级双指触摸缩放、角色离屏头像回位、后台恢复、卡片／地图姿态保留、按钮返回、Android 系统返回及重复进入。按钮与地面触摸坐标来自实时场景控制树／导航投影，不依赖截图猜测。

测试包使用隔离的本地农场 fixture 与拦截的游戏传输，地图瓦片仍由正常地图桥加载。九个关键状态的农场身份、版本、物品、金币、耕地和迁移状态一致；测试包未启动生产登录。关闭场景后独立导航地图已释放，重复进入时数量保持稳定。地图恢复透明窗口，地标使用不透明合成，未出现底层地图透出。卡片、场景近景和全景截图已人工查看；运行日志无脚本错误或崩溃。

正式包解包检查确认 24 个导入模型、布局 JSON、导航、场景和 shader 存在，tools/tests/观察器/测试 fixture 与启动参数均排除。68 个关键生产代码／模型／shader 条目与通过 Android 操作的测试包逐字节一致。模拟器原 Journey 覆盖安装后回读 APK 哈希和证书一致，5 份现有身份／外观／偏好文件保持一致；正常冷登录成功，线上原农场身份、地形、资产与迁移状态和安装前基线一致。

全部 Android 测试通过 `tools/android/run_test.sh` 管理；结束后停止测试与正式进程，模拟器显示尺寸恢复。Godot 导入／导出暂时关闭退出时停止 ADB 的设置，并在结束时恢复。

## 范围

用户随后重新连接 V2509A 并明确要求安装，集成后的 0.16.33 已覆盖安装到原 Journey。下面记录本次真机安装检查；完整的新场景交互仍以模拟器证据为准，等待用户真机体验。16KB 模拟器仍使用原生库页面大小兼容模式，本次没有修改原生库。没有部署服务器、发布新公开下载或发送消息。现有线上域／内容／业务镜像保持原状。

## 真机安装补充（2026-09-24）

V2509A 原 Journey 从 0.16.32 覆盖升级至上述同一份 0.16.33。安装前重新记录该手机当前的五份身份／外观／偏好文件及对应线上农场，不使用模拟器或历史身份恢复。安装后完整回读 base.apk，包名、版本、SHA256 和原证书一致；五份文件逐字节一致。

通过 `tools/android/run_test.sh` 完成正常冷启动，新的运行日志确认 `logged_in=true has_farm=true`，选择城市页面截图已查看。手机 shell logcat 返回空内容，因此本轮采用安装前日志留档、删除旧运行日志后冷启动新建日志的方式验证当前启动；没有将历史日志作为本次登录证据。新日志无脚本错误，当前进程持续运行，随后正常结束测试。

通过同一安装身份只读核对线上农场，农场身份、版本、地形、资产、耕地与迁移状态均和安装前基线一致，未发送玩法或搬迁命令。1080×2344 分辨率与密度 480 保持原样。此次真机范围为安装、签名／哈希回读、冷登录、城市页面和数据保留，未在正式包上重跑地标进入／惯性等全流程。

真机证据位于 `output/landmark-integration-2026-09-24/device/`：`installation.json`、`fresh-log-prepared.json`、`final-smoke.json`、`final-game.log`、`final-city.png` 与 `cleanup.json`；当前手机的私人基线保留在其 `private/` 子目录，不分发。

产品规则和具体尺寸见 [接入说明](../product/griffith-map-entry-2026-09-24.md)。证据根目录为 `output/landmark-integration-2026-09-24/`，包括 `android/verification.json`、`android/drag-inertia.json`、`android/pinch-motion.json`、`release/apk.json`、`release/qa-parity.json`、`release/model-sizes.json`、`emulator/installation.json` 和 `emulator/final-smoke.json`。私人基线位于该目录的 `emulator/private/`，不随 APK 分发。
