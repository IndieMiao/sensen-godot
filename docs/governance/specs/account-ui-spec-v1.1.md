# 账号与首次打开 · 界面规格 v1.1（不知火舞 2026-11-11；v1.1 按用户 bot 715 / 716 改：条款并进年龄页、Homestead → Home、首启底图另出方案）

> **依据**：诸葛亮方案 v2（〔私有路径〕，含「奕星定 4 处」）；奕星第二轮复核 account-plan-v2-review.md（第 2 节建档改到 NAME、第 4 节补三张系统态页）；decisions-yixing-1111.md；亚瑟技术方案 v1.3；Figma 页面 14 原设计帧（**LOCK-28 以 Figma 为准**，下表写出处帧号）；现行代码 farm-dev d9722030d（p0_age_card / p0_home_welcome / p0_settings_page / p0_profile_page / p0_people_drawer / p0_sys_screen / online_crowd）；已批口径 §10.6.2 / §10.6.4、q(17)、q(28)、q(237)、q(244)、q(274) 补记二、q(281)、q(289)、197 LOCK-22 / LOCK-30。
> **写法规矩**：App 文案一律英文（下文反引号里的）；中文版照 LOCK-23 增补走翻译表。首启几页出在玩家能切语言之前，新装机一律英文。**只写已有的写法能用的就用已有的**：每条新英文在第 9 节列出，标「新」。
> **范围**：只写提审最小集（v2 第 8 节 + 奕星定 ①：顶号这一轮做）。帧由安其拉照第 10 节出，我验收，11-13 随李白 q 行一起报批。


## ★ v1.1 改动（用户 11-11 bot 715 / 716，奕星核过：「同意及隐私条款能否和其他页合并, 加上勾选即同意; 所有homestead 换成home; 其他ok」+「注册的底图换掉」）
### A. 条款并进年龄页（取代 1.4 的单独 TERMS 页；1.1 / 1.2 按本节读）
- **并进年龄页，不并进起名页**。理由：①年龄页只有一个主键，勾选只卡这一个键；起名页有 `Continue`、`Skip for now`、`Sign in` 三个出口，三个都得卡，跳过和登录灰掉或点了弹提示都别扭；②同意在任何建档、登录之前就拿到，起名页的建档、登录直接带上本机记录；③少一页，顺序变成「年龄 + 同意 → 起名」。
- **ACC-AGE 新版式**（同一外壳、同一张卡，从上往下）：标题 `What year were you born?` → 24 → 年份滚轮（不变，138）→ 20 → **勾选行**：24 的勾选框（原设计 ONB-CONSENT 9:119341 那个，默认**不勾**），右边 `I agree to the Terms of Service and Privacy Policy`（原设计原句，Body 14，两个名字是 info 色链接，各自系统浏览器打开；点链接不改变勾选；勾选框连同非链接的字整片可点，点击区 ≥ 44 高）→ 8 → 一行 Caption 12 secondary：`Gensen is an online game with other players. We have zero tolerance for objectionable content or abusive behavior.`（原设计原句，Apple 1.2 要的那句，挪到这里）→ 20 → 主键。
- **主键四态**：没选年份写 `Pick your birth year`（灰）；选了年份、没勾写 `Agree to continue`（灰；原设计 ONB-CONSENT 的原句）；都有了写 `Continue`（亮）。先年份后勾选，按这个顺序写差什么。
- 点 `Continue` 照旧出确认卡 `Born in 2001?`（`Yes` / `Change`）；过了 → NAME；没过 → AGE-BLOCK（本机不记同意，什么都不发）。`Change` 回来勾选保持。
- 原 TERMS 页的第二段 `Names or behavior that break the rules can be reset, muted or suspended.` **去掉**（条款正文 §6 已写处置；页上留 Apple 要的零容忍那句就够）；`Agree and continue` 这句也不再用。新英文少 2 句，多用 1 句原设计的 `Agree to continue` 和 `I agree to the Terms of Service and Privacy Policy`（都是原设计句，不算新）。
- **老号**：语音卡过了年龄门、跳过年龄的那批，进一张只有同意的卡（同一外壳）：标题 `Before you start`（原设计）→ 零容忍那句（Body 14）→ 勾选行同上 → 主键没勾 `Agree to continue`（灰）/ 勾了 `Continue`。其余老号走新版年龄页。
- 帧：ACC-AGE 改三态（未选 / 选了没勾 / 都有）+ 老号同意卡 ACC-CONSENT-OLD；ACC-AGE-CONFIRM 背后换成新版式；原 ACC-TERMS 634:197085 作废（Superseded，留在 row 155 备查）。
### B. Homestead → Home（照 q(306)（用户 11-10，0.3.5，SGODOT-461），用户 715 ② 重申；李白盘点：游戏里玩家看得到的英文早已没有 Homestead，只有佛罗里达真实城市 Homestead 保留，不另起 q 行）
- 本规格里 `Homestead Lv6 · Last played 3 days ago` → `Home Lv6 · Last played 3 days ago`；删号第 2 页 `Your Homestead Lv6, …` → `Your Home Lv6, …`。
- 帧里看得到的 Homestead 一律照 q(318) 的写法换：位置芯片 `San Francisco · Homestead` → `San Francisco · Home`、地上名牌 `Homestead Lv1` → `Home Lv1`、个人页农场卡 `Farmer's Home`（q(306) ① 已定，中文「农夫的家园」）。涉及帧：ACC-DELETE-2 641:197438、ACC-CONFLICT 641:197383、ACC-LINK-ASK 650:197840、ACC-NAME-RESET 653:198694、PROFILE-1-EDIT 643:197324 / ACC-RENAME 644:197332（农场卡）。改前图（实拍）不改。
### C. 首启 / 注册页底图换掉 —— **定稿：方案 3 品牌米色**（用户 11-11 16:35 bot 728「注册底图3」，奕星核过）
- **定了的做法**：ACC-SHELL 外壳（首启年龄 / 没过 / 起名 / 登录 / 没找到农场、老号同意卡、已退出页、系统态 SESSION / CLAIMED / DELETED / SUSPENDED）底图一律换成方案 3：整屏 `#F6F4EA`，最下面约 20% 渐变到淡绿（像地平线），不放场景、不放人物；上面照旧 `Gensen` 字标（自带小芽苗，不另加）。素材：上官婉儿 〔私有路径〕（实现直接用这张，宽铺满、底对齐；长屏顶上同色延伸，不露边）。定稿帧：Review row 159 方案 3 列 661:199003（年龄）/ 661:199027（起名）/ 661:199048（长屏）。
- **定稿数**（从 scheme3 原图逐行取色，360×800 坐标）：y 0–632 整片 `#F6F4EA`；y 632 → 屏底 **直线渐变**到 `#D6E6BE`（不透明，不叠透明度；渐变高 168，约占屏高 21%）。长屏：渐变**跟屏底走**，高度固定 168（按宽度比例，不按屏高比例），上面多出来的部分就是 `#F6F4EA`。外壳背后不再用 surface，整屏是这个底。卡片照旧：surface `#FBF8F1` + 描边 + 阴影，不变。实现用图或用代码画渐变都行，结果要和这组数一样。
- **范围**（11-11 用户 bot 733「系统页也换」；奕星 735 向用户更正范围，以此为准）：首启 / 注册几页 + 账号系统态四页（SESSION / CLAIMED / DELETED / SUSPENDED）+ 已退出页 + **SYS-MAINT、SYS-UPDATE**（这两页原来用的就是被换掉的插画农场）。**不换**：SYS-LOADING-FAIL（`Can't connect`，垫的是 q(290) 用户定的启动图 + 遮罩）、PLACE_FAIL（`Couldn't get there`，垫的是 11-06 用户定的城镇地图 + 遮罩）、LAUNCH 启动图、SCENE 换场景过场。这几种用的都是用户另外定过的画面，不是被嫌弃的那张，所以不扩大。FAIL 也不加字标。sys_backdrop_farm.jpg 已经没有地方用（哪吒 4b2d9e53d 删掉了）。
- ~~两套底图并存~~：用户 bot 733 定「系统页也换」，不再并存（先前「维护页用启动图」的判断有误，已更正）。
- rows 155 / 156 / 158 里其他首启和系统态帧还画着旧的插画农场底图，**底图一律以方案 3 为准**，卡片和内容照那些帧，不重画。
- 旧底图 `sys_backdrop_farm` 已不再使用（bot 733，哪吒 4b2d9e53d 删掉了）。
- 以下是选之前的方案说明，留着备查：

