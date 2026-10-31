# Shared Hall Shell (SGODOT-319)

赵云制作。315 R3 主图为四间 POI 室内壳的设计依据；当前仅交公共壳，等待上官婉儿检查后继续 N1 家具包。

- `layout.json`：6.8 x 6.4 m，地面 Y=0.08，墙体从地面起高 3.7 m；窗洞、实例、简单碰撞、出口建议挂点。
- `hall_*.glb`：6 个局部轴心模块，窗框和窗格各实例化两次；玻璃两窗合为一个 surface。
- `hall_albedo_ao.png`：一张 2048² 图集，壳自身 AO，没有家具接触阴影或固定窗光。
- `hall_palette.json`：固定像素区、glTF / Blender UV 区、16 px 安全边、32 个复用色块，以及 324 的 16 个语义色映射。
- `shell_asset_stats.json`、`shell_reuse_provenance.json`、`provenance/hall_*/reuse_provenance.json`：统计和逐件来源。
- `scenes/shell_hall/shell_hall_art.tscn`：读取 layout 装配全部网格、碰撞和挂点。没有相机、光源、WorldEnvironment 或游戏依赖。`atlas_path` 可替换同布局皮肤图集，透明材质独立保留。

与 PR #563 并存：本交付不覆盖其 `asset_stats.json`、`palette.json`、`hallkit_palette.png`、`hall_opaque.tres`、`hall_glass.tres` 或家具 GLB。324 的 UV 重映射尚未执行；应按 `hall_palette.json.hallkit_324_mapping` 找目标色块后再重映射。

制作、审阅、暂定尺寸和验证见 `docs/design/poi-hotel-lobby-319-2026-10-31/README.md`。
