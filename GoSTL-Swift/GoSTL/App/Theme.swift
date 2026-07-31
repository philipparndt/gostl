import SwiftUI
import Observation
import simd

/// Available UI themes for the 3D viewport and surrounding chrome.
enum Theme: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark: return .dark
        case .light: return .light
        }
    }
}

/// Snapshot of all theme-driven colors used by the Metal renderer.
struct ThemeColors {
    let background: SIMD4<Float>
    let gridMinor: SIMD4<Float>
    let gridMajor: SIMD4<Float>
    let gridSuperMajor: SIMD4<Float>
    let gridLabel: SIMD4<Float>
    let dimensionLines: SIMD4<Float>
    let buildPlateSurface: SIMD4<Float>
    let buildPlateFrame: SIMD4<Float>
    let buildPlateGridMinor: SIMD4<Float>
    let buildPlateGridMajor: SIMD4<Float>
    let buildPlateCrosshair: SIMD4<Float>

    static let dark = ThemeColors(
        background:           SIMD4(0.059, 0.071, 0.098, 1.0),
        gridMinor:            SIMD4(100.0/255.0, 100.0/255.0, 100.0/255.0, 160.0/255.0),
        gridMajor:            SIMD4(140.0/255.0, 140.0/255.0, 140.0/255.0, 200.0/255.0),
        gridSuperMajor:       SIMD4(180.0/255.0, 180.0/255.0, 180.0/255.0, 240.0/255.0),
        gridLabel:            SIMD4(200.0/255.0, 200.0/255.0, 200.0/255.0, 1.0),
        dimensionLines:       SIMD4(255.0/255.0, 200.0/255.0, 100.0/255.0, 1.0),
        buildPlateSurface:    SIMD4(0.12, 0.15, 0.22, 0.45),
        buildPlateFrame:      SIMD4(0.35, 0.55, 0.85, 0.85),
        buildPlateGridMinor:  SIMD4(0.28, 0.38, 0.55, 0.35),
        buildPlateGridMajor:  SIMD4(0.32, 0.45, 0.62, 0.55),
        buildPlateCrosshair:  SIMD4(0.40, 0.55, 0.75, 0.70)
    )

    static let light = ThemeColors(
        background:           SIMD4(0.94, 0.95, 0.97, 1.0),
        gridMinor:            SIMD4(110.0/255.0, 110.0/255.0, 115.0/255.0,  80.0/255.0),
        gridMajor:            SIMD4( 70.0/255.0,  70.0/255.0,  80.0/255.0, 150.0/255.0),
        gridSuperMajor:       SIMD4( 30.0/255.0,  30.0/255.0,  40.0/255.0, 210.0/255.0),
        gridLabel:            SIMD4( 40.0/255.0,  40.0/255.0,  50.0/255.0, 1.0),
        dimensionLines:       SIMD4(220.0/255.0, 130.0/255.0,  30.0/255.0, 1.0),
        buildPlateSurface:    SIMD4(0.86, 0.89, 0.94, 0.50),
        buildPlateFrame:      SIMD4(0.18, 0.38, 0.68, 0.85),
        buildPlateGridMinor:  SIMD4(0.40, 0.50, 0.65, 0.30),
        buildPlateGridMajor:  SIMD4(0.22, 0.38, 0.58, 0.55),
        buildPlateCrosshair:  SIMD4(0.18, 0.32, 0.58, 0.70)
    )

    static func palette(for theme: Theme) -> ThemeColors {
        switch theme {
        case .dark: return .dark
        case .light: return .light
        }
    }
}

/// App-wide theme selection, persisted via UserDefaults.
@Observable
final class ThemePreferences: @unchecked Sendable {
    static let shared = ThemePreferences()

    private let userDefaultsKey = "GoSTL.theme"

    var current: Theme {
        didSet {
            guard oldValue != current else { return }
            UserDefaults.standard.set(current.rawValue, forKey: userDefaultsKey)
            NotificationCenter.default.post(name: .themeDidChange, object: current)
        }
    }

    var colors: ThemeColors { ThemeColors.palette(for: current) }

    private init() {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? Theme.dark.rawValue
        current = Theme(rawValue: raw) ?? .dark
    }
}

extension Notification.Name {
    static let themeDidChange = Notification.Name("ThemeDidChange")
}
