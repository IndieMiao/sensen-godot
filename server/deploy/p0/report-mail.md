# 举报邮件 SMTP 配置准备（SGODOT-484）

用户已定：liusen 阿里云 Direct Mail **美国弗吉尼亚 us-east-1**，发信域名
`notify.gensen.app`，收件 `support@gensen.app`。开通和 DNS 由蒙恬/83负责；
域名校验预计4～48小时，实际发信地址/SMTP凭据交付后才能启用。

`src/p0/report_mail.ts` 目前只是独立适配器，**尚未接入 report 写入、重试队列或
服务器启动流程**。本文件不是部署/发信授权，不表示域名验证已通过。

| 配置位 | 要求 |
| --- | --- |
| `P0_REPORT_MAIL` | 默认 `off`，仅接受 `off` / `on` |
| `P0_REPORT_MAIL_FROM` | 蒙恬交付的、验证通过的裸发信地址，域名须为 `notify.gensen.app`；不先假定用户名 |
| `P0_REPORT_SMTP_USER` | 对应 Direct Mail 发信地址，须与 FROM 相同 |
| `P0_REPORT_SMTP_PASSWORD` | 该地址的 SMTP 密码，不是阿里云 API AccessKey；只配运行环境，不进命令行/仓库/日志/卡评论 |

SMTP 端点固定 `smtpdm-us-east-1.aliyuncs.com:465`，隐式TLS且验证证书，最低TLS1.2。
`dm.us-east-1.aliyuncs.com` 是 API 接入点，不能填作 SMTP 主机；不得使用缺域名的
`smtpdm-us-east-1` 或旧悉尼/杭州端点。管理端开通如用aliyun CLI，需按蒙恬说明
显式指定美东API endpoint，不能仅靠`--region`。不改现有Google收件MX。

适配器只接受对外字段：双方支持码、系统原因标签、地点和层、时间、渠道。
固定收件人/主题，纯文本正文，没有附件或链接读取；多传名字、原始玩家ID、IP、
token、HTML、替代收件人都不会序列化。原因标签取现有举报原因规格，后裔的
实际协议枚举到位后由调用方映射；不直接把客户端自由文本发出。SMTP失败对调用方
只返回固定错误码，不把可能包含凭据/正文的供应商错误写入日志。

验证先用注入的假transport，不创建真实SMTP连接。当前9项用例及tsc通过；
后续PR1还要接持久化成功回调、重试/去重与关闭清理，并验证重启、重复报告和投递失败。
拿到正式配置后另做获准的测试邮件，核区域、DNS通过、TLS和收件成功；
SMTP接受消息不等于邮件已投递到支持邮箱。真实举报通知开关在该验收之前保持关闭。
