"""hex GUID → Unity 路径：Addressables 表 → overrides。"""
class GuidResolver:
    def __init__(self, addr_table: dict, overrides: dict):
        self.addr = addr_table
        self.overrides = overrides or {}
    def path_for_guid(self, guid: str):
        ov = self.overrides.get(guid)
        if isinstance(ov, str):
            return ov
        return self.addr.get(guid)
