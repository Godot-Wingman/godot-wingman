@tool
extends AcceptDialog
## The "Connect AI apps" window of the Godot Wingman panel.
##
## It lists the AI apps on this computer (Claude, Codex, Cursor...) and whether Godot
## Wingman is set up in each, with a Configure button per app. The work is done by the
## installed program: `godot-wingman setup --status --json` and
## `godot-wingman setup --client <app> --json`. The program notes where it is installed in
## installation.json (written by server/src/installation.ts). When that file is missing,
## for example after installing only this addon from the Asset Library, the window offers
## the one-line installer instead.

const EditorRegistryFile := preload("../bridge/editor_registry_file.gd")

const INSTALLATION_FILE_NAME := "installation.json"
const WINDOWS_INSTALL_COMMAND := "irm https://raw.githubusercontent.com/Godot-Wingman/godot-wingman/main/install/install.ps1 | iex"
const UNIX_INSTALL_COMMAND := "curl -fsSL https://raw.githubusercontent.com/Godot-Wingman/godot-wingman/main/install/install.sh | sh"
## What each outcome of `setup --status` means for the person, and the button it gets.
const STATUS_TEXTS := {
	"already set up": "Set up",
	"would add": "Not set up",
	"would update": "Set up with an older command",
	"skipped": "Not installed",
	"failed": "Cannot be changed automatically",
}

var _content: VBoxContainer
var _setup_thread: Thread
## True while the running setup is a Configure button's, not the status check.
var _is_configuring := false
## What the last Configure did, shown once above the list.
var _note := ""


func _init() -> void:
	title = "Connect AI apps to Godot Wingman"
	ok_button_text = "Close"
	var editor_scale := EditorInterface.get_editor_scale()
	min_size = Vector2i(int(640 * editor_scale), int(380 * editor_scale))
	_content = VBoxContainer.new()
	# Wrapping labels need a width, or they grow one word per line.
	_content.custom_minimum_size.x = 600 * editor_scale
	_content.add_theme_constant_override("separation", int(10 * editor_scale))
	add_child(_content)
	confirmed.connect(queue_free)
	canceled.connect(queue_free)
	tree_exiting.connect(_wait_for_setup_thread)


## Shows the window and fills it with the current state of every app.
func open() -> void:
	popup_centered(min_size)
	refresh()


func refresh() -> void:
	var installation := read_installation()
	if installation.is_empty():
		_show_install_offer()
		return
	_show_text("Checking the AI apps on this computer...")
	_run_setup(installation, ["--status"])


