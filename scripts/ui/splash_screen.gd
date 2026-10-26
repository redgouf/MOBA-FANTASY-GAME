class_name SplashScreen
extends CanvasLayer
## The first screen: the game's name, this build's version, Play, Check for
## updates and Quit. On opening (with "Update automatically" on) and on
## Check for updates it asks GitHub for the latest release (Updater); if
## it's newer, it lists the changes, downloads it, closes the game, swaps in
## the new version and starts it again, all in one go. Play skips it.

signal play_pressed

var updater: Updater
## Main sets this: check (and update) as soon as the splash opens.
var auto_check := false
var _manual := false
var _auto_box: CheckBox
var _root: Control
var _status: Label
var _notes: RichTextLabel
var _check: Button
var _install: Button
var _bar: ProgressBar
var _release: Dictionary = {}


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.size = Vector2(1600, 900)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.047, 0.036, 1.0)
	bg.size = _root.size
	_root.add_child(bg)
	# A faint Saradomin-blue / Zamorak-red split behind the title.
	for i in 2:
		var glow := ColorRect.new()
		glow.color = Color(0.25, 0.4, 0.9, 0.07) if i == 0 else Color(0.9, 0.2, 0.15, 0.07)
		glow.position = Vector2(800 * i, 0)
		glow.size = Vector2(800, 900)
		_root.add_child(glow)

	var p := OsrsUi.panel(_root, Rect2(500, 150, 600, 600))
	var title := OsrsUi.text(p, "Gielinor Legends", 46, OsrsUi.ORANGE, Rect2(0, 30, 600, 60))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = false
	var sub := OsrsUi.text(p, "A Saradomin-vs-Zamorak MOBA of Old School RuneScape builds", 15, OsrsUi.MUTED, Rect2(0, 92, 600, 22))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ver := OsrsUi.text(p, "Version %s%s" % [Updater.current_version(), "  ·  OSRS models" if Updater.is_personal_build() else ""],
		14, OsrsUi.YELLOW, Rect2(0, 118, 600, 20))
	ver.name = "Version"
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	OsrsUi.divider(p, 150)

	var play := _button(p, "Play", Rect2(150, 172, 300, 52), 22)
	play.name = "Play"
	play.pressed.connect(func() -> void: play_pressed.emit())
	_check = _button(p, "Check for updates", Rect2(150, 236, 300, 40), 16)
	_check.name = "CheckUpdates"
	_check.pressed.connect(check_for_updates)
	var quit := _button(p, "Quit", Rect2(150, 288, 300, 36), 15)
	quit.pressed.connect(func() -> void: get_tree().quit())
	_auto_box = CheckBox.new()
	_auto_box.name = "AutoUpdate"
	_auto_box.text = "Update automatically"
	_auto_box.button_pressed = Settings.auto_update
	_auto_box.focus_mode = Control.FOCUS_NONE
	_auto_box.add_theme_font_size_override("font_size", 13)
	_auto_box.add_theme_color_override("font_color", OsrsUi.MUTED)
	_auto_box.position = Vector2(222, 330)
	_auto_box.toggled.connect(func(on: bool) -> void:
		Settings.auto_update = on
		Settings.save_settings())
	p.add_child(_auto_box)

	_status = OsrsUi.text(p, "", 14, OsrsUi.WHITE, Rect2(24, 366, 552, 40))
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.clip_text = false
	_notes = RichTextLabel.new()
	_notes.bbcode_enabled = true
	_notes.position = Vector2(24, 410)
	_notes.size = Vector2(552, 124)
	_notes.add_theme_font_size_override("normal_font_size", 13)
	_notes.add_theme_color_override("default_color", Color(0.92, 0.88, 0.78))
	_notes.add_theme_stylebox_override("normal", OsrsUi.slot_box())
	_notes.visible = false
	p.add_child(_notes)
	_bar = ProgressBar.new()
	_bar.position = Vector2(24, 540)
	_bar.size = Vector2(552, 14)
	_bar.show_percentage = false
	_bar.visible = false
	p.add_child(_bar)
	_install = _button(p, "Download and install", Rect2(150, 540, 300, 40), 16)
	_install.name = "Install"
	_install.visible = false
	_install.pressed.connect(_download)

	var credit := OsrsUi.text(_root, "Free fan project, not for sale. Old School RuneScape and its assets are © Jagex Ltd; this game isn't affiliated with or endorsed by Jagex.",
		12, OsrsUi.MUTED, Rect2(0, 862, 1600, 20))
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	updater = Updater.new()
	add_child(updater)
	updater.checked.connect(_on_checked)
	updater.failed.connect(_on_failed)
	updater.progress.connect(_on_progress)
	updater.downloaded.connect(_on_downloaded)
	_boldify(_root)


