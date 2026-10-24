import AppKit
import PerformanceCore
import SwiftUI

/// Tabs, windows, profiles and extensions for Chrome, Brave or Edge, with
/// duplicate cleanup and window merging. Incognito windows are never touched.
struct BrowserPanel: View {
    let browser: ChromiumBrowser
    @Environment(\.dismiss) private var dismiss
    @Environment(LicenseStore.self) private var license
    @Environment(FixActions.self) private var actions

    private enum Phase {
        case primer, loading, loaded, notPermitted, notRunning, failed(String)
    }

    private struct Confirm: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let button: String
        let run: () async throws -> Void
    }

    @State private var phase: Phase = .loading
    @State private var windows: [BrowserWindow] = []
    @State private var extensions: ExtensionUsage?
    @State private var selected = Set<String>()
    @State private var confirm: Confirm?
    @State private var working = false

    private var isLoaded: Bool { if case .loaded = phase { true } else { false } }
    private let controller = BrowserController()
    private var primerKey: String { "primer.automation.\(browser.rawValue)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch phase {
            case .primer: primer
            case .loading: ProgressView("Reading your \(browser.appName) tabs…").frame(maxWidth: .infinity, minHeight: 200)
            case .loaded: loaded
            case .notPermitted:
                message("ClearDisk needs permission to see your tabs.",
                        "Turn on \(browser.appName) for ClearDisk in System Settings > Privacy & Security > Automation, then try again.") {
                    Button("Open Automation settings") { FixRunner().open(.automation) }.buttonStyle(PrimaryButtonStyle())
                    Button("Try again") { Task { await load() } }.buttonStyle(SecondaryButtonStyle())
                }
            case .notRunning:
                message("\(browser.appName) isn't running.", "Open it and try again.") {
                    Button("Try again") { Task { await load() } }.buttonStyle(SecondaryButtonStyle())
                }
            case .failed(let m):
                message("Couldn't read your tabs.", m) {
                    Button("Try again") { Task { await load() } }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(28)
        .frame(width: 760, height: isLoaded ? 620 : nil, alignment: .top)
        .background(Theme.window)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .task {
            if UserDefaults.standard.bool(forKey: primerKey) { await load() } else { phase = .primer }
        }
        .alert(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
               presenting: confirm) { c in
            Button(c.button, role: .destructive) { Task { await perform(c) } }
            Button("Cancel", role: .cancel) {}
        } message: { c in Text(c.message) }
    }

    // MARK: States

    private var primer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "hand.raised").font(.system(size: 28)).foregroundStyle(Theme.accentLight)
            Text("Let ClearDisk see your \(browser.appName) tabs").font(.system(size: 20, weight: .bold))
            Text("macOS will ask you to allow ClearDisk to control \(browser.appName). ClearDisk only reads tab titles and addresses, and only closes tabs you choose.")
                .font(.system(size: 14)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Not now") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("Continue") {
                    UserDefaults.standard.set(true, forKey: primerKey)
                    Task { await load() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.top, 6)
        }
    }

    private var loaded: some View {
        let normal = windows.filter { !$0.isIncognito }
        let dupes = TabCleanup.duplicates(in: windows)
        let plan = TabCleanup.mergePlan(windows)
        let tabCount = windows.reduce(0) { $0 + $1.tabs.count }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(tabCount) tabs in \(windows.count) \(windows.count == 1 ? "window" : "windows")")
                        .font(.system(size: 22, weight: .bold))
                    if let x = extensions {
                        Text("Extensions: \(x.count) running, \(Format.bytes(x.memoryBytes))")
                            .font(.system(size: 13)).foregroundStyle(Theme.text2)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(windows) { w in windowSection(w) }
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 10) {
                if !dupes.isEmpty {
                    paidButton("Close \(dupes.count) duplicate\(dupes.count == 1 ? "" : "s")") {
                        askClose(dupes, title: "Close \(dupes.count) duplicate \(dupes.count == 1 ? "tab" : "tabs")?")
                    }
                } else {
                    Text("No duplicate tabs").font(.system(size: 12.5)).foregroundStyle(Theme.text3)
                }
                if !selected.isEmpty {
                    let tabs = windows.flatMap(\.tabs).filter { selected.contains($0.id) }
                    paidButton("Close selected (\(tabs.count))") { askClose(tabs, title: "Close \(tabs.count) \(tabs.count == 1 ? "tab" : "tabs")?") }
                }
                if let plan {
                    let profiles = Set(normal.map { $0.profile ?? "" }).count
                    let who = plan.profile ?? "Default profile"
                    paidButton(profiles > 1 ? "Merge \(who) windows" : "Merge into one window") {
                        confirm = Confirm(title: profiles > 1 ? "Merge your \(who) windows?" : "Merge into one window?",
                                          message: "Tabs from \(plan.windowsToClose.count + 1) windows move into one. They'll reload. Other profiles and incognito windows aren't touched.",
                                          button: "Merge") { try await controller.merge(plan, browser) }
                    }
                }
                Spacer()
                Button {
                    Task { try? await controller.openMemorySaver(browser) }
                } label: { Label("Memory Saver settings", systemImage: "leaf") }
                .buttonStyle(SecondaryButtonStyle())
            }
            .disabled(working)
            Text("\(browser.appName) doesn't share memory per tab, so totals are for the whole browser.\(normal.count < windows.count ? " Incognito windows are never touched." : "")")
                .font(.system(size: 12)).foregroundStyle(Theme.text3)
        }
    }

    private func windowSection(_ w: BrowserWindow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: w.isIncognito ? "eyeglasses" : "macwindow")
                Text(w.isIncognito ? "Incognito (not touched)" : (w.profile ?? "Default profile"))
                Text("· \(w.tabs.count) tabs").foregroundStyle(Theme.text3)
            }
            .font(.system(size: 13, weight: .semibold)).padding(.bottom, 6)
            ForEach(w.tabs) { t in
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(get: { selected.contains(t.id) },
                                             set: { if $0 { selected.insert(t.id) } else { selected.remove(t.id) } }))
                        .labelsHidden().toggleStyle(.checkbox).disabled(w.isIncognito)
                    Text(t.title.isEmpty ? t.url : t.title).font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    Text(t.host).font(.system(size: 12)).foregroundStyle(Theme.text3).lineLimit(1)
                    if t.isActive { Pill(text: "Active", fg: Theme.text2, bg: Theme.raised) }
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Theme.card)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
    }

    private func message(_ title: String, _ body: String, @ViewBuilder buttons: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 20, weight: .bold))
            Text(body).font(.system(size: 14)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) { buttons(); Button("Close") { dismiss() }.buttonStyle(SecondaryButtonStyle()) }
        }
    }

    // MARK: Actions

    private func paidButton(_ title: String, action: @escaping () -> Void) -> some View {
        let locked = !license.isLicensed
        return Button {
            if license.isLicensed { action() } else {
                license.pendingUnlock = true
                dismiss()
            }
        } label: {
            HStack(spacing: 6) {
                if locked { Image(systemName: "lock") }
                Text(title)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityLabel(locked ? "\(title), requires license" : title)
    }

    private func askClose(_ tabs: [BrowserTab], title: String) {
        let names = tabs.prefix(5).map { "• " + ($0.title.isEmpty ? $0.host : $0.title) }.joined(separator: "\n")
        let more = tabs.count > 5 ? "\nand \(tabs.count - 5) more" : ""
        confirm = Confirm(title: title, message: names + more, button: "Close Tabs") { try await controller.close(tabs, browser) }
    }

    private func perform(_ c: Confirm) async {
        guard license.isLicensed else {
            license.pendingUnlock = true
            dismiss()
            return
        }
        guard !working, actions.mayRunPaidAction() else { return }
        working = true
        actions.isOperating = true
        defer { working = false; actions.isOperating = false }
        do {
            try await c.run()
            selected.removeAll()
        } catch {
            phase = state(for: error)
            return
        }
        await load()
    }

    private func load() async {
        phase = .loading
        do {
            windows = try await controller.windows(browser)
            phase = .loaded
        } catch {
            phase = state(for: error)
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.rawValue)?.path {
            extensions = await Task.detached { TabCleanup.extensions(fromPSArgs: (try? PSProcessSource.argsListing()) ?? "", appPath: app) }.value
        }
    }

    private func state(for error: Error) -> Phase {
        switch error as? BrowserError {
        case .notPermitted: .notPermitted
        case .notRunning: .notRunning
        case .failed(let m): .failed(m)
        case nil: .failed(error.localizedDescription)
        }
    }
}
