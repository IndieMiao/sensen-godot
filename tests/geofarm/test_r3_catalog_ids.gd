extends SceneTree
const Contract:=preload("res://demo/geofarm/geo_contract.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():printerr("catalog path required");quit(1);return
	var parsed:=JSON.new()
	if parsed.parse(FileAccess.get_file_as_string(args[0]))!=OK or not parsed.data is Dictionary:quit(1);return
	var rows:Array=parsed.data.get("parcels",[])
	var invalid:Array=[]
	for row in rows:
		if not row is Dictionary or not Contract.valid_id(row.get("block_id")):invalid.append(str(row.get("block_id","invalid row")))
	var star_ok:=Contract.valid_id("p-4591A011*") and Contract.farm_path("p-4591A011*")=="/farms/p-4591A011*.json"
	var rejects:=true
	for id in ["p-../farm","p-A/B","p-A\\B","p-A?x=1","p-A#x","p-A B","p-A|B","p-%2e%2e"]:
		rejects=rejects and not Contract.valid_id(id)
	print("CATALOG ",rows.size()," accepted=",rows.size()-invalid.size()," rejected=",invalid.size()," literal_star=",star_ok," separators_rejected=",rejects," sha256=",FileAccess.get_sha256(args[0]))
	if not invalid.is_empty():printerr("UNEXPECTED_REJECTED ",JSON.stringify(invalid))
	quit(0 if rows.size()==154444 and invalid.is_empty() and star_ok and rejects else 1)
