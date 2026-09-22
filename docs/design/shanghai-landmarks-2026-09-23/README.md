# 上海城市地图（2026-09-23）

上海复用洛杉矶城市地图框架：`assets/map/cities/<region_id>.json`（总览视角、地标、居民锚点）存在即启用城市地图；可拖动范围取 regions.json 的 placement_bounds。
五个地标（东方明珠、外滩、豫园、上海中心、静安寺）由 Sensenjoy `gpt-image-2` 以格里菲斯天文台、圣莫尼卡码头两张已上线地标为风格参考生成，处理同洛杉矶地标（512px PNG，底边 y=480）。
居民三处锚点：复兴公园（苗圃）、新天地（小馆）、田子坊（庭院）。
没有城市配置的城市仍走旧附近列表 UI；相关测试用 `CityMapData.force_legacy` 覆盖。
