import json,collections as C,sys
sys.path.insert(0,"tools/map/poi_survey"); from taxonomy import resolve
cities=["sf","nyc","beijing","shanghai"]
for vis in (False,True):
  print("\n### 仅 filterrank<=3（地图上实际显示的高优先级）" if vis else "### 全部采样")
  for use_name in (False,True):
    print(f"-- 店名关键词: {'开' if use_name else '关'}")
    for c in cities:
      A=[json.loads(l) for l in open(f"tools/map/poi_survey/data/{c}.jsonl")]
      if vis: A=[p for p in A if (p.get("filterrank") or 5)<=3]
      src=C.Counter(); leaf=0
      for p in A:
        k,s=resolve(p,use_name); src[s]+=1
      n=len(A); shown=n-src["hide"]
      spec=src["brand"]+src["maki"]+src["type"]+src["name"]
      print(f"  {c:9s} n={n:5d} 上图={shown/n:5.1%}  其中细类={spec/max(shown,1):5.1%}  | "+" ".join(f"{k}={v}" for k,v in src.most_common()))
    # restaurant subtree
  for c in cities:
    A=[json.loads(l) for l in open(f"tools/map/poi_survey/data/{c}.jsonl")]
    if vis: A=[p for p in A if (p.get("filterrank") or 5)<=3]
    R=[p for p in A if p.get("class")=="food_and_drink"]
    for use_name in (False,True):
      ks=C.Counter(resolve(p,use_name)[0] for p in R)
      gen=ks["food.restaurant"]
      print(f"  餐饮 {c:9s} n={len(R):4d} 店名{'开' if use_name else '关'}: 仍为泛'餐厅'={gen/len(R):5.1%}  子类数={len(ks)}")
