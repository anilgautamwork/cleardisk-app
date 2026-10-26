import ServiceManagement
import SwiftUI

struct PerformanceSettings: View {
    let coordinator: PerformanceCoordinator
    @Environment(\.dismiss) private var dismiss
    @AppStorage("performance.showMenuBar") private var showMenuBar = false
    @AppStorage("menuBarDisplay") private var display = MenuBarDisplay.icon
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled
    @State private var clear = false
    @State private var message: String?

    var body: some View {
        @Bindable var monitor = coordinator.monitor
        VStack {
            Form {
                Section("Monitoring") {
                    Toggle("Show performance in the menu bar", isOn: $showMenuBar)
                    Text("Readings update while the ClearDisk window is open. Enable the menu bar to keep monitoring after closing the window.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Menu bar shows", selection: $display) {
                        ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0) }
                    }.disabled(!showMenuBar)
                    Toggle("Start ClearDisk at login", isOn: $startAtLogin)
                        .onChange(of: startAtLogin) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                            } catch {
                                startAtLogin = SMAppService.mainApp.status == .enabled
                                message = "Could not change login startup. Review Login Items in System Settings."
                            }
                        }
                }
                Section("Usage history") {
                    Toggle("Keep CPU and memory history on this Mac", isOn: $monitor.keepHistory)
                    Text("Up to 30 days, recorded while monitoring runs. No process names or browser tabs are stored in this history.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Clear performance history…") { clear = true }
                    if let message { Text(message).foregroundStyle(.secondary) }
                }
                Section("License") {
                    Text("Performance diagnostics are free. Guided actions use your existing ClearDisk license.")
                    Button("Manage ClearDisk license…") {
                        coordinator.license.pendingUnlock = true
                        dismiss()
                    }
                }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding()
        }.frame(width: 540, height: 520)
            .alert("Clear recorded performance history?", isPresented: $clear) {
                Button("Clear History", role: .destructive) {
                    do { try monitor.clearHistory(); message = "Performance history cleared." }
                    catch { message = "History could not be cleared. Try again." }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Only ClearDisk's recorded CPU and memory history is removed. New history starts with the next sample if recording is enabled.") }
    }
}
