import AppKit
import SwiftUI

/// Identifies a top-level page in the Settings window.
///
/// Extracted from SettingsPanel.swift so panes can live in their own files.
enum SettingsPane: String, CaseIterable, Identifiable {
    case overview
    case menuBar
    case notifications
    case updates
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .menuBar: return "Menu Bar"
        case .notifications: return "Notifications"
        case .updates: return "Updates"
        case .about: return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "house"
        case .menuBar: return "menubar.rectangle"
        case .notifications: return "bell.badge"
        case .updates: return "arrow.down.circle"
        case .about: return "info.circle"
        }
    }
}

/// Shared building blocks for every settings pane.
struct SettingsRow<Trailing: View>: View {
    let label: String
    var detail: String? = nil
    var systemImage: String? = nil
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage).frame(width: 18)
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 13))
                if let detail { SettingsNote(detail) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: 32)
        .padding(.vertical, detail == nil ? 2 : 6)
        .overlay(alignment: .bottom) { SettingsTheme.rule.opacity(0.5).frame(height: 0.5) }
    }
}

struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsPaneTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 23, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: systemImage).accessibilityHidden(true)
                Text(title).accessibilityAddTraits(.isHeader)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 4) { content }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsTheme.inset, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9).strokeBorder(SettingsTheme.rule.opacity(0.7))
                        .allowsHitTesting(false)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
