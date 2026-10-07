# 原生 Figma 审阅导入包

本包把现有 84 张旧图稿与 204 张后续稿重建为可编辑的 Figma 组件实例。**本目录交付是可独立使用的本地导入包。此处验证记录来自本地模拟构建；本轮通过 MCP 创建新审阅页的实际执行与截图，另见上级交接文档和 cloud 记录，不能用本地报告替代。**

## 导入

1. 在 Figma 桌面端打开原 Gensen Design 文件。
2. 进入 Plugins → Development → Import plugin from manifest，选择本目录 `manifest.json`。
3. 运行 Gensen UI semantic refactor，点击 Create review page。
4. 完成后下载 import ledger，查看画面和其中的未完成目标记录。

导入创建 `14 · UI semantic refactor · 2026-10-06` 新页。它不修改、覆盖、删除原 Prototype 节点。若同名页已存在，导入器只打开该页，不重复建稿。中途停止保留本次局部结果，原页仍不变；本包尚未提供跨插件重启的自动断点恢复。

已打包 `code.js` 与 `ui.html`，正常导入不需要 Python、Node、网络或另传图片。`gensen-ui-refactor-plugin.zip` 是同一文件集的便携包。

## 新页结构

- 288 个 360×800 主审阅帧，每帧置于 Section 内并与稿外注释并列；没有额外 FRAME 祖先，原型 NAVIGATE 目标是同页最外层 FRAME。保留原设计 ID 映射，不是原节点的原位替换。
- 96 个旧稿状态实例按 `stateExamples` 保留；解释性组件表留作状态参考，不伪装成玩家流程页。
- 共享主组件在画板外：ObjectHeader、Quantity、Effect、CommandButton、NavigationRow、Dismiss、Close、Fact、Cost、NeedTile、ItemRow、InventoryCell、GearSlot、HUD、BuffChip、HeatRing、IngredientSlot、SceneAction、NoteSelection、Toast、Tab、StateBadge、ProfileIdentity、Sheet。
- 标题、数量、状态、效果分别使用命名文字/布尔属性；图标使用 INSTANCE_SWAP。命令含主执行、次执行、危险确认、次级危险操作、阻塞五个变体。导航是 44px 无填充文字箭头行，取消是文本。
- 使用现行 tokens 的 Nunito 20px 标题、14px 正文、12px 最小说明、深绿主行动与共享颜色/间距/圆角变量。标题不随数量变化。
- 库存五列，格内只呈现图标与数量，名称和作用在选中项详情中展示；Gear 六槽；Profile、纯场景、商店与背包、Cookbook/Experiment 与场景灶台、图鉴、普通面板分别构建。长内容使用可滚动内容区；待扣费用及执行操作固定在底部；材料所需／拥有量保留在独立要求行，不重复抄到底部。
- 154 个现有本地图标/内容组件 ID 优先复用。找不到时用原 SVG 创建原生可编辑后备图标，绝不将整页图烘焙成一张图片。
- 优先复用原场景 image hash 及其已验证别名，另打包原纯场景 JPEG 后备；数量和输入hash见构建报告，没有整页 UI 截图。
- 17 张旧稿另从原 HTML 提取 455 个原始库存格与快捷格信息，避免将“只描述选中项”的 descriptor 错画成一个物品的背包。来源见 `source-grid-evidence.json`。

## 可复用与交互边界

详情打开原生 overlay，阻塞动作打开统一 Toast；有效目标连接到本轮重建帧，取消/返回用原型 Back/Close。已经确定的金币、材料、奖励、替换损失保持在执行前可见。8 个代表流程有独立起点。

原型反应、未定义结果与独立补态数量以最新 `local-validation.json`、`local-destination-warnings.json` 及云端回执为准，不冻结旧构建的计数。明确的操作结果补充为独立状态；仍未定义的结果不伪造成功，也不跳到不相干页面。静态审阅稿不执行真实交易。

部分原型跳到状态表的入口已选择其实际状态内容作为 overlay；例如休息凳的可用态、鱼咬钩态和菜谱线索。当前 Cookbook 的解释表不再充当产品列表，入口改用重建的 `COOK-2a`。

未知玩法规则和稿外备注保留在各屏说明与源数据中；它们不进入玩家视口，也不被导入动作定案。12 位居民的操作保留居民参数，设施覆盖使用只读覆盖详情，避免原先跳到 Hana 或错误地图/放置页面。

## 本地验证

运行：

```sh
python3 docs/design/ui-refactor-2026-10-06/figma-plugin/build.py
node --check docs/design/ui-refactor-2026-10-06/figma-plugin/code.js
node docs/design/ui-refactor-2026-10-06/figma-plugin/validate.cjs
python3 docs/design/ui-refactor-2026-10-06/figma-plugin/build_gap_ledger.py
python3 docs/design/ui-refactor-2026-10-06/figma-plugin/package.py
```