- 范围：首启几页（年龄、没过、起名、登录、没找到农场）和系统态四页（同一外壳）。卡片、字标位置不变，只换底图。
- **硬约束**：年龄页之前一个请求都不发（q(312)），所以底图必须**打包在包里的静态图**，不能用要联网的地图瓦片；三种底色下卡片字都要清楚；360×800 和 iPhone 长屏都要不露边。
- 方案（安其拉出对照帧，上官婉儿出美术判断和素材，我验）：
  1. **接着启动图**：用 q(290) 用户定的启动图（launch_splash），压淡 / 虚化做底，从启动到首启画面不跳。
  2. **游戏内 3D 实拍**：自家农场（或塘边）的真机渲染实拍，静态打包，上方渐隐给卡片让位；和进游戏后看到的是同一个世界。
  3. **品牌纯色**：地色 `#F6F4EA`（HOME-WELCOME 同款）+ 字标 + 一个小芽苗点缀，不放场景。
- 每个方案出两帧：年龄页（新版式）+ 起名页，三个方案并排拼一张，配一句各自的好坏；长屏 iPhone（19.5:9）各一张确认不露边。
- **推荐（11-11 看过上官婉儿 mk_013 后改）：方案 2 农场那张**（盘古出 scheme2_farm / scheme2_pond，Metal 1080×2400，不放人物，主体在下半屏、上半屏渐隐），用户嫌的是「和游戏不是一路」，实拍就是马上要玩的那块地；**备选方案 3**（最干净、字最清楚）。方案 1 不推荐：启动图下半是一张大自拍脸，虚化后糊脸压在卡片底下，只能做到不脏。素材 〔私有路径〕。

---

## 0. 总的做法（先看这 6 条）
1. **首启几页共用一个外壳 ACC-SHELL**，照原设计 ONB-AGE-2 9:119318 / ONB-CONSENT 9:119341 / ONB-NAME 9:119537：上面 `Gensen` 字标（UiWordmark，y 84），下面衬农场插画渐隐（和 SYS 系统态同一张底图 `sys_backdrop_farm`），中间一张卡（左右各 16、宽 328、顶 y 170；**圆角 24；从卡外沿量，内容离左右 21、离上 25、主键下沿离卡底 21，照原帧 ONB-* 的数**（帧里是 pt 24 / px 20 / pb 20 加 1 px 描边；11-11 验收时定，哪吒量过，原写 20 / 20 作废）；底色 surface + 描边 + 阴影）。卡里：标题 Title XB20 → 正文 Body 14 secondary → 内容 → 主键（48 高）。**没有 HUD、没有 ×**，安卓返回键在首启几页不退出页面（AGE 回到桌面，同现在冷启动）。系统态的新页（第 6 节）也用这个外壳，和现有 SYS-SESSION 9:119672 一个样子。
2. **主键灰着时写还差什么**（照原设计 ONB-NAME `Enter a name`、REPORT-1 `Choose a reason`，和 q(28) 的「按钮句式：动作 · 差什么」同一路子），能点时写动作。
3. **确认用卡，不用整页**：生日确认、退出登录、绑定冲突都用现有确认卡（BLOCK-CONFIRM 9:108492 的样子：标题 + 正文 + 主键 + 次键 `Cancel`，压在 scrim 上）。
4. **提示用现有 toast**（ToastLayer Info，落在快捷栏位置），不新起组件。
5. **名字显示一律不带代号**（v2 §8：4 位代号放提审后）。默认名照现在 `Traveller 8c3f`。
6. **商店版**（Play + App Store / TestFlight）隐藏：Settings 的 `Test options` 组整组不出；牌室整个地点不出（v2 §10 清单）；Voice Profile 卡不出（若二批 #7 批「所有包都藏」则 OSS 包也不出）。藏了的东西**不留空位**，下面的块直接上移，间距照页面原规矩。

---

## 1. 首次打开（新装机）
顺序：启动加载 → **AGE**（→ 确认卡）→ 没过：**AGE-BLOCK**；过了：**TERMS** → **NAME**（或 Sign in）→ 选家城 HOME-WELCOME（照现在）→ 大头针 → 新手引导。
建档在 NAME 点主键或 `Skip for now` 之后（奕星复核第 2 节：技术方案的 `session/guest` 挪到 NAME）。AGE、TERMS 只记在本机。

