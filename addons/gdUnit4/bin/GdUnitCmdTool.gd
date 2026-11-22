#!/usr/bin/env -S godot -s
extends SceneTree


var _cli_runner: GdUnitTestCIRunner


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_cli_runner = GdUnitTestCIRunner.new()
	root.add_child(_cli_runner)


# do not use print statements on _finalize it results in random crashes
func _finalize() -> void:
	# sensen C-24: SceneTree.finalize() frees root, and the runner with it, before _finalize. queue_delete on the freed
	# runner wrote into freed memory: glibc aborted at exit (exit 134) after all tests passed.
	if is_instance_valid(_cli_runner):
		queue_delete(_cli_runner)
	if OS.is_stdout_verbose():
		prints("Finallize ..")
		prints("-Orphan nodes report-----------------------")
		Window.print_orphan_nodes()
		prints("Finallize .. done")