`build.py` 可用 Pillow；没有 Pillow 时在 macOS 自动使用 `sips`。验证在隔离的模拟 Plugin API 中创建全部对象，检查文字属性绑定、实例关系、288 帧尺寸、原页不变、最小字号、单屏主命令数量及滚动区/固定底部重叠。另检查 NAVIGATE 目标拓扑、信息头四字段独立绑定、半透明 Paint 不绑定颜色变量、以及 resize 后设置 HEIGHT 自动换行。

每次构建重新生成本地计数、专项检查与 bundle SHA-256。主稿固定为288张，原状态例为96个；独立流程、NPC／仓储交易、免费旅行、Crop-dex 与支持场景另计。准确声明与实际构建映射在 `local-validation.json` 的 `scenarioChecks.standaloneRouting` 中；组件、实例、反应和缺口以同一 bundle hash 的报告为准。

**这些检查不等同于 Figma 渲染。** 实际插件 API 行为、字体排版、图像解码、真实组件覆盖和原型演示仍需在导入后截图检查，288张主卡已有分批云端写入回执，但仍不能据本地报告声称“全部最终视觉或交互验收通过”。

## 本次视觉审计后的补充

- HUD保留体力条与coin图标，Full/Bonus不再显示恢复倒计时，头像、Inbox、位置和Buff有44px入口。
- 当前厨房显式使用2/3/4/5槽；旧Cookbook25格、Experiment20格与2个已投槽+锁定第三槽保留。火候环点击锅区，不新增普通底部Tap按钮。
- Buff失效保留Cast/Sow及快捷栏，只有轻提示。放置预览明确是Coverage schematic；实际地块锚点仍需运行场景验证。
- 留言使用可见单选变体；发出邀请/接受帮工仅显示对应反馈，不跳到另一玩家或离线结算页面。单件Claim保留物品身份。
- 材料行不会把技能/印章门槛误记为消耗；选中物品详情先于网格；卖出收益在操作前显示。
- Overlay反应不传只支持MANUAL模式的overlayRelativePosition。Toast使用全屏透明Overlay内的底部位置，2.5秒关闭。
- 模拟API现在仿照真实Figma的resize重置AUTO行为，加入主组件高度/2–5槽/火候/旧厨房格数/Buff/HUD/关闭专项检查。

源码顺序由 `build.py` 管理。标准插件现包含真实 Avatar 27 个部位资产、30 个衣橱变体及 29 个换装外观，Compact 背包/厨房/场景组件，以及独立结果补态。补态保留自己的映射，不追加或重编号原 288 张主稿。

厨房实际截图发现的问题另见 `../cloud/kitchen-selection-review.json`。本轮新选择器保留25/20/5真实格子，已知材料图标从名称解析；旧未知组合仍显示Fine/15s/Unknown dish。厨房入口改用6个FacilityMarker变体，真实图地标与1/2/3灶数分开记录；火候页使用透明中心及同一锅位相机，首菜保留5秒和50%金区。准备好的云端小脚本与精确节点配置见 `../cloud/kitchen-adapter-notes.md`，脚本仅供root执行。


## 组件规格与本地交互

- 标题、数量、状态、作用独立成字段。获得结果留正文，待扣费用只在操作区出现一次；主执行为实色、信息入口为空底箭头、取消为文本。
- 沿用原稿的紧凑比例：核心物品标题14px、作用12px、核心动作≥12px、分类与数量10–11px；仅GearSlot 只读标签、Profile ID、社交统计标签、集合／图鉴格 caption允许9px。该例外不用于普通正文、核心数量或动作。共享HUD保留ID与属性，使用透明底和独立胶囊。
- 厨房保留原相机1.85倍、锅心约(180,193)、槽位239px、预览292px与抽屉320px。Cookbook25格、旧Experiment20格、P0示例5格保留；实际无库存项显示Not owned并通过Toast解释。没有把整页烘焙为图。
- Bag与厨房筛选只修改本地原型变量的可见性。厨房鱼/香草移除及恢复只更新锅内选择、预览与可用槽数，库存数字保持不变；只有调味时不能开火。
- Show kitchen/Show on map使用只读相机或地图高亮，保留来源的玩家与资源，不把信息入口连接成旅行、采集或已领奖结果。
- 独立结果页区分取包与进食；关闭进入保留结果资源的场景。矿洞Express到达页不会直跳精英战利品。
- 未知拥有量使用中性Required提示；真实0仍为不足，不能用默认值将未知条件画成绿色达成。

`local-validation.json` 记录被验证的准确bundle SHA-256；`package.py`拒绝打包与当前源码不一致的旧验证报告。`source-manifest.json`逐项列出原生模块、数据、场景与构建工具的SHA-256；打包时再次核对全部输入，再读回ZIP中的code.js确认与验证hash一致。`artifact-manifest.json`记录ZIP及每个成员的hash。原生云端的完整截图覆盖与实际原型验收仍以 `cloud/` 的最新记录为准。

