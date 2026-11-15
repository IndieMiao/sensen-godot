# 举报邮件 SMTP 配置准备（SGODOT-484）

83已交付：liusen 阿里云 Direct Mail **美国弗吉尼亚 us-east-1**，触发邮件发信地址
`reports@notify.gensen.app`，域名已验证，20:09在美西机测试SMTP登录成功。
实际收件人**只读MAIL_TO，不在程序写死，也没有默认值**。用户已确认收件为
shaojie@gensen.app，83已更新美西MAIL_TO；support@不存在。业务接线及真实送达尚未验收，发送保持关闭。

`src/p0/report_mail.ts` 是独立适配器；`src/p0/report_outbox.ts` 提供持久队列，
由 `report_delivery.ts` 接 `voice.onReport` 与服务器启动/关闭，按JSONL补扫恢复漏入队的报告。
本文件不是部署或真实发信授权；SMTP登录成功不等于业务投递验收。

| 配置位 | 要求 |
| --- | --- |
| `P0_REPORT_MAIL` | 默认 `off`，仅接受 `off` / `on` |
| `SMTP_HOST` | `smtpdm-us-east-1.aliyuncs.com`；其他地域或API主机拒绝 |
| `SMTP_PORT` | 仅465或80；25不支持 |
| `SMTP_SECURITY` | 465必须`ssl`，80必须`starttls`；不允许明文或错配 |
| `SMTP_USER` | 发信地址全称，须与MAIL_FROM相同 |
| `SMTP_PASS` | SMTP密码；不是阿里云API AccessKey，只由美西root注入，禁止复制或打印 |
| `MAIL_FROM` | 已验证的发信地址，当前为reports@notify.gensen.app；域名须notify.gensen.app |
| `MAIL_TO` | 管理员确认后的单个裸邮箱地址；必填，无默认值；拒绝收件人列表、显示名和换行 |

凭据仅在美西US-p0 `/root/secrets/directmail-reports-smtp.env`（root:root 600），
由root在部署时注入上述七个变量；应用本身不读取此文件、不因此改成root运行。
不要下载到开发机、复制到仓库/镜像、输出在命令参数/日志/聊天中。
七个变量存在也不会自动启用发送，还须独立设置`P0_REPORT_MAIL=on`；业务接线
与真实送达验收完成前保持off。旧P0_REPORT_MAIL_FROM/P0_REPORT_SMTP_USER/
P0_REPORT_SMTP_PASSWORD配置不再读取，避免与83交付不一致。

465用隐式TLS，80用强制STARTTLS（requireTLS=true，服务端不支持就失败），
均验证证书且最低TLS1.2；不降级到明文，不使用25。
`dm.us-east-1.aliyuncs.com` 是 API 接入点，不能填作 SMTP 主机；不得使用缺域名的
`smtpdm-us-east-1` 或旧悉尼/杭州端点。管理端开通如用aliyun CLI，需按蒙恬说明
显式指定美东API endpoint，不能仅靠`--region`。不改现有Google收件MX。

适配器只接受对外字段：双方支持码、系统原因标签、地点和层、时间、渠道。
收件人取已校验的MAIL_TO快照、主题固定，纯文本正文，没有附件或链接读取；多传名字、原始玩家ID、IP、
token、HTML、替代收件人都不会序列化。标题及正文含权威举报编号，格式校验后才进入标题。
`report_notice.ts` 按后裔484评论550d0c5d的五枚举映射原因，不认识/空值转Something else；不转发自由文本。SMTP失败对调用方
只返回固定错误码，不把可能包含凭据/正文的供应商错误写入日志。

验证只用注入的假transport，不创建真实SMTP连接；覆盖83七变量映射、缺MAIL_TO
拒启用、两种TLS组合、禁25/明文/其他地域、收件人不被举报对象或配置后续修改覆盖，
以及外发字段白名单和错误脱敏。
队列先独立验证重启、去重、并发、写失败、投递失败及关闭；业务接入仍需权威记录落盘后的稳定编号和补扫。
拿到正式配置后另做获准的测试邮件，核区域、DNS通过、TLS和收件成功；
SMTP接受消息不等于邮件已投递到最终收件邮箱。真实举报通知开关在该验收之前保持关闭。
日额度2000、免费总额度2000且每日最多200免费、超出按¥2/千封（83交付口径）；
没有打开/点击跟踪。后续队列要限速并避免集中重试，新域名不用批量真邮件测试。
密码轮换或接入问题交83处理，详情以directmail-notify-gensen-runbook-20261112.md为准。

## 队列接入约定（11-13 开发准备）

每个服务进程仅一个 `ReportOutbox(file, deliveryOrNull)` 写者，和现有 P0 单写者一致。适配器默认关时
传 `null`，队列只入盘不发送；启用时传 `createReportMailer(config)`。调用方定时调 `tick()`，每次最多
尝试一封；并发 tick 共用一次发送。关闭时先 await queue.close()，再 mailer.close()。

权威举报必须先持久化（含只在自有服务器存的名字快照），再经 `onReport(line)` 调用
`reportLineNotice(line)` → `enqueue(line.id, notice)`。编号由后裔的写入端生成并固定：
`R-YYYYMMDD-XXXXXXXX`（UTC日期+8位Crockford随机字符）；队列不生成/替换编号，载荷id必须一致。
队列只投影编号、双方支持码、原因标签、地点/层、时间、渠道；不存姓名、原始ID、IP或凭据。
回调或入队失败后，启动扫描 `voice_reports.jsonl` 中v2行，重放同一id；已入队/已sent不重复入队。
旧v1行无稳定编号，不猜编号、不自动补发；仍交原举报留存处理。损坏v2行应留给管理排错，不打印原始行。
channel按权威行保留oss/play/appstore/空串（旧包），不把空值猜成oss；name为当时profile.name或null，始终不出邮件。
回调接入 `report_delivery.ts`：入队错误只打固定事件、不向玩家暴露异常；每30秒补扫并最多尝试发送一封。
启动先补扫，关闭先停计时器、解除回调、等待在途投递，再关transport。默认off不构造SMTP transport，仍保留队列。
历史v1、损坏行、过期或未来时间行不会发送；损坏行仅汇总告警，不输出原始举报/名字。已过365天的队列记录也不发送。

默认发送间隔30秒，失败从1分钟指数退避到最多1小时；UTC每日最多200次尝试（含失败），限额/下一次时间
都在SMTP调用前原子写盘，重启不清零。200是开发用保守配置，低于通道2000封/天总上限；不代表独占全部额度，
还须和邮箱验证码的全局额度一起核。时间倒退不会重置预算。读取坏队列直接报固定错误，不静默丢消息；写失败
保留原内存状态和文件，让调用方重试。供应商错误不写日志。

同一id重放（含发送成功后）不重复排队；同一id携带不同内容拒绝。
补扫遇到这种内容冲突时保留原队列载荷和原JSONL，单列conflicts计数/固定告警并继续后续行；真正读写失败仍中止待重试。
但SMTP接收成功后，进程崩溃或本地sent确认写失败时可能重投，**不保证恰好一次**；SMTP接受也不等于最终送达邮箱。
目前已接调度及到期物理清理，详见report-retention.md；P0_REPORT_RETENTION默认off，须获得批准启用并复演后才算政策落实。
sent回执和积压通知按原举报时间到期、不因重试重新计时。真实邮件仍等获准送达验收，状态不写入玩家存档，不改玩家存档版本。
