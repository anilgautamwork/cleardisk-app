import AppKit
import SwiftUI
import SyncDoctorCore

struct ICloudDoctorView: View {
    @Environment(ICloudDoctorState.self) private var doctor
    @Environment(LicenseStore.self) private var license
    @State private var rows: [ICloudItem] = []
    @State private var showFolders = false
    @State private var inspectionItem: ICloudItem?
    @State private var confirmation: ICloudConfirmation?
    @State private var confirmClearHistory = false

    private struct Query: Hashable {
        let result: UUID?
        let search: String
        let filter: String
        let sort: String
        let age: Int
    }
    private var query: Query {
        Query(result: doctor.result?.id, search: doctor.search, filter: doctor.filter.rawValue,
              sort: doctor.sort.rawValue, age: doctor.olderThanDays)
    }

    var body: some View {
        @Bindable var doctor = doctor
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                ScreenHeader(title: "iCloud Doctor", subtitle: "Understand sync status and the space iCloud Drive uses on this Mac.")
                if doctor.isScanning {
                    Button(doctor.isCancelling ? "Stopping…" : "Cancel Scan") { doctor.cancelScan() }
                        .disabled(doctor.isCancelling).padding(.top, 30).padding(.trailing, 28)
                } else {
                    Button(doctor.result == nil ? "Scan iCloud Drive" : "Scan Again") { doctor.startScan() }
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                        .disabled(doctor.isOperating).padding(.top, 24).padding(.trailing, 28)
                }
            }
            if doctor.isScanning {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(doctor.scannedCount.formatted()) items inspected").font(.system(size: 13, weight: .semibold))
                        Text(doctor.progressPath).lineLimit(1).truncationMode(.middle).foregroundStyle(UI.textSecondary)
                    }
                    Spacer()
                }.padding(.horizontal, 28).padding(.bottom, 16)
            }
            if doctor.result == nil && !doctor.isScanning {
                introduction
            } else if let result = doctor.result {
                health(result)
                resultControls
                if showFolders { folderList(result) } else { itemTable }
                if !showFolders, let item = doctor.selectedItem { selectionDetails(item) }
            } else {
                Spacer()
            }
            operationStatus
            footer
        }
        .task(id: query) {
            let items = doctor.result?.items ?? []
            let search = doctor.search, filter = doctor.filter, sort = doctor.sort, age = doctor.olderThanDays
            let filtered = await Task.detached(priority: .userInitiated) {
                ICloudDoctorState.visibleItems(items, search: search, filter: filter, sort: sort, olderThanDays: age)
            }.value
            guard !Task.isCancelled else { return }
            rows = filtered
        }
        .sheet(item: $inspectionItem) { ICloudInspectorView(item: $0) }
        .sheet(item: $confirmation) { review in
            ICloudActionConfirmation(review: review) { destination in
                confirmation = nil
                doctor.perform(review.action, item: review.item, destination: destination, license: license)
            }
        }
        .confirmationDialog("Clear iCloud observation history?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { doctor.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears only ClearDisk’s local sync observations. Your files are unchanged. Potentially stuck labels need new comparable scans at least one hour apart.")
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "icloud").font(.system(size: 40, weight: .light)).foregroundStyle(UI.accentLight)
            Text("See what’s waiting. Know what’s local.").font(.system(size: 23, weight: .semibold))
            Text("Scan public file metadata in iCloud Drive to find errors, conflicts, pending transfers and local copies. Scanning doesn’t open file contents or request downloads.")
                .font(.system(size: 15)).foregroundStyle(UI.textSecondary).fixedSize(horizontal: false, vertical: true)
            Divider().overlay(UI.cardBorder)
            Text("macOS may ask for access. Unknown metadata stays unknown. This checks Drive files, not Photos, Messages, backups or your account’s full storage quota.")
                .font(.system(size: 13)).foregroundStyle(UI.textSecondary).fixedSize(horizontal: false, vertical: true)
            Text("Scanning and Download Now are free. Removing a local download and creating a verified archive use your existing ClearDisk license.")
                .font(.system(size: 13)).foregroundStyle(UI.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 620, alignment: .leading)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func health(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(completionLabel(result), systemImage: result.isComplete ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(result.isComplete ? UI.textPrimary : UI.reviewText)
                Spacer()
                Text(result.finishedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12)).foregroundStyle(UI.textSecondary)
            }
            if let location = doctor.location, !location.isAccessible {
                Text(location.accessSummary).font(.system(size: 12)).foregroundStyle(UI.reviewText).textSelection(.enabled)
            }
            if !result.issues.isEmpty {
                DisclosureGroup("\(result.issues.count.formatted()) access or scan issues") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(result.issues) { issue in
                                Text("\(issue.path): \(issue.error?.localizedDescription ?? issue.kind.rawValue)")
                                    .font(.system(size: 11)).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 100)
                }.font(.system(size: 12)).foregroundStyle(UI.reviewText)
            }
            HStack(spacing: 18) {
                Text("\(result.items.count.formatted()) inspected")
                Text("Mac available: \(doctor.location?.volumeAvailableBytes.map(fmtBytes) ?? "Unknown")")
                Text(doctor.networkStatus)
            }.font(.system(size: 12)).foregroundStyle(UI.textSecondary)
            Text("Network reachability is not Apple service health. Cloud-only files are normal; missing metadata cannot prove sync is healthy.")
                .font(.system(size: 11)).foregroundStyle(UI.textSecondary)
        }.padding(14).background(UI.surface).padding(.horizontal, 28).padding(.bottom, 12)
    }

    private func completionLabel(_ result: ScanResult) -> String {
        if result.wasCancelled { return "Scan cancelled — partial observations" }
        if result.hitItemLimit { return "50,000-item limit reached — partial observations" }
        if !result.isComplete { return "Scan incomplete — overall sync health unknown" }
        let files = result.items.filter { $0.kind == .file && !isICloudMetadataNoise($0) }
        if files.isEmpty { return "Scan complete — no files found" }
        let problems = result.items.reduce(0) { $0 + (!isICloudMetadataNoise($1) && ($1.hasAnyError || $1.hasUnresolvedConflicts == true) ? 1 : 0) }
        if problems > 0 { return "Scan complete — \(problems.formatted()) items need review" }
        if files.contains(where: { $0.isWaitingToUpload || $0.isUploading == true || $0.isDownloading == true }) {
            return "Scan complete — pending transfers observed"
        }
        return "Scan complete — no errors reported in accessible metadata"
    }

    private var resultControls: some View {
        @Bindable var doctor = doctor
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                TextField("Search file or folder path", text: $doctor.search)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Search iCloud results")
                Picker("View", selection: $showFolders) {
                    Text("Files").tag(false)
                    Text("Folder totals").tag(true)
                }.pickerStyle(.segmented).frame(width: 190)
            }
            if !showFolders {
                HStack(spacing: 12) {
                    Picker("Filter", selection: $doctor.filter) {
                        ForEach(ICloudDoctorState.Filter.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(maxWidth: 250)
                    Picker("Sort", selection: $doctor.sort) {
                        ForEach(ICloudDoctorState.Sort.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(maxWidth: 230)
                    Picker("Modified", selection: $doctor.olderThanDays) {
                        Text("Any time").tag(0)
                        Text("Over 30 days ago").tag(30)
                        Text("Over 1 year ago").tag(365)
                    }.frame(maxWidth: 230)
                }.font(.system(size: 12))
                HStack {
                    Text("\(rows.count.formatted()) matching items · Allocation is not reclaimable space; Finder metadata is excluded from problem filters.")
                    Spacer()
                }.font(.system(size: 11)).foregroundStyle(UI.textSecondary)
                if doctor.olderThanDays > 0 {
                    Text("Modification age does not show whether a file is still used.")
                        .font(.system(size: 11)).foregroundStyle(UI.reviewText).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.padding(.horizontal, 28).padding(.bottom, 10)
    }

    private var itemTable: some View {
        @Bindable var doctor = doctor
        return Group {
            if rows.isEmpty {
                VStack(spacing: 8) {
                    Text("No matching items").font(.system(size: 17, weight: .semibold))
                    Text("Try another filter or search. Incomplete scans show only inspected items.")
                        .font(.system(size: 13)).foregroundStyle(UI.textSecondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(rows, selection: $doctor.selectedPath) {
                    TableColumn("File / path") { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(item.relativePath).font(.system(size: 10)).foregroundStyle(UI.textSecondary).lineLimit(1).truncationMode(.middle)
                        }.padding(.vertical, 3).help(item.path)
                    }.width(min: 170, ideal: 270)
                    TableColumn("State") { item in
                        Text(iCloudStateLabel(item, stuck: doctor.stuckPaths.contains(item.path)))
                            .font(.system(size: 11)).foregroundStyle(item.hasAnyError || item.hasUnresolvedConflicts == true ? UI.reviewText : UI.textSecondary)
                    }.width(min: 110, ideal: 145)
                    TableColumn("File size") { item in
                        Text(item.kind == .directory ? "See totals" : item.logicalSize.map(fmtBytes) ?? "Unknown").monospacedDigit().font(.system(size: 11))
                    }.width(90)
                    TableColumn("Local bytes") { item in
                        Text(item.kind == .directory ? "See totals" : item.allocatedSize.map(fmtBytes) ?? "Unknown").monospacedDigit().font(.system(size: 11))
                    }.width(90)
                }.tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }.padding(.horizontal, 20)
    }

    private func folderList(_ result: ScanResult) -> some View {
        let folders = doctor.folderTotals.filter { doctor.search.isEmpty || $0.relativePath.localizedStandardContains(doctor.search) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Totals include inspected descendant files; parent and child rows overlap. \(result.isComplete ? "Coverage completed." : "Coverage incomplete — these are partial totals.")")
                .font(.system(size: 12)).foregroundStyle(result.isComplete ? UI.textSecondary : UI.reviewText)
            Table(folders) {
                TableColumn("Folder") { folder in
                    Text(folder.relativePath).lineLimit(1).truncationMode(.middle).help(folder.path)
                }.width(min: 180, ideal: 300)
                TableColumn("Files") { Text($0.files.formatted()).monospacedDigit() }.width(65)
                TableColumn("File bytes") { Text(fmtBytes($0.logical)).monospacedDigit() }.width(90)
                TableColumn("Local bytes") { Text(fmtBytes($0.allocated)).monospacedDigit() }.width(90)
                TableColumn("Unknown sizes") { Text($0.unknownSizes.formatted()).monospacedDigit() }.width(95)
            }.font(.system(size: 12))
        }.padding(.horizontal, 28)
    }

    private func selectionDetails(_ item: ICloudItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.path).font(.system(size: 11)).lineLimit(2).textSelection(.enabled)
            Text("Modified: \(item.modificationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown") · Upload complete: \(item.isUploaded.map { $0 ? "Yes" : "No" } ?? "Unknown")")
                .font(.system(size: 11)).foregroundStyle(UI.textSecondary)
            if let error = item.accessError ?? item.uploadError ?? item.downloadError {
                Text(error.localizedDescription).font(.system(size: 12)).foregroundStyle(UI.reviewText).textSelection(.enabled)
            } else if item.hasUnresolvedConflicts == true {
                Text("Review versions in the app that owns this file or in Finder. ClearDisk cannot resolve conflicts.")
                    .font(.system(size: 12)).foregroundStyle(UI.reviewText)
            }
            if doctor.stuckPaths.contains(item.path) {
                Text("Matching pending states were observed at least one hour apart. This does not prove uninterrupted failure between scans.")
                    .font(.system(size: 11)).foregroundStyle(UI.reviewText)
            }
            HStack(spacing: 10) {
                Button("Reveal in Finder") { revealInFinder(item.path) }
                Button("Inspect Metadata") { inspectionItem = item }
                Spacer()
                Menu("File Actions") {
                    Button("Download Now…") { request(.download, item: item) }
                    Button("Remove Local Download…") { request(.evict, item: item) }
                        .disabled(ICloudFileActions.evictionRefusal(for: item) != nil)
                        .help(ICloudFileActions.evictionRefusal(for: item) ?? "Remove only the current Mac download")
                    Button("Archive to Mac…") { request(.archive, item: item) }
                        .disabled(item.kind != .file && item.kind != .directory)
                    Divider()
                    Button("Keep Downloaded — Finder guidance") {
                        NSWorkspace.shared.open(URL(string: "https://support.apple.com/guide/mac-help/mchlc994344b/mac")!)
                    }
                }.frame(width: 140).disabled(doctor.isOperating || doctor.isScanning)
            }.controlSize(.small)
        }.padding(14).background(UI.surface).padding(.horizontal, 28).padding(.vertical, 10)
    }

    private func request(_ action: ICloudDoctorState.Action, item: ICloudItem) {
        if action != .download && !license.isLicensed { license.showUnlock = true; return }
        let destination = action == .archive ? VerifiedArchive.defaultDestination : nil
        confirmation = ICloudConfirmation(action: action, item: item, destination: destination)
    }

    private var operationStatus: some View {
        Group {
            if doctor.isOperating {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("\(doctor.operationLabel)…").font(.system(size: 12))
                    Spacer()
                    if doctor.operationLabel == ICloudDoctorState.Action.archive.rawValue {
                        Button("Cancel Archive") { doctor.cancelOperation() }.controlSize(.small)
                    }
                }.padding(14).background(UI.surface).padding(.horizontal, 28)
            } else if let message = doctor.operationMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message).font(.system(size: 12)).foregroundStyle(doctor.operationFailed ? UI.reviewText : UI.textPrimary).textSelection(.enabled)
                    if let original = doctor.archivedOriginal, let archive = doctor.archiveURL {
                        Text("Deleting the original in Finder removes it from iCloud and your other synced devices. Review your verified copy first.")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(UI.reviewText)
                        HStack {
                            Button("Reveal Verified Archive") { revealInFinder(archive.path) }
                            Button("Review Original in Finder") { revealInFinder(original.path) }
                        }.controlSize(.small)
                    }
                }.padding(14).background(UI.surface).padding(.horizontal, 28)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = doctor.historyMessage { Text(message).font(.system(size: 11)).foregroundStyle(UI.textSecondary) }
            HStack(spacing: 14) {
                Link("Apple System Status", destination: URL(string: "https://www.apple.com/support/systemstatus/")!)
                Button("iCloud Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane?iCloud")!)
                }.buttonStyle(.link)
                Spacer()
                Button("Clear History…") { confirmClearHistory = true }.buttonStyle(.link).disabled(doctor.isScanning)
            }.font(.system(size: 12)).tint(UI.accentLight)
            Text("History stays on this Mac. Local-copy removal frees Mac storage only. ClearDisk never deletes cloud originals.")
                .font(.system(size: 11)).foregroundStyle(UI.textSecondary)
        }.padding(.horizontal, 28).padding(.vertical, 14)
    }
}