## 克隆组件与未知材料状态

本轮真实MCP证据显示，`Component.clone()`可能把新主件放在页面根层，并清空子层的`componentPropertyReferences`。复制后须显式加入原Component Set，使用原owner属性键重绑Title、Value与Icon，再对实例显式设置源字段并回读；不能保留已经错误的默认Timber。`unknown-requirement-fixes.js`已处理这项差异。

`NeedTile/check`表示库存尚未确认，以灰边与灰色`Required ×N`展示，不把未知库存填成0或1。Travel Rations已实际截图核对Travel Permit／Required ×1／护照图标，9条反应不变；原met字段也未变。错误克隆曾被拒绝，最终修复回执与截图见`../cloud/p2p3-visual-review.json`。

## 尚未连线的示例动作

`prototype-gap-ledger.json`按唯一页面／动作／类型／目标合并重复报告，并区分：未模拟的本地控制状态、未作画的同物品结算结果、账户操作、信息入口，以及已经打开当前页的入口。缺少某个示例结果帧不等于玩法规则未定义；它也不授权编造库存、奖励或跨流程重置资源。原型中的这些限制保持显式记录，不能据288张图稿的写入或结构检查声称所有按钮都完成运行级模拟。

实际选材交互、短面板、原相机和资源连续性的云端证据另见上级 `cloud/` 报告。本地离线HTML只用于字段与流程结构检查，未完整同步所有原生视觉精修，不作为最终视觉交付替代。

## 统一 Quick Bar（本轮追加）

所有完整栏统一使用五个 `Compact/QuickSlot` 实例和一个 `Compact/QuickEnd/Bag` 或 `/Close` 实例：行336×68、间距4；场景位置(12,708)，容器保留原起点。Slot52×68内surface52×64，选中上抬4；22px图标、10px两行名称与独立10px数量行。Pin为顶部居中徽标，可与选中态组合；空槽虚线且隐藏图标。Bag容量点只来自明确容量或明确满包状态。

4张Buff的数量依用户要求采用明确设计样例：农耕24/10/6/2，钓鱼12/3/1；来源见 `../data/toolbar-fixture-provenance.json`，不是实时库存。其余原有数量、selected状态及Bag跳转保持原数据。`scenarioChecks.unifiedQuickBar`覆盖40条完整栏，以及5个代表页的数据/布局和两个额外空栏。

## 信息窗的复合组件族

`component-family-fixes.js` 在连线完成后把普通详情与 Pin 上下文统一为 `Overlay/InformationSheet` 实例，把反馈统一为 `Overlay/Feedback` 实例。外层 Frame 继续承担原型目标，因此原链接的 Frame ID 不变；相同布局的 Apple、Carp 等内容不建立物品专属母件或行数变体。

| 修改目标 | 上游组件或变量 |
| --- | --- |
| 信息窗的底色、边框、圆角、整体布局 | `Overlay/InformationSheet`；共享 surface / border / radius 变量 |
| 标题、数量、状态、作用 | 嵌套并暴露属性的 `ObjectHeader` |
| 正文段落的字体与行距 | `Information/Paragraph`，Text 属性，自动高度 |
| 数值、条件、列表项目 | 已有 `Fact` / `Cost` / `NeedTile` / `ItemRow` 实例，放入 Content Slot |
| 信息窗关闭 | 嵌套并暴露属性的 `Dismiss`；每个实例保留原关闭反应 |
| 浮层区块与正文间距 | `space/overlay-block=12` / `space/overlay-body=8` |
| 反馈消息与按钮 | `Overlay/Feedback` 内的 `Toast` / `Dismiss` |

Content 是原生 Figma Slot，支持实际数量的原子行；不用每种物品或每种行数创建母件。Body viewport 在主件上设置垂直滚动、最大高度440与HUG；短内容自然收缩。Info主件 `strokesIncludedInLayout=false`，避免边框额外改变高度。主件直接使用共享视觉变量，不使用不能可靠跟随HUG的绝对背景实例。

Slot 插入可能重新生成后代ID，不能声称这些ID原封不动。源码记录插入前ID与slotOrdinal；MCP迁移须在下一次独立读取中重新定位后代并检查内容和反应。普通正文TEXT改为Paragraph实例也会得到新ID。外层原型Frame、其定时器与显式变量模式保留；Feedback的2.5秒CLOSE仍在外层。14张相机快照与1张教程火候继续使用自己的场景布局。

本地验证逐窗比较可见文本多重集和完整反应列表，并检查Slot、共享主件、暴露关闭属性与稳定外层目标。本地mock不模拟MCP的代理失效和后代重新编号；真实迁移的独立回读与截图以云端记录为准。本地从干净数据新建的浮层数量也不冒充云端已经整理后的存活数量。
