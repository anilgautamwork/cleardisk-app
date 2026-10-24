import Foundation

public enum Format {
    /// Memory-style sizes ("1.6 GB"), matching Activity Monitor.
    public static func bytes(_ b: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: b)
    }

    /// Disk sizes in the decimal units disks are sold in, whole numbers ("995 GB", "2 TB").
    public static func storage(_ b: Int64) -> String {
        let gb = Double(b) / 1_000_000_000
        return gb >= 1000 ? "\(Int((gb / 1000).rounded())) TB" : "\(Int(gb.rounded())) GB"
    }

    /// Whole-number percent ("246%").
    public static func percent(_ p: Double) -> String {
        "\(Int(p.rounded()))%"
    }
}
