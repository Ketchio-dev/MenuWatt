import AppKit
import SwiftUI
import MenuWattCore

struct ProcessEnergySectionView: View {
    let presentation: ProcessEnergySectionPresentation

    @State private var showsMoreProcesses = false
    private let initialCount = 5

    var body: some View {
        let remainingCount = max(presentation.entries.count - initialCount, 0)

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Top Energy", systemImage: "bolt")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("CPU + wakeups estimate")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .help("Relative score per second based on CPU time and interrupt wakeups.")
            }

            if let unavailableMessage = presentation.unavailableMessage {
                UnavailableCaption(unavailableMessage)
            }

            ForEach(presentation.entries.prefix(initialCount)) { entry in
                ProcessEnergyRow(entry: entry)
            }

            if remainingCount > 0 {
                Button { showsMoreProcesses.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showsMoreProcesses ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text(showsMoreProcesses ? "Show fewer processes"
                             : "Show \(remainingCount) more \(remainingCount == 1 ? "process" : "processes")")
                            .font(.system(size: 11))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsMoreProcesses ? "Expanded" : "Collapsed")
                if showsMoreProcesses {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(presentation.entries.dropFirst(initialCount)) { entry in
                            ProcessEnergyRow(entry: entry)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct ProcessEnergyRow: View {
    let entry: ProcessEnergyEntry

    @State private var isHovering = false
    private var runningApp: NSRunningApplication? {
        NSRunningApplication(processIdentifier: entry.pid)
    }

    var body: some View {
        let app = runningApp
        let displayName = app?.localizedName ?? entry.name

        Button {
            activate(app)
        } label: {
            HStack(spacing: 6) {
                ProcessIcon(icon: app?.icon)
                Text(displayName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(format: "%.1f", entry.energyImpact))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Click to activate • Right-click for more")
        .contextMenu {
            if let app {
                Button("Activate \(displayName)") { activate(app) }
                Button("Quit \(displayName)") { app.terminate() }
                Button("Force Quit \(displayName)") { app.forceTerminate() }
                Divider()
            }
            Button("Open Activity Monitor") { openActivityMonitor() }
            Button("Copy PID (\(entry.pid))") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(entry.pid), forType: .string)
            }
        }
    }

    private func activate(_ app: NSRunningApplication?) {
        if let app {
            app.activate(options: [.activateIgnoringOtherApps])
        } else {
            openActivityMonitor()
        }
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
    }
}

struct ProcessIcon: View {
    let icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 14, height: 14)
    }
}