### 1.1 AGE · 出生年份（帧 ACC-AGE，从 ONB-AGE-2 9:119318 改）
- 标题 `What year were you born?`（**沿用语音年龄卡的问句**，p0_age_card.gd `QUESTION`）。不写年龄要求、不写为什么问。
- 原设计是月 / 日 / 年三个滚轮，**改成一个年份滚轮**（用户 11-02「只看年份」）：照语音年龄卡 V5 的滚轮（383 50108c43）——从今年往下 100 年，打开时停在今年、**什么都没选**；中间一格 primary-tint 带、XB20，两边各两格渐隐（55 % / 30 %）；滚轮宽同卡内宽。拖停、点一格、鼠标滚都算选。
- 主键：没选时灰、写 `Pick your birth year`（原设计 ONB-AGE 写 `Pick your birthday`，只有年份，改一个词）；选了写 `Continue`。
- 卡高照内容：标题 → 24 → 滚轮（**WHEEL_H = 138**，按 p0_age_card 实算：带 40 + 2 ×（26 + 23））→ 24 → 主键。打开时今年在带上，上面是前两年，下面空（今年以后没有年份）。

### 1.2 生日确认卡（帧 ACC-AGE-CONFIRM）
- 点 `Continue` 后，对**所有答案**都出同一张确认卡（v2 §1.1 2a：只防手滑，不因答案不同而不同）。
- 标题 `Born in 2001?`；没有正文；主键 `Yes`、次键 `Change`（描边，同 BLOCK-CONFIRM 的 `Cancel` 位置）。`Change` 关卡、滚轮停在刚才那年。
- 点 `Yes`：过了 → TERMS；没过 → AGE-BLOCK。中间不出 toast、不出加载。

### 1.3 AGE-BLOCK · 没过（帧 ACC-AGE-BLOCK，从 ONB-AGE-NO 9:119332 改）
- 标题 `Sorry, you can't play Gensen.`（原设计写 `create an account`；老号也会落到这一页，他们已经有农场，改成 play。**新**）
- 正文 `Thanks for your interest in Gensen.`（原设计原句）。
- 下面一条文字链接 `Privacy Policy ›`（Settings › Legal 的同一种链接，info 色；系统浏览器打开 q(281) 的网址）。
- **没有按键、没有返回、不能重答**；本机记「没过」，以后打开都直接停在这一页（不连服务器）。不写数字、不写 13（因为按「今年 − 出生年 ≥ 14」判，2013 年出生、已满 13 岁的人也会落到这里）。
- 老号（第 5 节）答「没过」：同一页；**存档只挡不删**（奕星：等用户回二批 #3 再定）。

### 1.4 TERMS · 同意条款（帧 ACC-TERMS，从 ONB-CONSENT 9:119341 改）
- 标题 `Before you start`（原设计）。
- 正文两段（Body 14，段距 8）：
  1. `Gensen is an online game with other players. We have zero tolerance for objectionable content or abusive behavior.`（原设计原句；Apple 1.2 要的那句）
  2. `Names or behavior that break the rules can be reset, muted or suspended.`（**新**；v2 §1.1 第 4 步「违规的名字和行为会被重置、禁言或停用」）
- 两行链接（原设计）：`Terms of Service ›`、`Privacy Policy ›`，各一行 44 高，info 色 Bold 15，› 靠右；系统浏览器打开（条款 gensen.app/terms、隐私 q(281) 的网址）。
- **去掉原设计的勾选框**，主键直接写 `Agree and continue`（**新**；原设计是「勾选 → `Agree to continue` 变 `Continue`」两步）。理由：按键文字本身就是同意动作，少一次点；也没有预先勾好的框（v2 §1.1）。主键常亮。
- 本机记条款版本。

### 1.5 NAME · 起名（帧 ACC-NAME / -ERR / -KEYBOARD，从 ONB-NAME 9:119537、ONB-NAME-2 9:119549 改）
- **去掉原设计左上的 ‹**（前面两页已经过了，没有可回的）。
- 标题 `What should we call you?`；正文 `Shown to other players. You can change it every 7 days.`；字段标签 `Name`；输入框占位 `Your name`；框下说明 `2–16 letters or numbers`（以上都是原设计原句）。
- 主键三态：空 / 长度不够时灰、写 `Enter a name`；校验不过时灰、写 `Try another name`（原设计 ONB-NAME-2）；能用时写 `Continue`（**沿用** AGE 页）。点了先走不建档的校验接口，过了才建档；校验中主键灰着、字不变，不加转圈（一般 < 0.5 s；超时走 SYS-CMD-FAIL toast，见 1.7）。
- 框下说明的三种红字（Caption 12，color/danger，替换灰字那一行，不加行）：
  - 长度不对：`2–16 letters or numbers`（原句变红）
  - 有不能用的字（表情、`@`、`#`、`/`、`:`、看不见的字符等）：`That character can't be used`（**新**）
  - 词库 / 冒充 / 混用字母表：`That name isn't allowed`（原设计 ONB-NAME-2，不加句号、不说是哪个词）
  - 输入框描边同时变 danger；改动一个字就恢复灰字和正常描边，主键回到对应态。
- 主键下面一行文字键 `Skip for now`（**新**；UiDismissButton，居中，44 高，同 `Return to main account` 那种）：直接建档，用默认名 `Traveller 8c3f`。跳过的号**第一次改名不算冷却**（奕星复核第 4 节建议，进最小集）。
- 卡最下面，隔一条 1 px 分隔线，一行 `Already have a farm? Sign in`（**新**；`Already have a farm?` Body 14 secondary + `Sign in` info Bold，整行 44 可点）→ 1.6。**老号（第 5 节）不出这一行。**
- **键盘**：进页不自动弹键盘（先让玩家看到全部选项）；点输入框才弹。键盘起来时：字标淡出，卡整体上移到「主键下沿离键盘上沿 12」，`Skip for now` 和 Sign in 那行可以被键盘盖住（打字时用不到）；键盘收起后回原位。动效同 MOTION_DRAWER_MS 250 ms ease-out。键盘的回车 = 主键。
- 输入框：一行，最多接受 16 个字形（按字形簇算，超了不再进字），不自动大写首字母以外的改动，关自动更正。

