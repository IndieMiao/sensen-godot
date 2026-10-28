# SGODOT-354 客户端：快熟作物与前期升级反馈

依据：用户批准的 q(245)–q(247)，farm-dev `aca4070f`；不知火舞 `7d26755a` / `b7e795cd` 走查清单。Lv4 定300。服务端由苏烈的 #535 `e0e87f925e2d8e06321027b009360f112f6550f3` 提供，两端配套进0.2.13；本 PR 不改服务端、共享数值表、存档或部署。审核哪吒，画面不知火舞。

## 实现与字段

- `view.fast_crops[]` 与普通 `crops[]`、引导 `quick_seeds[]` 分开；字段按苏烈354 `7ef93fab` / `76299d05`，保留 id/name/seed/seed_name/farming/grow_s/seed_price/price/energy/xp/first_xp。名字和买卖价从服务端读取，不在客户端复制配平表。
- 五种作物可播、按固定 grow_s 展示生长阶段，不能施肥；收成保留各自物品。背包归Produce，Homestead Stall按表价售卖，其他柜台拒收。厨房Experiment即使收到矛盾的cook标记也排除；正常配方/图鉴/委托仍读取普通作物与服务端事实，不把fast_crops加入普通列表。
- Today对快熟作物只生成每种一条倒计时，不加Harvest/Water目标行。所有作物剩余≤300000ms用m:ss，之后按原分钟/小时取整；现有Today刷新管线随秒数更新。静态时长<60s写秒，其余写1m/5m/20m/1h。主行动键Growing副行按哪吒6461465539修回普通作物的key_ready（Cress为Ready in 1m、Scallion为Ready in 20m、Bok Choy为Ready in 1h），只有q(217)快熟萝卜用m:ss；Today与主键暂不同格式的统一另起q行，不混进本PR。田格胶囊不改。
- 单复数：Cress / Pea Shoots / Baby Spinach / Bok Choy保持，Scallion→Scallions。Today与一次多格收获飘字均覆盖；飘字按聚合后的数量选词，其他物品的已有格式不变。
- P0Notify排计划和软提示两条入口都排除快熟系列；混有普通作物时，最早成熟只取普通作物。快熟萝卜原行为保持。
- HOME-1按服务端next的coins/skills/materials显示40/80/300和新门槛，钱包需求仍含既有40金币底，不把底线当消费；不新增体力奖励后果行。低级页脚删掉已不成立的“fills Energy to the new max”半句，保留既有“Upgrading is free of Energy”，Lv5起原句保持；不知火舞已在354 `f31fe553`同意此清理，按q(247)④处理。
- HOME-2直接读已有homestead事件的 **energy实得值**：Lv2–4正数写`+N Energy`，0不写整段；旧服缺energy字段时回退`Energy full`，与显式0区分；Lv5起`Energy full`。reason=homestead的体力事件不另飘字。现有HUD原来直接换数，本次按q(247)给升级实得正数加300ms数字过渡（沿用既有数字滚动时长token），仅显示插值，权威数值/行动判断不变；新数据到来取消旧过渡。

## 图标与占位植株

安其拉354 `2a774986` 交付的10枚SVG原字节接入，已由不知火舞 `67788172` 验收；主件在Figma图标行9:100583，Review row108看板214:172494。种子包保持统一青色顶带，无闪电/“快”角标。实际背包和Stall行已查看。

植株最终为B/B/L/B/L：Cress/Pea Shoots用Herb，Baby Spinach/Bok Choy用Lettuce。原H被不知火舞f31fe553更正；先实拍C成熟态确认露出橙根，再按她的条件改Scallion为B。五种逐实例换色，复用现有网格，无新绘制层；收获副本保留对应颜色。它们仍是占位外形，正式美术不在本次验收内。

本地缓存未用--import/--editor：新增通知/牌室类从当前tracked脚本补索引；牌室两张缺失纹理只从源文件与.import逐字节一致的工作区复制。十枚SVG用独立无autoload的Godot --script栅格化，按官方CompressedTexture2D格式写本地缓存，再由原生加载器解码并核对像素；提交的是SVG与标准.import设置，不提交.godot缓存。无ADB或手机操作。

## 自动验证

- 首版 `tests/p0 + tests/ui_kit` **1921/1921，189组，0 errors/failures/skipped/orphans，exit0，report_885**；日志 `output/liubang-354-client/full-delivery.log`。
- 新增10条354回归，覆盖五作物名称/图标/播种/售价、厨房排除、Today边界和单复数、通知与软提示排除、固定时长/占位批次/收获颜色、HOME-1读新需求而不加奖励行、HOME-2实得及HUD过渡/无重复飘字、多格飘字。现有快熟萝卜、HOME、通知也跑定向；全部包含在最终全量中。
- 共享 `tests/farm/test_crop_field.gd` **14/14、exit0，report_884**，验证普通作物批次和阶段仍正常。补HUD过渡前的report_880/883等为阶段性记录，不混称最终头。

## 首版真实本地服务联调（已通过部分沿用）

以git archive提取 #535完整server/assets到 `output/liubang-354-client/server-source/`；真实HTTP服务仅监听127.0.0.1:3192，使用独立qa354账号和状态文件。客户端userdir `gensen-liubang-354-client`。没有修改生产源码，也没有手写view响应代替服务端。

