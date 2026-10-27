# SGODOT-341：可见的 Test options 与默认 On

依据：用户10-27晚要求、不知火舞341 `d559585e` / 位置更正 `0d94c10d`、玩法方案 q(244)。基于已合 #516/#517/#524 的 farm-dev `18cdeb4c` 开工，随后快进到仅补设计文档的 `0d4b7af7`。此项排入0.2.12；审核人按奕星本次派活为哪吒，不知火舞看图，合由奕星执行。

## 最终改动

- Settings 主页在 **Legal 整组正上方**增加独立无组名的 `Test options ›` 导航行，复用现有 SettingRow LINK，无副标题或值。Legal 中 Licenses / Version 的内容、顺序和组结构保持。当前基线尚无 Notifications 行，没有添加占位；后续 Notifications 组位于本入口之前。
- 入口通往既有测试子页，保留标题、开关、Main/Test、Start new test account、确认卡、Return to main account 以及底部说明。Version 仍为只读行；七点加长按事件、状态机与文件已移除，只有可见入口。
- `P0TestAccounts.enabled()` 的**缺省值为 true**。已保存的显式 Off/On 均优先，不强改设备选择，也不改已有测试号的 `active_guide`。新测试号在创建时固定选项；主号及普通新号仍不发送 guide_v3，不把主号原地重置。
- 老号重测走原有新建独立 g3test 号/回主账号路径。主身份文件、验证备份、测试号偏好隔离、Avatar key、切换等待在途队列等实现不改；不改服务端、存档版本或全局 GUIDE_V3_READY，无新增英文。

## 自动回归

Settings + guide_test_accounts 定向 **26/26**，report_870，0 errors/failures/skipped/orphans、exit0。保留账号保护与返回测试，删除两条已退役手势成功测试，增加三条新默认/旧选项兼容/可见入口路由回归；Settings 现有用例追加 Legal 组不拆、入口单独成组、位置/文案/点击与 Version 无手势监听的断言。

覆盖：未配置默认On但主号仍legacy；显式Off跨重载保持；已有测试号不被新默认追改；新建默认进入guide_v3，之后切Off不影响当前号、下次新建才生效；反复创建不同id；主凭据/备份/偏好保留；备份失败拒绝切换、空主号恢复、不同非空身份不覆盖；测试号选城及离线启动失败返回入口继续可用。

布局更正后的首次全量 report_871 有一条未修改的行动环测试失败：抖动要求 >3px，实测2.999992；单独原样重跑行动环 **14/14、report_872、exit0**。未放宽断言、未改行动环实现。最终布局和相同实现原样重跑 **1841/1841、184组、0 errors/failures/skipped/orphans、exit0，report_873**。基座1840，退役2条旧手势测试、增加3条新回归，净增1条；更正前 report_869 的1841通过不作为最终布局的完成证据。

## 真实本地服与客户端实测

隔离项目及 userdir `gensen-liubang-341-visible-test-options`，真实P0服务 `127.0.0.1:3191`，使用当前基线完整服务源码，无fixture替换响应。仅在该任务目录创建一个legacy主号（777 coins、独立背包/农场），不是用户账号。

最终两个独立Godot进程均exit0，共 **21项检查全部为true**：

1. 未配置设备默认On；主号仍legacy。实际七点Version再长按2.1秒仍停在Settings；点击可见入口进入测试页。
2. Start先弹原确认卡，Cancel不切号；确认后生成独立g3test id、首次状态为引导，tips/quickbar/Avatar隔离。选城页实际点击Return回原主号。
3. 再次Start得到不同测试id；测试号建家（城市选择由QA设定，Continue/Build/确认用真实viewport点击），测试页可见Return。退出整个进程再启动，仍是同一测试号与引导选项。
4. 重启后从测试页实际点击Return；主身份和验证备份原字节、tips/quickbar、Avatar、金币/背包/田格/农场坐标与基线一致，主号引导仍关闭。
5. 主号页显式切Off，写盘重载仍Off；新建第三个测试号为legacy，从选城再回主号后Off仍显示，主号资产文件保持。

额外比较服务端主号的 coins / bag / plots / travel / guide / skills / gear / storage / homestead，全部与本轮新建基线相同。读取/在线时间字段不用于“完全不变”承诺，正常主号的自然生长不会被冻结。

## 材料及边界

要求的两图为 `SGODOT-341-visible-settings-main.png`（Test options在Legal整组上方）和 `SGODOT-341-visible-options-main-on.png`（Main、默认On）。另附既有确认卡、Test页Return与返回Main后保存Off的三图，以及21项检查/服务端字段对比和测试摘要。全部上传 [SGODOT-341](https://plane.sensenjoy.cn/zili/browse/SGODOT-341/)，五图均实际查看。Settings截图的Version是独立开发构建的 `dev`，未伪装成已发布0.2.12。

早期驱动两次失败只留本地：一次在真实城市列表到达前点中加载占位页的空返回回调；一次直接发建家命令绕过了页面的完成回调。驱动已改为等待真实城市列表、实际点击返回和建家确认，完整重新跑通；未为QA问题改产品实现。最初“拆Version”的图片已归档，不作最终设计证据。

此次未做新的Android覆盖安装或真机验收；旧#505的隔离Android覆盖安装证据仍只对应当时版本，不能改称本头验证。当前升级兼容覆盖通过旧选项文件/已有测试号回归及实际双进程重启。测试进程退出有7个ObjectDB warning，未宣称消除既有退出警告。

所有本人捕获Godot与3191本地服已停止；无 --import/--editor、ADB、用户手机、部署或存档迁移。奕星已核实香港65d31948能走S0–S11，并安排明早解冻部署#518/#520补齐标记；这是已转达的部署安排，本轮未探测或部署生产，不重复请求确认。后端没有本次新增代码依赖。
