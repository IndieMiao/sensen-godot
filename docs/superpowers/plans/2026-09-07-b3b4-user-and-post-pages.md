# 用户主页与动态详情 —— 实施记录（2026-09-07 深夜）

对应 Plane SGODOT-93（B4 别人的资料页）、SGODOT-92（B3 一级评论）、SGODOT-61（E1 资料页举报拉黑入口）、
SGODOT-101（D4 关注 UI）。服务端早就有资料 / 关注 / 评论 / 举报接口，这一刀是把它们接成页面。

## 1. 结构

- **`PostCard`**（`modules/ui/post_card.gd`）：feed 卡片从 feed_page 抽出来的统一构造，feed 时间线、用户主页动态列表、
  动态详情三处共用同一套节点名（Post_<id> / Author / Text / Pictures / Like / Meta / Report / Block），行为通过 ctx 回调注入。
  「N comments」从 Label 改成按钮（进详情）；作者名可点（进主页）。静态方法里没有 `self.tr`，走 `TranslationServer.translate`，
  字串仍由页面里的 `tr()` 抽取。
- **用户主页**（`scenes/app/pages/user_page.gd`，`AppRoutes.USER`，`setup({"user_id"} | {"handle"})`）：资料卡（昵称 / @handle /
  简介 / 关注者数 / 关注数（受隐私开关）/ 「关注了你」）+ 关注 / 发消息 / 举报 / 拉黑 + 动态列表（分页）。
  关注 / 取关后重拉资料，计数与关系以服务端为准；发消息 = `POST /im/dm` 再压栈聊天页；拉黑后离开本页；
  被拉黑（任一方向）服务端 404 → 「这个用户不可用」；看自己时不显示操作行。
- **动态详情**（`scenes/app/pages/post_page.gd`，`AppRoutes.POST`，`setup({"post"} | {"post_id"})`）：卡片 + 评论列表（分页）+
  评论框（键盘避让 SHRINK）。别人的评论可举报（target `comment`）/ 拉黑作者（本页撤掉其全部评论）；自己的可删；
  拉黑帖子作者则离开本页。评论数随增删更新卡片。
- **入口**：feed 卡片「N comments」→ 详情，作者名 → 主页；聊天页单聊页头菜单「查看主页」；用户主页动态卡片同样可进详情。

## 2. 坑

- `_ready` 里 `call_deferred("load")` 与测试里显式 `await p.load()` 撞车：显式调用中途让出帧时延迟调用插进来，
  再拉一次资料把 `user` 覆盖成了后面剧本里的响应。页面加 `loading / loaded` 守卫只跑一次（聊天页的 `load_history`
  本来就有 `loading` 守卫，所以没撞）。
- `await (a() if c else b())` 是语法错误：拆成 if / else。
- handle 服务端一律小写，`setup` 里先 `to_lower()`。

## 3. 测试

`test_user_page.gd`（5）、`test_post_page.gd`（3）、feed +1（导航）、im +1 处（查看主页）；全套 817；新文案 12 条含 zh_CN。

## 4. 仍待

用户主页头像与「关注者 / 关注中」列表页；设置页的「关注列表可见」开关（`following_visible`）；评论的相对时间用页面时钟。

## 5. 2026-09-08 收尾

- 关注者 / 关注中 / 新粉丝列表页 `scenes/app/pages/follow_list_page.gd`（`AppRoutes.FOLLOW_LIST`，`setup({user_id, kind})`），
  用户主页与「我的」页的计数变成可点按钮；「关注中」被对方关掉可见时服务端 403 → 「这位用户没有公开关注列表」。
- 头像：`AvatarThumb`（`modules/ui/avatar_thumb.gd`）+ `AvatarPortraits`（`modules/avatar/thumbs/avatar_portraits.gd`，
  挂在 Avatar 门面下的共享离屏渲染器，按装扮 JSON 缓存，头肩特写 192 px）。用户主页 / 我的页直接显示，
  列表行与 feed 作者行用按钮 icon（着色覆盖成白，不然主题会把彩图染黑）。渲染失败或 headless 保持占位图标。
- B7 装扮同步：换装房保存后 `PUT /users/me/profile {avatar}`；「我的」页 `sync_avatar`：服务端空而本地有 → 推；
  服务端有而本地空 → 落地。测试里用 `avatar_api` 注入替身，绝不碰真机存档。
- QA 钩子：`SENSEN_QA_ME=1`（进「我的」页并同步装扮）、`SENSEN_QA_FOLLOWERS=1`（截自己的关注者列表）、
  `SENSEN_PORTRAIT_DEBUG=1`（头像渲染图落到 user://qa/portrait_NN.png）。