## The launch command of the installed program: {command, args, version}, or {} when the
## program is not installed.
static func read_installation() -> Dictionary:
	var file_path := EditorRegistryFile.get_product_home_directory().path_join(INSTALLATION_FILE_NAME)
	if not FileAccess.file_exists(file_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if not parsed is Dictionary or not parsed.has("command"):
		return {}
	if not FileAccess.file_exists(String(parsed["command"])):
		return {}
	return parsed


func _run_setup(installation: Dictionary, extra_arguments: Array[String]) -> void:
	if _setup_thread != null:
		return
	var program_arguments := PackedStringArray(installation.get("args", []))
	program_arguments.append_array(["setup", "--json", "--project", ProjectSettings.globalize_path("res://")])
	program_arguments.append_array(extra_arguments)
	var command := String(installation["command"])
	# Checking Claude Code runs its own command, which can take a few seconds, so the
	# program runs on a thread and the editor stays responsive.
	_setup_thread = Thread.new()
	_setup_thread.start(func() -> void:
		var output: Array = []
		var exit_code := OS.execute(command, program_arguments, output, true)
		_on_setup_finished.call_deferred(exit_code, "\n".join(output))
	)


func _on_setup_finished(exit_code: int, output_text: String) -> void:
	_wait_for_setup_thread()
	var result: Variant = null
	for line in output_text.split("\n", false):
		if line.strip_edges().begins_with("{"):
			result = JSON.parse_string(line)
	if exit_code != 0 or not result is Dictionary:
		_is_configuring = false
		_show_text("Godot Wingman could not check the AI apps:\n%s" % output_text.strip_edges().left(1500))
		return
	if _is_configuring:
		# Remember what happened to that app, then list every app again.
		_is_configuring = false
		var steps: Array = result.get("steps", [])
		var step: Dictionary = steps[0] if not steps.is_empty() else {}
		if step.get("outcome", "") == "added" or step.get("outcome", "") == "updated":
			_note = "%s is configured (%s). Restart it to use Godot Wingman." % [step.get("client", ""), step.get("detail", "")]
		else:
			_note = "%s was not changed: %s" % [step.get("client", ""), step.get("detail", "")]
		refresh()
		return
	_show_apps(result)


func _wait_for_setup_thread() -> void:
	if _setup_thread != null:
		_setup_thread.wait_to_finish()
		_setup_thread = null


func _show_apps(result: Dictionary) -> void:
	_clear()
	if _note != "":
		var note_label := Label.new()
		note_label.text = _note
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_label.add_theme_color_override("font_color", EditorInterface.get_base_control().get_theme_color("accent_color", "Editor"))
		_content.add_child(note_label)
		_note = ""
	var intro := Label.new()
	intro.text = "Godot Wingman %s can be added to these AI apps. Restart an app after configuring it." % result.get("version", "")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(intro)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(16 * EditorInterface.get_editor_scale()))
	_content.add_child(grid)
	var theme_source := EditorInterface.get_base_control()
	for step: Dictionary in result.get("steps", []):
		var outcome := String(step.get("outcome", ""))
		var name_label := Label.new()
		name_label.text = String(step.get("client", ""))
		grid.add_child(name_label)

		var status_label := Label.new()
		status_label.text = STATUS_TEXTS.get(outcome, outcome)
		status_label.tooltip_text = String(step.get("detail", ""))
		status_label.mouse_filter = Control.MOUSE_FILTER_PASS
		status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if outcome == "already set up":
			status_label.add_theme_color_override("font_color", theme_source.get_theme_color("success_color", "Editor"))
		elif outcome == "skipped" or outcome == "failed":
			status_label.modulate = Color(1, 1, 1, 0.55)
		grid.add_child(status_label)

		var configure_button := Button.new()
		configure_button.text = "Update" if outcome == "would update" else "Configure"
		configure_button.disabled = outcome != "would add" and outcome != "would update"
		if step.get("id", "") == "vscode":
			configure_button.tooltip_text = "VS Code is set up per project: this writes .vscode/mcp.json in this Godot project."
		var client_id := String(step.get("id", ""))
		configure_button.pressed.connect(func() -> void: _configure(client_id))
		grid.add_child(configure_button)

	var check_again_button := Button.new()
	check_again_button.text = "Check again"
	check_again_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	check_again_button.pressed.connect(refresh)
	_content.add_child(check_again_button)
	reset_size.call_deferred()


func _configure(client_id: String) -> void:
	var installation := read_installation()
	if installation.is_empty():
		_show_install_offer()
		return
	_show_text("Configuring...")
	_is_configuring = true
	_run_setup(installation, ["--client", client_id])


func _show_install_offer() -> void:
	_clear()
	var is_windows := OS.get_name() == "Windows"
	var install_command := WINDOWS_INSTALL_COMMAND if is_windows else UNIX_INSTALL_COMMAND
	var explanation := Label.new()
	explanation.text = "The Godot Wingman program is not installed on this computer yet. It is what your AI app starts, and it adds itself to the AI apps it finds.\n\nInstall it with this command in %s:" % ("PowerShell" if is_windows else "a terminal")
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(explanation)

	var command_row := HBoxContainer.new()
	_content.add_child(command_row)
	var command_field := LineEdit.new()
	command_field.text = install_command
	command_field.editable = false
	command_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_row.add_child(command_field)
	var copy_button := Button.new()
	copy_button.text = "Copy"
	copy_button.pressed.connect(func() -> void: DisplayServer.clipboard_set(install_command))
	command_row.add_child(copy_button)

	var buttons := HBoxContainer.new()
	_content.add_child(buttons)
	if is_windows or OS.get_name() == "macOS":
		var install_button := Button.new()
		install_button.text = "Open a terminal and install"
		install_button.tooltip_text = "Runs the command above in a new %s window." % ("PowerShell" if is_windows else "Terminal")
		install_button.pressed.connect(func() -> void: _run_installer_in_terminal(install_command))
		buttons.add_child(install_button)
	var check_again_button := Button.new()
	check_again_button.text = "Check again"
	check_again_button.pressed.connect(refresh)
	buttons.add_child(check_again_button)
	reset_size.call_deferred()


func _run_installer_in_terminal(install_command: String) -> void:
	if OS.get_name() == "Windows":
		OS.create_process("powershell.exe", ["-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", install_command], true)
	else:
		var apple_script := 'tell application "Terminal" to do script "%s"' % install_command.c_escape()
		OS.create_process("osascript", ["-e", apple_script, "-e", 'tell application "Terminal" to activate'])


func _show_text(text: String) -> void:
	_clear()
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)
	reset_size.call_deferred()


func _clear() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
