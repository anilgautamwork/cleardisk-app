import AppKit
import Core
import SwiftUI

@MainActor
@Observable
final class MacChecksState {
    enum Check: String, CaseIterable, Identifiable {
        case intelligence = "Apple Intelligence"
        case intel = "Intel apps"
        var id: String { rawValue }
    }
    var selected: Check = .intelligence
    var running: Check?
    var progress = ""
    var message: String?
    var storage: IntelligenceStorageReport?
    var apps: IntelAppReport?
    var storageDate: Date?
    var appsDate: Date?
    private var request = UUID()
    private var task: Task<Void, Never>?

    func scan() {
        guard running == nil else { return }
        let check = selected
        running = check
        message = nil
        progress = "Preparing read-only check…"
        request = UUID()
        let id = request
        if check == .intelligence { storage = nil } else { apps = nil }
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let update: @Sendable (String) -> Void = { [weak self] label in
                Task { @MainActor [weak self] in
                    guard let self, self.request == id, self.running != nil else { return }
                    self.progress = label
                }
            }
            do {
                switch check {
                case .intelligence:
                    let report = try AppleIntelligenceStorage.scan(progress: update)
                    try Task.checkCancellation()
                    await MainActor.run { [weak self] in
                        guard let self, self.request == id else { return }
                        self.storage = report
                        self.storageDate = Date()
                        self.running = nil
                    }
                case .intel:
                    let report = try IntelAppScan.scan(progress: update)
                    try Task.checkCancellation()
                    await MainActor.run { [weak self] in
                        guard let self, self.request == id else { return }
                        self.apps = report
                        self.appsDate = Date()
                        self.running = nil
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.request == id else { return }
                    self.running = nil
                    self.message = "Check stopped. You can scan again."
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        request = UUID()
        running = nil
        message = "Check cancelled. Nothing was changed."
    }
}

struct MacChecksView: View {
    @Bindable var checks: MacChecksState
    @State private var showAllApps = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Mac checks", subtitle: "Understand AI storage and prepare your apps for the next macOS.")
            HStack {
                Picker("Check", selection: $checks.selected) {
                    ForEach(MacChecksState.Check.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 380)
                Spacer()
                if checks.running != nil {
                    Button("Cancel check") { checks.cancel() }
                } else {
                    Button(checks.selected == .intelligence ? "Scan AI storage" : "Scan installed apps") { checks.scan() }
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                }
            }.padding(.horizontal, 28).padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let running = checks.running {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Checking \(running.rawValue)…").font(.headline)
                                Text(checks.progress).font(.callout).foregroundStyle(UI.textSecondary)
                            }
                        }.accessibilityElement(children: .combine)
                    }
                    if let message = checks.message { Text(message).foregroundStyle(UI.textSecondary) }
                    if checks.selected == .intelligence { intelligenceContent } else { intelContent }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(28).padding(.top, 0)
            }
        }
    }

    private var intelligenceContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Apple Intelligence stores models on your Mac so supported features can work locally. This check measures recognized model and support folders, including preinstalled assets.")
                .fixedSize(horizontal: false, vertical: true)
            if let report = checks.storage {
                VStack(alignment: .leading, spacing: 5) {
                    Text(report.incomplete && report.locations.allSatisfy { $0.files == 0 }
                         ? "No readable model files"
                         : "\(fmtBytes(report.measuredBytes)) measured in recognized assets")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Text(report.incomplete ? "Partial result: some locations could not be measured. This is a lower bound." : "Allocated file sizes, not a promise of space you can recover.")
                        .foregroundStyle(report.incomplete ? UI.reviewText : UI.textSecondary)
                    if let date = checks.storageDate { Text("Checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(UI.textSecondary) }
                }
                if report.incomplete {
                    Button("Review Full Disk Access") { FullDiskAccess.openSettings() }
                        .buttonStyle(.bordered)
                }
                ForEach(report.locations.filter { $0.status != .missing }) { location in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(location.title).font(.headline)
                            Spacer()
                            Text(location.status == .unavailable || (location.status == .partial && location.files == 0) ? "Not measured" : fmtBytes(location.bytes))
                                .font(.headline).monospacedDigit()
                        }
                        Text(location.explanation).foregroundStyle(UI.textSecondary)
                        Text(location.path).font(.caption).foregroundStyle(UI.textSecondary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if location.status == .partial || location.status == .unavailable {
                            Text("Access is incomplete. Check disk access in System Settings, then scan again; protected files may remain unreadable.")
                                .foregroundStyle(UI.reviewText)
                        } else {
                            Text("\(location.files.formatted()) files · Managed by macOS").font(.caption).foregroundStyle(UI.textSecondary)
                        }
                        if location.status != .unavailable {
                            Button("Show folder in Finder") { revealInFinder(location.path) }.buttonStyle(.link)
                        }
                    }.padding(16).card()
                }
                let missing = report.locations.filter { $0.status == .missing }
                if !missing.isEmpty {
                    DisclosureGroup("\(missing.count) locations not present") {
                        ForEach(missing) { Text($0.path).font(.caption).textSelection(.enabled).padding(.vertical, 4) }
                    }.foregroundStyle(UI.textSecondary)
                }
            } else if checks.running != .intelligence {
                Text("Choose Scan AI storage to measure the files on this Mac. No full disk scan is needed.").foregroundStyle(UI.textSecondary)
            }
            Divider()
            Text("Let macOS manage these files").font(.headline)
            Text("ClearDisk does not remove Apple Intelligence assets. Review the available Siri and Apple Intelligence controls in System Settings. Changing a setting may not immediately free space, and macOS may download assets again.")
            Text("This is a known-folder inventory, not Apple's complete storage accounting. Other models, shared assets, snapshots and inaccessible files can explain a different total in System Settings. Folder names may change with macOS updates; a zero here does not prove Apple Intelligence is absent. Hard-linked files are counted once; APFS shared storage can still affect physical usage.")
                .font(.callout).foregroundStyle(UI.textSecondary)
            HStack(spacing: 18) {
                Button("Open System Settings") { openSettings() }.buttonStyle(.bordered)
                Link("Apple Intelligence requirements", destination: URL(string: "https://support.apple.com/121115")!)
            }
        }.textSelection(.enabled)
    }

    private var intelContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("On Apple silicon, Intel-only apps rely on Rosetta. Apple says general-purpose Rosetta support ends after macOS 27; macOS 28 retains limited support for certain older games.")
            Text("This checks the main executable in apps under /Applications and your user Applications folder, including subfolders. It does not audit plug-ins, extensions, helper programs or apps elsewhere. A Universal result is not a guarantee that every component is ready.")
                .font(.callout).foregroundStyle(UI.textSecondary)
            if let report = checks.apps {
                Text("\(report.intelApps.count) Intel-only \(report.intelApps.count == 1 ? "app" : "apps") found · \(report.apps.count) apps checked")
                    .font(.title2.weight(.semibold))
                if let date = checks.appsDate { Text("Checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(UI.textSecondary) }
                if !report.unavailablePaths.isEmpty {
                    DisclosureGroup("\(report.unavailablePaths.count) locations could not be read") {
                        ForEach(report.unavailablePaths, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                    }.foregroundStyle(UI.reviewText)
                }
                Toggle("Show all apps, including Universal and Apple silicon", isOn: $showAllApps)
                    .toggleStyle(.checkbox)
                let visible = report.apps.filter { showAllApps || [.intelOnly, .legacyIntel, .unknown].contains($0.architecture) }
                if report.apps.isEmpty {
                    Text("No apps were identified in the checked locations. This does not establish compatibility for apps elsewhere.").foregroundStyle(UI.textSecondary)
                } else if visible.isEmpty {
                    Text("No Intel-only or undetermined main executables were found in these locations. Check any plug-ins and apps stored elsewhere separately.").foregroundStyle(UI.textSecondary)
                }
                LazyVStack(spacing: 8) {
                    ForEach(visible) { app in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(app.name).font(.headline)
                                Text(app.version).font(.caption).foregroundStyle(UI.textSecondary)
                                Spacer()
                                Text(app.architecture.rawValue).font(.callout.weight(.semibold))
                                    .foregroundStyle(app.architecture == .intelOnly || app.architecture == .unknown ? UI.reviewText : UI.textSecondary)
                            }
                            Text(app.path).font(.caption).foregroundStyle(UI.textSecondary).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if app.architecture == .intelOnly {
                                Text("Find an Apple silicon or Universal update before upgrading to macOS 28. ClearDisk cannot determine whether Apple's limited game exception applies.").font(.callout)
                            } else if app.architecture == .unknown {
                                Text("The main executable is missing, unreadable or not a recognized Mach-O binary. Check with the developer; this is not a compatibility pass.").font(.callout)
                            } else if app.architecture == .legacyIntel {
                                Text("32-bit Intel apps already require an older macOS. This is not a new macOS 28 issue.").font(.callout)
                            }
                            Button("Show app in Finder") { revealInFinder(app.path) }.buttonStyle(.link)
                        }.padding(16).card()
                    }
                }
            } else if checks.running != .intel {
                Text("Choose Scan installed apps. ClearDisk reads app metadata and executable headers without launching the apps.").foregroundStyle(UI.textSecondary)
            }
            Divider()
            Text("Update before you upgrade").font(.headline)
            Text("Use the app's Check for Updates command, the App Store, or the developer's website. Keep apps you still need until you've tested a replacement. Nothing is removed by this check.")
            Link("Apple's Intel app compatibility guidance", destination: URL(string: "https://support.apple.com/102527")!)
        }.textSelection(.enabled)
    }

    private func openSettings() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
