# 水面材质与 V2509A 检查 · 2026-09-19

目标为 Journey 0.16.3 / 2026091904，仅客户端呈现更新；保持 `com.sensen.journeypreview`、原签名、原账号及存档。未经明确要求不向 Joey 发送，本轮无消息发送。

## 已完成验证

- Godot 4.7.2：钓鱼、农场美术与地块三组共 **27 项测试通过**。包含新增的提示卡换行后高度收缩回归。证据：`output/water-material-2026-09-19/qa/godot-results.xml`。
- Mobile / Compatibility 均实际渲染检查。原生特写使用专门观察相机，只证明材质呈现，不作为普通游戏镜头或触控通过证据。位于 `output/water-material-2026-09-19/native/`。
- V2509A（`10AFAF162200319`）使用原 Journey 公共服务，经普通触控走到水边，抛竿、咬钩、按住/松开拉竿、失败结算、关闭返回通过；核对人物手部变化、拉竿状态和紧凑提示卡。另从东岸自然走到南岸再次打开钓鱼。
- 模拟器（`emulator-5560`）：相同农场流程通过；普通步行到达街区柳影湖、芦苇河，真实抛竿并关闭通过。
- 新水材质没有改动水域判定或导航。农场原来的水色地面和装饰比钓鱼椭圆偏移半格，现统一视觉边界，消除蓝色错边。
- 真机观察到早于联机完成点击钓鱼会被首次位置同步清掉行走路径；QA 改为等待连接完成后点击。本轮未修改联机或寻路行为，该早期点击问题仍可单独处理。
- 真机还发现旧提示卡会在首次宽度排版前留下异常高度；修复后 ready 卡高度为 138.06 物理像素（46 逻辑像素），不再大块遮挡人物/水面。

所有 Android 场景通过 `tools/android/run_test.sh` 启动并在结束时停止。触控坐标来自只读场景树观察数据；南岸步行坐标由实际水面投影与源码固定相机方向推算，无传送、存档注入或服务端奖励注入。观察代码仅用于验证，正式包不含观察器。

## 性能取样与限制

真机东岸静止取样 10 次为 84–87 FPS，中位 86；模拟器为 57–61，中位 60。另一次真机南岸运行约 30–31 FPS，随后设备 thermal status 为 LIGHT、皮肤温度约 38°C。不同运行之间的取样不能作为严格性能对比，也不宣称所有场景稳定 60 FPS。一次捕获的反射探针不持续重绘六面，水面使用不透明通道避免透明排序问题。

原生 Mobile 专用观察脚本退出时有 7 个 Texture RID 警告；Android 游戏文件日志未见脚本或 shader 编译错误、崩溃。此单次原生退出警告不作为已定位的 Android 运行期内存泄漏。

本轮呈现沿用现有低多边形美术，取参考图的水深、透底和光纹层次，不是照片级还原；静态反射不包含实时玩家倒影。完整多人鱼经济、长期性能与真实玩家自然难度不属于这次材质验收。

## 存档

更新前为 farm v256、47 个作物格、187 金币，原生锈剑/初始鱼竿装备保留。QA 后为 v262；全部游戏状态字段除自然推进的 `clock` 和本轮操作的 `fishing` 外逐项一致。原安装密钥、农场选择、洛杉矶地区选择、UI 状态与本地外观五份文件哈希一致。无清理数据、无重建账号、无服务端迁移。

## 证据

- 真机：`output/water-material-2026-09-19/device/pond-ready.png`、`pond-cast.png`、`pond-reel.png`、`pond-result.png`、`pond-south-ready.png`，及 `result.json` / `south-game.log`。
- 模拟器：`output/water-material-2026-09-19/emulator/result.json`、`street-result.json`、`street_lake-cast.png`、`street_river-cast.png`。
- 私有存档和账号备份位于对应 `private/`，不上传到下载服务。
- 原签名 SHA-256：`38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673`。

## 正式包

正式 0.16.3 / 2026091904 已覆盖安装到 V2509A，移除观察器后重新冷启动进入原农场、走到水边并打开/关闭钓鱼通过。`device/final-smoke.json` 全部通过；已从设备拉回实际安装 APK 比较哈希，原签名和五份本地状态文件复核一致。最后截图为 `device/final-ready.png` / `final-bank.png`。

- 文件：`sensen-journey-water-0.16.3.apk`，152991302 bytes。
- SHA-256：`fa1efdcf9f6d0c982b4e208ef0c3e5fae524e4d51af60a0ea36b17eed816bbbb`。
- 本轮不部署后端。
- [DMIT 美国下载](https://download-us.sensenjoy.cn:8443/farm/releases/water-20260919-fa1efdcf9f6d/sensen-journey-water-0.16.3.apk) / [OSS 备用](https://oss.sensenjoy.cn/farm/releases/water-20260919-fa1efdcf9f6d/sensen-journey-water-0.16.3.apk)。
- 两个地址均完成 HTTPS 全量下载、SHA-256 对比及 Range 206 字节校验；证据 `release/download/verification.json`。
- 未向 Joey 或其他联系人发送任何消息。
