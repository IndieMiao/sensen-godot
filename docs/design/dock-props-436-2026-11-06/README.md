# SGODOT-436 码头小件 v1 审阅

作者：黄忠；virtual_user_id：`5281cd25-6a49-4df8-9802-f3e534956e80`。

- `SGODOT-436_dock_props_v1_catalogue.png`：12件与1.745m默认人物，标宽X×高Y×深Z和实测面数。
- `SGODOT-436_dock_props_v1_example_360.png`：10.4×6m小渡口，360×800、43°正交、宽6.72m；使用426码头、430浪花、432海湾、434远景及428铺地。
- `SGODOT-436_dock_props_v1_validation.json`：GLB几何和色板、真实Godot材质/射线接口验证、冷导入、依赖来源。

12件合计5,678三角面 /12surface，单件252–716面。全套哑光顶点色，无贴图；售票亭留图形牌位、不写字。木色#A3815D /#B89972 /#795F47，铁件深褐。跳板接口顶面Y1.2m，接缝齐平，426端头矮墩每侧留13cm。

新套件放 `assets/landmarks/_shared/dock_props/`，源在 `tools/art/source/dock_props_436/`；未改现有资产，没有交付游戏layout或接入代码。
432使用#837的74cbc529（海湾），其余固定在206ab822。草地、石板、海面、浪花和远景仅为审阅环境，颜色与资源保持其原版；预览实例内调整水位与透明绘制顺序。
所有Godot/Blender进程经gs66-render.lock串行执行，桌面RTX2060 /Godot4.7.2 Vulkan Mobile实渲；未做真机性能测试。
