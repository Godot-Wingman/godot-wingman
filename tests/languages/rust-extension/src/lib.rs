//! A GDExtension class for the tests: WingmanGreeter, a Node2D with an exported
//! property, a method and a signal.

use godot::prelude::*;

struct WingmanExtension;

#[gdextension]
unsafe impl ExtensionLibrary for WingmanExtension {}

/// Says hello when the game starts.
#[derive(GodotClass)]
#[class(base = Node2D, init)]
struct WingmanGreeter {
    #[export]
    #[init(val = GString::from("hello from Rust"))]
    greeting: GString,
    base: Base<Node2D>,
}

#[godot_api]
impl INode2D for WingmanGreeter {
    fn ready(&mut self) {
        godot_print!("WingmanGreeter is ready: {}", self.greeting);
    }
}

#[godot_api]
impl WingmanGreeter {
    #[signal]
    fn greeted();

    /// The greeting in capital letters.
    #[func]
    fn shout(&self) -> GString {
        GString::from(self.greeting.to_string().to_uppercase().as_str())
    }
}
