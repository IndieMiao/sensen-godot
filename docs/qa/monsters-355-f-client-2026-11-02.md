# 355 第一批 F 客户端功能草稿

PR 目标 `feat/355-b1`，亚瑟审功能、周瑜看接口。A 的 #618 保持挂起，本轮不改 A。v4q(6) 仍待批，正式模型尚未交付；本轮是代码占位行为与资源接口草稿，不能当作最终美术、真实服务端结算或上线验收。

## 依据与边界

已读 `docs/tech/355-b1-contract-efg.md` §10、§12.2，以及 #617 v0.5 后续9104357b；v4q(6)从74cea9e6补读到46746a01（新增掉落首得记录属于服务端，客户端行为不变）。3D接口按上官婉儿 `355-b1-3d-plan-2026-11-02.md` 第4/6节，实际查看了设定图v1.1，岩甲虫按下半张v3的单角与细腿方向。

产品修改只有 `modules/mining/monsters/` 新文件及 monsters.gd 的KINDS行。monster_brain.gd、monster_view.gd、registry其它函数、slime原实现、p0_mine_combat.gd、p0_mine.gd均未改。现有未知kind回归由mob_cave_bat改成真正未知的测试id，保持fallback覆盖。

## 行为和资源

- BatBrain：fly_high/windup不进targets，dash俯冲时可打，recover后回到飞高；位移走已有PlayerMover与战斗碰撞步骤。BeetleBrain：每次charge后无论命中与否都进入meta.durations.stunned窗口，受击不延长该窗；stunned()供现有挥刀管线发送双倍伤害标记。ShroomBrain：on_hit进入hide，窗口内不能再进targets；周期spore在meta.spore_at给一次普通touch机会。
- SlimeKingBrain保留追逐、预警、冲撞、恢复的史莱姆模式，使用自己的JSON时长和hit_at。三色守关同一代码史莱姆本体/尺寸数据，换色和头饰；精英共用普通怪的模型与动作，仅换色，HP/伤害/掉落全部仍由服务器view/content负责。
- f_brain复用寻路预算、碰撞和命中时刻辅助；所有行为参数从node.meta或由meta生成的spec读。占位JSON包含radius/hit_point/durations/hit_at/spore_at，以及move、contact_range、spore_interval/spore_range；这些字段需与正式模型JSON一起保留，已在355发接口对齐说明。
- 新怪view继承已有SlimeView保留HP节点、预警条、圆形假影，替换Body下的外观；所有模型和粒子关闭实时阴影。代码占位体由圆润形状组成，蝙蝠有地面影子，甲虫亮橙边和单角，菇菇红帽白点；精英只染色。占位外形不宣称最终美术。
- 默认路径 `assets/monsters/<family>/<family>.glb`，存在就实例化并用AnimationPlayer；缺失使用代码占位体。JSON由现有注册表优先读模型旁文件、否则placeholder。可选meta.model只替换资源路径，测试用它验证模型加载分支；不需要换brain或战斗代码。
- 所有动作经play()；占位用Tween，模型用AnimationPlayer，循环和速率按meta时长。模型染色使用UV2.x遮罩，脸不染；材质和AnimationLibrary按实例隔离。代码王头饰优先加载crown/ironback_plates/quartz_cluster.glb，没文件时用各自的软形状占位；跟随Body缩放，不另改本体。
- 动画通过Tween.custom_step/AnimationPlayer.advance与战斗使用相同限幅帧时间；阶段切换从0开始。暂停时不推进攻击/缩回/硬直动作，空闲循环可以继续。die有自己的短更新生命周期并最终隐藏。

## 明确待项

**真实死亡触发尚须E所有者衔接。** 当前p0_mine_combat.sync_p0/down直接隐藏hp≤0节点，没有调用play("die")，也不再update。F已提供可独立播放/自行结束的die动作，但不越界改E核心；请求已写355 `ba4de019`、`163cdf9b`、`39374cc5`。E需要首次判死时调用一次，并让节点在动作结束前保持可见；原slime无die时长可沿用旧行为。此项未闭环前本PR保持Draft。

E现有HUD把怪数/精英名称固定写Slime/Elite Slime，F不改HUD；最终名称与守关层UI随E。正式灰模/动画、3D配色与头饰到位后要验证真实GLB（当前只用测试PackedScene验证加载/动作接口）。客户端命中标记到服务器的结算还需和E/F服务端联调。

## 验证与录屏

新增13条回归：kind/节点/影子，蝙蝠可命中窗，甲虫未命中也硬直及不重置，菇菇缩回和spore时刻，charge命中时刻，寻路预算，真实swing的targets/stunned，Tween动作与die，精英几何共用/换色，模型路径/AnimationPlayer/材质资源隔离，孢子视觉时刻，慢帧和暂停。与原注册表7条合计定向20条；新增脚本/着色器/测试的.uid由原生ResourceUID生成。

早期全量2090/2090（report908）是慢帧修正前的阶段结果，不作为最终头结论。矿内录屏暴露了Tween墙钟先结束的问题，已改为共享战斗时钟并补回归；定向20/20（report909）通过。最终新基线结果另记在交付评论/测试摘要。

材料位于 `output/liubang-355-f`。私有userdir `gensen-liubang-355-f`、transport替身、旧P0矿场景默认43°/zoom1相机。怪物kind/HP及无岩石状态是本地fixture；玩家与怪物移动、动画、挥刀过滤使用实际客户端代码，contact在录屏中断开服务器发送，HP固定，不宣称真实击杀结算。录屏末尾die是显式调用view API，**不是已接通的服务器死亡路径**。

普通/精英/三色王各一张合照与约3秒待机视频；三种行为各8.32秒视频与两张截图、解码帧和状态JSON。王与精英合照的旧固定Elite Slime大卡由QA隐藏以免挡住模型，非产品代码修改；其余旧Run/Slime文字仍保留。按原帧时间差VFR编码，无加速；状态采样检查飞高不可打、俯冲可打、硬直、hide与spore均实际出现，图像像素非空且变化。桌面Metal不是Android/真机性能验收。

首次QA脚本类型推断错误导致autoload未运行，已修正并按本次确认的PID53776停掉失败进程；失败画面未上传。正常最终6轮捕获均exit0，无脚本/引擎错误；所有本人捕获进程已按记录PID核退出。无editor/import、ADB、生产部署或存档操作。
