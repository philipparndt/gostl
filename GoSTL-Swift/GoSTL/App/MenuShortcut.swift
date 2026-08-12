import SwiftUI

/// The modifiers a menu command may use.
///
/// There is no case for "none", and that absence is the whole point. A menu item
/// with `.keyboardShortcut("o", modifiers: [])` takes a bare `o` before the
/// event ever reaches the first responder, so the viewport's own `case "o"` in
/// `InputHandler` was unreachable while there was a menu and the only path when
/// there was not — the same key owned by two different pieces of code depending
/// on whether GoSTL was running as an application or embedded in someone else's
/// window (0481). Two owners is one too many even when only one of them fires,
/// because which one it is cannot be told from either.
///
/// So single keys belong to the viewport, listed in `ViewportKeys`, and a menu
/// command cannot claim one: `menuShortcut` is the only way this app declares a
/// shortcut, and it cannot express a bare key.
enum MenuModifiers {
    case command
    case commandShift
    case commandShiftOption

    var eventModifiers: EventModifiers {
        switch self {
        case .command: return .command
        case .commandShift: return [.command, .shift]
        case .commandShiftOption: return [.command, .shift, .option]
        }
    }
}

extension View {
    /// A keyboard shortcut for a menu command, which always has a modifier.
    func menuShortcut(_ key: KeyEquivalent, _ modifiers: MenuModifiers) -> some View {
        keyboardShortcut(key, modifiers: modifiers.eventModifiers)
    }
}

/// The single keys the viewport answers to, which no menu command may bind.
///
/// This list is what `InputHandler.handleKeyDown` switches on. It is written
/// down separately because the hazard it guards against is invisible from
/// either side: a menu item that binds one of these bare takes the key away
/// from the viewport silently, and the viewport's own case becomes dead code
/// that still looks live. `MenuModifiers` makes that unwritable; this says
/// which keys are at stake, for whoever wonders why a menu item has no
/// shortcut beside it.
///
/// The keys are still shown to the user — as `KeyHint` badges in the panel,
/// beside the action they perform, which is where somebody looking for them
/// looks.
enum ViewportKeys {
    static let owned: Set<Character> = [
        "1", "2", "3", "4", "5", "6", "7",   // camera presets
        "w", "g", "i", "m",                  // wireframe, grid, panel, material
        "d", "a", "r", "t",                  // distance, angle, radius, triangles
        "x", "y", "z", "c",                  // axis constraints, end, clear
        "f",                                 // frame the model
        "l",                                 // level
        "o",                                 // open with go3mf
    ]
}
