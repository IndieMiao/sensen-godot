# 钓鱼点美术与 Pitch 展示

2026-09-25。以用户提供的 [Grassland & Pond 参考图](reference.png) 为本轮美术目标，重点为圆润奶油色岸石、明亮草甸、清透蓝水、动态阳光闪烁和水深颜色衰减。

本轮已接入三种系统鱼塘的真实运行场景。展示器调用相同的 `FishingPondScene`、`WaterShore` 和 `FishingWater`，使用隔离的默认角色与钓鱼等待姿态；没有登录、抛竿请求或鱼获结算。地点目录、岸线、导航、鱼获规则及个人存档不变。

用户随后要求真机覆盖安装。0.16.39 已保留手机最新 Voice Profile 功能并安装到 V2509A，三种鱼塘与相机、前后台检查通过，见 [真机截图／录像及报告](../../qa/pond-pitch-phone-2026-09-25.md)。

## 展示素材

- [Pitch 评审素材包 ZIP](../../../output/pond-pitch-2026-09-25/pitch/gensen-fishing-art-review.zip)
- [1920×1200 实际渲染主图](../../../output/pond-pitch-2026-09-25/pitch/gourd-hero.png)
- [Android 动态水体录像，约 12 秒](../../../output/pond-pitch-2026-09-25/pitch/water-motion.mp4)
- [岸石／水体近景](../../../output/pond-pitch-2026-09-25/native/gourd-detail.png)
- [参考图与实际场景对照](../../../output/pond-pitch-2026-09-25/reference-runtime.png)
- [旧版与新版对照](../../../output/pond-pitch-2026-09-25/before-after.png)
- [桌面 Metal 与 Android Vulkan 同帧对照](../../../output/pond-pitch-2026-09-25/desktop-android.png)
- [三种鱼塘：月牙](../../../output/pond-pitch-2026-09-25/native/crescent-hero.png)、[葫芦](../../../output/pond-pitch-2026-09-25/native/gourd-hero.png)、[曲湾](../../../output/pond-pitch-2026-09-25/native/meander-hero.png)

主图与录像均由实际 Godot 场景产生，没有用参考图替换游戏背景。素材是美术评审成果，尚未公开发布或向合伙人发送；用户手机安装状态以上述后续真机报告为准。

## 美术实现

岸石沿原有岸线按弧长分布，采用平滑圆润几何、暖白矿物纹理和低位湿润色差。大、小石块穿插低矮花叶丛；靠近镜头的石块沿岸展开，限制横向宽度和高度，以免遮挡默认落点的浮漂。额外几何检查覆盖全部 12 个地点的随机种子，确认较高石面没有侵入原导航保留区。

水面根据同一岸线距离图定义视觉水深：浅滩保留较大的水底卵石，越深越降低底部对比并转向蓝色。RGB 分别做指数吸收及体积散射，提供类似 depth fog 的效果。这里的水深是美术定义的水盆深度，不是现实地理测深；不依赖屏幕深度纹理，因此正交镜头在 Metal/Vulkan 上使用相同计算。

两层流动波纹驱动折射和焦散；视角与太阳方向驱动微小波面的高光，并对细碎闪光做像素导数过滤。保留岸边缓存倒影与浮漂涟漪。草甸使用有 mipmap 的纹理及批量草簇，替代依赖 GPU 浮点细节的逐像素正弦噪声。

场景保留三种已经发布的鱼塘轮廓和现有角色系统。与参考图相比，树冠造型、植被密度、柔和间接光和角色服装仍有区别；本轮没有声称逐像素复刻或已经获得用户美术验收。

## 本地查看

双击 [open_pond_art.command](../../../tools/dev/open_pond_art.command)，或在仓库运行：

```sh
tools/dev/open_pond_art.command
```

展示器默认播放水体动态；拖动平移、滚轮／双指缩放，空格暂停／继续，R 复位。它使用独立用户目录且禁止网络自动启动，不修改正常 Journey 角色或存档。

Android 并行测试与重现命令见 [并行测试说明](../../qa/parallel-godot-android.md)，验证结果见 [QA 报告](../../qa/pond-pitch-2026-09-25.md)。
