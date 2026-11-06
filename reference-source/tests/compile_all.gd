extends SceneTree
## Loads every .gd in the project so parse/compile errors surface. Exit code 1 on failure.

func _initialize() -> void:
	var bad := 0
	var files: Array = []
	_collect("res://scripts", files)
	_collect("res://tests", files)
	for f in files:
		if f.ends_with("compile_all.gd"):
			continue
		var s = load(f)
		if s == null or (s is GDScript and not s.can_instantiate() and not f.contains("autoload")):
			print("FAILED to compile: ", f)
			bad += 1
	print("compiled %d scripts, %d failures" % [files.size(), bad])
	quit(1 if bad > 0 else 0)

func _collect(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	for n in d.get_directories():
		_collect(dir + "/" + n, out)
	for n in d.get_files():
		if n.ends_with(".gd"):
			out.append(dir + "/" + n)
