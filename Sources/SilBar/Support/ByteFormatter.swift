import Foundation

enum ByteFormatter {
    private static let units = ["B", "KB", "MB", "GB", "TB"]

    static func speed(_ bytesPerSecond: UInt64) -> String {
        "\(size(bytesPerSecond))/s"
    }

    static func size(_ bytes: UInt64) -> String {
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if value >= 100 || unitIndex == 0 {
            return "\(Int(value.rounded())) \(units[unitIndex])"
        }

        return String(format: "%.1f %@", value, units[unitIndex])
    }
}
