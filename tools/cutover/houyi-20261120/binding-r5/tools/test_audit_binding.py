import json,copy
from audit_binding import sha,canonical,bound_row,verify_reports
row={'parcel_id':'X','geometry':{'type':'Polygon','coordinates':[[[0,0],[1,0],[1,1],[0,0]]]},'address':'public test'};row['source_geometry_hash']=sha(canonical(row['geometry']))
f={'schema':4,'dataset_version':'test-dataset','generator_version':'v1','block_id':'p-X','parcel_id':'X','name':'Original'};blob=canonical(f);expected={'farm_schema':4,'dataset_version':'test-dataset','generator_version':'v1','audit_code_sha256':{'audit.py':'abc'},'source_candidates_sha256':'def'}
result={'block_id':'p-X','source_geometry_hash':row['source_geometry_hash'],**bound_row(blob,row,f,expected)}
base=[{'scope':'all_included_partition','binding':expected,'shard':0,'shards':1,'count':1,'results':[result]}];files={'farms/p-X.json':sha(blob)};rows={'p-X':row}
verify_reports(base,expected,rows,{'p-X'},files,lambda _:blob)
cases=[]
for name in ['same_id_different_bytes','source_row_changed','audit_code_changed','missing_farm_hash','wrong_dataset','wrong_generator','packaged_hash_changed','duplicate_result','missing_partition']:
 reports=copy.deepcopy(base);exp=copy.deepcopy(expected);rr=copy.deepcopy(rows);ff=copy.deepcopy(files);bb=blob
 if name=='same_id_different_bytes':bb=canonical({**f,'name':'Replaced'})
 elif name=='source_row_changed':rr['p-X']['address']='replacement'
 elif name=='audit_code_changed':exp['audit_code_sha256']['audit.py']='different'
 elif name=='missing_farm_hash':del reports[0]['results'][0]['farm_sha256']
 elif name=='wrong_dataset':bb=canonical({**f,'dataset_version':'other'})
 elif name=='wrong_generator':bb=canonical({**f,'generator_version':'v2'})
 elif name=='packaged_hash_changed':ff['farms/p-X.json']='0'*64
 elif name=='duplicate_result':reports[0]['results']*=2;reports[0]['count']=2
 elif name=='missing_partition':reports[0]['shards']=2
 try:verify_reports(reports,exp,rr,{'p-X'},ff,lambda _:bb)
 except AssertionError:cases.append(name)
 else:raise AssertionError('unsafe audit reuse accepted '+name)
print(json.dumps({'positive':1,'negative_rejections':cases,'passed':1+len(cases)},indent=2))
