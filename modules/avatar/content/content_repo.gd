class_name ContentRepo
extends RefCounted

## 分发接缝：一期所有资源在主包内，恒可用。
## 二期实现：按 manifest.pack 查 PCK → 未下载则下载校验 → load_resource_pack 挂载。
func ensure_available(_part_id: String) -> Error:
	return OK
