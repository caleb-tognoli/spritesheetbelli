class_name WebFiles
## File picking and downloading for the web build, where file dialogs can't reach the
## user's files. Picked files are copied into [constant UPLOAD_DIR] so the rest of the app
## can open them by path; files written to [constant OUTPUT_DIR] are then downloaded.

const UPLOAD_DIR := "user://web_uploads"
const OUTPUT_DIR := "user://web_output"
const IMAGE_TYPES := ".png,.jpg,.jpeg,.jpe,.webp"

## Opens the browser's file picker and sends each file to Godot as base64
const PICKER_SCRIPT := """
(function() {
	var input = document.createElement('input');
	input.type = 'file';
	input.accept = '%s';
	input.multiple = %s;
	input.webkitdirectory = %s;
	// Some browsers only open the picker for inputs in the page
	input.style.display = 'none';
	document.body.appendChild(input);
	input.onchange = function() {
		input.remove();
		var files = Array.from(input.files).filter(function(f) {
			return !%s || /\\.(png|jpe?g|jpe|webp)$/i.test(f.name);
		});
		files.forEach(function(file) {
			var reader = new FileReader();
			reader.onload = function() {
				var data = String(reader.result);
				window.sbelliReceiveFile(file.name, data.substring(data.indexOf(',') + 1), files.length);
			};
			reader.readAsDataURL(file);
		});
	};
	input.click();
})();
"""
const MIME_TYPES := {
	"png": "image/png",
	"jpg": "image/jpeg",
	"jpeg": "image/jpeg",
	"jpe": "image/jpeg",
	"webp": "image/webp",
	"json": "application/json",
	"atlas": "text/plain",
	"xml": "application/xml",
	"tres": "text/plain",
	"zip": "application/zip",
}

## Keeps the JavaScript callback alive while the browser reads files
static var _callback: JavaScriptObject


static func is_web() -> bool:
	return OS.has_feature("web")


## Opens the browser's file picker. [param on_files] receives the copied files' paths.
## With [param folder], the user picks a folder and gets every file in it.
static func pick(accept: String, multiple: bool, on_files: Callable, folder := false) -> void:
	DirAccess.make_dir_recursive_absolute(UPLOAD_DIR)
	var received := {"paths": PackedStringArray(), "count": 0}
	_callback = JavaScriptBridge.create_callback(
		func(args: Array) -> void:
			var file_name: String = str(args[0]).get_file()
			var total := int(args[2])
			var path := UPLOAD_DIR.path_join(file_name)
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file:
				file.store_buffer(Marshalls.base64_to_raw(str(args[1])))
				file.close()
				received.paths.append(path)
			received.count += 1
			if received.count >= total:
				on_files.call(received.paths)
	)
	var window := JavaScriptBridge.get_interface("window")
	window.sbelliReceiveFile = _callback
	var flags := [accept, str(multiple).to_lower(), str(folder).to_lower(), str(folder).to_lower()]
	JavaScriptBridge.eval(PICKER_SCRIPT % flags, true)


## Where a file the user saves goes before it's downloaded
static func output_path(file_name: String) -> String:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	return OUTPUT_DIR.path_join(file_name.get_file())


## Downloads a file written by the app, when running in a browser
static func download(path: String) -> void:
	if not is_web() or not FileAccess.file_exists(path):
		return
	var mime: String = MIME_TYPES.get(path.get_extension().to_lower(), "application/octet-stream")
	JavaScriptBridge.download_buffer(FileAccess.get_file_as_bytes(path), path.get_file(), mime)


## Downloads every file in [param folder] as one zip
static func download_folder(folder: String, zip_name: String) -> void:
	if not is_web():
		return
	var zip_path := output_path(zip_name)
	var zip := ZIPPacker.new()
	if zip.open(zip_path) != OK:
		return
	for file in DirAccess.get_files_at(folder):
		zip.start_file(file)
		zip.write_file(FileAccess.get_file_as_bytes(folder.path_join(file)))
		zip.close_file()
	zip.close()
	download(zip_path)
