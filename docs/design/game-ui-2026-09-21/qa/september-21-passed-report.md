# Journey UI visual QA · 2026-09-21

final result: passed

本轮视觉与交互验收通过：已把生成目标与最新 Godot / Android 截图放在同一张对照图中，逐项检查字体、间距、色彩、图像和文案。没有尚未处理的 P0 / P1 / P2 视觉问题。原生验证和隔离 HTTP Android 的 29 次真实触控均通过。公开发布、最终签名包和真机覆盖安装由发布 QA 单独记录；本文不以视觉通过代替发布或存档校验。

上一轮报告原文保存在 [previous-design-qa.md](docs/design/game-ui-2026-09-21/qa/previous-design-qa.md)；本次第一轮的原始结论保存在 [round-1-report.md](docs/design/game-ui-2026-09-21/qa/round-1-report.md)。下文保留发现与修正历史，不把最初的 blocked 状态改写为一次通过。

## 目标、状态与归一方法

用户的 [游戏风格参考](docs/design/game-ui-2026-09-21/references/game-style-reference.png) 定义奶油白浮起面板、蓝紫边缘、紫色选中态、青绿主按钮；[背包布局参考](docs/design/game-ui-2026-09-21/references/bag-layout-reference.png) 定义物品详情条、搜索筛选和五列网格。

实际生成目标为 [农场](docs/design/game-ui-2026-09-21/generated/farm-design.png)、[背包](docs/design/game-ui-2026-09-21/generated/bag-design.png)、[次级界面](docs/design/game-ui-2026-09-21/generated/secondary-design.png)。图片来自本轮 Sensenjoy API，资源与尺寸记录在 [assets.json](docs/design/game-ui-2026-09-21/assets.json)。

| 证据 | 原始像素 | 对照尺度与状态 |
| --- | --- | --- |
| 农场、背包生成目标 | 848×1855 | 等比到 360×788；农场步行 HUD、背包选中石料。 |
| 次级生成设计板 | 1448×1086 | 四个 724×543 单格分别等比到 360×270。设计板单格不是完整手机视口，剩余画布留白，禁止纵向拉伸伪造同高。 |
| 最新 Android 截图 | 720×1560 | 观察器记录的逻辑视口为 360×780，按 2:1 等比缩小；没有浏览器边框或 CSS/deviceScaleFactor。使用本轮隔离 HTTP 场景 01–15。 |
| 原生 Godot 图库 | 360×780 | 1:1；补充料理、居民详情、分类/排序菜单、矿井、语音状态和合照。 |
| 窄屏交互图库 | 328×600、360×780 | 1:1；14 张完整交互截图验证五列网格、角色六槽、详情、交易和恢复状态。 |

全部并排图、来源、像素、裁切与 SHA256 见 [comparison-manifest.json](docs/design/game-ui-2026-09-21/qa/comparison-manifest.json)。对照只做等比缩放、明确标注的裁切和留白，没有重绘、替换或拼造实际游戏背景。

## 全图与局部对照

![农场：生成目标与最新 Android](docs/design/game-ui-2026-09-21/qa/farm-comparison-final.png)

![背包：生成目标与最新 Android](docs/design/game-ui-2026-09-21/qa/bag-comparison-final.png)

农场保留顶部信息、独立目标行、右侧在线与真实装扮回位入口、底部三项操作。中央区域继续显示可自由移动的真实 3D 场景。背包按本轮紧凑要求收至约 62% 高度；额外的委托入口、详情信息按钮和真实物品用途仍可达，底部列表滚动显示其余条目。

次级界面完整并排：

- [交易面板](docs/design/game-ui-2026-09-21/qa/secondary-stall-comparison.png)：紫色出售/种子页签、真实物品和价格、固定批量操作。
- [居民委托](docs/design/game-ui-2026-09-21/qa/secondary-request-comparison.png)：现有居民、需求、酬劳和追踪/交付入口。
- [料理面板](docs/design/game-ui-2026-09-21/qa/secondary-kitchen-comparison.png)：真实料理图、材料持有/需求数、缺料禁用状态和制作操作。
- [队伍面板](docs/design/game-ui-2026-09-21/qa/secondary-party-comparison.png)：当前未组队状态、邀请码、组队与矿井/线路操作；已组队与语音状态在原生图库中另有完整滚动证据。

![农场控件局部](docs/design/game-ui-2026-09-21/qa/farm-controls-focused.png)

![背包选中物品、搜索和网格局部](docs/design/game-ui-2026-09-21/qa/bag-selected-focused.png)

![菜单展开状态与概念入口](docs/design/game-ui-2026-09-21/qa/menus-focused.png)

菜单图明确区分目标已有的筛选/排序入口与目标未画出的原生展开状态。实际分类菜单使用蓝色实心勾选和蓝色空心圈；排序菜单是两个即时动作，没有伪造单选状态。

