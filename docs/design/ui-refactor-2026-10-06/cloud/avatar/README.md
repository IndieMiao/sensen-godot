# Avatar 独立云端制作入口

这些脚本只由主代理通过已授权的 `use_figma` 执行。子代理只准备本地代码、压缩展示副本和结构检查；不修改 root 的 `build_cloud.py`。

- 固定文件：Gensen `OMLTC3yw3u2WDjOZhLnhaR`。
- 固定新稿页：`481:53`；原图与原游戏资产保留。
- 状态：本目录 `state.json`。每次成功 MCP 调用后先合并完整回执，再生成下一阶段。
- 每个上传／构建脚本少于 **48,000 字符**。构建时使用现有 `cloud/minify.cjs`。
- 返回所有真实新增／修改／移除 ID；继承 ID 按 prefix + CSV suffix 分组，可由回执处理器还原。Avatar 连线使用紧凑 `linkRows` 返回，状态文件会展开为正常字段。

## 1. 图片上传

`prepare_uploads.py` 已生成 57 张展示副本与 `uploads/upload-000.js` 至 `upload-043.js`。所有源 PNG 都在 `avatar-assets/`，不覆盖；新 PNG 保留透明度、人物自适应 240–288 宽、无损 RGBA PNG（不量化颜色/alpha），缩略图仍为 160×160，背景另存 JPEG。`upload-manifest.json` 记录原图／上传图 SHA、尺寸和透明度保留方法。

首版 RGBA 调色板压缩因透明斑块已拒绝；若曾执行旧批次，需要按新脚本更新。`currentImages` 只有上传 SHA 与当前 manifest 匹配才计数，phase builder 会拒绝旧副本。

按序把每个上传脚本的**完整内容**作为 `use_figma.code` 执行。脚本在页内 x=20000 的 `Avatar · source assets · 2026-10-06` 专属区域保留真实图层和 imageHash；相同 key 的重试通过相同图层与内容 hash 幂等处理。

保存原始完整工具结果后运行：

```sh
AVATAR_RUN_DIR=docs/design/ui-refactor-2026-10-06/cloud/avatar
python3 "$AVATAR_RUN_DIR/merge_avatar_result.py" /tmp/avatar-upload-000-result.json
```

可以一次传入多个回执。isError、非完整 JSON、没有合法 Avatar 结果的文件会被拒绝，**不会**推进状态。不得把截断输出当作成功回执。

## 2. 共享缩略图与格子

在 27 张缩略图已上传并合并后生成：

```sh
python3 "$AVATAR_RUN_DIR/build-avatar-phase.py" thumbnails
```

执行打印出的 `phases/...js`，合并结果。此阶段创建 27 个真实缩略图主件、原 none.svg 主件，以及 Avatar Part Tile 的 Default / Selected 两变体。名称是 TEXT，缩略图是 INSTANCE_SWAP；分类复用已有 Tab。

## 3. 整屏变体

五类每次 3 个最稳妥；Bags 第二批只有 2 个。先生成并执行 0–2，再生成并执行 3–5；每次调用后合并状态。

```sh
python3 "$AVATAR_RUN_DIR/build-avatar-phase.py" variants Hair --offset 0 --count 3
python3 "$AVATAR_RUN_DIR/build-avatar-phase.py" variants Hair --offset 3 --count 3
```

同样处理 `Outfits`、`Shoes`、`Bags`、`Glasses`，然后：

```sh
python3 "$AVATAR_RUN_DIR/build-avatar-phase.py" variants defaults --count 1
python3 "$AVATAR_RUN_DIR/build-avatar-phase.py" group
```

Reset 使用真实的 `hairhat0 + cloth0 + shoes0` 渲染，不冒用当前基准。共 30 个变体（27 件、两个卸下、一个默认整套），每个都拥有上半角色预览、下半三列真实部件网格。

## 4. 保存结果与继续编辑

对应顺序为 `base`、manifest 的 27 个部件、`defaults`，共 29 个。可通过具体 ID 或 offset/count 分批：

```sh
python3 "$AVATAR_RUN_DIR/build-avatar-phase.py" saved all --offset 0 --count 3
python3 "$AVATAR_RUN_DIR/build-avatar-phase.py" continuations all --offset 0 --count 3
```

递增 offset 为 3、6、9…27，最后一批只有 2 个。也可以先完成全部 saved 再完成全部 continuations。保存结果完整保留 `PROFILE-1-P0` 的信息和菜单；base 不显示 Look saved。每种已保存试穿均有对应的继续编辑实例，Done 不统一回默认外观。

## 5. 连线

待 30 个变体和两组 29 个 Frame 全部完成后：

```sh
python3 "$AVATAR_RUN_DIR/build-avatar-phase.py" wire --count 48
```

执行、合并、再次用相同命令生成下一批。选择逻辑总是取状态中尚未 wired 的前 48 条，因此**不需要递增 offset**。持续至生成结果中的 selected 为空。BACK 返回进入衣柜的 Profile，不表现为保存。

## 6. 填入正式三张卡

在主变体连线完成后，分别生成并执行：

```sh
python3 "$AVATAR_RUN_DIR/build-avatar-phase.py" compose PROFILE-1-P0 --rebuild
python3 "$AVATAR_RUN_DIR/build-avatar-phase.py" compose KEEP-P0-1 --rebuild
python3 "$AVATAR_RUN_DIR/build-avatar-phase.py" compose KEEP-P0-2 --rebuild
```

它们只处理本轮新稿中已确认的 `482:310 / 482:312 / 482:314`，验证所属页和 360×800 尺寸，返回所有被替换子节点的 ID。PROFILE-1-P0 使用真实基准；KEEP-P0-1 使用真实衣柜；KEEP-P0-2 是已保存 Silver Crop 示例。此路径不加通用 HUD 或 floating Close。

再次运行第 5 步，连好正式 Profile 新增的 Details / Back；其余 Avatar 链接在 composition 时已连到同一组精确结果。

## 7. 回读与截图

`inspect` 可生成当前 Avatar 状态的只读结构回读脚本。实际验收需查看：基准 Profile → Hair 选另一件 → 角色变化 → Done 后同一外观 → Edit look 同一选择 → Back 无保存；另查 Reset、Outfits、Bags、Glasses、卸下与长标签。

本地 API 模型验证不是云端渲染验收。保存所有成功工具回执和最终截图；不要仅凭脚本返回状态宣称视觉通过。若调用中断／部分执行且没有完整回执，先读当前生成节点，不应盲目复用旧状态重建组件。
