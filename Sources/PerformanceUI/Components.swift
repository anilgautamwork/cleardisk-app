import AppKit
import PerformanceCore
import SwiftUI

struct Pill: View {
    let text: String
    var symbol: String?
    let fg: Color
    let bg: Color

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(fg)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(bg, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct VerdictPill: View {
    let verdict: Verdict

    var body: some View {
        switch verdict {
        case .safe: Pill(text: verdict.label, symbol: "checkmark.circle", fg: Theme.green, bg: Theme.greenBG)
                .accessibilityLabel("Verdict: Safe to quit")
        case .review: Pill(text: verdict.label, symbol: "exclamationmark.triangle", fg: Theme.amber, bg: Theme.amberBG)
                .accessibilityLabel("Verdict: Review")
        case .leave: Pill(text: verdict.label, symbol: "checkmark.shield", fg: Color(hex: 0xC4C4CC), bg: Color(hex: 0x24242C))
                .accessibilityLabel("Verdict: Leave it")
        }
    }
}

struct StatusPill: View {
    let status: Status

    var body: some View {
        Pill(text: status.pillLabel, fg: Theme.color(status),
             bg: status == .quiet ? Theme.greenBG : status == .busy ? Theme.amberBG : Theme.redBG)
            .accessibilityLabel("Status: \(status.pillLabel)")
    }
}

struct LeaveNote: View {
    let text: String

    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.text3)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(isEnabled ? Theme.button.opacity(configuration.isPressed ? 0.75 : 1) : Theme.raised, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(isEnabled && hovered ? 0.07 : 0)))
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { hovered = $0 }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color.white.opacity(configuration.isPressed ? 0.10 : hovered && isEnabled ? 0.06 : 0.025), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.controlBorder))
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovered = $0 }
    }
}

/// A fix button. Paid fixes show a lock until the license is active;
/// clicking a locked one opens the Unlock sheet, then runs the fix.
struct FixButton: View {
    let fix: FixID
    let group: ProcessGroup?
    var prominent = false
    @Environment(FixActions.self) private var actions
    @Environment(LicenseStore.self) private var license

    var body: some View {
        let locked = fix.isPaid && !license.isLicensed
        Button {
            actions.perform(fix, group: group)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: locked ? "lock" : fix.symbol)
                Text(fix.title(group))
            }
        }
        .buttonStyle(FixStyle(prominent: prominent && !locked, purple: locked || fix.isPaid))
        .accessibilityLabel(locked ? "\(fix.title(group)), requires license" : fix.title(group))
    }
}

/// Filled for the main action, purple outline for paid actions, gray outline otherwise.
private struct FixStyle: ButtonStyle {
    let prominent: Bool
    let purple: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: prominent || !purple ? 13.5 : 12, weight: purple || prominent ? .semibold : .medium))
            .foregroundStyle(prominent ? Color.white : purple ? Color(hex: 0xDDD6FE) : Theme.text)
            .padding(.horizontal, prominent ? 16 : purple ? 10 : 14)
            .padding(.vertical, prominent || !purple ? 9 : 6)
            .background(prominent ? Theme.button : purple ? Color(hex: 0x1E1830) : Color.white.opacity(0.025),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(prominent ? .clear : purple ? Color(hex: 0x665097) : Theme.controlBorder))
            .overlay(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(isEnabled && hovered ? 0.06 : 0)))
            .opacity(isEnabled ? configuration.isPressed ? 0.75 : 1 : 0.45)
            .onHover { hovered = $0 }
    }
}

extension FixID {
    func title(_ g: ProcessGroup?) -> String {
        switch self {
        case .explain: "Explain this process"
        case .openSpotlightSettings: "Spotlight settings"
        case .openLoginItemsSettings: "Login Items settings"
        case .openDisplaySettings: "Displays settings"
        case .openAccessibilityDisplay: "Reduce transparency"
        case .openBatterySettings: "Battery settings"
        case .openWiFiSettings: "Wi-Fi settings"
        case .quitApp: "Quit \(g?.displayName ?? "app")"
        case .rebuildSpotlightIndex: "Rebuild Spotlight index"
        case .reviewTabs: "Review tabs"
        case .openClearDisk: "Free up space"
        case .restartMac: "Restart…"
        }
    }

    var symbol: String {
        switch self {
        case .explain: "text.magnifyingglass"
        case .quitApp: "xmark.circle"
        case .rebuildSpotlightIndex: "arrow.clockwise"
        case .reviewTabs: "rectangle.stack"
        case .openClearDisk: "internaldrive"
        case .restartMac: "power"
        default: "slider.horizontal.3"
        }
    }
}

/// Real app icon for app groups, an SF Symbol tile for system processes.
struct ProcessIcon: View {
    let group: ProcessGroup
    let symbol: String
    var size: CGFloat = 34

    var body: some View {
        if let app = group.appPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app))
                .resizable().frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5))
                .foregroundStyle(Color(hex: 0xC4B5FD))
                .frame(width: size, height: size)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: 0x2C2C36)))
                .accessibilityHidden(true)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
    }
}
