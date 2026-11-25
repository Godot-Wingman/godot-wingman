@tool
extends RefCounted
## Scales an image down and encodes it (JPEG, PNG or WebP) for sending to the AI.
## Shared by the editor and the running game, so it uses no editor-only classes.

const DEFAULT_MAX_SIZE := 1280
const DEFAULT_QUALITY := 0.8


## Returns the encoded bytes plus size and MIME type. `params` may contain max_size
## (longest side in pixels), format ("jpeg", "png", "webp") and quality (0 to 1).
static func encode_bytes(image: Image, params: Dictionary) -> Dictionary:
	var max_size := int(params.get("max_size", DEFAULT_MAX_SIZE))
	var longest_side := maxi(image.get_width(), image.get_height())
	if max_size > 0 and longest_side > max_size:
		var scale_factor := float(max_size) / float(longest_side)
		image.resize(
			maxi(1, roundi(image.get_width() * scale_factor)),
			maxi(1, roundi(image.get_height() * scale_factor)),
			Image.INTERPOLATE_LANCZOS
		)

	var format := String(params.get("format", "jpeg"))
	var encoded_bytes: PackedByteArray
	var mime_type := "image/jpeg"
	if format == "png":
		encoded_bytes = image.save_png_to_buffer()
		mime_type = "image/png"
	elif format == "webp":
		encoded_bytes = image.save_webp_to_buffer(true, float(params.get("quality", DEFAULT_QUALITY)))
		mime_type = "image/webp"
	else:
		image.convert(Image.FORMAT_RGB8)
		encoded_bytes = image.save_jpg_to_buffer(float(params.get("quality", DEFAULT_QUALITY)))

	return {
		"mime_type": mime_type,
		"bytes": encoded_bytes,
		"width": image.get_width(),
		"height": image.get_height(),
	}

