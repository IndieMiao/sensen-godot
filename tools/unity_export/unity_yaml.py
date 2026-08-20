"""Tuanjie/Unity YAML 宽松解析：去 %TAG 指令、规约文档分隔符后 safe_load_all。"""
import re
from pathlib import Path
import yaml

_DOC_RE = re.compile(r"^--- !u!\d+ &\d+.*$", re.M)

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