### 1.6 Sign in（帧 ACC-SIGNIN-iOS / -Android / ACC-NOFARM，从 ONB-SIGNIN 9:119464 改）
- 同一外壳，卡左上加 ‹（44，回 NAME；安卓返回键同）。标题 `Sign in to your farm`（原设计 `Sign in to start your farm`，这里是找回已有农场，改两个词；**新**）。
- 键（原设计样式，48 高、间距 12）：iOS `Continue with Apple`（黑底白字，在上）、`Continue with Google`（描边，G 标）；安卓只有 `Continue with Google`。**去掉原设计的 `Continue with Email`**（D2 不做邮箱）。Apple 键不比 Google 小、不在后面（HIG）。没有 Google Play 服务的安卓机：不出 Google 键，卡里只写一句 `Sign-in isn't available on this phone.`（**新**）。
- 点键 → 系统登录框。取消登录 → 回到这张卡，不提示。
- **找到农场**：盖加载层（SYS-LOADING）直接进那个农场，跳过选城、大头针、引导；本机的年龄、条款一起写进那个号，不再出 TERMS（奕星复核第 2 节）。
- **没找到**（帧 ACC-NOFARM，同一外壳的卡）：标题 `No farm found`（**新**）；正文 `This Google account has no farm yet.`（Apple 时写 Apple；**新**；11-11 验收时改短：原句在 286 宽下第二行只剩 `yet.`）；主键 `Start a new farm`（**新**）→ 回 NAME，建档后自动绑上这个账号，绑上后出 toast `Linked with Google`（5.2 同一句）；次键 `Try another account`（**新**）→ 回登录卡。
- **待绑凭据过期**（奕星复核 B-6）：没找到农场 → `Start a new farm` → 在 NAME 停了超过 10 分钟才点主键，服务端回 `pending_expired`：回到 1.6 的登录卡，出 Info toast `Sign-in expired. Please sign in again.`（**新**）。NAME 里打的名字本机先留着，重新登录、再走到 NAME 时预填。不用 SYS-CMD-FAIL 的连网句（不是网的问题，写成连网失败会误导）。
- **查询失败**（网络、服务端）：照现成 SYS-CMD-FAIL 的 toast，**不写成「没找到」**（q(207) ④）。

### 1.7 断网
- AGE、TERMS 不连网。NAME 的校验和建档、登录要连网：失败时照现成 SYS-CMD-FAIL toast（`Check your connection and try again.` 系列），留在原页、主键恢复可点；不另做断网页。首次冷启动就连不上的照现在的 SYS-LOADING-FAIL `Can't connect`。

---

## 2. 设置（照 §10.6.4 已批分组；P0 现行顺序上加东西，不重排已批的）
P0 主页从上到下：**Account（新，最上）** → Home city（照旧）→ Notifications（照旧，q(237)）→ General（`Language ›` 照旧 + **`Help and feedback ›` 新行**）→ Test options（照旧；**商店版整组不出**）→ Privacy（照旧）→ Legal（**加 `Terms of Service ›` 为第一行**，其余照 q(281)：Privacy Policy → Licenses → Version → Support code + 卡下说明）→ **`Sign out`（只在绑了账号时）** → **`Delete account`**。
帧：ACC-SETTINGS-GUEST、ACC-SETTINGS-LINKED（各要整页滚到底一张），参照 SETTINGS-1 9:108154、SETTINGS-1-2 9:119938。

### 2.1 Account 组（组名 `Account`，原设计）
- 一行 UiSettingRow LINK，整行进 ACC-ACCOUNT（2.2）：
  - 游客：行名 `Playing as a guest`（**新**），副行 `Link an account to keep your farm`（**新**），›。
  - 绑了：行名照原设计 `Signed in with Apple` / `Signed in with Google`（都绑了写 `Signed in with Apple and Google`，**新**）；**不写邮箱**（不存邮箱；§10.6.4 补注），没有副行，›。
