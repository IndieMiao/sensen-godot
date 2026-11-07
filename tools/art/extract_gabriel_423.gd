extends "res://tools/pipeline/extract_parts.gd"
## Safe single-part append for both art and runtime branches. Does not replace the manifest.
func _initialize():
 var path="res://assets/avatar/parts_manifest.json"
 var text=FileAccess.get_file_as_string(path)
 var data=JSON.parse_string(text)
 var recipe=JSON.parse_string(FileAccess.get_file_as_string("res://assets/avatar/source/recipes_gabriel.json")).parts[0]
 var entry=_process_part(recipe)
 if entry==null:quit(1);return
 var found=false
 for item in data.parts:
  if item.id==entry.id:
   assert(item==entry,"Existing Gabriel registry entry differs; inspect before replacing")
   found=true
 if not found:
  var end=text.find("\n\t]")
  assert(end>=0,"Unexpected manifest formatting")
  var block=JSON.stringify(entry,"\t",false).replace("\n","\n\t\t")
  FileAccess.open(path,FileAccess.WRITE).store_string(text.substr(0,end)+",\n\t\t"+block+text.substr(end))
 var npc_path="res://assets/avatar/npc_only.json"
 var npc={"version":1,"npc_only":[]}
 if FileAccess.file_exists(npc_path):npc=JSON.parse_string(FileAccess.get_file_as_string(npc_path))
 if not npc.npc_only.has(entry.id):npc.npc_only.append(entry.id)
 FileAccess.open(npc_path,FileAccess.WRITE).store_string(JSON.stringify(npc,"\t",false)+"\n")
 print("Gabriel extracted; preserved all existing manifest and NPC-only entries. Render the real thumbnail next.")
 quit()
