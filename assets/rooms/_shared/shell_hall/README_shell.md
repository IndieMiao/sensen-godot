# Shared Hall Shell (SGODOT-319)

赵云制作。315 R3 主图为四间 POI 室内壳的设计依据；公共壳已通过上官婉儿技术检查（319 `5fe1b06c` / PR #594），窗洞、窗台、护墙板及顶线高度均定为正式值。

- `layout.json`：6.8 x 6.4 m，地面 Y=0.08，墙体从地面起高 3.7 m；窗洞、实例、简单碰撞、出口建议挂点。
- `hall_*.glb`：6 个局部轴心模块，窗框和窗格各实例化两次；玻璃两窗合为一个 surface。
- `hall_albedo_ao.png`：一张 2048² 图集，壳自身 AO，没有家具接触阴影或固定窗光。
- `hall_palette.json`：固定像素区、glTF / Blender UV 区、16 px 安全边、32 个复用色块，以及 324 的 16 个语义色映射。
- `shell_asset_stats.json`、`shell_reuse_provenance.json`、`provenance/hall_*/reuse_provenance.json`：统计和逐件来源。
- `scenes/shell_hall/shell_hall_art.tscn`：读取 layout 装配全部网格、碰撞和挂点。没有相机、光源、WorldEnvironment 或游戏依赖。`atlas_path` 可替换同布局皮肤图集，透明材质独立保留。

与 PR #563 并存：本交付不覆盖其 `asset_stats.json`、`palette.json`、`hallkit_palette.png`、`hall_opaque.tres`、`hall_glass.tres` 或家具 GLB。N1 已将扶手椅、圆边桌、风景画的副本重映射至酒店图集，原库保留；其他 324 件可按 `hall_palette.json.hallkit_324_mapping` 找目标色块后重映射。

`parquet` 区可以直接**换花纹**，不限于换色，例如 N2 可改为 `#DFD1B4` 石砖。室内 6.6 x 6.2 m 地面占用该区安全矩形 `(16,16)–(1008,1008)`；地板 UV 相对 X/Z **转了 90°**，X 对 V、Z 对 U。制作石砖或有方向的花纹时按这组轴向摆放；地台边缘取独立单色色块中心，不受花纹影响。N1 以相同 UV 布局的 `poi_hotel_lobby/room_albedo_ao.png` 作为皮肤，公共图集保留。

制作、审阅、正式尺寸和验证见 `docs/design/poi-hotel-lobby-319-2026-10-31/README.md`。
