# SGODOT-427 教堂套件 v1.1

黄忠 · PR #829。此版依赖 poi_church 的图集，删除套件重复PNG及其.import，节省893,410字节PNG源文件；原教堂全部71文件保持原字节。
七个复用GLB仅修改JSON中的图片URI，BIN（几何、UV、颜色）和其他JSON字段逐一核对不变，opaque_atlas.tres直接引用原教堂图集。

新增wall_door_2m：2m模数、4.8m墙高、1.4×2.6m真实门洞、双木门扇，无字无符号，1,132面、1surface。
套件共19件、30,552面/19surface。门替换示例左墙中段，默认图能看见木门；Map门钮推荐局部位置写在manifest和README。
示例8×8m、4张长椅、无迷宫，实测通道1.213m；68,504面/54surface。
审阅默认镜头43°、屏宽6.72m，焦点为(-0.70,1.30,-0.30)以纳入入口；人物1.745m。草地未新增布景。

图片均为Godot Mobile/Vulkan实渲：19件件表加人、360×800默认、全景、门墙近景、彩窗换色对照。
所有Godot/Blender经共享flock，用后退出；没有新地点/游戏场景/layout交付。
README已补后续小教堂镜头或草地小路处理建议。

验证：297项资产检查、149项Godot检查通过，含门洞、接缝、共享图集加载、完整BIN比较、原目录哈希。
手机格式：隔离工程启用import_etc2_astc=true，两次清除.godot冷导入成功，套件全部.import相对源文件无变化，第二次整个隔离工程除缓存外零变化。
两张8×1色板是compress/mode=0、vram_texture=false的无损资源，Godot不写imported_formats；不能把它们误判为缺少手机压缩格式。
已有poi_church图集.import确实只有s3tc_bptc，首次冷导入在隔离依赖副本补了etc2_astc。本次遵照不改poi_church的边界未提交原目录的变化，因此不宣称整个原仓库冷导入零差异。

附件validation包含两次冷导入的完整文件差异、色板导入模式，以及几何与Godot检查结果。
旧v1材料保留在church-kit-423-2026-11-06，当前套件审阅归SGODOT-427。
