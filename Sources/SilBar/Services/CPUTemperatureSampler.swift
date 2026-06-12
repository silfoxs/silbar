import Darwin
import Foundation
import IOKit

final class CPUTemperatureSampler: @unchecked Sendable {
    private let preferredKeys = [
        "Tp09", "Tp0T", "Tp0P", "Tp0E", "Tp0F", "Tp0H",
        "Tp01", "Tp05", "Tp0D", "Tp0d", "Tp1h", "Tp2h",
        "TC0P", "TC0E", "TC0D", "TC0F", "TC0H", "TC0p",
        "TCXC", "TCXc", "TC0C", "TC1C", "TC2C", "TC3C"
    ]
    private var discoveredKey: String?

    func sampleCelsius() -> Double? {
        sampleSMCCelsius() ?? sampleHIDCelsius()
    }

    private func sampleSMCCelsius() -> Double? {
        guard let connection = SMCConnection.open() else {
            return nil
        }
        defer {
            connection.close()
        }

        if let discoveredKey, let value = connection.readTemperature(key: discoveredKey), value.isPlausibleTemperature {
            return value
        }

        if let match = preferredKeys.compactMap({ key -> (String, Double)? in
            guard let value = connection.readTemperature(key: key), value.isPlausibleTemperature else {
                return nil
            }
            return (key, value)
        }).first {
            discoveredKey = match.0
            return match.1
        }

        if let match = connection.discoverTemperature().first {
            discoveredKey = match.key
            return match.value
        }

        return nil
    }

    private func sampleHIDCelsius() -> Double? {
        #if arch(arm64)
        AppleSiliconHIDTemperatureReader().sampleCPUCelsius()
        #else
        nil
        #endif
    }
}

#if arch(arm64)
private final class AppleSiliconHIDTemperatureReader {
    private let temperatureUsagePage = 0xff00
    private let temperatureUsage = 0x0005
    private let temperatureEventType: Int64 = 15
    private let cpuPrefixes = [
        "pACC MTR Temp",
        "eACC MTR Temp",
        "PMU tdie",
        "PMU2 tdie"
    ]

    func sampleCPUCelsius() -> Double? {
        guard let systemRef = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
            return nil
        }
        let system = systemRef.takeRetainedValue()

        let matching = [
            "PrimaryUsagePage": temperatureUsagePage,
            "PrimaryUsage": temperatureUsage
        ] as CFDictionary
        IOHIDEventSystemClientSetMatching(system, matching)

        guard let servicesRef = IOHIDEventSystemClientCopyServices(system) else {
            return nil
        }
        let services = servicesRef.takeRetainedValue()

        var cpuValues: [Double] = []
        var fallbackValues: [Double] = []

        for index in 0..<CFArrayGetCount(services) {
            let service = unsafeBitCast(
                CFArrayGetValueAtIndex(services, index),
                to: IOHIDServiceClientRef.self
            )

            guard
                let eventRef = IOHIDServiceClientCopyEvent(service, temperatureEventType, 0, 0)
            else {
                continue
            }
            let event = eventRef.takeRetainedValue()

            let value = IOHIDEventGetFloatValue(event, Int32(temperatureEventType << 16))
            guard value.isPlausibleTemperature else {
                continue
            }

            if let name = productName(for: service), cpuPrefixes.contains(where: name.hasPrefix) {
                cpuValues.append(value)
            } else {
                fallbackValues.append(value)
            }
        }

        return cpuValues.max() ?? fallbackValues.max()
    }

    private func productName(for service: IOHIDServiceClientRef) -> String? {
        guard let valueRef = IOHIDServiceClientCopyProperty(service, "Product" as CFString) else {
            return nil
        }
        let value = valueRef.takeRetainedValue()

        return value as? String
    }
}

private typealias IOHIDEventSystemClientRef = CFTypeRef
private typealias IOHIDServiceClientRef = CFTypeRef
private typealias IOHIDEventRef = CFTypeRef

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(
    _ allocator: CFAllocator?
) -> Unmanaged<IOHIDEventSystemClientRef>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
@discardableResult
private func IOHIDEventSystemClientSetMatching(
    _ client: IOHIDEventSystemClientRef,
    _ matching: CFDictionary
) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(
    _ client: IOHIDEventSystemClientRef
) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(
    _ service: IOHIDServiceClientRef,
    _ type: Int64,
    _ options: Int32,
    _ timeout: Int64
) -> Unmanaged<IOHIDEventRef>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(
    _ service: IOHIDServiceClientRef,
    _ property: CFString
) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: IOHIDEventRef, _ field: Int32) -> Double
#endif

private final class SMCConnection {
    private let connection: io_connect_t

    private init(connection: io_connect_t) {
        self.connection = connection
    }

    static func open() -> SMCConnection? {
        let serviceNames: [String] = ["AppleSMC", "AppleSMCKeysEndpoint"]

        for serviceName in serviceNames {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(serviceName))
            guard service != 0 else {
                continue
            }
            defer {
                IOObjectRelease(service)
            }

            var connection = io_connect_t()
            guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
                continue
            }