### 2.2 ACC-ACCOUNT · 账号页（从 SET-ACCOUNT 9:119958 改）
- 顶栏 ‹ `Account`（原设计）。
- 绑了的：组名 `Signed in with`（原设计），卡里每个已绑一行：左 `Apple` / `Google`，右灰字 `Signed in`（原设计；原设计的邮箱副行去掉）。**没有解绑键**（奕星定 ②）。
- 还能绑的：组名 `Add a sign-in method`（原设计），下面按平台给键（描边 48，间距 12）：iOS `Continue with Apple`、`Continue with Google`；安卓 `Continue with Google`。原设计写 `Add Google` / `Add Email`：Email 去掉；Apple 键按 HIG 只能用「Sign in / Sign up / Continue with Apple」，所以两键都写 `Continue with …`。都绑了就不出这一组。
- 键下说明（Caption 12 secondary）：游客写 `Link an account to get your farm back on a new phone.`（**新**，v2 §5.1）；绑了一个还能绑写原设计 `Another way in, so you never lose your farm.`；iOS 只绑了 Apple 时再加一句 `To play on Android too, add Google.`（**新**；另起一行，不接在上一句后面）。
- 绑定成功：页面就地刷新 + toast `Linked with Google`（**新**）。取消：不提示。失败：SYS-CMD-FAIL toast。
- **绑定冲突**（这个外部账号已经有别的农场；帧 ACC-CONFLICT，确认卡）：标题 `This Google account already has a farm`（**新**）；正文一行那个农场的简况 `Home Lv6 · Last played 3 days ago`（**新**；v1.1 照用户「所有 homestead 换成 home」，即 q(306)；原 `Homestead Lv6` 照位置芯片 / 农场卡的叫法，时间照 q(28) `Last seen` 的写法换成 played）；眼前的农场没绑任何账号时，再加一行 danger 色 `This farm isn't linked. Switching deletes it.`（**新**；11-11 验收时改短：原句第二行只剩 `deleted.`）；主键 `Switch to that farm`（**新**；有红字那行时主键用 danger 色，同 BLOCK-CONFIRM 的 `Block`）；次键 `Cancel`。切走：盖加载层进那个农场。不合并两个农场。
### 2.3 Help and feedback（从 SET-HELP 9:120076 改）
- General 组 `Language ›` 下面一行 `Help and feedback ›`（§10.6.4 已批的行）。子页顶栏 ‹ `Help and feedback`，P0 只一行 `Contact us` / 副行 `Opens your email app` ›（原设计；`Send feedback` 那行以后做，P0 不出，不画灰）。
- 点了打开系统邮件：收件人 = 对外支持邮箱（二批 #6 定，推荐 support@gensen.app）；主题 `Gensen support · AB12C-3DE45`（支持码）；正文预填三行 `Support code: …` / `Version: 0.3.9 (…)` / `Phone: iOS 18.6`（或 `Android 14`），下面空两行给玩家写。没有邮件 App：toast `No email app found. Email us at support@gensen.app`（**新**）。
### 2.4 Legal 加一行
- `Terms of Service ›` 放 Legal 第一行、`Privacy Policy ›` 之前（原设计 SETTINGS-1-2 的顺序）；同 Privacy Policy 那一行的样子（P0 现在**不带** `Opens in your browser` 副行，两行一致都不带）。网址上线前不出（同 q(281) ①）。
### 2.5 Sign out（只在绑了账号时）
- 照原设计 SETTINGS-1-2：Legal 下面 24，描边大键 `Sign out`（48 高、整宽），下面 12 是 Delete account 卡。游客整个不出（§10.6.4 补注：游客退出就回不来）。
- 点了确认卡（帧 ACC-SIGNOUT）：标题 `Sign out?`（**新**）；正文 `You can sign in again with Apple.`（按绑了的写 Apple / Google / `Apple or Google`；**新**）；主键 `Sign out`、次键 `Cancel`。
- 退出后：ACC-SHELL 的「已退出」页，照原设计 SYS-SESSION-2 9:119679：标题 `You've been signed out`、正文 `Please sign in again.`、主键 `Sign in`（→ 1.6 的登录卡）；**加一个次键 `Start a new farm`**（**新**，同 1.6）→ NAME（本机年龄、条款已过，不再问）。
### 2.6 Delete account（两步，照原设计 SET-DELETE-1 / -3；去掉 -2 的重新登录）
- 主页最下面一张卡（原设计）：一行 danger 色 `Delete account`，副行 `Deletes your farm, items and progress`，›。游客也有。
- 第 1 页 ACC-DELETE-1（9:120113）：顶栏 ‹ `Delete account`；标题 `Delete your account?`；正文 `Your farm, items, coins and progress will be deleted. This can't be undone.`（原句去掉 `friends`，P0 没有好友）；绑了 Apple 的再加一句 `Gensen will also lose access to your Apple ID.`（**新**）；danger 主键 `Continue`；下面文字链接 `Keep my account ›`（原设计；= 返回）。
- 原设计第 2 页「Confirm it's you · 重新登录」**不做**（技术方案撤销 Apple 授权用绑定时存的 refresh token，不用再登录）。
- 第 2 页 ACC-DELETE-2（照 9:120133）：标题 `Delete your account for good?`（原设计 `Delete Lin's account for good?`，名字可能是 `Traveller 8c3f`，读着别扭，去掉名字）；正文写这个号实际有的：`Your Home Lv6, 230 coins and 19 bag items will be gone.`（原设计句式；数为 0 的项不写；只剩农场时写 `Your Home Lv1 will be gone.`）；danger 主键 `Delete my account`；文字链接 `Keep my account ›`。
- 点了：主键灰 + 转圈不超 3 s；成功 → 首启从 NAME 开始（本机年龄、条款已过），新游客号；失败 → SYS-CMD-FAIL toast，留在这页。冷静期：等用户回二批 #2，推荐立即删，本规格按立即删写。

---

## 3. 个人页 · 名字与 `Edit`（LOCK-22 照旧，不复议）
- 名字：显示玩家起的名字（现在写死 `Farmer`）。名字和称号那一行照 q(180) ④ 的排法和截断（名字不截，先截称号；极端名字才截名字末尾）。
- **加回 `Edit ›`**：照原设计 PROFILE-1 9:108063——名字那一行最右边，右距 16，info 色 Bold 12 `Edit ›`，点击区 44 高、≥ 44 宽。称号的可用宽度相应减去 `Edit ›` 的宽 + 12。它和形象右下的 `Edit look ›` 靠位置分开（一个在形象区、一个在名字行），文案照 LOCK-22 不改。
- 点 `Edit ›` → 底部抽屉 ACC-RENAME（UiDrawer）：标题 `Edit name`（**新**）；`Name` 标签 + 输入框（预填现在的名字，光标在末尾，键盘自动弹）；说明 `2–16 letters or numbers · You can change it every 7 days`（两句原句合成一行）；三种红字同 1.5；主键 `Save`（**新**；没改动时灰、写 `Save`），次键 `Cancel`。存了：抽屉收起，名字就地更新，toast `Name saved`（**新**）。
- **冷却中**点 `Edit ›`：不开抽屉，Info toast `You can change your name again in 5 days`（**新**；剩余时长按天**向上取整**，剩 ≤ 24 小时一律写 `in 1 day`，不用 `tomorrow`：剩 2 小时写 tomorrow 可能其实是今天；11-11 奕星复核 D-4）。`Edit ›` 本身不变灰（照 §10.6.2 的「常显」）。
- P0 个人页的签名、可复制 ID 继续不出（P0 没数据；不是去掉锁定项，见 7.2 说明）。**支持码不上个人页**（q(281) ②，只在 Legal）。

---

## 4. 名字在别处的显示
| 位置 | 规则 | 帧 |
|---|---|---|
| 头顶名牌（Label3D，LOCK-07 / q(274)） | 显示名字，不带代号。**最宽不超过默认名 `Traveller wwww` 画出来的宽**（取默认名里最宽的情况），超了末尾 `…`。这样起了名的人不会比现在更挤（q(311) ⑤ 名牌会叠，那次照实接受的是默认名的宽） | ACC-NAMEPLATE（16 个汉字名、16 个 W） |
| 「这一层的人」抽屉行（q(289)） | 名字 XB15 占满左边，**超了末尾 `…`**（现在是硬裁 clip_text，改成省略号）；Mute / Block / Report 三键宽度不让。自己那一行同样规则，`You` 不让 | ACC-DRAWER-LONG |
| 确认卡标题 `Block <name>?`（q(274)）、举报抽屉标题 `Report <name>` | 标题一行；放不下时**只截名字**、末尾 `…`，`?` 保留（照 P0Titles.fit 的做法：先算固定部分宽，剩下给名字） | ACC-BLOCK-LONG |
| Settings › Blocked players 子页（BP1） | 写对方**现在的名字**（服务端给什么写什么；被重置过就是默认名）；一行放不下末尾 `…`，`Unblock` 键和 `Blocked Oct 7` 不让（同抽屉行；奕星复核 C-1） | — |
| 语音说话时的绿名 | 同名牌 | — |
| 农场名 | 照旧 `Farmer's Home`，不跟名字变（v2 §4.2） | — |
- **验收量法**：一律按画出来的样子量（同 q(311) 口径），用 16 个 `W` 和 16 个汉字（中文走 NotoSansSC Regular 回退）各出一张。

