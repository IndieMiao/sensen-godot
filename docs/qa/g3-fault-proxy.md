# G3 真机故障注入

仅代理本机 `127.0.0.1:3103` 的隔离 QA 服务，监听 `127.0.0.1:3104`。不接受上游域名配置，不连接生产服务。普通游戏 APK 通过同一个代理地址完成故障、强退与重启恢复；过程中切换服务器地址会改变命令日志的隔离范围。

先启动 QA 服务，再单独启动代理：

```sh
pnpm --dir server exec tsx tools/g3_fault_proxy.ts
```

设置下一条指定操作在服务端确认提交后挂起响应，并挂起相同 key 的自动重试：

```sh
curl -sS http://127.0.0.1:3104/__fault/arm \
  -H 'content-type: application/json' \
  -d '{"type":"buy_seeds","mode":"after_commit","replay":"hold"}'
```

`type` 支持 `buy_seeds`、`cook_dish`、`save_decorations`。`mode` 为 `before_forward` 时，在向上游发送命令前挂起，因此服务端没有收到该操作。`replay` 为 `pass` 时，后续相同 key 请求正常转发；为 `hold` 时不再向上游发送并持续挂起。

真机触发操作后检查状态。`held_total >= 1` 表示已进入故障点；`after_commit` 还应确认 `applied_responses = 1`、`after_first_commit` 存在。

```sh
curl -sS http://127.0.0.1:3104/__fault/status
```

强退游戏，允许原 key 重放，再以相同服务地址启动游戏：

```sh
curl -sS http://127.0.0.1:3104/__fault/replay \
  -H 'content-type: application/json' -d '{"replay":"pass"}'
```

恢复后重新读取权威状态，并检查钱包、种子、食材、菜品及布置摘要：

```sh
curl -sS http://127.0.0.1:3104/__fault/verify \
  -H 'content-type: application/json' -d '{}'
```

- 提交后丢包：`applied_responses = 1`、`replayed_responses >= 1`、`unchanged_since_first_commit = true`，且 `first_delta` 与 `total_delta` 相等。
- 提交前丢包：允许重放前 `unchanged_before_forward = true`，成本变化为零；允许重放后只观察到一次 `applied`。
- `snapshot_error = true` 或任何必要快照缺失时，不能据此声称成本验证通过。测试期间避免在相同账号进行其他操作；摘要比较是观察证据，服务端命令表可用于独立核对。

`POST /__fault/disarm`（JSON `{}`）取消下一次故障，并允许后续重放。已挂起的连接仍等待客户端超时或关闭。存在等待中的客户端时重新 `arm` 返回 `CLIENT_STILL_WAITING`。`Ctrl-C` 停止代理并关闭挂起连接。

管理接口仅接受无 `Origin` 的本机请求，修改操作要求 JSON。状态只包含命令 key 和 farm ID 摘要、计数及限定的资源快照。token、安装密钥及请求原文不会写入日志或状态；验证请求临时使用内存中的认证头访问 QA 服务。

回归检查：

```sh
pnpm --dir server exec vitest run test/http/g3_fault_proxy.test.ts
pnpm --dir server typecheck
```
