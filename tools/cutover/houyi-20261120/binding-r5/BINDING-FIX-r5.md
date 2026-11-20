# 最终审核绑定补齐

旧两包28b1/45f4、291379/81c74保持冻结且reviewed=false。本轮在独立binding-r5目录修审核和封包入口，不生成farm或MVT。

审核先校验钉住的旧输入manifest、included清单、源快照报告与source-candidates实际字节；读取farm同一份bytes先核input manifest SHA，再解析做完整源几何/拓扑审核。每行新增farm_path/farm_sha256/source_row_sha256/dataset/schema/generator_version，原source_geometry_hash继续核对。分片头记录源候选gzip SHA、included SHA、旧input manifest SHA、两份审核代码SHA、generator源码SHA、Python/Shapely/pyproj/numpy版本。

finalize要求分片编号精确覆盖且不重复，分片上下文等于实际输入/源码版本，每行farm字节SHA与实际文件及输入manifest一致、源记录/几何hash一致、dataset/schema/generator一致。只按ID集合或来源数量相同不再能通过。静态审计摘要包含完整绑定头、每分片报告SHA及排序farm/path/hash集合摘要；详细逐行证据在独立review包。最终metadata变更产生新static/review两archive及两manifest，farm/MVT字节不变。

针对负例覆盖同ID换名字字节、换源记录、换审核版本、缺farm hash、错dataset/generator、错packaged SHA、重复行、缺分片，全部必须拒绝。没有把旧报告补hash假装新跑；实际全量新审核另记录PID/退出码。
