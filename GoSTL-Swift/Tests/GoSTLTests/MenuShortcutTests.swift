import XCTest
@testable import GoSTL

/// Who owns a single key.
///
/// `MenuModifiers` has no case for "no modifier", so `menuShortcut` cannot
/// declare a bare-letter menu shortcut — but `keyboardShortcut` still can, and
/// that is the mistake this guards. A menu item with
/// `.keyboardShortcut("o", modifiers: [])` consumes the key before the first
/// responder sees it, so `InputHandler`'s own `case "o"` was dead code while
/// GoSTL had a menu and the only path when it was embedded in another app's
/// window and had none (0481). Nothing about that is visible from either file.
///
/// So the claim is about the source of the menus, and it is checked there: the
/// commands declare their shortcuts through `menuShortcut` and through nothing
/// else. Reading a file in a test is unusual, and it is here because the
/// alternative — trusting a comment that says "do not do this" — is what was
/// there before.
final class MenuShortcutTests: XCTestCase {
    /// The app's own source, found relative to this file.
    private func appSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)   // …/Tests/GoSTLTests/this
            .deletingLastPathComponent()             // …/Tests/GoSTLTests
            .deletingLastPathComponent()             // …/Tests
            .deletingLastPathComponent()             // …/GoSTL-Swift
        let source = root.appendingPathComponent("GoSTL/App/GoSTLApp.swift")
        return try String(contentsOf: source, encoding: .utf8)
    }

    func testTheMenusDeclareTheirShortcutsThroughMenuShortcutAndNothingElse() throws {
        let source = try appSource()
        let offenders = source
            .split(separator: "\n")
            .enumerated()
            .filter { $0.element.contains("keyboardShortcut") }
            .map { "line \($0.offset + 1): \($0.element.trimmingCharacters(in: .whitespaces))" }

        XCTAssertEqual(
            offenders, [],
            "menu commands use menuShortcut, which cannot bind a bare key that the viewport owns"
        )
    }

    func testNoModifierIsNotSomethingAMenuShortcutCanAskFor() {
        // Every case has Command in it. Written as a test rather than left to
        // the reader of the enum, because a case added later without Command
        // would reintroduce exactly the shadowing this exists to prevent.
        for modifiers in [MenuModifiers.command, .commandShift, .commandShiftOption] {
            XCTAssertTrue(
                modifiers.eventModifiers.contains(.command),
                "\(modifiers) would let a menu item shadow a viewport key"
            )
        }
    }

    func testTheViewportOwnsTheKeysTheHintsInThePanelShow() {
        // The panel shows these as KeyHint badges beside the action they
        // perform. If one is not in the table, the table is out of date and the
        // next bare menu shortcut over it will look allowed.
        for key: Character in ["o", "t", "d", "a", "r", "l", "w", "g", "i", "m"] {
            XCTAssertTrue(ViewportKeys.owned.contains(key), "\(key) is shown in the panel but not claimed")
        }
    }
}
