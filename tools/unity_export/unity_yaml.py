"""Tuanjie/Unity YAML 宽松解析：去 %TAG 指令、规约文档分隔符后 safe_load_all。"""
import re
from pathlib import Path
import yaml

# anchor（fileID）可以是负数：Unity/Tuanjie 里 MonoBehaviour 子资源常见
# `--- !u!114 &-4807600157798773482`。此前正则只吃 &\d+，漏掉负号 → 这一行
# 不被规约成 `---` → PyYAML 撞上未知标签 !u!114 直接抛错 → **整个文件返回空**，
# 连后面带材质参数的 Material 文档一起丢。25 个部件里 24 个没有材质参数就是这条。
_DOC_RE = re.compile(r"^--- !u!\d+\b.*$", re.M)

def load_documents(path):
    p = Path(path)
    if not p.is_file():
        return []
    text = p.read_text(encoding="utf-8", errors="replace")
    text = "\n".join(l for l in text.splitlines() if not l.startswith("%"))
    text = _DOC_RE.sub("---", text)
    try:
        return [d for d in yaml.safe_load_all(text) if isinstance(d, dict)]
    except yaml.YAMLError:
        return []

def load_monobehaviour(path):
    for doc in load_documents(path):
        if "MonoBehaviour" in doc:
            return doc["MonoBehaviour"]
    return None
