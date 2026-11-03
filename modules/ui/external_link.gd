class_name ExternalLink
## Every page the app hands to the system browser goes through open(): one door, so a test run or a headless run
## records the address instead of opening it. Before it, each test run opened the voice-match H5 (and could open the
## map credits, a licence's link, the store page) in the desktop's default browser and never closed it — the user's
## Edge grew tab by tab. Tests read `asked`; `shell_opens` counts the real OS.shell_open calls this process made.

const GDUNIT := "res://addons/gdUnit4/"

## The addresses asked for while quiet(), oldest first.
static var asked: Array[String] = []
## The real OS.shell_open calls this process made (0 for a whole test run: the guard test).
static var shell_opens := 0

static func open(url: String) -> void:
	if quiet():
		asked.append(url)
		return
	shell_opens += 1
	OS.shell_open(url)

## Nothing leaves the process: no display (--headless), or gdUnit runs it — its command-line tool is the main loop's
## script (runtest.sh), the editor's runner the main scene (GdUnitTestRunner.tscn).
static func quiet() -> bool:
	if DisplayServer.get_name() == "headless": return true
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return false
	var s = tree.get_script()
	if s is Script and (s as Script).resource_path.begins_with(GDUNIT): return true
	return tree.current_scene != null and tree.current_scene.scene_file_path.begins_with(GDUNIT)
