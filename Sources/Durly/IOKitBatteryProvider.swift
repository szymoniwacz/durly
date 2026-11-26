import Foundation
import IOKit
import IOKit.ps
import DurlyCore

struct IOKitBatteryProvider: BatteryProvider {
    func read() throws -> BatterySnapshot {
        // Query only the internal battery. No privileged calls or SMC writes.
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { throw BatteryReadError.unavailable }

        var powerSource: [String: Any]?
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any],
                  description["Type"] as? String == "InternalBattery" else { continue }
            powerSource = description
            break
        }
        guard let powerSource = powerSource else { throw BatteryReadError.unavailable }

        var registry: [String: Any] = [:]
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        if service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let values = properties?.takeRetainedValue() as? [String: Any] {
                registry = values
            }
        }
        return BatteryDecoder.decode(registry: registry, powerSource: powerSource)
    }
}
