@tool
extends RefCounted
## Finding nodes by name, shared by the editor and the running game (no editor classes here).

## Shorter names would match almost everything when looking for names that contain them.
const MINIMUM_PARTIAL_NAME_LENGTH := 3


## Paths of nodes whose name looks like the last part of `wanted_path` (same name in
## another place, different upper/lower case, or a name that contains it). Helps the AI
## fix a wrong path without listing the whole scene.
static func find_similar_node_paths(search_root: Node, wanted_path: String, maximum_count: int = 5) -> Array[String]:
	var wanted_name := wanted_path.get_file().to_lower()
	var similar_paths: Array[String] = []
	if wanted_name == "":
		return similar_paths
	var nodes_to_visit: Array[Node] = [search_root]
	while not nodes_to_visit.is_empty() and similar_paths.size() < maximum_count:
		var node: Node = nodes_to_visit.pop_front()
		var node_name := String(node.name).to_lower()
		var is_similar := node_name == wanted_name or node_name.contains(wanted_name) \
			or (node_name.length() >= MINIMUM_PARTIAL_NAME_LENGTH and wanted_name.contains(node_name))
		if node != search_root and is_similar:
			similar_paths.append("\"%s\"" % String(search_root.get_path_to(node)))
		nodes_to_visit.append_array(node.get_children())
	return similar_paths
