# 举报邮件 SMTP 配置准备（SGODOT-484）

83已交付：liusen 阿里云 Direct Mail **美国弗吉尼亚 us-east-1**，触发邮件发信地址
`reports@notify.gensen.app`，域名已验证，20:09在美西机测试SMTP登录成功。
实际收件人**只读MAIL_TO，不在程序写死，也没有默认值**。虽然runbook更新记载
MAIL_TO已改为shaojie@gensen.app，最新转达仍要求等收件人确认，因此真实发送继续关闭。

`src/p0/report_mail.ts` 目前只是独立适配器，**尚未接入 report 写入、重试队列或
服务器启动流程**。本文件不是部署或真实发信授权；SMTP登录成功不等于业务投递验收。

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
七个变量存在也不会自动启用发送，还须独立设置`P0_REPORT_MAIL=on`；收件地址确认
与真实送达验收完成前保持off。旧P0_REPORT_MAIL_FROM/P0_REPORT_SMTP_USER/
P0_REPORT_SMTP_PASSWORD配置不再读取，避免与83交付不一致。

465用隐式TLS，80用强制STARTTLS（requireTLS=true，服务端不支持就失败），
均验证证书且最低TLS1.2；不降级到明文，不使用25。
`dm.us-east-1.aliyuncs.com` 是 API 接入点，不能填作 SMTP 主机；不得使用缺域名的
`smtpdm-us-east-1` 或旧悉尼/杭州端点。管理端开通如用aliyun CLI，需按蒙恬说明
显式指定美东API endpoint，不能仅靠`--region`。不改现有Google收件MX。

适配器只接受对外字段：双方支持码、系统原因标签、地点和层、时间、渠道。
收件人取已校验的MAIL_TO快照、主题固定，纯文本正文，没有附件或链接读取；多传名字、原始玩家ID、IP、
token、HTML、替代收件人都不会序列化。原因标签取现有举报原因规格，后裔的
实际协议枚举到位后由调用方映射；不直接把客户端自由文本发出。SMTP失败对调用方
只返回固定错误码，不把可能包含凭据/正文的供应商错误写入日志。

验证只用注入的假transport，不创建真实SMTP连接；覆盖83七变量映射、缺MAIL_TO
拒启用、两种TLS组合、禁25/明文/其他地域、收件人不被举报对象或配置后续修改覆盖，
以及外发字段白名单和错误脱敏。
后续PR1还要接持久化成功回调、重试/去重与关闭清理，并验证重启、重复报告和投递失败。
拿到正式配置后另做获准的测试邮件，核区域、DNS通过、TLS和收件成功；
SMTP接受消息不等于邮件已投递到最终收件邮箱。真实举报通知开关在该验收之前保持关闭。
日额度2000、免费总额度2000且每日最多200免费、超出按¥2/千封（83交付口径）；
没有打开/点击跟踪。后续队列要限速并避免集中重试，新域名不用批量真邮件测试。
密码轮换或接入问题交83处理，详情以directmail-notify-gensen-runbook-20261112.md为准。
