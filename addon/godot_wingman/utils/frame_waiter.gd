@tool
extends RefCounted
## Waits until the editor has drawn a new frame, for screenshots and renders.
##
## The editor saves power by only drawing when something changes. When it sits idle,
## waiting for RenderingServer.frame_post_draw alone could wait forever. So we ask for a
## redraw, and if no frame comes within a short time, we draw one ourselves.

const MAXIMUM_WAIT_MILLISECONDS := 500


static func wait_for_drawn_frame(tree: SceneTree) -> void:
	var state := {"drawn": false}
	var mark_drawn := func() -> void: state["drawn"] = true
	RenderingServer.frame_post_draw.connect(mark_drawn, CONNECT_ONE_SHOT)
	EditorInterface.get_base_control().queue_redraw()
	var deadline_milliseconds := Time.get_ticks_msec() + MAXIMUM_WAIT_MILLISECONDS
	while not state["drawn"] and Time.get_ticks_msec() < deadline_milliseconds:
		await tree.process_frame
	if not state["drawn"]:
		RenderingServer.frame_post_draw.disconnect(mark_drawn)
		RenderingServer.force_draw()
