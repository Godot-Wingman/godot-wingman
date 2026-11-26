@tool
extends RefCounted
## An error returned by a request handler.
##
## GDScript has no exceptions, so handlers return an instance of this class
## instead of a normal value when something goes wrong. The dispatcher turns it
## into an error response that the MCP server shows to the AI.

## Short machine-readable error name, for example "NODE_NOT_FOUND".
var code: String
## What went wrong, written for the AI that called the tool.
var message: String
## Optional advice on how to fix the call.
var hint: String
## Optional extra data, for example the list of compile errors.
var details: Variant


func _init(error_code: String, error_message: String, error_hint: String = "", error_details: Variant = null) -> void:
	code = error_code
	message = error_message
	hint = error_hint
	details = error_details


func to_dictionary() -> Dictionary:
	var result := {"code": code, "message": message}
	if hint != "":
		result["hint"] = hint
	if details != null:
		result["details"] = details
	return result
