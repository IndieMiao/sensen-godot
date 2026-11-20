# 管理补删与只读检查（SGODOT-484，契约 v1.6.8）

正式服只能由83在执行前问奕星；本PR没有部署或实际删除授权。所有接口只在现有独立loopback管理监听器，
继承 `x-p0-admin` 鉴权，不在公网游戏app注册。支持码仅为定位线索，不能证明普通网页请求者身份。

- `GET /admin/delete/preview?player=...` 或 `?support_code=...`：不结算、不建档、不写入，返回已有
  previewAccountDeletion摘要（支持码、是否存在/已删除、绑定类别、农场概要），不返回令牌/名字。
- `POST /admin/delete {player | support_code}`：严格二选一，先读取预览再复用deleteAccount；支持码搜索存档、
  accounts行和deletedPlayers当前30天删除记录的并集，多命中409、未知404，不任取一个。成功`{ok:true}`；
  ACCOUNT_DELETE_INCOMPLETE或媒体释放未确认`{ok:true,incomplete:true}`；前段其他失败500 delete_failed。
- `GET /admin/delete/incomplete`：只列当前删除名单内仍有账号行或存档的号，字段player/support_code/deleted_at/
  account_remaining/save_remaining。仅管理端可见，原始ID不进审计或本机输出文件。

命令：`deploy-hk.sh --target us delete <player|support-code>` 默认只预览，显式加 `--confirm` 才POST补删。
`delete-incomplete`只读输出清单；两者结果只到终端，不tee保存原始账号数据。审计仅支持码、动作和时间。
此脚本步骤不运行部署、不更改任何容器或数据目录，只调用已启动管理API；本轮仅语法检查，未连接正式服。

删除结束再以requireConfirmed检查本进程未确认媒体租约，避免重试时活动lease已清便误报完成；媒体异常仍属
incomplete。账号/语音年龄/双向blocks按共用删除逻辑清理，举报记录保留到独立保留期，不随账号删除。

清单不是失败全集：尚未写deleted、超过30天已prune、仅语音残留都可能不在清单。持有效删除记录的纯语音残留
仍可按支持码补跑；超出可定位范围时返回unknown_player，按失败日志人工排查，不暴力猜号/扩扫描私有文件。
部署前须获准环境复演及用户批准；历史备份清理是另一项，不能称所有副本立即消失。
