class_name Updater
extends Node
## Checks GitHub Releases for a newer version of the game and installs it.
##
## Where it looks: rules.json → "updates": {"repo": "owner/name"}. The repo's
## latest release is read from the GitHub API; its tag ("v0.10.0") is compared
## with this build's version (project.godot → config/version), its notes are
## the change list, and its asset ending in "-windows.zip" is the download.
## The personal setup updates too when its models come from osrs_models.pck
## (only the exe is replaced, the pack stays); an old personal exe with the
## models built in only reports that a new version exists.
##
## Installing (exported Windows build): the zip is downloaded next to the exe,
## then a small script waits for the game to close, unzips it over the old
## exe and starts the new one.

signal checked(result: Dictionary)
signal progress(done: int, total: int)
signal downloaded(path: String)
signal failed(message: String)

const API := "https://api.github.com/repos/%s/releases/latest"

var _http: HTTPRequest
var _download: HTTPRequest
var _download_total := 0
var _download_path := ""


## This build's version ("0.10.0").
static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


static func repo() -> String:
	return str(GameData.rule("updates", {}).get("repo", ""))


## The personal setup: the private OSRS models, either loaded from
## osrs_models.pck next to the exe (ModelPack) or built into an old-style
## personal exe (export feature "personal").
static func is_personal_build() -> bool:
	return models_from_pack() or OS.has_feature("personal")


## Models in osrs_models.pck survive an update (only the exe is replaced),
## so this setup can install public releases.
static func models_from_pack() -> bool:
	return ModelPack.loaded


## Whether installing a public release is safe here: everything but an
## old-style personal exe with the models built in (it would lose them).
static func can_install() -> bool:
	return models_from_pack() or not OS.has_feature("personal")


## "v0.10.1" -> [0, 10, 1]; anything that isn't a number counts as 0.
static func parse_version(v: String) -> Array[int]:
	var out: Array[int] = []
	var s := v.strip_edges().trim_prefix("v").trim_prefix("V")
	for part in s.split("-")[0].split("."):
		out.append(int(part) if part.is_valid_int() else 0)
	while out.size() < 3:
		out.append(0)
	return out


## True when `latest` is a newer version than `current`.
static func is_newer(latest: String, current: String) -> bool:
	var a := parse_version(latest)
	var b := parse_version(current)
	for i in maxi(a.size(), b.size()):
		var x: int = a[i] if i < a.size() else 0
		var y: int = b[i] if i < b.size() else 0
		if x != y:
			return x > y
	return false


## Reads a GitHub "latest release" reply into what the splash screen shows:
## {version, newer, notes, url (release page), download, size, name}.
static func read_release(data: Dictionary, current: String) -> Dictionary:
	var tag := str(data.get("tag_name", ""))
	var out := {
		"version": tag.trim_prefix("v"),
		"newer": tag != "" and is_newer(tag, current),
		"notes": str(data.get("body", "")).strip_edges(),
		"url": str(data.get("html_url", "")),
		"download": "", "size": 0, "name": "",
	}
	for a in data.get("assets", []):
		var n := str(a.get("name", "")).to_lower()
		if n.ends_with("-windows.zip") and not n.contains("personal"):
			out["download"] = str(a.get("browser_download_url", ""))
			out["size"] = int(a.get("size", 0))
			out["name"] = str(a.get("name", ""))
			break
	return out


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(_on_checked)


## Asks GitHub for the latest release; answers with `checked` or `failed`.
func check() -> void:
	if repo() == "":
		failed.emit("No update source is set up (rules.json → updates.repo).")
		return
	var headers := ["Accept: application/vnd.github+json", "User-Agent: GielinorLegends/" + current_version()]
	var err := _http.request(API % repo(), headers)
	if err != OK:
		failed.emit("Couldn't start the check (error %d)." % err)


func _on_checked(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit("Couldn't reach GitHub. Check your internet connection.")
		return
	if code == 404:
		failed.emit("No published release was found. Releases have to be public for the game to see them.")
		return
	if code != 200:
		failed.emit("GitHub answered %d. Try again in a minute." % code)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary):
		failed.emit("GitHub's reply couldn't be read.")
		return
	checked.emit(read_release(data, current_version()))


## Downloads a release zip next to the game (the "updates" folder).
func download(url: String, size: int = 0) -> void:
	if url == "":
		failed.emit("This release has no Windows download.")
		return
	var dir := update_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	_download_path = dir.path_join("update.zip")
	_download_total = size
	if _download != null:
		_download.queue_free()
	_download = HTTPRequest.new()
	_download.download_file = _download_path
	_download.timeout = 0.0
	add_child(_download)
	_download.request_completed.connect(_on_downloaded)
	var err := _download.request(url, ["User-Agent: GielinorLegends/" + current_version()])
	if err != OK:
		failed.emit("Couldn't start the download (error %d)." % err)


func _process(_delta: float) -> void:
	if _download != null and _download.get_http_client_status() == HTTPClient.STATUS_BODY:
		var total := _download_total if _download_total > 0 else _download.get_body_size()
		progress.emit(_download.get_downloaded_bytes(), total)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit("The download failed (%s). Try again." % (str(code) if result == HTTPRequest.RESULT_SUCCESS else "no connection"))
		return
	downloaded.emit(_download_path)


## Where downloads go: an "updates" folder next to the exe (user data when
## running from the editor).
static func update_dir() -> String:
	if OS.has_feature("editor"):
		return OS.get_user_data_dir().path_join("updates")
	return OS.get_executable_path().get_base_dir().path_join("updates")


## The Windows script that swaps in the new version once the game has closed.
static func install_script(zip: String, exe: String, pid: int) -> String:
	var dir := exe.replace("\\", "/").get_base_dir().replace("/", "\\")
	return "\r\n".join([
		"@echo off",
		"rem Gielinor Legends updater: waits for the game to close, unzips the new version over it and restarts it.",
		":wait",
		"tasklist /FI \"PID eq %d\" 2>NUL | find \"%d\" >NUL && (ping -n 2 127.0.0.1 >NUL & goto wait)" % [pid, pid],
		"powershell -NoProfile -ExecutionPolicy Bypass -Command \"Expand-Archive -LiteralPath '%s' -DestinationPath '%s' -Force\"" % [zip, dir],
		"del \"%s\"" % zip,
		"start \"\" \"%s\"" % (dir + "\\GielinorLegends.exe"),
		"del \"%~f0\"",
	]) + "\r\n"


## Writes the install script, starts it and closes the game. Returns false
## (and does nothing) where it can't self-install: not Windows, or the editor.
func install(zip: String) -> bool:
	if OS.get_name() != "Windows" or OS.has_feature("editor"):
		return false
	var exe := OS.get_executable_path()
	var bat := update_dir().path_join("install_update.bat")
	var f := FileAccess.open(bat, FileAccess.WRITE)
	if f == null:
		failed.emit("Couldn't write the installer next to the game (is the folder read-only?).")
		return false
	f.store_string(install_script(zip.replace("/", "\\"), exe.replace("/", "\\"), OS.get_process_id()))
	f.close()
	OS.create_process("cmd.exe", ["/c", bat.replace("/", "\\")])
	get_tree().quit()
	return true
