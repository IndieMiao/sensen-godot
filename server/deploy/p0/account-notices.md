# 名字重置通知（SGODOT-484，v1.6.10）

实现依据：后裔review-r1契约§1.2，完整SHA-256
`edb9eaf8d07bb09469fbdc8c58c0b9a6f98a904aa1c00898c4b5c75f138b1ccc`；周瑜484/c94462d3协议技术无阻塞，
奕星484/3a1b6eea确认账号级已确认、多未读取最新和历史兼容。本PR仅服务端，不混v1.6.11或q(326)客户端文案。

存档新增可选 `account_notices.name_reset = {version,ack_version}`。SAVE_VERSION仍7，无迁移/全量回填，不改accounts.json。
版本1..MAX_SAFE_INTEGER，已阅0..version；所有入口共用nameResetWatermark读取并返回副本。
无新字段且合法非负安全整数name_reset_at逻辑映射1/0；无旧时间为0/0。新字段存在则只认新水位，损坏不降级猜历史。

- 管理reset_name先同步重读、验证next版本、clone，原清名/锁7天/内部时间与新版本同一次put；保留ack_version，游戏seq只加一次。
  同毫秒/回拨不影响事件递增；坏水位/溢出500 notice_failed，零写零广播。普通写盘失败沿原moderation_write_failed，旧内存/文件保留。
- GET `/v1/p0/account/notices`：只读peek，不调用find/get（不能结算包裹或建档）；只回 `{ok:true,name_reset:null|{version}}`。
- POST `/v1/p0/account/notices/ack`：严格 `{kind:"name_reset",version}`；未来版本409 notice_version_conflict，形状非法400schema。
  同步读取/clone/put，只写ack_version=max(A,v)，不改version/seq/名字/锁期/资产，不广播；v≤A直接成功不写。
  损坏或写盘失败500notice_failed，成功后丢响应/重启可重试。旧ACK1不能确认后来的事件2。

两路沿游戏key/版本守卫与identify，但必须via=token；user/admin token只处理自身，旧ID的legacy旁路也不可用。
被停用仍403suspended，不继承删号例外；无存档401，不建档；半删记录有残留admin token也拒绝。两路所有返回no-store。
不扩view.account或voice/status，不传旧名字、sanctions、report、管理时间/身份或支持码。

旧水位读取只做逻辑映射：GET不写；旧事件ACK首次写1/1，旧未读后的管理reset写2/0；新水位确认后不因旧时间仍在而复活。
过了7天、普通改名、退出/换设备都不自动确认。删号沿既有state删除，不另留通知或重建账号。

账号级“已确认一次”不是严格显示exactly-once：多个设备已开卡可能各点OK，服务端幂等。
首场景时机、OK之外不ACK、待ACK与generation/旧回包隔离由哪吒接线。q(326)迟到文案仍待用户批；本PR不改文案、不延长锁期、不默默确认。
新可选字段/历史1/0列整包部署格式变更报用户，不是本PR授权上线；不动正式号、迁移、部署或QA94固定环境。