---

## 5. 老玩家第一次打开新版
- 认领 token 期间照现在的启动加载层。然后：**AGE**（语音年龄卡答过「过」的跳过；答过「没过」的直接 AGE-BLOCK，只挡不删）→ **TERMS** → **NAME**（同 1.5，**不出 Sign in 那一行**；`Skip for now` 保留现在的默认名，第一次改名不算冷却）→ 直接进农场（不走选城、引导）。
- 进了农场，出一次「绑定提醒」（6.6）。

---

## 6. 系统态与处置（新增四张页 + 两种提示）
外壳同 ACC-SHELL（字标 + 插画底 + 卡），照原设计 SYS-SESSION 9:119672 的样子：卡里上面一个 64 圆底图标（primary-tint 底，照原帧 SYS-SESSION 的数；11-11 验收时定，原写 56 作废）、标题 Title XB20 居中、正文 Body 14 secondary 居中、主键。整屏、接所有点击、没有 HUD、没有 ×；出现时停掉所有请求（技术方案：401 / 403 不算断网，不进 SYS-OFFLINE 的重试）。
### 6.1 顶号 · SYS-SESSION（照原设计 9:119672，奕星定 ①）
- 标题 `Signed in on another device`、正文 `You've been signed out here.`、主键 `Sign in`（都是原设计原句）→ 1.6 登录卡。技术方案里写的 `Your farm is open on another phone.` / `Sign in again` 是占位，**以 Figma 原句为准**（LOCK-28），不另起。
### 6.2 认领冲突 · SYS-CLAIMED（409，帧 ACC-CLAIMED，奕星复核第 4 节）
- 老号第一次升级时，这个号已经被别的手机认领过（如 iCloud 恢复、换机拷数据）。
- 标题 `Farm open on another phone`（**新**；11-11 验收时改短：原句第二行只剩 `phone`）；正文 `Sign in with the account you linked, or contact us with your support code.`（**新**）；下面一行支持码 `Support code AB12C-3DE45`（Caption 12 secondary，整行点按复制，toast 照 q(281) `Support code copied`）；主键 `Sign in` → 1.6；次键 `Contact us` → 2.3 的邮件；再下面文字键 `Start a new farm` → NAME（本机先补 AGE、TERMS）。
### 6.3 号在别处被删 · SYS-DELETED（401 account_deleted，帧 ACC-DELETED）
- 标题 `This account was deleted`（**新**）；正文 `You can start a new farm on this phone.`（**新**；11-11 改：原句「在另一台手机或网页上删的」覆盖不到「Apple 账号被删 → 只绑 Apple 的号照删」，不列原因，只说能做什么；奕星复核 D-10）；主键 `Start a new farm` → NAME（本机年龄、条款已过不再问）。没有登录键（号已经没了）。
### 6.4 停用 · SYS-SUSPENDED（403 suspended，帧 ACC-SUSPENDED / -PERM）
- 有期限：标题 `Account suspended`（**新**）；正文 `You can play again on Nov 20.`（**新**；日期照游戏里现有的 `Oct 2` 写法，按手机本地时区）。
- 永久：标题同上；正文 `This account can't be used anymore.`（**新**）。
- 两种都有：支持码一行（同 6.2，可复制）；主键 `Contact us`（2.3 的邮件）。没有别的出口（停用期间打开就是这一页）。到期后下次打开照常进。
### 6.5 系统态优先级（改 §10.7 的表，李白起 q 行）
`SYS-UPDATE > SYS-MAINT > SYS-DELETED > SYS-SUSPENDED > SYS-SESSION > SYS-CLAIMED > SYS-LOADING > SYS-OFFLINE > SYS-CMD-FAIL > Toast`
理由：删号是终态，压过一切（除了要先更新才认得新错误码的强更和维护）；停用压过顶号（在哪台手机都进不去）；认领冲突只在启动时出，排在 SESSION 后。AGE-BLOCK 不在表里：它在一切网络请求之前，本机直接出。
### 6.6 绑定提醒（帧 ACC-LINK-ASK，SoftPrompt，同 NOTIF-ASK）
- 文案：标题 `Keep your farm safe`（v2 §6 原句，**新**）；正文 `Link an account to get your farm back on a new phone.`（同 2.2 游客说明）；主键 `Link account`（**新**）→ ACC-ACCOUNT；次键 `Not now`（照 q(236) 现有）。
- 只给游客；每台设备每个号只出一次；`Not now` 之后不再出（Settings 照样能绑）。
- 时机和收起规则照 q(236) ④ / q(237) ③，**但不要「田里有在长的作物」那一条**（绑定和作物无关；11-11 奕星复核 D-1）：在自己农场室外、手指都抬起、没有面板 / 卡片 / 对话三条齐了就出；被打断只收起、不记已问。
- **一次运行只出一张软提示**：新玩家引导结束那次运行出通知软提示（q(235)，照旧），绑定提醒等下一次打开、条件满足再出；老玩家更新后第一次进农场就出绑定提醒，通知软提示照它原来的规则排到之后。
### 6.7 处置的两种提示
- **禁语音**（安卓；iOS 语音进提审包就两端）：麦克风键照常位置，画成灰（disabled 态，同年龄门以前没开的灰键）；点了 Info toast `Voice chat is off for you until Nov 20.`（v2 §7 原句，**新**）；永久写 `Voice chat is off for you.`（**新**）。人数胶囊、抽屉照常（还能 Block / Report）。
- **名字被重置**：下次打开、进入第一个场景后，一张确认卡（只一个主键）：标题 `Your name was reset`（**新**）；正文 `It didn't follow our rules. You can choose a new name on your profile in 7 days.`（**新**）；主键 `OK`。只出一次。
- **禁进多人地点**：不做（v2 三种；奕星复核建议苏烈 PR1 拿掉）。

