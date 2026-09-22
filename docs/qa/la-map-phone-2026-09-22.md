# 洛杉矶地图 0.16.13 · 真机安装供审阅

2026-09-22，用户明确要求“安装到真机我检查”。已将地图与紧凑UI更新覆盖安装到 V2509A 的原 Journey 应用；未安装模拟器QA身份或本机3196测试服务配置。

| 项目 | 核对值 |
| --- | --- |
| 设备 | V2509A，`10AFAF162200319` |
| 包名 / 版本 | `com.sensen.journeypreview`，`0.16.13 / 2026092206` |
| 原版本 | `0.16.12 / 2026092202` |
| APK SHA256 | `f950c4bd963de49a584e327f7c9d76665f9d4ec474d0df20e5877ae1fa5ed190` |
| 原证书 SHA256 | `38771d94b8fbfa11651cc440e3746c9182114461a90cc0ab7188d7b708515673` |
| APK 字节数 | `161735043` |
| 接口 | `https://farm.sensenjoy.cn/preview/journey/v1` |
| 后端 | `shoreline-farm-20260921`，domain27/content `50c2dbdde04c9678` |

最终包使用正常选城入口、原数据目录和五个正式autoload；包内没有观察器、测试账号、测试入口资源或QA feature。51个地图脚本/资源文件与已验证的QA3包逐字节一致。安装前验证了手机现有签名并归档旧APK，停止应用后读取该手机最新的五份身份/偏好/装扮文件及服务器农场基线；没有使用历史基线恢复数据。

`adb install -r`成功。Vivo的外部来源提示仅对已识别的Sensen Journey Preview勾选“已了解应用的风险检测结果”并继续安装。没有卸载或清理应用数据。安装后的base.apk已重新拉回验证，版本、证书和完整SHA256与构建文件一致。

同一无观察器包通过正常冷启动/原账号登录检查，选城页截图已目视检查；日志无脚本/解析/编译错误或Android崩溃。五份文件安装后与冷启动后均保持原字节；farm_id、version、地形、位置、迁居状态和所有非clock状态与即时基线相等。当前农场51格、187金币、10个背包堆叠、relocation.used=true均保留，没有种植、购买、赠送、换装或重新选址命令。

本次真机检查范围为安装、冷登录与保存保持。地图完整流程此前在隔离模拟器验证；本轮未重复真机地图操作，留给用户自行审阅。打开原来的 Sensen Journey Preview，选择“洛杉矶”进入新地图。

证据位于 `output/la-map-device-2026-09-22/`：`release/apk.json`、`release/map-payload-match.json`、`device/installation.json`、`device/final-smoke.json`、`device/final-city.png`。个人基线与认证信息保存在忽略目录下的 `device/private/`，不用于公开分发。

仅做本地构建和用户指定手机安装。没有发布新的公共下载链接，没有部署或迁移服务，也没有向Slack/飞书收件人发送更新。测试经 `tools/android/run_test.sh` 运行并在结束时停止应用；用户可正常自行启动检查。