private struct ICloudConfirmation: Identifiable {
    let id = UUID()
    let action: ICloudDoctorState.Action
    let item: ICloudItem
    let destination: URL?
}

private struct ICloudActionConfirmation: View {
    let review: ICloudConfirmation
    let confirm: (URL?) -> Void
    @State private var chosenDestination: URL?
    @State private var destinationError: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(review.action.rawValue).font(.system(size: 23, weight: .semibold))
            Text(review.item.path).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Text(explanation).font(.system(size: 14)).foregroundStyle(UI.textSecondary).fixedSize(horizontal: false, vertical: true)
            if let destination = chosenDestination ?? review.destination {
                Text("Destination: \(destination.path)").font(.system(size: 12)).textSelection(.enabled)
                Text("This release accepts only ClearDisk Archives in your home folder or its subfolders. Keep this folder outside any sync service.")
                    .font(.system(size: 12)).foregroundStyle(UI.textSecondary)
                Button("Choose Archive Subfolder…") { chooseDestination() }
                if let destinationError { Text(destinationError).font(.system(size: 12)).foregroundStyle(UI.reviewText) }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(review.action.rawValue) { confirm(chosenDestination ?? review.destination) }.buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width: 530).background(UI.canvas).foregroundStyle(UI.textPrimary)
    }
    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose an archive subfolder"
        panel.message = "Choose ClearDisk Archives in your home folder, or a folder inside it. Other locations are not supported."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = VerifiedArchive.defaultDestination
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        do {
            try VerifiedArchive.validateDestination(chosen)
            chosenDestination = chosen
            destinationError = nil
        } catch { destinationError = error.localizedDescription }
    }

    private var explanation: String {
        switch review.action {
        case .download:
            "Request a download using macOS. This uses network data and Mac disk space. A request is not a completed download, and does not permanently pin the file. Scan again to observe progress."
        case .evict:
            "Remove only the downloaded copy on this Mac. The iCloud original remains. This does not free iCloud account storage, and you’ll need a network connection to download it for offline use again. ClearDisk rechecks the file’s sync state immediately before requesting removal and refuses unknown or unsafe states."
        case .archive:
            "Copy to a verified location outside sync services, without overwriting files. ClearDisk checks file contents and source stability before marking the copy verified. This is a file-content archive, not a full-fidelity backup. Finder tags, extended attributes and permissions are not preserved; executable files and unsupported metadata, including resource forks, are refused. Close the file’s app before archiving. Cloud-only items must be explicitly downloaded first. Cancellation or failure keeps the iCloud original and may leave a partial copy, which will be identified. A verified copy does not free iCloud storage; any original removal remains your separate choice in Finder."
        }
    }
}

private struct ICloudInspectorView: View {
    let item: ICloudItem
    @Environment(\.dismiss) private var dismiss
    @State private var report: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Raw Metadata").font(.system(size: 23, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("A fresh read of public metadata. <nil> means macOS returned no value. The report includes paths; it stays local unless you copy and share it.")
                .font(.system(size: 12)).foregroundStyle(UI.textSecondary)
            if let report {
                ScrollView([.horizontal, .vertical]) {
                    Text(report).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.background(UI.surface)
                Button("Copy Report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
            } else {
                ProgressView("Reading metadata…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(24).frame(width: 760, height: 560).background(UI.canvas).foregroundStyle(UI.textPrimary)
        .task {
            let url = item.url
            report = await Task.detached(priority: .userInitiated) { RawInspector.inspect(url: url).reportText() }.value
        }
    }
}