---

## 7. 举报原因单（李白起新 q 行，推翻 q(274) 补记二「不选原因直接 toast」）
- 入口照旧：「这一层的人」抽屉每行 `Report`（两端，q(309)）。
- 点了出底部抽屉 ACC-REPORT（从 REPORT-1 9:108351 改）：标题 `Report <name>`（截断照第 4 节）；原因单选，每行 52 高、左圆圈；下面一行说明 `Reports are private. <name> won't know it was you.`（原设计原句，Caption 12 secondary；名字截断同标题）；主键没选时灰 `Choose a reason`，选了 `Submit report`（都是原设计 / q(28) 现有）；右上 Close 44。
- **原因用 q(28) 已批的那套、按入口给子集**（不用 v2 新列的 6 个，免得新起英文）：抽屉入口给 5 个——`Offensive name or bio`、`Harassment`、`Offensive voice chat`（这个地点开着语音、**而且这台手机能用语音**（麦克风键显示着）时才出；iOS 提审包带语音就两端一样，不带就 iOS 不出；不看被举报人开没开过麦；11-11 奕星复核 D-8）、`Cheating or bots`、`Something else`。（v2 的 `Hate or threats` / `Sexual content` 归在 `Harassment` / `Offensive …` 里；要拆细由用户在 q 行里定。）
- **去掉原设计的 `Community Guidelines ›` 行**（P0 没有单独的守则页；条款在 TERMS 已看过）。
- 提交后：抽屉收起 + Info toast `Report sent`（q(274) 现有），**不出 REPORT-1-DONE 结果卡、不顺手提示屏蔽**（q(274) 补记二照旧）。同一个人再点 `Report`：不开抽屉，toast `You already reported this`（现有）。

---

## 8. 和已批口径的关系（我在 197 发的复议 / 说明；李白的 q 行另起）
### 8.1 复议 · LOCK-30 增补（年龄门挪到首次打开）——随账号方案报批
- 原锁（11-02 增补）：「第一次点麦克风键先过年龄门（Voice chat / What year were you born? / Continue），按『今年 − 出生年 ≥ 14』才算过，没过的这台设备上入口不显示」。
- 拟改：年龄门挪到首次打开（ACC-AGE + 确认卡），算法、只存过 / 没过不变；之后点麦克风键**不再出年龄卡**，直接接系统麦克风权限；首次打开没过的进不了游戏，所以「没过的入口不显示」这种状态不再出现。老号：语音卡答过「过」的首启跳过 AGE；答过「没过」的首启停在 AGE-BLOCK。
- 不变：麦克风键和人数胶囊的位置、抽屉（含 q(289) 自己一行）、名牌说话绿名、Close、语音的地点清单。语音年龄卡的组件（滚轮）挪到首启页复用。
- 一并：禁语音态（6.7）是麦克风键的一个新态（灰 + 点了 toast），**纯附加**，写进同一条复议。
### 8.2 复议 · LOCK-22 增补「Voice Profile 卡」——随账号方案报批
- 原锁（11-03 增补）：安卓照旧显示，点按先过语音的年龄门，没答过先出年龄卡（标题 `Voice Profile`），没过的点了 toast `Voice Profile isn't available`。
- 拟改：①年龄门挪到首启（同 8.1），点卡不再出年龄卡，`Voice Profile isn't available` 这一态不再出现；②**商店版不出这张卡**（D7；二批 #7 批「所有包」则 OSS 也不出），不出时 Collections 是最后一块（同 iOS 现行）。
- 不变：卡的样子、位置、他人页没有。
### 8.3 说明（不改锁定属性，记备查）
- **LOCK-22 名字与 `Edit`**：恢复锁定里本来就有的 `Edit`（P0 当初是没数据才没放，奕星核过头注释）；P0 只改名字，签名和可复制 ID 仍按 P0 范围不出（同 8d0d8212 齿轮那条的道理：分期实现，不改条文）。
- **LOCK-16 / 牌室**：商店版整个牌室地点不出（D6）；锁定的荷官、牌桌内容不变，只是这个包里没有这个地点。
- **LOCK-23**：首启几页在能切语言之前，新装机一律英文，中文版照增补走翻译表（含本规格全部新句）。
- **LOCK-30 抽屉行**：名字从 `Traveller xxxx` 变成玩家起的名字、超长 `…`（第 4 节）；`Report` 之后多一个原因抽屉（第 7 节，q 行定）。行结构 Mute / Block / Report 不变。
- **LOCK-06 HUD**：不动，名字不进 HUD。
- Settings 页本身不在 197 清单里（8d0d8212），第 2 节的改动走 q 行补注。
### 8.4 要李白起 / 补的 q 行（给他对照）
新 q 行：首会话顺序（AGE / 确认 / TERMS / NAME 插在选家城前）；举报原因单（推翻 q(274) 补记二那句）；系统态四页和优先级表（6.5）；绑定提醒和「一次运行一张软提示」。补注：§10.6.4（Account 行不写邮箱、Sign out 只给绑了的、Help and feedback 先只做 Contact us、Legal 加 Terms of Service、商店版不出 Test options）；q(244)（商店版不出）；q(17)（顶号这一轮做、SYS-SESSION 用原设计句）。

---

