import Foundation

// Intel AppleSMC 80-byte ABI, researched against SMCKit in bclm v0.1.0.
// See docs/smc-read-probe.md for provenance and limitations.
public enum SMCChargeKey: String, CaseIterable {
    case bclm = "BCLM"
    case bfcl = "BFCL"

    fileprivate var code: UInt32 {
        switch self {
        case .bclm: return 0x42434C4D
        case .bfcl: return 0x4246434C
        }
    }
}

public enum SMCReadError: Error, Equatable {
    case unsupportedDevice, serviceUnavailable, connectionFailed(Int32)
    case driverFailed(Int32), malformedResponse, keyNotFound
    case controllerFailed(UInt8), unexpectedMetadata(size: UInt32, type: UInt32)
    case closeFailed(Int32)
}

// No arbitrary key, opcode, or write method is exposed by this reader.
// The exchange closure is the platform boundary; the codec is portable.
public struct SMCChargeReader {
    private let exchange: ([UInt8]) throws -> [UInt8]

    public init(exchange: @escaping ([UInt8]) throws -> [UInt8]) {
        self.exchange = exchange
    }

    public func read(_ key: SMCChargeKey) throws -> UInt8 {
        let metadata = try checked(exchange(Self.request(key, metadata: true)))
        let size = Self.uint32(metadata, at: 28)
        let type = Self.uint32(metadata, at: 32)
        guard size == 1, type == 0x75693820 else {
            throw SMCReadError.unexpectedMetadata(size: size, type: type)
        }
        let data = try checked(exchange(Self.request(key, metadata: false)))
        // The read reply's keyInfo is not assumed to be populated. The preceding
        // metadata reply establishes the size; the full frame is required.
        return data[48]
    }

    private func checked(_ reply: [UInt8]) throws -> [UInt8] {
        guard reply.count == 80 else { throw SMCReadError.malformedResponse }
        switch reply[40] {
        case 0: return reply
        case 132: throw SMCReadError.keyNotFound
        default: throw SMCReadError.controllerFailed(reply[40])
        }
    }

    private static func request(_ key: SMCChargeKey, metadata: Bool) -> [UInt8] {
        // Explicit little-endian Intel ABI. All reserved bytes are zero.
        var bytes = [UInt8](repeating: 0, count: 80)
        put(key.code, into: &bytes, at: 0)
        if !metadata { put(1, into: &bytes, at: 28) }
        bytes[42] = metadata ? 9 : 5
        return bytes
    }

    private static func put(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        for i in 0..<4 {
            bytes[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i))
        }
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 { value |= UInt32(bytes[offset + i]) << (8 * i) }
        return value
    }
}
