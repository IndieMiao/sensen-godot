extends "res://tools/pipeline/extract_parts.gd"
## Append or refresh Gabriel only; preserve every unrelated registry entry.
func _initialize():
 var path="res://assets/avatar/parts_manifest.json"
 var data=JSON.parse_string(FileAccess.get_file_as_string(path))
 var recipes=JSON.parse_string(FileAccess.get_file_as_string("res://assets/avatar/source/recipes_gabriel.json")).parts
 var ids=["cloth1_npc_gabriel","cloth36_npc_gabriel","hairhat0_npc_gabriel","shoes3_npc_gabriel"]
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--only="):
   var selected=arg.trim_prefix("--only=")
   recipes=recipes.filter(func(p):return p.id==selected)
   if recipes.is_empty():push_error("Unknown Gabriel part: "+selected);quit(1);return
   ids=[selected]
 data.parts=data.parts.filter(func(p):return not ids.has(p.id))
 var npc_path="res://assets/avatar/npc_only.json"
 var npc={"version":1,"npc_only":[]}
 if FileAccess.file_exists(npc_path):npc=JSON.parse_string(FileAccess.get_file_as_string(npc_path))
 npc.npc_only=npc.npc_only.filter(func(id):return not ids.has(id))
 for recipe in recipes:
  var entry=_process_part(recipe)
  if entry==null:quit(1);return
  data.parts.append(entry);npc.npc_only.append(entry.id)
 if not _errors.is_empty():push_error(str(_errors));quit(1);return
 FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(data,"\t",false)+"\n")
 FileAccess.open(npc_path,FileAccess.WRITE).store_string(JSON.stringify(npc,"\t",false)+"\n")
 print("Gabriel extracted; preserved unrelated entries. Render the affected real thumbnails next.")
 quit()
