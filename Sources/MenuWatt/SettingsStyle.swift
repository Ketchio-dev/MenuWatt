import AppKit
import SwiftUI

/// Local to Settings: the status-item artwork and dashboard keep their identity.
enum SettingsTheme {
    static let accent = Color(nsColor: adaptive(light: 0xb42121, dark: 0xf0786e))
    static let button = Color(red: 180 / 255, green: 33 / 255, blue: 33 / 255)
    static let canvas = Color(nsColor: adaptive(light: 0xfafafa, dark: 0x202023))
    static let sidebar = Color(nsColor: adaptive(light: 0xf0f0f2, dark: 0x19191c))
    static let rule = Color(nsColor: adaptive(light: 0xdedee2, dark: 0x38383d))
    static let inset = Color(nsColor: adaptive(light: 0xffffff, dark: 0x29292d))

    private static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255,
                           green: CGFloat((value >> 8) & 0xff) / 255,
                           blue: CGFloat(value & 0xff) / 255, alpha: 1)
        }
    }
}

struct SettingsControlsStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13))
            .tint(SettingsTheme.accent)
            .accentColor(SettingsTheme.accent)
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

struct SettingsActionStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        SettingsActionLabel(configuration: configuration, prominent: prominent)
    }

    private struct SettingsActionLabel: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration
        let prominent: Bool

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .background(prominent ? SettingsTheme.button : SettingsTheme.inset,
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isFocused ? SettingsTheme.accent
                                      : prominent ? Color.clear : SettingsTheme.rule, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
        }
    }
}

/// A tiny brand cue, drawn as vector geometry rather than a new app logo.
struct SettingsKetchupMark: View {
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1).fill(SettingsTheme.accent)
                .frame(width: 5, height: 3)
            Bottle().fill(SettingsTheme.accent).frame(width: 10, height: 13)
                .overlay {
                    RoundedRectangle(cornerRadius: 1).fill(SettingsTheme.sidebar)
                        .frame(width: 5, height: 3).offset(y: 2)
                }
        }
        .frame(width: 12, height: 18)
        .accessibilityHidden(true)
    }

    private struct Bottle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.width * 0.3, y: 0))
            path.addLine(to: CGPoint(x: rect.width * 0.7, y: 0))
            path.addLine(to: CGPoint(x: rect.width * 0.7, y: rect.height * 0.2))
            path.addQuadCurve(to: CGPoint(x: rect.width, y: rect.height * 0.42),
                              control: CGPoint(x: rect.width, y: rect.height * 0.25))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.9))
            path.addQuadCurve(to: CGPoint(x: rect.width * 0.85, y: rect.height),
                              control: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: rect.width * 0.15, y: rect.height))
            path.addQuadCurve(to: CGPoint(x: 0, y: rect.height * 0.9),
                              control: CGPoint(x: 0, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height * 0.42))
            path.addQuadCurve(to: CGPoint(x: rect.width * 0.3, y: rect.height * 0.2),
                              control: CGPoint(x: 0, y: rect.height * 0.25))
            path.closeSubpath()
            return path
        }
    }
}
