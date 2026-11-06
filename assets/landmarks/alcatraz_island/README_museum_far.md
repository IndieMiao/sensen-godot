# alc_museum_far · SGODOT-424

黄忠，当前 **v0 形体阶段 / 正式配色待马可波罗交接**，保持草稿、暂不合并。
源近档：#792 b16c31982f34a64cdd4f9c6683064edbf20837a0 的 alc_museum.glb。

- 远档 802 三角面 / 1 surface，近档 3,252 面的 24.66%。
- 与近档相同原点和包围：X=-20..20、Y=0..9、Z=-5..5.24 m。
- 主体、屋顶、门框、门、墙角饰条的552面顶点/法线/颜色直接保留；25扇窗各简化为10面。
- 顶点色完全取自指定近档，不猜最终色板；材质哑光、不加纹理。
- `alc_museum_far.glb.import` 保留原UID uid://mtqh1ecarvqm，带 nodes/root_script=null、
  gltf/texture_map_mode=1、light_baking=1。材质沿用既有 alc_far_material_import.gd。
- 装配维持 `(0,10,-13)`、yaw0、scale1，LOD 55m、margin0；待正式色确认并验收后，
  马可波罗把主体 `lod_groups` 的 far_placeholder 改为 false。远档按原宿主规则不投影。

源和确定性脚本：`tools/art/source/alcatraz_museum_far_424/`。
独立测量/切档截图：`docs/design/alcatraz-museum-far-424-2026-11-06/v0/`。
配色交接在 Plane 424 评论 7dfec065；正式近档推送后再对色、重跑54/56m验图。
