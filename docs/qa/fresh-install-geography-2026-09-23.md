# 新装机生成农场失败：网络连接超时修复

用户在安装 0.16.32 后反馈卡住。V2509A 实际安装版本／版本码为 0.16.32 / 2026092311，本次安装时间 2026-09-23 19:28:55；当前 files 内是新生成的 install_key，无 farm_choice 或 outfit 文件。日志确认登录成功，`has_farm=false / NO_FARM`。未擅自恢复历史身份或农场，也未替用户确认新建农场。

早期截图被 USB 调试授权弹窗覆盖；弹窗消失后的实际错误为选地页 `Map service is temporarily unavailable. Please try again.`，即 `GEOGRAPHY_UNAVAILABLE`。这与授权弹窗本身是两个问题，不能把前者归因于 USB。

## 根因与修复

生产 Node 22 的网络地址族自动选择默认每个候选地址只等待 250ms。访问 Overpass 主源时，两条 IPv4 尝试均 ETIMEDOUT，IPv6 则 ENETUNREACH；一次完整失败约 636ms，尚未到 OSM 的 30 秒请求上限。备用源超时／429，整体返回服务不可用。

同一生产主机、同一应用镜像，仅将地址尝试时间设为 1500ms：

- 默认洛杉矶选址：OSM 200、43 个地物、280 个顶点，约 6.6 秒成功生成。
- 上海人民公园：OSM 200、27 个地物，约 3.3 秒成功生成。
- 原 Silver Lake 水岸样例：OSM 200 后按既定规则补 ESA，两次 Range 206、131072 字节，约 14.2 秒成功生成。

上线变更仅为原 `journey-app` 的 `NODE_OPTIONS: --network-family-autoselection-attempt-timeout=1500`。镜像仍是 `sha256:9de4d962de28910879680c1ee0ad7d4fe0e78525533ac3c14b24431462c4498b`，业务源码、域版本、内容版本不变。OSM 30 秒总期限、ESA 9 秒期限、字节限制、未知地表拒绝、原几何校验和验证均未放宽。未替换 OSM 数据源、伪造陆地、改 TLS 校验或部署代理。

配置已写入生产 `/opt/farm/journey-preview/compose.yml` 并仅重建 Journey app 容器。原文件与回执留在服务器 `operations/network-timeout-20260923/`；后续部署应保留 [配置片段](../../server/deploy/journey-network.override.yml)。

## 数据与验证范围

重建前后的三个完整表摘要逐字节一致：74 个 farms、1599 条 commands、38 条 farm_creations；无数据库恢复。公开 healthz 正常，domain 27 / content `50c2dbdde04c9678`。

原包无需重装。新身份的启动、登录、选城、地图与生成按钮展示已用模拟器第二 Android 用户隔离验证；原模拟器用户 0 已恢复，测试用户 10 已停止。没有在生产为 QA 创建农场。

真机已定位错误并保持当前页面；数据请求修复的证据是生产主机只读生成重放，不能当作用户手机已经创建农场成功。用户已确认先卸载／清过数据，按全新账号处理，不恢复旧身份。修复后的手机实际重试结果仍待确认。

生产配置生效后再次运行未经临时网络参数覆盖的重放，继承 1500ms 设置；OSM 200、43 个地物、280 个顶点，约 8 秒生成成功。

记录：`output/map-release-2026-09-23/phone-stall/`，新装隔离检查：`fresh-install/`。

## 用户实际重试与旧数据核对

用户随后已在手机新身份下成功建场，当前手机身份查询 `/farms/me` 返回新农场（0 个地块），截图已进入正常城市地图浏览；本轮未代替用户按确认按钮。线上总数从 74 增至 75。

用卸载前本机身份备份只读查询，旧农场仍在（版本335、58个地块、187金币）。排除本次新增农场后，原74个完整farm行的摘要仍为 `987a140dbca3e8cfa163cf3a2119be04`，与修复前逐字节相同。不是清库或旧存档迁移。

服务器使用匿名安装ID，没有Joey姓名／邮箱绑定，无法仅凭名字定位他的具体farm行；所有原有农场均保留。保留应用数据覆盖升级无需建新农场，卸载／清数据才会生成另一身份。未向Joey发送消息。证据：`output/map-release-2026-09-23/identity-check/`。
