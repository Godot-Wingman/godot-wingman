# C# and GDExtension (Rust, C++) projects

Godot Wingman works with every language Godot supports. The editor side always talks GDScript, but your game code can be anything.

## Find out what the project uses

`get_editor_state` returns `csharp_available` (the editor is the .NET build) and `gdextensions` (loaded native extensions, for example a Rust library).

## C#

- C# needs the .NET build of Godot ("Godot_v4.x-stable_mono").
- Scripts are `.cs` files; the class name must match the file name.
- After changing C# code, the project must be built (`dotnet build` in the project folder, or the Build button in the editor) before the editor sees new classes, properties or signals.
- `get_class_docs` with `language: "csharp"` shows C# code examples. Godot's C# API uses PascalCase: `move_and_slide()` is `MoveAndSlide()`.

## GDExtension (Rust with godot-rust, C++ with godot-cpp)

- The native code lives outside the Godot project, usually in a Cargo or CMake project, and is compiled into a library listed in a `.gdextension` file.
- Build it with its own tool (`cargo build`, `scons`, `cmake`). Use your own shell for that; Godot Wingman does not compile native code.
- Godot reloads extensions marked `reloadable = true` in the `.gdextension` file when the library changes. Otherwise restart the editor.
- Classes registered by the extension are real engine classes: `get_class_docs` reads them from the running editor, and they can be added as nodes like any built-in class.
- Heavy work (world generation, pathfinding over huge maps) is a good fit for Rust or C++; keep scene setup and glue code in GDScript.