## Every text on the splash screen in the bold OSRS font (big titles keep
## the quill font). Without the OSRS pack nothing changes.
func _boldify(n: Node) -> void:
	if not OsrsFont.active:
		return
	var bold := OsrsFont.get_font("b12_full")
	for c in n.get_children():
		if c is Label or c is Button or c is RichTextLabel:
			var big := c is Label and (c as Label).get_theme_font_size("font_size") >= 30
			if not big:
				(c as Control).add_theme_font_override("normal_font" if c is RichTextLabel else "font", bold)
				if c is RichTextLabel:
					(c as Control).add_theme_font_override("bold_font", bold)
		_boldify(c)
	if auto_check and Settings.auto_update:
		check_for_updates(false)


func _button(parent: Control, text: String, rect: Rect2, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	OsrsUi.style_button(b, size)
	parent.add_child(b)
	return b


## Checks GitHub; a newer version downloads and installs straight away when
## the check was clicked, or (automatic check) when "Update automatically"
## is on.
func check_for_updates(manual: bool = true) -> void:
	_manual = manual
	_check.disabled = true
	_install.visible = false
	_notes.visible = false
	_status.add_theme_color_override("font_color", OsrsUi.WHITE)
	_status.text = "Checking for updates..."
	updater.check()


## Shows a check's result (also used by tests with a made-up release).
func _on_checked(r: Dictionary) -> void:
	_release = r
	_check.disabled = false
	_install.visible = false
	_notes.visible = false
	if not bool(r.get("newer", false)):
		_status.add_theme_color_override("font_color", OsrsUi.GREEN)
		_status.text = "You have the latest version (%s)." % Updater.current_version()
		return
	_status.add_theme_color_override("font_color", OsrsUi.YELLOW)
	_status.text = "Version %s is out (you have %s). What's new:" % [r.get("version", "?"), Updater.current_version()]
	_notes.text = _format_notes(str(r.get("notes", "")))
	_notes.visible = true
	if not Updater.can_install():
		_status.text += "\nThis personal build has the models built in: ask for a new one."
	elif str(r.get("download", "")) == "":
		_status.text += "\nThis release has no Windows download yet."
	elif _manual or Settings.auto_update:
		_download()      # one step: download, install, restart
	else:
		_install.text = "Update now (%s)" % _mb(int(r.get("size", 0)))
		_install.visible = true


func _on_failed(message: String) -> void:
	_check.disabled = false
	_install.disabled = false
	_bar.visible = false
	_status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	_status.text = message


func _download() -> void:
	_install.visible = false
	_bar.visible = true
	_bar.value = 0.0
	_status.text = "Downloading version %s..." % _release.get("version", "?")
	updater.download(str(_release.get("download", "")), int(_release.get("size", 0)))


func _on_progress(done: int, total: int) -> void:
	if total > 0:
		_bar.max_value = total
		_bar.value = done
		_status.text = "Downloading version %s... %s of %s" % [_release.get("version", "?"), _mb(done), _mb(total)]


func _on_downloaded(path: String) -> void:
	_bar.value = _bar.max_value
	_status.text = "Installing: the game will close and reopen on the new version%s." % (
		" (your OSRS models stay)" if Updater.models_from_pack() else "")
	if not updater.install(path):
		_status.text = "Downloaded to %s. Unzip it over the game folder to update." % path.get_base_dir()
		if str(_release.get("url", "")) != "":
			OS.shell_open(str(_release["url"]))


## Markdown-ish release notes to BBCode: headings orange, bullets kept.
static func _format_notes(md: String) -> String:
	var out: Array[String] = []
	for line in md.split("\n"):
		var l := line.strip_edges(false, true)
		if l.begins_with("#"):
			out.append("[color=#ff981f][b]%s[/b][/color]" % l.lstrip("# "))
		elif l.begins_with("- ") or l.begins_with("* "):
			out.append("  •  " + l.substr(2).replace("**", ""))
		else:
			out.append(l.replace("**", ""))
	return "\n".join(out).strip_edges()


static func _mb(bytes: int) -> String:
	return "%.1f MB" % (float(bytes) / 1048576.0)
