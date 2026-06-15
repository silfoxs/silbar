import Foundation

enum StatusBarPreferences {
    static let showNetworkTransfer = "statusBar.showNetworkTransfer"
    static let showCPUUsage = "statusBar.showCPUUsage"
    static let showCPUTemperature = "statusBar.showCPUTemperature"
    static let showMemoryUsage = "statusBar.showMemoryUsage"
    static let showStorageUsage = "statusBar.showStorageUsage"
    static let metricOrder = "statusBar.metricOrder"

    static func orderedMetricKinds(defaults: UserDefaults = .standard) -> [StatusBarMetricKind] {
        let savedKinds = defaults.stringArray(forKey: metricOrder) ?? []
        var orderedKinds: [StatusBarMetricKind] = []

        for rawValue in savedKinds {
            guard
                let kind = StatusBarMetricKind(rawValue: rawValue),
                !orderedKinds.contains(kind)
            else {
                continue
            }
            orderedKinds.append(kind)
        }

        for kind in StatusBarMetricKind.allCases where !orderedKinds.contains(kind) {
            orderedKinds.append(kind)
        }

        return orderedKinds
    }

    static func setMetricOrder(_ kinds: [StatusBarMetricKind], defaults: UserDefaults = .standard) {
        defaults.set(kinds.map(\.rawValue), forKey: metricOrder)
    }
}
