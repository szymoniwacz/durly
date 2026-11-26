import Foundation
import Darwin
import IOKit
import DurlyCore

// Obtain actual platform identity locally; no caller-supplied capability token.
enum NativeSMCProbe {
    private static let session = SMCProbeSession()

    static func platformIdentity() -> (model: String, os: String, architecture: String) {
        var size = 0
        var model = ""
        if sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0, size < 1024 {
            var buffer = [CChar](repeating: 0, count: size)
            let status = buffer.withUnsafeMutableBytes { bytes in
                sysctlbyname("hw.model", bytes.baseAddress, &size, nil, 0)
            }
            if status == 0, size > 0, size <= buffer.count,
               let terminator = buffer.prefix(size).firstIndex(of: 0), terminator == size - 1 {
                model = String(bytes: buffer.prefix(terminator).map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
            }
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #if arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "other"
        #endif
        return (model, os, architecture)
    }

    static func read() throws -> SMCProbeReport {
        let identity = platformIdentity()
        guard SMCProbeTarget.supports(model: identity.model, os: identity.os,
                                      architecture: identity.architecture) else {
            throw SMCReadError.unsupportedDevice
        }
        #if arch(x86_64)
        var connection: io_connect_t = 0
        return try session.run(open: {
            guard let matching = IOServiceMatching("AppleSMC") else {
                throw SMCReadError.serviceUnavailable
            }
            let service = IOServiceGetMatchingService(kIOMasterPortDefault, matching)
            guard service != 0 else { throw SMCReadError.serviceUnavailable }
            defer { IOObjectRelease(service) }
            let opened = IOServiceOpen(service, mach_task_self_, 0, &connection)
            guard opened == kIOReturnSuccess, connection != 0 else {
                throw SMCReadError.connectionFailed(opened)
            }
            let handle = connection
            return SMCChargeReader { request in
                var reply = [UInt8](repeating: 0, count: 80)
                var replySize = reply.count
                let status = request.withUnsafeBytes { input in
                    reply.withUnsafeMutableBytes { output in
                        IOConnectCallStructMethod(handle, 2, input.baseAddress,
                                                  input.count, output.baseAddress, &replySize)
                    }
                }
                guard status == kIOReturnSuccess else { throw SMCReadError.driverFailed(status) }
                guard replySize == 80 else { throw SMCReadError.malformedResponse }
                return reply
            }
        }, close: {
            let closed = IOServiceClose(connection)
            guard closed == kIOReturnSuccess else { throw SMCReadError.closeFailed(closed) }
        })
        #else
        throw SMCReadError.unsupportedDevice
        #endif
    }
}
