class_name SaveStore
extends RefCounted
## Keeps the run in one JSON file. A save writes `path + ".tmp"` and renames it over `path`, so
## a kill during the write leaves the previous save whole. A file that cannot be loaded is moved
## to `path + ".corrupt"`, which leaves the player with a clean "New run" and the file to inspect.

var _path: String


func _init(path := "user://run.json") -> void:
	_path = path


## Writes `run` over the save. Returns false when the write or the rename fails, and then
## the previous save is untouched.
func save(run: RunState) -> bool:
	var temp_path := _path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	var written := file.store_string(JSON.stringify(run.to_dict()))
	file.close()
	if not written or DirAccess.rename_absolute(temp_path, _path) != OK:
		DirAccess.remove_absolute(temp_path)
		return false
	return true


## Loads the saved run, or returns null when there is none. A file that is not valid JSON, whose
## root is not an object, or that `RunState.from_dict` rejects (another version included) is moved
## to `path + ".corrupt"`, replacing an older one.
func load_run() -> RunState:
	if not FileAccess.file_exists(_path):
		return null
	var json := JSON.new()
	var run: RunState = null
	if json.parse(FileAccess.get_file_as_string(_path)) == OK and json.data is Dictionary:
		run = RunState.from_dict(json.data)
	if run == null:
		_set_aside()
	return run


## True when there is a save that loads. It loads the file, so an unusable one is set aside.
func has_save() -> bool:
	return load_run() != null


## Deletes the save.
func clear() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)


func _set_aside() -> void:
	var corrupt_path := _path + ".corrupt"
	if FileAccess.file_exists(corrupt_path):
		DirAccess.remove_absolute(corrupt_path)
	DirAccess.rename_absolute(_path, corrupt_path)