            return SMCConnection(connection: connection)
        }

        return nil
    }

    func close() {
        IOServiceClose(connection)
    }

    func readTemperature(key: String) -> Double? {
        guard let data = readKey(key), data.bytes.count >= 2 else {
            return nil
        }

        switch data.type {
        case fourCharCode("flt "):
            guard data.bytes.count >= 4 else {
                return nil
            }
            let raw = UInt32(data.bytes[0]) << 24
                | UInt32(data.bytes[1]) << 16
                | UInt32(data.bytes[2]) << 8
                | UInt32(data.bytes[3])
            return Double(Float(bitPattern: raw))
        case fourCharCode("sp1e"):
            return data.unsignedFixedPoint(scale: 16_384)
        case fourCharCode("sp3c"):
            return data.unsignedFixedPoint(scale: 4_096)
        case fourCharCode("sp4b"):
            return data.unsignedFixedPoint(scale: 2_048)
        case fourCharCode("sp5a"):
            return data.unsignedFixedPoint(scale: 1_024)
        case fourCharCode("sp69"):
            return data.unsignedFixedPoint(scale: 512)
        case fourCharCode("sp78"):
            return data.signedFixedPoint(scale: 256)
        case fourCharCode("sp87"):
            return data.signedFixedPoint(scale: 128)
        case fourCharCode("sp96"):
            return data.signedFixedPoint(scale: 64)
        case fourCharCode("spa5"):
            return data.unsignedFixedPoint(scale: 32)
        case fourCharCode("spb4"):
            return data.signedFixedPoint(scale: 16)
        case fourCharCode("spf0"):
            return data.signedFixedPoint(scale: 1)
        case fourCharCode("fpe2"):
            return data.fpe2Value()
        default:
            return nil
        }
    }

    func discoverTemperature() -> [(key: String, value: Double)] {
        guard let count = keyCount(), count > 0 else {
            return []
        }

        var matches: [(String, Double)] = []
        for index in 0..<min(count, 4_096) {
            guard
                let key = key(at: index),
                key.hasPrefix("T"),
                let value = readTemperature(key: key),
                value.isPlausibleTemperature
            else {
                continue
            }

            matches.append((key, value))
        }

        let preferred = matches.filter { $0.0.hasPrefix("Tp") || $0.0.hasPrefix("TC") }
        return preferred.isEmpty ? matches : preferred
    }

    private func keyCount() -> Int? {
        guard let data = readKey("#KEY"), data.bytes.count >= 4 else {
            return nil
        }

        let value = UInt32(data.bytes[0]) << 24
            | UInt32(data.bytes[1]) << 16
            | UInt32(data.bytes[2]) << 8
            | UInt32(data.bytes[3])
        return Int(value)
    }

    private func key(at index: Int) -> String? {
        var input = SMCKeyData()
        input.data8 = SMCCommand.readIndex.rawValue
        input.data32 = UInt32(index)

        guard let output = call(input: &input), output.result == 0 else {
            return nil
        }

        return string(fromFourCharCode: output.key)
    }

    private func readKey(_ key: String) -> SMCReadData? {
        var input = SMCKeyData()
        input.key = fourCharCode(key)
        input.data8 = SMCCommand.readKeyInfo.rawValue

        guard let keyInfoOutput = call(input: &input) else {
            return nil
        }

        input.keyInfo = keyInfoOutput.keyInfo
        input.data8 = SMCCommand.readBytes.rawValue

        guard let output = call(input: &input), output.result == 0 else {
            return nil
        }

        let bytes = withUnsafeBytes(of: output.bytes) { Array($0) }
        let dataSize = min(Int(keyInfoOutput.keyInfo.dataSize), bytes.count)
        return SMCReadData(
            type: keyInfoOutput.keyInfo.dataType,
            bytes: Array(bytes.prefix(dataSize))
        )
    }

    private func call(input: inout SMCKeyData) -> SMCKeyData? {
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMCSelector.handleYPCEvent.rawValue),
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )

        return result == kIOReturnSuccess ? output : nil
    }
}

private enum SMCSelector: UInt8 {
    case handleYPCEvent = 2
}

private enum SMCCommand: UInt8 {
    case readBytes = 5
    case readIndex = 8
    case readKeyInfo = 9
}

private struct SMCReadData {
    let type: UInt32
    let bytes: [UInt8]
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPowerLimitData()
    var keyInfo = SMCKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPowerLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private extension SMCReadData {
    func unsignedFixedPoint(scale: Double) -> Double? {
        guard bytes.count >= 2 else {
            return nil
        }

        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return Double(raw) / scale
    }

    func signedFixedPoint(scale: Double) -> Double? {
        guard bytes.count >= 2 else {
            return nil
        }

        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return Double(Int16(bitPattern: raw)) / scale
    }

    func fpe2Value() -> Double? {
        guard bytes.count >= 2 else {
            return nil
        }

        return Double((Int(bytes[0]) << 6) + (Int(bytes[1]) >> 2))
    }
}

private func fourCharCode(_ value: String) -> UInt32 {
    var result: UInt32 = 0
    let bytes = Array(value.utf8.prefix(4))

    for byte in bytes {
        result = (result << 8) | UInt32(byte)
    }

    for _ in bytes.count..<4 {
        result <<= 8
    }

    return result
}

private func string(fromFourCharCode value: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff)
    ]

    return String(bytes: bytes, encoding: .ascii) ?? ""
}

private extension Double {
    var isPlausibleTemperature: Bool {
        self >= 5 && self <= 125
    }
}
