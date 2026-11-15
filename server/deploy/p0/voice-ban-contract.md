# 禁语音网络投影（SGODOT-484，契约 v1.6.9）

本服务端增量叠 #1070 的 b55de1eb7，不修改原 PR 正在复看的头；协议以共享
`contract-accounts.md` §1.1（送审文件 SHA-256 c23294299997f0ec1b8dea6420165bb77684c0c31a46103cb735fa1614fa1c60，
周瑜484/81cd2b93审、奕星确认）为依据。保持 Draft 交周瑜，不部署。

内部钩子由布尔 `voiceBanned` 改为 `voiceBan(player)`，读取当前存档的 `{until: number|null}` 或无记录。
这里故意不先调用会把畸形期限过滤为无记录的 `inForce`；P0Voice先校验，之后按真实服务端时钟判定：
无记录/已到期/已解除 → null，有效毫秒 → UTC完整ISO，明确null → 永久。游戏clock_ms不参与。
永久值不能以 `!!until` 判断。畸形值返回既有503 VOICE_UNAVAILABLE，不省字段或伪装成永久。

`GET /v1/p0/voice/status` 保持available/age，并始终返回ban：
- 未禁：`ban:null`
- 限期：`ban:{until:"2026-11-20T08:00:00.000Z"}`
- 永久：`ban:{until:null}`

join、heartbeat、JWT签名后复查使用同一投影；被禁时403 `{ok:false,code:"VOICE_BANNED",until:ISO|null}`。
HTTP answer只保留这个错误的until白名单，不spread内部记录；无有效until的裸VOICE_BANNED不能当永久下发。
整号suspended鉴权优先、合法删号例外不变。status在能力关闭/年龄未通过时仍可报告禁令，不改available/age。
不改存档格式、不扩view.account、不向其他玩家公开，不下发report/at/name/管理信息。

测试包含：三态及精确到期、解除、畸形数据、毫秒存档与ISO网络区分、能力/年龄保持、鉴权先行与停用仍可删号、
HTTP白名单、JWT异步期间的新期限，以及同账号旧status延迟到新响应之后的真实Fastify响应顺序。

**乱序回包的边界**：服务端不存客户端ban缓存，旧HTTP响应不会改变新的存档或后续拒绝；它仍可能在网络上晚到。
新增回归明确保留这个事实，不伪造一个客户端消费器来声称问题已经解决。哪吒后续接线必须用请求序号/身份generation
拒绝较早status覆盖较新status或join/heartbeat禁令，仍需客户端自身回归。此服务端 PR 不修改Godot，也不增加公网序号字段。
玩家两句沿用q(315)③，日期由手机本地化；本轮不实现UI、不宣称前端验收或自动开麦。
