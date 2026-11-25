@tool
extends RefCounted
## Shows an "Allow / Deny" dialog in the editor.
##
## Used in the "confirm" permission mode: before the AI changes anything, the person
## sitting at the editor sees what is about to happen and decides.

const DEFAULT_TIMEOUT_SECONDS := 120.0


## Shows the dialog and waits for the answer. Returns true when the person clicked
## "Allow". Closing the dialog, clicking "Deny" or waiting too long all mean no.
static func ask(title: String, description: String, timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS) -> bool:
	var dialog := ConfirmationDialog.new()
	dialog.title = "AI request: %s" % title
	dialog.dialog_text = description
	dialog.dialog_autowrap = true
	dialog.ok_button_text = "Allow"
	dialog.cancel_button_text = "Deny"
	dialog.min_size = Vector2i(520, 0)

	# Both buttons and the timer report into this small state object, and we wait
	# until one of them has written an answer.
	var decision := {"answered": false, "allowed": false}
	var answer := func(allowed: bool) -> void:
		if not decision["answered"]:
			decision["answered"] = true
			decision["allowed"] = allowed

	dialog.confirmed.connect(answer.bind(true))
	dialog.canceled.connect(answer.bind(false))

	var base_control := EditorInterface.get_base_control()
	base_control.add_child(dialog)
	dialog.popup_centered()

	var tree := base_control.get_tree()
	var deadline_milliseconds := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not decision["answered"] and Time.get_ticks_msec() < deadline_milliseconds:
		await tree.process_frame

	dialog.queue_free()
	return decision["allowed"]
