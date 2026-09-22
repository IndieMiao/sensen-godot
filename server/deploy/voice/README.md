# 队伍语音：阿里云 LiveKit

2026-09-16 用户选择自建。复用阿里云香港 ECS `i-j6ce29842p9wiwecoue6`（47.76.226.41），没有购买 LiveKit Cloud 或新增实例。

| 环境 | 手机连接地址 | ECS 管理端口 | ICE TCP / UDP | TURN UDP | relay UDP |
| --- | --- | --- | --- | --- | --- |
| 开发 | `wss://voice-dev.sensenjoy.cn` | 17880 | 17881 / 17882 | 3478 | 30300–30399 |
| 生产 | `wss://voice.sensenjoy.cn` | 7880 | 7881 / 7882 | 443 | 30000–30299 |

两个容器、密钥、配置和房间命名空间独立。开发密钥访问生产已验证被拒绝。两者仍共享一台 ECS 的故障域；这不是多区高可用部署。Caddy 管理 HTTPS 证书并转发信令；语音站点不启用访问日志，避免记录连接 URL 中的短期 token。没有录音服务。

## 开发配置

本机不需要运行 LiveKit。`server/.env.voice.local` 已配置远端开发服务、已加入 gitignore，权限 0600。新开发环境参考 `server/.env.voice.development.example`，通过私密渠道填入开发 key/secret：

```sh
cd server
node --env-file=.env.voice.local --import tsx src/index.ts
```

这只加载语音配置；游戏数据库、PEPPER 等原有启动配置仍按 `server/README.md` 准备。不要在正式应用导出、聊天、截图或仓库中放 API key/secret。

## 生产配置与维护

ECS 目录 `/opt/sensen-voice`：

- `compose.yml`：固定 LiveKit 1.13.7，自动重启，生产 512 MiB / 0.8 CPU、开发 384 MiB / 0.4 CPU。
- `prod.yaml` / `dev.yaml`：服务配置和各自密钥，私有权限。
- `private/voice-production.env`：只由正式游戏后端容器加载。
- 游戏容器同时连接 `sensen-journey-preview_default`（隔离数据库网络）与 `farm_default`；演练容器也必须接上后者才能调用同机 SFU。

游戏后端 `LIVEKIT_URL` 返回给客户端；`LIVEKIT_ADMIN_URL` 仅供同机内部管理 API，绝不返回客户端。

操作前先保留当前配置和镜像摘要。日常检查：

```sh
cd /opt/sensen-voice
docker compose ps
docker compose logs --tail 50 livekit-prod
docker stats --no-stream
```

单独更新开发：`docker compose up -d --no-deps livekit-dev`。更新生产服务会影响正在通话的队伍，应在低峰安排。切换游戏后端沿用数据库备份、副本演练、指纹对比和单 realtime writer 流程；不能同时运行两个正式游戏写入进程。

当前支持 UDP 直连、ICE/TCP 和 TURN/UDP。尚未提供 TURN/TLS TCP 443；只允许 TCP 443 的受限企业网络可能无法通话。开发 TURN UDP 3478 与生产 TURN UDP 443 均已完成强制中继双向音频测试；每次网络配置变更后需重新验证。

## 费用与容量

LiveKit 服务端 Apache-2.0，软件免费。现有 ECS 公网为按流量计费、峰值 100 Mbps；语音下行会增加阿里云账单，不能称为完全免费。未开通任何 LiveKit Cloud 付费套餐。

第一版每队 8 个语音席位；正式游戏发证全局默认最多 32 个活动语音席位，开发建议 16。游戏 300 人组队/空间容量独立。限制是保守初始预算，不是同机容量压测结论，也不能阻止拥有旧有效 token 的恶意客户端创建旧房间；API/流量异常需监控，扩量前做并发和地区网络测试。

## 客户端与权限契约

主动加入、首次麦克风授权、默认静音；用户开麦后持续说话，非按住说话模式。收听独立控制。跨场景保留 VoiceSession，自动重连保留本次音频选择。退到后台、退出、切换账号时断开并重置静音，不做后台录音。

游戏服务器校验当前队伍和身份，发 20 秒租约、约 5 秒续期，原生层有独立超时关闭机制。离队/被踢/租约失效后切换房间代际并关闭旧房间；剩余成员短暂重连，旧房间 token 不能进入新房间。管理员 API 故障时停止发新凭证，队伍动作仍可正常完成。

Android 为官方 LiveKit SDK 2.28.2，源码在 `native/voice/android`。`tools/android/prepare_voice_plugin.py` 生成忽略的 Gradle 配置；正式导出助手自动执行该步骤。iOS 预留相同控制/事件协议和官方 Swift SDK 2.17.0；Apple 桥接已编译，但 Godot iOS 适配、打包、真机与跨平台通话仍需后续验收。
