import Foundation

/// Plain-text diagnosis for `whyslow-cli`.
public enum Report {
    public static func render(result: DiagnosisResult, groups: [ProcessGroup], catalog: ProcessCatalog,
                              signals: SystemSignals) -> String {
        var lines = ["Status: " + statusLabel(result.status)]
        if let hero = result.hero { lines.append("Cause: " + hero.headline) }
        lines += result.more.map { "Also: " + $0.headline }
        lines.append("CPU \(Format.percent(signals.cpuLoadPercent)) · Memory \(signals.pressure.label) · Heat \(signals.thermal.label)")
        lines.append("")
        for g in groups.prefix(10) {
            let e = catalog.explain(g)
            let name = g.helperCount > 0 ? "\(g.displayName) (+\(g.helperCount))" : g.displayName
            lines.append("\(name)  \(Format.percent(g.cpuPercent))  \(Format.bytes(g.memoryBytes))  \(e.verdict.label)  — \(e.title)")
        }
        return lines.joined(separator: "\n")
    }

    public static func statusLabel(_ s: Status) -> String {
        switch s {
        case .quiet: "Quiet"
        case .busy: "Busy"
        case .struggling: "Struggling"
        }
    }
}