## 9. 新英文清单（约 45 句；中文同步走 L10n 表）
原设计 / 现有可直接用的（不算新）：`What year were you born?`、`Continue`、`Thanks for your interest in Gensen.`、`Privacy Policy`、`Terms of Service`、`Before you start`、`Gensen is an online game with other players. We have zero tolerance for objectionable content or abusive behavior.`、`What should we call you?`、`Shown to other players. You can change it every 7 days.`、`Name`、`Your name`、`2–16 letters or numbers`、`Enter a name`、`Try another name`、`That name isn't allowed`、`Continue with Apple`、`Continue with Google`、`Account`、`Signed in with Apple`、`Signed in with`、`Signed in`、`Add a sign-in method`、`Another way in, so you never lose your farm.`、`Help and feedback`、`Contact us`、`Opens your email app`、`Sign out`、`Delete account`、`Deletes your farm, items and progress`、`Delete your account?`、`Keep my account`、`Delete my account`、`You've been signed out`、`Please sign in again.`、`Sign in`、`Signed in on another device`、`You've been signed out here.`、`Reports are private. … won't know it was you.`、`Choose a reason`、`Submit report`、q(28) 原因 5 个、`Report sent`、`You already reported this`、`Not now`、`Support code copied`、`Cancel`。
**新**：`Pick your birth year`、`Born in %d?`、`Yes`、`Change`、`Sorry, you can't play Gensen.`、`Names or behavior that break the rules can be reset, muted or suspended.`、`Agree and continue`、`That character can't be used`、`Skip for now`、`Already have a farm?`、`Sign in to your farm`、`Sign-in isn't available on this phone.`、`No farm found`、`This %s account has no farm yet.`、`Start a new farm`、`Try another account`、`Playing as a guest`、`Link an account to keep your farm`、`Signed in with Apple and Google`、`Signed in with Google`、`Link an account to get your farm back on a new phone.`、`To play on Android too, add Google.`、`Linked with %s`、`This %s account already has a farm`、`Home Lv%d · Last played %s`、`This farm isn't linked. Switching deletes it.`、`Switch to that farm`、`Gensen support · %s`（邮件主题）及正文三行标签、`No email app found. Email us at %s`、`Sign out?`、`You can sign in again with %s.`、`Your farm, items, coins and progress will be deleted. This can't be undone.`（改句）、`Gensen will also lose access to your Apple ID.`、`Delete your account for good?`、`Your %s will be gone.` 句式、`Edit name`、`Save`、`Name saved`、`You can change your name again in %s`、`Farm open on another phone`、`Sign in with the account you linked, or contact us with your support code.`、`Support code %s`、`This account was deleted`、`You can start a new farm on this phone.`、`Account suspended`、`You can play again on %s.`、`This account can't be used anymore.`、`Keep your farm safe`、`Link account`、`Voice chat is off for you until %s.`、`Voice chat is off for you.`、`Sign-in expired. Please sign in again.`、`Your name was reset`、`It didn't follow our rules. You can choose a new name on your profile in 7 days.`、`OK`。
（`Save` / `OK` / `Yes` 若词库里已有就不算新；李白入表时核。）

---

- **登录键上的标志**：实现必须用 Apple / Google 的官方标志和按钮规范（Apple 用 ASAuthorizationAppleIDButton 或官方 logo 资源；Google 用四色 G 官方 svg），Figma 原组件 SignInButton 里的标志是示意图形，不能照抄。

## 10. 交安其拉的帧（第一段已出：Review row 155 633:197011，见文末验收记录）（11-12 出，11-13 报批；竖屏 360×800，页面 14 新开一个 Review row）
**第一批（报批要用的，先出）**：
1. ACC-AGE（未选）/ ACC-AGE（选了 2001）/ ACC-AGE-CONFIRM
2. ACC-AGE-BLOCK
3. ACC-TERMS
4. ACC-NAME（空）/ -ERR（`That name isn't allowed`）/ -KEYBOARD（键盘起来）
5. ACC-SIGNIN-iOS / -Android、ACC-NOFARM
6. ACC-SETTINGS-GUEST（滚到顶、滚到底各一）/ ACC-SETTINGS-LINKED（底部带 Sign out）
7. ACC-ACCOUNT（iOS 游客 / iOS 只绑 Apple / 安卓绑了 Google）、ACC-CONFLICT（带红字那种）
8. ACC-DELETE-1 / ACC-DELETE-2
9. PROFILE-1 加 `Edit ›`（P0 现行个人页上改）、ACC-RENAME（抽屉 + 键盘）
10. ACC-REPORT（未选 / 选了）
11. SYS-SESSION（原帧对一下即可）、ACC-CLAIMED、ACC-DELETED、ACC-SUSPENDED / -PERM
**第二批（实现前给到就行）**：ACC-SIGNOUT 确认卡、已退出页（SYS-SESSION-2 改）、ACC-LINK-ASK、ACC-HELP、名字截断三张（名牌、抽屉、`Block <name>?`，各 16 W / 16 汉字）、禁语音灰键 + toast、名字被重置卡。
**改前图**（报批对照）：现在的 Settings 主页、个人页、语音年龄卡、抽屉点 Report 后的 toast 各一张（实拍或现行帧）。
注意：报批图核掉开发键和教学卡；Figma 原设计帧里有 `〔邮箱〕`、`Continue with Email`、勾选框、`Community Guidelines`、`Block Ann too`，改出来的帧里都不能留。


---
## 验收记录
- 11-11 第一段（§10 1–5，Review row 155 633:197011，安其拉 491 cdffaec4）：11 帧逐张看过，结构、文案、主键几态对规格都对。要改两处：ACC-NOFARM 正文改短句；Apple / Google 标志换官方的，或在图注里写明是示意。键盘态不另出矮屏，上移规则留给实现。
- 11-11 第二段（§10 6–11，row 155，18 帧，安其拉 491 77e9f6b9）：结构、文案、顺序都对规格。要改三处：冲突卡红字改短句；认领冲突页标题改短；只绑 Apple 那页的说明第二句另起一行。系统态图标圆底照原帧 64。
- 11-11 奕星复核 q(312)–q(317) 的 6 处界面写法定了（李白转）：D-1 绑定提醒不要作物那一条；D-4 改名冷却向上取整、≤ 24 h 写 `in 1 day`；D-8 `Offensive voice chat` 要地点开语音、而且本机能用语音才出；D-10 SYS-DELETED 正文改成 `You can start a new farm on this phone.`（645:197720 要改帧）；B-6 待绑凭据过期出 toast `Sign-in expired. Please sign in again.`，回到登录卡；C-1 屏蔽名单写现在的名字、末尾截断。
- 11-11 v1.1 A / B 帧验收：A 节 row 158 659:198790（ACC-AGE 659:198791 / 659:198825 / 659:198854、CONFIRM 659:198884、CONSENT-OLD 659:198908 / 659:198931）通过；B 节四帧通过；个人页两帧（643:197324 / 644:197332）实拍底图里的 `Farmer's Homestead` 待改为 `Farmer's Home`。
- 11-11 用户 bot 728 选了首启底图方案 3（品牌米色）；规格 C 节已定稿。
- 11-11 用户 bot 733「系统页也换」，奕星 735 更正范围：只有 MAINT / UPDATE 换米色；FAIL / PLACE_FAIL / LAUNCH / SCENE 不变。
