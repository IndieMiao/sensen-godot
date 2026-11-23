extends RefCounted
## Godot 4 instantiates project autoloads even under --script, so the real AppRouter already
## owns /root/AppRouter and a second node of that name is renamed. The code under test resolves
## the router by that path, so detach the singleton while the fake is installed, then put it back.
## Isolated QA projects have no autoloads; there `real` is null and nothing is detached.

## Installs `fake` as /root/AppRouter and returns the detached real router (or null).
static func install(root: Window, fake: Node) -> Node:
	var real := root.get_node_or_null("AppRouter")
	if real: root.remove_child(real)
	fake.name = "AppRouter"; root.add_child(fake)
	return real

## Removes and frees `fake`, then reattaches the real router returned by install().
static func restore(root: Window, fake: Node, real: Node) -> void:
	if is_instance_valid(fake):
		if fake.get_parent() == root: root.remove_child(fake)
		fake.free()
	if real: root.add_child(real)