## 第一轮发现与处理

| 级别 | 首轮发现 | 修正与最终证据 |
| --- | --- | --- |
| P2，已关闭 | 小按钮九宫格穿过圆角，拉伸成过长斜边；初步调整切片仍不足以适配 44px 控件。 | 第一轮先调整切片，第二轮进一步从生成素材派生紧凑尺寸，使切片边距小于控件高度的一半。保留原素材轮廓和透明边缘；[首轮对照](docs/design/game-ui-2026-09-21/qa/farm-comparison-initial.png) 与最终 [控件局部](docs/design/game-ui-2026-09-21/qa/farm-controls-focused.png) 可比。 |
| P2，已关闭 | SVG 根节点缺少实际尺寸，原生菜单可能按 256px 源图布局。 | 当时的 59 个图标补齐实际 24×24；最终扩充为 63 个，逐文件检查均为 width=24 / height=24，保留原库 viewBox 与路径。最终 [菜单局部](docs/design/game-ui-2026-09-21/qa/menus-focused.png) 没有巨大图标或被撑开的行高。 |
| 待验证，已补齐 | 其他页面尚未以实际截图及操作验收。 | 十组原生图库共 140 页、290 张当前目录清单中的截图，含完整滚动内容；14 张窄屏交互图以及 Android 的 29 次触控补充真实行为验证。 |

## 第二轮及实机布局问题的关闭记录

| 级别 | 发现、影响 | 修正后证据 |
| --- | --- | --- |
| P2，已关闭 | 选中页签沿用深色 font_color，紫底上文案不清晰。 | 对齐选中态和普通态的颜色键。[修正前后同宽局部](docs/design/game-ui-2026-09-21/qa/selected-tab-history.png) 显示紫底白字、普通页签深字。 |
| P2，已关闭 | PopupMenu 的 native radio 纹理不受普通图标色影响，奶油底上的白圈不清晰。 | 缓存原图标的蓝色调制版本，保留形状/尺寸。[42 分类](output/ui-redesign-2026-09-21/gallery/42-bag-category-menu.png) 与 [43 排序](output/ui-redesign-2026-09-21/gallery/43-bag-sort-menu.png) 最后重拍，extra 组 13 页/17 图无运行错误。 |
| P2，已关闭 | 自动换行提示在宽度确定前保留过大的最小高度，短句或获救提示占据大量场景空间。 | 先设文字可用宽度，再随 minimum_size_changed 回算自然高度。[短提示](output/ui-redesign-2026-09-21/gallery/23-farm-toast.png)、[获救](output/ui-redesign-2026-09-21/gallery/73-mine-rescue.png) 已重拍；[toast 回归](reports/report_1293/results.xml) 2/2 通过。 |
| P1，已关闭 | Android 农场初次进入时安全区还未布局，在线按钮被放到屏外，无法打开队伍。 | 初始延迟布局、监听 root rect 变化，未形成有效安全区时回退视口安全区。[最新 Android 农场](output/ui-redesign-2026-09-21/android/01-farm.png) 和 [队伍](output/ui-redesign-2026-09-21/android/12-party.png) 已验证入口与触控；[在线/矿井回归](reports/report_1294/results.xml) 44/44 通过，包含真实 SafeAreaMargin 的延迟初始化与后续 inset 变化。 |
| P2，已关闭 | 矿井标题省略到“第…”导致当前层数不可读，改换行后背景一度保留旧高度。 | 标题改为 14px 可换行，背景跟随最小高度变化。[矿层截图](output/ui-redesign-2026-09-21/gallery/70-mine-floor-3.png) 完整显示层数，标题卡不再残留空白高度。 |
| P2，已关闭 | 隐藏、挂起或后台状态下，头像预览仍可能启动渲染/异步装配。 | 预览生命周期加入祖先可见性/禁用状态、后台检查及异步代次取消；[头像回归](reports/report_1287/results.xml) 4/4 通过。画面只证明显示结果，停止渲染的结论来自该回归。 |
| P2，已关闭 | 石料用途按钮仅显示目标名“铜镐”，容易误认当前选中物品。 | 改为“去制作”/“去料理”，完整目标保留在既有路由与提示中；[Android 石料详情](output/ui-redesign-2026-09-21/android/05-bag-details.png) 显示新动词，未更改实际用途。 |

![修正后的状态证据](docs/design/game-ui-2026-09-21/qa/final-state-evidence.png)

## 五项视觉一致性检查

