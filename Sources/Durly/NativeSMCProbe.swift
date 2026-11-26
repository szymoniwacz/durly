import Foundation
import IOKit
import DurlyCore

// Read-only diagnostic boundary. No privileged helper and no write selector.
enum NativeSMCProbe {
    static func read(capability: ControlCapability) throws -> [SMCChargeKey: Result<UInt8, Error>] {
        guard capability.reason == .unverifiedBackend else { throw SMCReadError.unsupportedDevice }
        #if arch(x86_64)
        guard let matching = IOServiceMatching("AppleSMC") else {
            throw SMCReadError.serviceUnavailable
        }
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, matching)
        guard service != 0 else { throw SMCReadError.serviceUnavailable }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let opened = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard opened == kIOReturnSuccess, connection != 0 else {
            throw SMCReadError.connectionFailed(opened)
        }
        // All per-key failures are captured as results, so this path always closes.
        let reader = SMCChargeReader { request in
            var reply = [UInt8](repeating: 0, count: 80)
            var replySize = reply.count
            let status = request.withUnsafeBytes { input in
                reply.withUnsafeMutableBytes { output in
                    IOConnectCallStructMethod(connection, 2, input.baseAddress,
                                              input.count, output.baseAddress, &replySize)
                }
            }
            guard status == kIOReturnSuccess else { throw SMCReadError.driverFailed(status) }
            guard replySize == 80 else { throw SMCReadError.malformedResponse }
            return reply
        }
        var values: [SMCChargeKey: Result<UInt8, Error>] = [:]
        for key in SMCChargeKey.allCases {
            values[key] = Result { try reader.read(key) }
        }
        let closed = IOServiceClose(connection)
        guard closed == kIOReturnSuccess else { throw SMCReadError.closeFailed(closed) }
        return values
        #else
        throw SMCReadError.unsupportedDevice
        #endif
    }
}
