# SGODOT-419 · Cooking Pot Wait · A 炖锅翻滚

黄忠制作。原尺寸米制，+Y 向上、+Z 朝前，根节点原点在锅底中心。

实例化 `cooking_pot_wait.tscn`，由接入端显式调用：

```gdscript
var animation := pot.get_node("AnimationPlayer") as AnimationPlayer
animation.play("tumble")  # 1.8 s，无缝循环
animation.play("idle")    # 合盖静止，仅蒸汽；也负责清除上一动作的姿态
```

两个动画都没有 autoplay。根节点不参与动画；`PotRig` 只有最高 0.002 m 的轻颠。
盖子保留原后沿转轴 `(0, 0.181, -0.107)`；v1.1 最高上移 0.0144 m，略微倾斜，含倾斜的前沿抬升约 0.01722 m（≤ 1.8 cm）。
程序应使用 `idle` 结束翻滚，不要只用 `stop()` 将锅冻结在半开状态。

原 `../stove_pot/stove_pot.glb` 以场景实例引用，仅显示 `pot_big`，`pot_normal` 隐藏。
原 GLB、纹理、import 和 UID 均不改。原锅含把手宽 0.280 m、高 0.242 m、深 0.214 m；锅口半径约 0.105 m。

`Steam` 路径为 `PotRig/StovePot/pot_big/lid/Steam`，是 5 粒子的 GPUParticles3D，
`local_coords = true`，不投影；本地位置 `(0.062, 0.032, 0.146)` 对齐原锅合盖出汽口，随盖移动。
原 GLB 的 `pot_big/vent` 挂点仍在原位置。蒸汽使用渐变纹理资源和颜色渐变；单粒子的理论最高 alpha 为 0.119，
即便 5 粒子全部重叠，合成 alpha 上界也低于 0.5。不带灯光、相机、环境、灶台或地面。
v1.1 将蒸汽收成向上的 5° 小锥，初速度 0.040–0.052 m/s、寿命 1.2 s；透明度约束在整条蒸汽上都成立。

整件仅 2 个绘制材质：锅/汤/3 个圆泡/白沫共用哑光顶点色材质，另一个给蒸汽。
为满足这个预算，新场景将原锅的两张色板材质取样到顶点色副本（`pot_body_colours.res`、`pot_lid_colours.res`），
仅在此实例覆写 mesh 资源；顶点位置、索引、UV、surface 和盖轴与原锅逐数组一致，
法线重新打包的数值误差小于 0.0002（验证报告列出实测值）。
原锅文件和其他使用者不受影响。圆泡只使用缩放动画，不是粒子。
新内容使用 Godot 原生 ArrayMesh `.res`、材质 `.tres` 和场景 `.tscn`；UID 由 Godot 生成，
这些原生资源无需 `.import`，原锅的 `.glb.import` 则照旧使用。

可见摆放几何 2,028 三角面（原大锅 684 + 汤、泡、白沫 1,344），8 surface；
蒸汽另计最多 10 面、1 次粒子绘制。隐藏的小锅仍随原 GLB 加载，但不参与绘制。

生成脚本与自查：`tools/art/source/cooking_pot_wait_419/`。
交检图、视频与实测说明：`docs/design/cooking-pot-wait-419-2026-11-05/`。
最新手机尺寸图是独立透明 `SubViewport` 的叠层预览（200×180，摆在 360×800 的 `(80,150)`）。
锅宽 180 px、锅口固定 `(180,235)`，暖色左上主光由预览宿主提供；运行时同样由哪吒提供镜头、灯光和叠层接入。
预览的透视镜头俯角 62°、水平 FOV 39.9253°，位置 `(0,0.5297685,0.1942029)`；
朝向沿 `(0,-sin(62°),-cos(62°))`。锅的根变换仍为单位矩阵。
这是为原尺寸高锅适配 200×180 框的镜头，不能把原 120 px / 43° 厨房推近取景当作本版交付。
