# B4（部分）首启合规流 + 设置 + 删号：R2 年龄门 / R3 同意 / R1 Firebase 侧（实施记录）

- 日期：2026-09-07 ｜ 分支：`feat/next-feature` ｜ Plane：SGODOT-93（B4，部分）、57（R2）、58（R3）、56（R1，客户端与 Firebase 侧）
- 上游：`2026-09-07-dev-task-breakdown.md` §3 B4 / R1–R3；08-30 调研 §5.1#2、#4、§5.3
- 性质：实施记录 + 交接。自动化全绿；条款 / 隐私 URL 与联系邮箱待 SSLAUNCH B2 / B3 / B6 / C6 填入。

## 0. 结论

| 项 | 结果 |
|---|---|
| 全量测试 | **722 例 / 87 套件，0 errors / 0 failures / 0 orphans** |
| 新增测试 | `test_first_run.gd` 5 例；`test_compliance_pages.gd` 12 例（年龄门 3、同意 3、设置删号 / 登出 4、我的页验证 2）；boot / routes 用例跟随更新 |
| i18n | 新增 17 条 zh_CN，`extract_pot.gd -- --check` 66 key OK |
| 无头冒烟 | `--qa-scene=agegate / consent / shell`、fresh boot 无脚本错误 |
| 未做 | 资料卡 / 编辑 / 形象上传 / Space 3D（等 D2 / D4 后端）；服务端级联删除与 Apple token revocation（D2）；年龄门 / 同意版本回写服务端（D2）；真机走查 |

## 1. 做了什么

- **`modules/app/first_run.gd`（`FirstRun`）**：`user://first_run.json` 只存结论——`age_gate_passed / age_gate_blocked / age_gate_at / consent_version / consent_at`，**不存生日**；`age_years()` 周岁算法（生日未到减一）；`record_age_gate()`、`record_consent()`、`consent_current()`；`next_route(signed_in)`：被拒或未过门 → 年龄门，同意版本不匹配 → 同意页，否则按会话进壳 / 登录。
- **`modules/app/legal_links.gd`（`LegalLinks`）**：隐私政策 / 条款 URL、支持邮箱、`CONSENT_VERSION`（改版即改此值，全员重新同意）。URL 为空时相关按钮禁用并在 tooltip 说明来源。
- **年龄门页** `scenes/app/age_gate_page.gd`：中立措辞只问生日（年 / 月 / 日 OptionButton），不提"13 岁"；未选全提示；≥13 → 同意页；<13 → 拒绝文案、控件禁用、持久化，重开仍被拒。`today / first_run / navigate` 可注入。
- **同意页** `scenes/app/consent_page.gd`：零容忍声明 + 隐私 / 条款外链 + 勾选框，勾选前「继续」禁用；记录版本后按会话去壳或登录。
- **启动决策** `boot.gd`：`decide(signed_in, first_run)` = `FirstRun.next_route`。`AppRouter` 加 `AGE_GATE / CONSENT` 路由、`go_to_route()`、`--qa-scene=agegate|consent`，返回键归 `BACK_LEAVE_APP`。
- **设置页**：语言 / 隐私政策 / 服务条款 / 联系我们 / **删除账号**（ConfirmationDialog 确认 → `FirebaseAuth.delete_account(id_token)` → 本地登出 → 登录页；`CREDENTIAL_TOO_OLD_LOGIN_AGAIN` 提示重新登录后再删；dev 会话跳过 Firebase）/ 登出。服务端级联留 `TODO(D2)` 注释一处。
- **我的页**：显示邮箱 + 提供方；Tab 显示时 `FirebaseAuth.lookup` 拉验证状态，未验证给「重发验证邮件」。

## 2. 关键决定

1. **年龄门只存结论不存生日**：生日本身是 PI，COPPA 要求采集任何 PI 前先过门，设备上留生日没有任何用处。
2. **被拒状态持久化、重装才能重试**：与 SSLAUNCH F9 需求稿一致；不给"改个生日再试"的入口。
3. **同意带版本号**：条款改版是必然事件（SSLAUNCH B2/B3 定稿、以后每次修订），版本号让重新征求同意变成改一个常量。
4. **删号先做 Firebase 侧**：Apple 5.1.1(v) 要求 App 内可发起完整删号；服务端资料级联在 D2，客户端已留好挂点，不等后端。

## 3. 手工验收（待人工）

1. 清 `user://first_run.json` 冷启动：年龄门 → 选 2013-09-07 之前的日期可过、之后被拒且重开仍被拒 → 同意页勾选后进登录页。
2. 登录后设置 → 删除账号 → 确认：Firebase 控制台用户消失、App 回登录页；未近期登录的账号删除会提示重新登录。
3. 我的页：未验证邮箱显示「Email not verified」与重发按钮，点击后收到邮件。

## 4. 下一步

B4 剩余（资料卡 / 编辑 / 形象上传）等 D0 → D2 / D4；C1 原生登录等 SSLAUNCH A9 与原生构建环境；下一项可在纯 Godot 侧推进的是 **A5 文本输入与键盘专项**（聊天页 / 发布器 / 资料编辑三处输入框的键盘避让）或 **B5 地图主页整合**（复用 09-04 Demo 基线）。