| 必查面 | 检查结论与保留差异 |
| --- | --- |
| 字体与排版 | Nunito 750，中文 Noto Sans SC 后备与 0.45 字重补偿；正文/按钮约 14px，标题约 17–24px，小条目 11–12px。全图和局部显示中英文基线、数字与中文换行完整；矿层标题和长状态按实际宽度换行。字形是项目字体，不把生成图中的不确定字形当作可复刻字体文件；对照稿的标题字重/尺寸略夸张，实际按窄屏信息密度收敛。 |
| 间距与布局节奏 | 44px 主要点击目标、52px 农场底栏、背包五列与固定页签/关闭、面板内滚动均稳定。328×600 与 360×780 的库存/角色/交易图未隐藏持续操作；菜单、对话和错误状态有边界内空间。真实 3D 构图、背包约 62% 高度、第三个委托页签及竖屏单列配方是既有功能和紧凑要求的适配。 |
| 色彩与状态 | PAPER #fffdf8、INK #34416f、BLUE #586bd7、VIOLET #9273dd、GREEN #239f9f 已作为统一语义色；奶油面、紫色选中、青绿主行动、数量/不足状态可区分。生成贴图保留渐变与下沿阴影；实际更紧凑的按钮阴影比概念大胶囊更集中，已确认没有切片相交。深色通知配白字；状态不只依赖颜色，还保留文字/数字。 |
| 图像与素材品质 | 面板、按钮和城市背景使用本轮 API 素材及等比派生版本；没有用页面截图覆盖原生界面。63 个 Phosphor 库图标为真实 24×24，保留 Lucide 回退；角色是实际装扮的 3D 预览，农作物/道具采用既有资源。与概念稿的立体插画图标相比，库图标更简洁；这是统一图标库的选择，不声称图案逐像素一致。未见新增透明杂边、变形图像或缺失图标。 |
| 文案与内容 | 使用真实金币、库存、品质、六装备槽、居民与请求。石料按钮明确去制作，料理显示真实材料不足；误操作/未知结果/重连/关闭分支保持。概念稿中的“小田”、示意价格、饭团/烤鱼、音乐/画质设置均没有被误植入游戏；当前队伍保留真实邀请、访问、语音和矿井/线路功能。 |

源稿中的固定人物、屋舍和农田位置不是本次 UI 验收的地图合同。玩家已有地理农场和自由镜头继续有效，角色可以离开画面，点击真实装扮头像回位。料理采用实际已有配方，居民使用原角色，设置只展示已实现功能；这些差异明确保留，不宣称与概念稿完全一致。

## 实际步骤与行为证据

1. 农场与自由镜头：正常。Android 已验证角色离屏后头像回位、步行/种地切换，在线入口保持可见。
2. 背包与人物：正常。选中石料、五列列表、搜索/分类/排序、拖动取消点击、六装备槽及切换入口均有截图与真实触控证据。
3. 摊位与居民：正常。Android 实际购买三颗种子，余额变化来自隔离服务器；委托页、详情和追踪/交付分支保留。
4. 队伍与钓鱼：正常。Android 实际打开队伍、发起服务器钓鱼和进入收线；原生图库补充已组队/语音/确认状态，模态打开时联机徽章隐藏而连接继续。
5. 次级与恢复状态：正常。原生图库覆盖选城、迁居预览/待确认、工作台/料理、矿井、换装、旧界面、合照保存、加载失败、离线和物品暂存。

[Android 结果](output/ui-redesign-2026-09-21/android/result.json) 记录 29 次触控全部通过，公共存档未被测试写入；[godot.log](output/ui-redesign-2026-09-21/android/godot.log) 未发现脚本、解析或着色器运行错误。原生 [14 图交互报告](output/game-ui-2026-09-21/inventory/report.json)、[完整覆盖清单](output/ui-redesign-2026-09-21/coverage.md) 与各 gallery/catalog-*.json 保留完整证据。不同轮次的重复用例不累计为独立新测试。

## 边界与后续记录

- 视觉 QA 已通过；最终无观察器签名包、公开下载校验、真机覆盖安装和原身份/地形/资产比对以发布记录为准，不在本文提前断言完成。
- 原生 macOS MapBridge 不提供 Android 的实际地图底图，因此 native 选址页的底图空白不作为地图渲染验收；对照只用其原生控件，真实地图仍以 Android/真机证据为准。
- 截图不能证明 TalkBack、键盘全路径、系统字体缩放或所有色觉场景合规。本轮验证了所列原生触控、尺寸与文字可读性，没有声称完整 WCAG 验收。
- 引擎退出时的 RefCounted 提示可在仅异步加载 farm.tscn、未创建 UI 的最小场景复现；与本轮节点孤立无关，见 [诊断](output/ui-redesign-2026-09-21/leak-diagnosis.md)。

本轮无需新增视觉修复。后续只补齐最终发布与真机证据；如设备上出现新的实际布局问题，按具体截图重新开启对应项。

最终发布补充：0.16.10 已通过 V2509A 正式无观察器包的地图、农场及背包检查，原账号和当前存档保留，双端下载已验证。实际原生地图证据：[final-map.png](output/ui-redesign-2026-09-21/device/final-map.png)。详见[最终 QA 与发布记录](docs/qa/game-ui-2026-09-21.md)。
