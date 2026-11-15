# 管理三处置（SGODOT-484）

接口仅注册在独立 `P0_ADMIN_PORT` 的 loopback 管理 app，要求 `x-p0-admin` 管理鉴权。
正式服只由 83 执行，执行前先问奕星；本 PR 不是部署或实际处置授权。
举报落盘和邮件只通知，不会自动执行任何处罚。`sanctions` 新可选存档字段部署前随账号批次报用户批准。

`POST /admin/moderate`：JSON 必须且只能带 `player` 或 `support_code` 其中一个，支持码多命中返回
409 `ambiguous_support_code`，无命中404 `unknown_player`，不创建账号。不返回名字或其他人的资料。

| action | 其他字段 | 行为 |
| --- | --- | --- |
| `reset_name` | 可选 `report` | 清 profile.name，使客户端显示默认名；name_locked_until 写真实服务端现在+7天，记录 name_reset_at；广播已有房间的名字更新 |
| `voice` | 必须 `until`，可选 `report` | 写 sanctions.voice，立即调用 voice.drop 结束现租约；保留年龄、blocks、报告和房间，不踢游戏 WS；后续 join/heartbeat 拒绝 |
| `suspended` | 必须 `until`，可选 `report` | 写 sanctions.suspended，立即 drop 语音和 hub.kick（4001）；后续身份请求按现有identify回403 suspended，不撤token以便保持该错误语义；现有合法删号例外不变 |

`until` 是未来的UTC毫秒时间或 `null`（不自动到期），不设默认处罚时长；到期由既有 `inForce` 判定。
`report` 如有必须是 `R-YYYYMMDD-XXXXXXXX`，作为人工处置来源记录。未知字段/动作、同时传两种定位、
缺少until或无效时间均400 `schema`。不提供未定的批量处罚、任意字段修改或新解除规则。

使用 clone 后 `store.put`，写成功再影响在线连接；put写失败恢复旧内存映射，回500 `moderation_write_failed`，
不执行drop/kick。写盘成功但通知/drop/kick失败回500 `moderation_incomplete` 且 `applied:true`，
说明存档已生效、即时副作用需检查/重试，不冒称未处罚。管理接线使用voice.drop(player,{requireConfirmed:true})；
真实媒体首轮失败抛固定VOICE_RELEASE_UNCONFIRMED，转上述管理失败，原有限后台重试继续。未确认租约保留在进程内，
管理重复调用不能因为活跃租约已移除就误报完成；确认已离开/peer已复用后才清除。其他drop/leave/后台调用仍正常resolve，
不制造未处理拒绝。此是本进程即时释放确认，不是跨进程持久任务，不能保证第三方故障时即时移除。
每次调用都视为新的人工命令；重新调用reset_name会按该次时间锁7天，操作者须先确认已生效结果再重试。

审计只写支持码、动作、时间、期限、来源编号和是否 incomplete；不写姓名、原始player ID、token或底层异常。
管理补删 `POST /admin/delete` / `GET /admin/delete/incomplete` 是11-16独立PR，不在本处置接口中。

依赖禁语音PR #1068；`VOICE_BANNED` 为候选协议码，前端提示待奕星/哪吒确认，不在本PR擅加英文文案。
测试从真实管理请求驱动写盘及HTTP/WS/语音拒绝，不以预先改存档重启作为完整链证据。
