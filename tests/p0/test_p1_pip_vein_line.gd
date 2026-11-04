extends GdUnitTestSuite

const Gear := preload("res://modules/p0/p0_gear_logic.gd")
const MINE := "Willow Vein"
const LINE := "Copper's a start! There's iron at Willow Vein. Get down to Floor 10!"
var _content: Dictionary

func before_test() -> void:
	_content = P0Logic.content()
	P0Logic._content = _content.duplicate(true)

func after_test() -> void:
	P0Logic._content = _content
	for suffix in ["bar", "tips"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_file(suffix)))

func _file(suffix: String) -> String:
	return "user://test_pip_vein_%d_%s.json" % [OS.get_process_id(), suffix]

func _view() -> Dictionary:
	return {seq=10, energy={value=210,max=220}, bag={slots=[],capacity=25},
		firsts=["harvest:crop_radish"], guide={step=null,pip=null},
		first_dig={giver="res_pip",floor=3,have=3,done=true},
		pip_line={key="pip_vein",vein="wd-42-13",name=MINE},
		residents={res_pip={affinity=5,stage="Stranger",next_at=15,next_stage="Acquainted",request_state="none"},
			res_old_kai={affinity=0,stage="Stranger",next_at=15,next_stage="Acquainted",request_state="none"}}}

func _ui(v: Dictionary) -> P0Ui:
	var ui: P0Ui=auto_free(P0Ui.new())
	ui.quick_store=_file("bar")
	ui.tips_path=_file("tips")
	add_child(ui)
	await get_tree().process_frame
	ui.set_view(v)
	ui.set_surface("farm")
	return ui

func _line(ui: P0Ui) -> String:
	if ui._modal == null: return ""
	for node in ui._modal.find_children("*","UiResidentBar",true,false):
		if not node.is_queued_for_deletion(): return str(node.data.get("line",""))
	return ""

func test_approved_template_and_authoritative_name_are_used_without_local_completion_inference() -> void:
	var v:=_view()
	assert_str(Gear.pip_line(v,"res_pip")).is_equal(LINE)
	P0Logic._content.mine.first_dig.lines.pip_vein="New text about %s."
	assert_str(Gear.pip_line(v,"res_pip")).is_equal("New text about Willow Vein.")
	assert_str(Gear.pip_line(v,"res_old_kai")).is_empty()
	for first in [null, {}, {done=false}]:
		v.first_dig=first
		v.gear={weapon="weapon_copper_sword"}
		v.rewards=["first_dig"]
		v.mine={rank=40}
		assert_str(Gear.pip_line(v,"res_pip")).is_empty()

func test_missing_or_consumed_line_never_leaks_the_id_or_template() -> void:
	for line in [null, {}, {key="other",vein="wd-42-13",name=MINE}, {key="pip_vein",vein="wd-42-13"}, {key="pip_vein",name=MINE}]:
		var v:=_view()
		v.pip_line=line
		assert_str(Gear.pip_line(v,"res_pip")).is_empty()
	P0Logic._content.mine.first_dig.lines={}
	assert_str(Gear.pip_line(_view(),"res_pip")).is_empty()

func test_guide_has_priority_and_finishing_it_mid_conversation_waits_for_next_talk() -> void:
	var v:=_view()
	v.guide={step="t_water",pip={line="Water these plots first."}}
	# Even an inconsistent old snapshot cannot overrule the guide on screen.
	assert_str(Gear.pip_line(v,"res_pip")).is_empty()
	var ui:=await _ui(v)
	var sent:=[]
	ui.command.connect(func(cmd): sent.append(cmd))
	ui.open_resident("res_pip")
	assert_str(_line(ui)).is_equal("Water these plots first.")
	assert_int(sent.size()).is_equal(1)
	ui.set_view(_view())
	ui.open_resident("res_pip")   # the runtime refreshes an open bar after a reply
	assert_str(_line(ui)).is_not_equal(LINE)
	assert_int(sent.size()).is_equal(1)
	ui.close_modal()
	ui.open_resident("res_pip")
	assert_str(_line(ui)).is_equal(LINE)
	assert_int(sent.size()).is_equal(2)

func test_synchronous_talk_reply_cannot_swallow_the_line_or_send_a_second_talk() -> void:
	var ui:=await _ui(_view())
	var sent:=[]
	var displayed_when_sent:=[]
	ui.command.connect(func(cmd):
		sent.append(cmd)
		displayed_when_sent.append(_line(ui))
		var consumed:=_view()
		consumed.pip_line=null
		consumed.seq=11
		ui.set_view(consumed)
		ui.open_resident("res_pip"))
	ui.open_resident("res_pip")
	assert_array(sent).is_equal([{type="talk",resident="res_pip"}])
	assert_array(displayed_when_sent).is_equal([LINE])
	assert_str(_line(ui)).is_equal(LINE)
	assert_bool(ui.resident_asks_here()).is_false()
	ui.open_resident("res_pip")
	assert_int(sent.size()).is_equal(1)
	ui.close_modal()
	ui.open_resident("res_pip")
	assert_int(sent.size()).is_equal(2)
	assert_str(_line(ui)).is_not_equal(LINE)

func test_reply_and_affinity_rebuild_keep_this_conversation_but_other_residents_and_new_ui_do_not() -> void:
	var ui:=await _ui(_view())
	ui.open_resident("res_pip")
	var consumed:=_view()
	consumed.pip_line=null
	consumed.residents.res_pip.affinity=7
	ui.set_view(consumed)
	ui.resident_affinity({resident="res_pip",delta=0})
	ui.open_resident("res_pip")
	assert_str(_line(ui)).is_equal(LINE)
	ui.open_resident("res_old_kai")
	assert_str(_line(ui)).is_not_equal(LINE)
	ui.open_resident("res_pip")
	assert_str(_line(ui)).is_not_equal(LINE)
	var next_ui:=await _ui(consumed)
	next_ui.open_resident("res_pip")
	assert_str(_line(next_ui)).is_not_equal(LINE)
	assert_bool(FileAccess.file_exists(_file("tips"))).is_false()

func test_reopening_after_an_unacknowledged_talk_uses_server_offer_instead_of_a_local_said_flag() -> void:
	var ui:=await _ui(_view())
	ui.open_resident("res_pip")
	ui.close_modal()
	ui.open_resident("res_pip")
	assert_str(_line(ui)).is_equal(LINE)   # server still offers it; a failed talk must not permanently lose the line
	var consumed:=_view()
	consumed.pip_line=null
	ui.set_view(consumed)
	ui.close_modal()
	ui.open_resident("res_pip")
	assert_str(_line(ui)).is_not_equal(LINE)

func test_completed_view_stays_done_without_reopening_first_dig_task() -> void:
	var v:=_view()
	assert_bool(v.first_dig.done).is_true()
	assert_dict(Gear.first_dig(v)).is_empty()
	assert_dict(Gear.first_dig_card(v)).is_empty()
	assert_dict(Gear.first_dig_row(v)).is_empty()
	assert_str(Gear.pip_line(v,"res_pip")).is_equal(LINE)
