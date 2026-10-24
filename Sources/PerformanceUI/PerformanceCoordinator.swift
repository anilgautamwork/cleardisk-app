import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
public final class PerformanceCoordinator {
    let monitor = Monitor()
    let router = Router()
    let license = LicenseStore()
    @ObservationIgnored lazy var actions = FixActions(license: license, monitor: monitor, router: router)
    @ObservationIgnored private lazy var statusItem = PerformanceStatusItem(coordinator: self)
    @ObservationIgnored var presentWindow: () -> Void = {}
    var openStorage: () -> Void = {}
    var openPerformance: () -> Void = {}
    var fileOperationActive: () -> Bool = { false }

    public init() {}

    public func configureWindow(_ present: @escaping () -> Void) { presentWindow = present }
    func closeMenu() { statusItem.close() }

    public var isOperating: Bool { actions.isOperating }

    public func configure(isLicensed: @escaping () -> Bool, requestUnlock: @escaping () -> Void,
                          openStorage: @escaping () -> Void, openPerformance: @escaping () -> Void,
                          fileOperationActive: @escaping () -> Bool) {
        license.check = isLicensed
        license.requestUnlock = requestUnlock
        self.openStorage = openStorage
        self.openPerformance = openPerformance
        self.fileOperationActive = fileOperationActive
        actions.openStorage = openStorage
        actions.fileOperationActive = fileOperationActive
    }

    public func setMonitoring(visible: Bool, menuBar: Bool) {
        monitor.setEnabled(visible || menuBar)
        monitor.windowVisible = visible
        if NSClassFromString("XCTestCase") == nil { statusItem.setVisible(menuBar) }
    }
}

@MainActor
@Observable
final class LicenseStore {
    var check: () -> Bool = { false }
    var requestUnlock: () -> Void = {}
    var pendingUnlock = false
    func presentPendingUnlock() {
        guard pendingUnlock else { return }
        pendingUnlock = false
        requestUnlock()
    }
    var isLicensed: Bool { check() }
    var showUnlock = false {
        didSet {
            if showUnlock {
                showUnlock = false
                requestUnlock()
            }
        }
    }
}

public struct PerformanceView: View {
    let coordinator: PerformanceCoordinator
    @State private var settings = false

    public init(coordinator: PerformanceCoordinator) { self.coordinator = coordinator }

    public var body: some View {
        @Bindable var router = coordinator.router
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Performance section", selection: $router.screen) {
                    ForEach(Screen.allCases, id: \.self) { screen in
                        Text(screen.title).tag(screen)
                    }
                }.pickerStyle(.segmented).labelsHidden()
                Button("Check now") { coordinator.monitor.checkNow() }
                Button { settings = true } label: {
                    Image(systemName: "gearshape")
                }.help("Performance settings").accessibilityLabel("Performance settings")
            }.padding(20)
            Divider()
            Group {
                if coordinator.monitor.catalog == nil {
                    ContentUnavailableView("Process descriptions are unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text("Reinstall ClearDisk to restore its process catalog."))
                } else {
                    switch router.screen {
                    case .overview: OverviewView()
                    case .processes: ProcessesView()
                    case .backgroundItems: BackgroundItemsView()
                    case .internet: InternetView()
                    case .usage: UsageView()
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.window).foregroundStyle(Theme.text).tint(Theme.accent)
        .environment(coordinator.monitor).environment(coordinator.router)
        .environment(coordinator.actions).environment(coordinator.license)
        .modifier(PerformancePresentation(coordinator: coordinator))
        .sheet(isPresented: $settings, onDismiss: coordinator.license.presentPendingUnlock) {
            PerformanceSettings(coordinator: coordinator)
        }
    }
}

private struct PerformancePresentation: ViewModifier {
    let coordinator: PerformanceCoordinator

    func body(content: Content) -> some View {
        @Bindable var actions = coordinator.actions
        @Bindable var router = coordinator.router
        content
            .alert(actions.confirmation?.title ?? "Confirm action", isPresented: Binding(
                get: { actions.confirmation != nil }, set: { if !$0 { actions.confirmation = nil } }),
                   presenting: actions.confirmation) { confirmation in
                Button(confirmation.confirm, role: confirmation.destructive ? .destructive : nil) {
                    Task { await confirmation.action() }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text($0.message) }
            .alert("The app is still running", isPresented: Binding(
                get: { actions.stuckAlert != nil }, set: { if !$0 { actions.stuckAlert = nil } })) {
                Button("Restart…") { actions.confirmRestart() }
                Button("Not now", role: .cancel) {}
            } message: { Text("Save your work. Restarting your Mac may help if an app will not quit.") }
            .sheet(item: $router.browser, onDismiss: coordinator.license.presentPendingUnlock) { browser in
                BrowserPanel(browser: browser).environment(coordinator.license)
                    .environment(coordinator.monitor).environment(coordinator.actions)
            }
            .overlay(alignment: .bottom) {
                if let toast = actions.toast {
                    Text(toast).padding(14).background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
                        .padding(20).task(id: toast) {
                            do { try await Task.sleep(for: .seconds(5)) } catch { return }
                            if actions.toast == toast { actions.toast = nil }
                        }
                }
            }
    }
}

public struct PerformanceMenu: View {
    let coordinator: PerformanceCoordinator
    public init(coordinator: PerformanceCoordinator) { self.coordinator = coordinator }
    public var body: some View {
        MenuBarView().environment(coordinator.monitor).environment(coordinator.router)
            .environment(coordinator.actions).environment(coordinator.license).environment(coordinator)
    }
}

public struct PerformanceStatusLabel: View {
    let coordinator: PerformanceCoordinator
    public init(coordinator: PerformanceCoordinator) { self.coordinator = coordinator }
    public var body: some View { MenuBarStatusLabel().environment(coordinator.monitor) }
}