**19个场景、69项检查全部true，最终所有场景进程exit0**：

- 五种种子详情各一张：10s / 1m / 5m / 20m / 1h；Stall上架与五种卖价卡；实际卖出各一份，金币增量1/3/3/4/4。
- 五种成熟田格各一张，占位批次B=2/L=2/H=1；厨房Experiment保留普通萝卜/鱼/调味料，快熟系列不出现。
- 五种各实际播种浇水一格、再播第二格，Today一格/多格名称分别捕获；只有Scallions增加s。
- 普通生菜先用本地dev时间跳转准备到约5:03，再按真实墙钟连续录像，捕获6m→5:00→4:59→4:58，不加速录像。
- 五种单格和两格收获分别捕获；多格案例用隔离Farming Lv9号走真正的Harvest All命令，不宣称新手已解锁批量收获。早期驱动错误地期待跨两次回复合并物品飘字，实际仅XP跨回复合并；改为同一批量命令后全部通过，未改变旧物品飘字合并规则。
- HOME-1 Lv2–5需求与HOME-2四档：实际升级扣40/80/300/750，实得40/15/0和Lv5回满；0案例235体力在新上限230以上，保留Bonus+5且无`+0 Energy`。为稳定复现，升级前用仅本地dev/energy设定输入能量。
- HUD实际采样如170/200→175/210→183/210→210/210，205/210→207/220→216/220→220/220；零增益235/220→235/230，不造正收益。无额外升级体力飘字。
- 首版Cress主键Ready in 0:10截图已被本次审阅修正覆盖；最终key_ready格式以返修回归为准，不将旧图当作新头主键证据。

这些是桌面Metal隔离状态切片和真实命令路径验证，部分用现有plotface定位及程序调用既有面板；不是用户号、完整主线步行、原生触摸、Android/真机或生产性能验收。成熟田由QA初始状态准备，不把短片当作等满一小时的证据。服务端规则完整验证由#535自己的报告承担。

## 审阅材料与收尾

材料均在 `output/liubang-354-client/` 并上传 [SGODOT-354](https://plane.sensenjoy.cn/zili/browse/SGODOT-354/)：50张原始实拍、种子/模型/Today/收获/售价/HOME六张对照板、导出视频解码抽帧一张；三个按墙钟VFR编码视频为Today阈值 **9.44秒**、HOME体力 **7.20秒**、五种收获单复数 **24.44秒**。视频可见变化、原图及对照板已检查；原始帧/时间戳、19份前后服务端视图/事件与检查记录保留，可重放核对。

原版HUD无滚动的早期录像、错误的跨回复收获驱动、Lv5初始材料漏配Quartz和首次缓存脚本错误只留本地，最终已重录/重跑，失败材料不上传。正常捕获仍有既有5个ObjectDB退出warning，不宣称修复该旧提示。全部本人测试、捕获、缓存脚本和3192服务已退出，按记录PID核验；无模式杀进程、--editor/--import、ADB、装机、部署或存档迁移。

依赖 #535 的新视图/数值内容，同版集成后再发；不自行合入或安排发布。请哪吒审代码、不知火舞按354清单走查模型占位、文字与页脚。

## 代码审与走查返修（6461465539 / 40b05732 / f31fe553 / 31f204fe）

- PR增量前已留言“还有增量，先别合”（6461582206）。主键副行照q(97)/q(44)回key_ready，仅快熟萝卜保留m:ss；不知火舞更正此项不用197复议，统一主键与Today另起q行，不在本PR。
- 已停用的HUD文字辅助today_line和today_rows一致排除fast ready/sown目标，保留growing倒计时，普通作物目标保持；按走查意见不额外拍该已无调用的旧胶囊。
- HOME-2缺energy用旧服Energy full，显式0仍只写Max Energy；已同意的HOME-1页脚与Lv5滚动保持。
- 十枚.svg.import补原生ResourceUID生成的稳定uid行：各自有效/唯一、与既有资产UID不冲突、配置回读/纹理加载通过。用独立Godot --script完成，没有editor/import或ADB。回归校验UID元数据与原生编码往返，不依赖编辑器的UID索引。
- 用#535原完整源在本地3193、新隔离账号拍成熟Scallion：C控制图露出橙色根，最终B图为绿色植株，B/C两图相机/站位相同。田格与成熟状态直接来自真实GET；只用现有plotface定位。原H图、旧快熟主键m:ss图不再作最终模型/主键证据，其他已通过画面沿用。
- 返修定向4组 **68/68、0 errors/failures/skipped/orphans、exit0，report_887**；新增主键明确格式、today_line目标过滤、UID回归，已有收益测试加缺字段与显式0对照，原模型断言同步B。
- 新成熟B图、C控制/对比、几何/状态JSON及最终测试摘要上传354，文件位于output/liubang-354-review-fix/。两次捕获均exit0；本人3193服务和捕获进程已停；既有5个ObjectDB退出warning未改。

返修最终全量 **1924/1924、189组、0 errors/failures/skipped/orphans、exit0，report_888**；日志output/liubang-354-review-fix/full-final.log。基于首版1921加3条回归；更新后不再把旧主键m:ss或H占位当成当前结果。
