@tool
extends RefCounted
## Turns the Markdown the AIs write into parts the chat can show: text as BBCode for a
## RichTextLabel, and code blocks on their own, so the chat can show them in a box
## with a Copy button.
##
## Covers what AIs write in practice: headings, bold, italic, strikethrough, inline
## code, code blocks, bulleted and numbered lists (nested by indentation), quotes,
## tables, horizontal rules and links. res:// paths become links that open the file.

const PART_TEXT := "text"
const PART_CODE := "code"

static var _inline_code_pattern := _compile("`([^`]+)`")
static var _link_pattern := _compile("\\[([^\\]]+)\\]\\(([^)\\s]+)\\)")
static var _project_path_pattern := _compile("(?<![\\w/=])(res://[\\w\\-./]*[\\w/])")
static var _bold_pattern := _compile("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
static var _italic_pattern := _compile("(?<![\\w*])([*_])(?=\\S)(.+?)(?<=\\S)\\1(?![\\w*])")
static var _strikethrough_pattern := _compile("~~(?=\\S)(.+?)(?<=\\S)~~")
static var _heading_pattern := _compile("^(#{1,6})\\s+(.*)$")
static var _bullet_pattern := _compile("^(\\s*)[-*+]\\s+(.*)$")
static var _numbered_pattern := _compile("^(\\s*)\\d+[.)]\\s+(.*)$")
static var _rule_pattern := _compile("^\\s*([-*_])(\\s*\\1){2,}\\s*$")
static var _table_separator_pattern := _compile("^\\s*\\|?\\s*:?-{2,}:?\\s*(\\|\\s*:?-{2,}:?\\s*)*\\|?\\s*$")


## [{"type": PART_TEXT, "bbcode": String}, {"type": PART_CODE, "code": String,
## "language": String}], in order. `colors`: {"dim": Color, "code_background": Color,
## "link": Color}. `base_font_size` is the size of normal text, for headings.
static func to_parts(markdown: String, colors: Dictionary, base_font_size: int) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var text_lines := PackedStringArray()
	var lines := markdown.replace("\r\n", "\n").split("\n")
	var line_index := 0
	while line_index < lines.size():
		var line := lines[line_index]
		var stripped := line.strip_edges()
		if stripped.begins_with("```") or stripped.begins_with("~~~"):
			var fence := stripped.left(3)
			var code_lines := PackedStringArray()
			line_index += 1
			while line_index < lines.size() and not lines[line_index].strip_edges().begins_with(fence):
				code_lines.append(lines[line_index])
				line_index += 1
			_add_text_part(parts, text_lines, colors, base_font_size)
			text_lines.clear()
			parts.append({"type": PART_CODE, "code": "\n".join(code_lines), "language": stripped.substr(3).strip_edges()})
		else:
			text_lines.append(line)
		line_index += 1
	_add_text_part(parts, text_lines, colors, base_font_size)
	return parts


## The text without Markdown marks, for measuring and copying.
static func to_plain_text(markdown: String) -> String:
	var plain := _inline_code_pattern.sub(markdown, "$1", true)
	plain = _link_pattern.sub(plain, "$1", true)
	plain = _bold_pattern.sub(plain, "$2", true)
	plain = _italic_pattern.sub(plain, "$2", true)
	plain = _strikethrough_pattern.sub(plain, "$1", true)
	return plain


static func _add_text_part(parts: Array[Dictionary], lines: PackedStringArray, colors: Dictionary, base_font_size: int) -> void:
	# Blank lines at the start and end of a part only add space around code blocks.
	var first_index := 0
	var last_index := lines.size() - 1
	while first_index <= last_index and lines[first_index].strip_edges().is_empty():
		first_index += 1
	while last_index >= first_index and lines[last_index].strip_edges().is_empty():
		last_index -= 1
	if first_index > last_index:
		return
	var bbcode := _blocks_to_bbcode(lines.slice(first_index, last_index + 1), colors, base_font_size)
	parts.append({"type": PART_TEXT, "bbcode": bbcode})


static func _blocks_to_bbcode(lines: PackedStringArray, colors: Dictionary, base_font_size: int) -> String:
	var output := PackedStringArray()
	var dim := _html(colors.get("dim", Color.GRAY))
	## Open list tags, innermost last: [indentation, "ul" or "ol"].
	var open_lists: Array = []
	var line_index := 0
	while line_index < lines.size():
		var line := lines[line_index]
		var bullet := _bullet_pattern.search(line)
		var numbered := _numbered_pattern.search(line)
		var list_match := bullet if bullet != null else numbered
		if list_match != null:
			var indentation := list_match.get_string(1).replace("\t", "    ").length()
			var list_tag := "ul" if bullet != null else "ol type=1"
			while not open_lists.is_empty() and indentation < int(open_lists.back()[0]):
				output.append("[/%s]" % String(open_lists.pop_back()[1]).get_slice(" ", 0))
			if open_lists.is_empty() or indentation > int(open_lists.back()[0]):
				open_lists.append([indentation, list_tag])
				output.append("[%s]" % list_tag)
			output.append(_inline_to_bbcode(list_match.get_string(2), colors))
			line_index += 1
			continue
		while not open_lists.is_empty():
			output.append("[/%s]" % String(open_lists.pop_back()[1]).get_slice(" ", 0))

		var stripped := line.strip_edges()
		var heading := _heading_pattern.search(stripped)
		if heading != null:
			var level := heading.get_string(1).length()
			var size := int(base_font_size * ([1.35, 1.2, 1.1, 1.0, 1.0, 1.0][level - 1]))
			output.append("[font_size=%d][b]%s[/b][/font_size]" % [size, _inline_to_bbcode(heading.get_string(2), colors)])
		elif _rule_pattern.search(stripped) != null:
			output.append("[color=#%s]%s[/color]" % [dim, "─".repeat(24)])
		elif stripped.begins_with(">"):
			var quote_lines := PackedStringArray()
			while line_index < lines.size() and lines[line_index].strip_edges().begins_with(">"):
				quote_lines.append(_inline_to_bbcode(lines[line_index].strip_edges().trim_prefix(">").strip_edges(), colors))
				line_index += 1
			output.append("[indent][color=#%s]%s[/color][/indent]" % [dim, "\n".join(quote_lines)])
			continue
		elif stripped.begins_with("|") and line_index + 1 < lines.size() and _table_separator_pattern.search(lines[line_index + 1]) != null:
			var table_rows: Array[PackedStringArray] = [_split_table_row(stripped)]
			line_index += 2
			while line_index < lines.size() and lines[line_index].strip_edges().begins_with("|"):
				table_rows.append(_split_table_row(lines[line_index].strip_edges()))
				line_index += 1
			output.append(_table_to_bbcode(table_rows, colors))
			continue
		else:
			# Leading spaces do not indent a paragraph in Markdown.
			output.append(_inline_to_bbcode(stripped, colors))
		line_index += 1
	while not open_lists.is_empty():
		output.append("[/%s]" % String(open_lists.pop_back()[1]).get_slice(" ", 0))
	return "\n".join(output)


static func _split_table_row(row: String) -> PackedStringArray:
	var cells := row.trim_prefix("|").trim_suffix("|").split("|")
	var trimmed := PackedStringArray()
	for cell in cells:
		trimmed.append(cell.strip_edges())
	return trimmed


static func _table_to_bbcode(rows: Array[PackedStringArray], colors: Dictionary) -> String:
	var column_count := 0
	for row in rows:
		column_count = maxi(column_count, row.size())
	var output := "[table=%d]" % column_count
	for row_index in rows.size():
		for column_index in column_count:
			var cell: String = rows[row_index][column_index] if column_index < rows[row_index].size() else ""
			var cell_text := _inline_to_bbcode(cell, colors)
			if row_index == 0:
				cell_text = "[b]%s[/b]" % cell_text
			output += "[cell padding=0,2,16,2]%s[/cell]" % cell_text
	return output + "[/table]"


## Inline Markdown to BBCode. Code spans and links are taken out first, so their
## contents are not read as bold or italic, and "[" is escaped everywhere else.
static func _inline_to_bbcode(text: String, colors: Dictionary) -> String:
	var kept: Array[String] = []
	var working := text
	working =_replace_matches(working, _inline_code_pattern, func(found: RegExMatch) -> String:
		kept.append("[bgcolor=#%s][code]%s[/code][/bgcolor]" % [_html(colors.get("code_background", Color(0, 0, 0, 0.3))), _escape(found.get_string(1))])
		return _placeholder(kept.size() - 1))
	working = _replace_matches(working, _link_pattern, func(found: RegExMatch) -> String:
		kept.append("[url=%s][color=#%s]%s[/color][/url]" % [found.get_string(2).replace("]", "%5D"), _html(colors.get("link", Color.CORNFLOWER_BLUE)), _escape(found.get_string(1))])
		return _placeholder(kept.size() - 1))
	working = _replace_matches(working, _project_path_pattern, func(found: RegExMatch) -> String:
		kept.append("[url=%s][color=#%s]%s[/color][/url]" % [found.get_string(1), _html(colors.get("link", Color.CORNFLOWER_BLUE)), _escape(found.get_string(1))])
		return _placeholder(kept.size() - 1))
	working = _escape(working)
	working = _bold_pattern.sub(working, "[b]$2[/b]", true)
	working = _strikethrough_pattern.sub(working, "[s]$1[/s]", true)
	working = _italic_pattern.sub(working, "[i]$2[/i]", true)
	for kept_index in kept.size():
		working = working.replace(_placeholder(kept_index), kept[kept_index])
	return working


static func _replace_matches(text: String, pattern: RegEx, replacement: Callable) -> String:
	var result := ""
	var position := 0
	for found in pattern.search_all(text):
		result += text.substr(position, found.get_start() - position)
		result += String(replacement.call(found))
		position = found.get_end()
	return result + text.substr(position)


static func _placeholder(index: int) -> String:
	return "\u0001%d\u0001" % index


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func _html(color: Color) -> String:
	return color.to_html(true)


static func _compile(pattern: String) -> RegEx:
	var regex := RegEx.new()
	regex.compile(pattern)
	return regex
