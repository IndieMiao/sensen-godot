# 宝剑仅挥砍时显示

2026-09-15。用户要求下矿后默认隐藏宝剑，只在挥砍动作期间显示。

## 实现与验证

矿井持剑模型默认隐藏，与现有挥砍效果的 0.16 秒显示时段同步。
空挥和命中都会显示；待机、普通移动、挥砍间隔、暂停与背包操作隐藏。
更换或卸下武器立即隐藏旧模型。仅改变显示，装备、伤害、攻速、命中与存档规则保持不变。

- Godot 战斗与延迟回归 19 项通过，0 错误、0 失败、0 孤立节点。
- 原生 Godot 在 390x844 和 960x720 检查待机、挥砍、移动三种画面，共 6 张截图；
  验证挥砍结束后即使仍在攻击冷却期间也隐藏，卸下武器后清除模型引用。
- Android 模拟器 `emulator-5560`、独立 QA 包实际连续挥砍 4 秒，
  观察到挥砍时显示、间隔隐藏、松手后隐藏，显示采样均处于挥砍时段，存档与版本保持不变。
  复用先前精英已击败的 QA 存档 `v155`，本轮没有再次修改数据库夹具。
- 两份公共 APK 直接解包加载检查实际编译脚本中的显隐行为，17 份内容文件一致，签名检查通过。
  本轮未操作用户真机；前轮障碍滑动与异步战斗结算保持。

证据：`output/weapon-visibility-emulator-2026-09-15/`，原生截图在
`output/localization-qa-combat-20260915/project/output/weapon-visibility/`。
模拟器检查后已停止 QA 应用，保留已有应用、服务和存档。

## 版本

R4：`0.8.3-combat-online.20260915`，版本码 `2026091506`，保留原包名和签名。
此为客户端更新，服务端仍是领域 19、内容 `357a6d361d4c7ab6`，无需部署服务或迁移存档。

| 包 | 下载 | SHA-256 |
| --- | --- | --- |
| Journey Preview | [R4 APK](https://oss.sensenjoy.cn/farm/releases/combat-20260915-r4/sensen-combat-online-2026-09-15-r4.apk) | `fcb6206a8c339c76c8c09dd0b0c8de2f6fc7563bc727cb8c6df92630e3d66887` |
| Workshop | [R4 APK](https://oss.sensenjoy.cn/farm/releases/combat-20260915-r4/sensen-workshop-combat-online-2026-09-15-r4.apk) | `37a72775cf9f8293cfbbcb4cd2265e6e04a0711bcdc595e46285fe36d8628597` |

发布、覆盖安装与飞书结果位于 `output/weapon-visibility-public-2026-09-15/`。
两包 CDN 完整下载的大小和 SHA-256 均一致；模拟器覆盖安装后身份、城市、农场、语言及 UI 存档文件逐字节保留。
完整 Journey APK 已上传[飞书云盘](https://a91obh1e4d.feishu.cn/file/IlyMbSF3iomSCVxFyqxcbERYnIg)，大小 133943448 字节。
22:42:55 通过 CLI bot 发送给张邵杰，消息 `om_x100b65a1d83d50a0ddc6e3dc26a01ed`，随后回读确认内容与接收会话。
