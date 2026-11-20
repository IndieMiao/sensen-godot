# 亚瑟 Cardigan 切换保存

用户2026-11-20明确切换，停止Herdr和Plane写入。此WIP只保存本机遗留自动生成UID，无新的业务改动，不作为可部署候选。

主工位182份未跟踪UID按原路径提交，基feat/google-available ea545e1a7df4e16af7ce1270991236dd57d0062e。
另一个U2工作树feat/gather-compact 59e914fb577be3259a4f5b787f9ca50b9a9d7006的179份UID中有不同值，独立保存在u2-untracked-uids.json的files映射，不覆盖主工位UID。原U2文件仍留在本机；需要恢复时按该基线和映射逐文件写回，不合成一套UID。

所有语音/地图原生工作树已提交，完整分支/SHA与后续事项见本机/Users/zhangshaojie/cardigan-pm-lessons/cutover/workers/yase.md。未上传任何证书、keystore、ASC私钥、账号数据或QA能力码。
