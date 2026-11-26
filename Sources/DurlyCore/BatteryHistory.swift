import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

public struct BatteryEpoch: Identifiable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let number: Int64
    public let sampleCount: Int64
}

public enum HistoryEventKind: String, Codable {
    case recordingStarted, recordingStopped, sleep, telemetryUnavailable, clockChange, replacement, appQuit, manualSMC
}

public struct HistoryEvent: Identifiable, Equatable, Codable {
    public let id: Int64
    public let capturedAt: Date
    public let kind: HistoryEventKind
    public let detail: String
    public let session: UUID?
}

public enum HistoryError: Error {
    case sqlite(Int32), unsupportedSchema, invalidSample, unknownEpoch, activeEpoch, unsafeExportDestination
}

// One connection, serialized by the lock. No hardware access.
public final class BatteryHistory {
    private let db: OpaquePointer
    private let lock = NSLock()
    public init(url: URL) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let opened = handle else {
            if let handle = handle { sqlite3_close(handle) }
            throw HistoryError.sqlite(result)
        }
        db = opened
        do {
            try check(sqlite3_busy_timeout(db, 2000))
            try execute("PRAGMA foreign_keys=ON")
            try execute("BEGIN IMMEDIATE")
            do {
                let version = try scalar("PRAGMA user_version")
                if version == 0 {
                    try execute("CREATE TABLE battery_epoch(id TEXT PRIMARY KEY, created_at REAL NOT NULL)")
                    try execute("CREATE TABLE sample(id INTEGER PRIMARY KEY, epoch TEXT NOT NULL REFERENCES battery_epoch(id), captured_at REAL NOT NULL, payload TEXT NOT NULL, UNIQUE(epoch,captured_at))")
                    try execute("PRAGMA user_version=1")
                }
                if version == 0 || version == 1 {
                    try execute("CREATE TABLE history_event(id INTEGER PRIMARY KEY, epoch TEXT NOT NULL REFERENCES battery_epoch(id), captured_at REAL NOT NULL, kind TEXT NOT NULL, detail TEXT NOT NULL, session TEXT)")
                    try execute("CREATE INDEX history_event_epoch ON history_event(epoch,id)")
                    try execute("PRAGMA user_version=2")
                }
                if (0...2).contains(version) {
                    try execute("ALTER TABLE sample ADD COLUMN session TEXT")
                    try execute("PRAGMA user_version=3")
                } else if version != 3 { throw HistoryError.unsupportedSchema }
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        } catch { sqlite3_close(db); throw error }
    }
    deinit { sqlite3_close(db) }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else { throw HistoryError.sqlite(result) }
    }
    private func execute(_ sql: String) throws {
        try check(sqlite3_exec(db, sql, nil, nil, nil))
    }
    private func statement<T>(_ sql: String, _ work: (OpaquePointer) throws -> T) throws -> T {
        var stmt: OpaquePointer?
        try check(sqlite3_prepare_v2(db, sql, -1, &stmt, nil))
        guard let stmt = stmt else { throw HistoryError.sqlite(SQLITE_ERROR) }
        defer { sqlite3_finalize(stmt) }
        return try work(stmt)
    }
    private func scalar(_ sql: String) throws -> Int64 {
        try statement(sql) { stmt in
            let result = sqlite3_step(stmt)
            guard result == SQLITE_ROW else { throw HistoryError.sqlite(result) }
            return sqlite3_column_int64(stmt, 0)
        }
    }
    private func bind(_ value: String, _ index: Int32, _ stmt: OpaquePointer) throws {
        try check(sqlite3_bind_text(stmt, index, value, -1,
            unsafeBitCast(-1, to: sqlite3_destructor_type.self)))
    }
    private func done(_ stmt: OpaquePointer) throws {
        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE else { throw HistoryError.sqlite(result) }
    }
    public func createEpoch(at date: Date) throws -> UUID {
        lock.lock(); defer { lock.unlock() }
        guard date.timeIntervalSince1970.isFinite else { throw HistoryError.invalidSample }
        let id = UUID()
        try statement("INSERT INTO battery_epoch(id,created_at) VALUES (?,?)") { stmt in
            try bind(id.uuidString, 1, stmt)
            try check(sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970))
            try done(stmt)
        }
        return id
    }
    public func appendEvent(epoch: UUID, at date: Date, kind: HistoryEventKind, detail: String = "", session: UUID? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        guard date.timeIntervalSince1970.isFinite else { throw HistoryError.invalidSample }
        try statement("INSERT INTO history_event(epoch,captured_at,kind,detail,session) VALUES (?,?,?,?,?)") { stmt in
            try bind(epoch.uuidString, 1, stmt)
            try check(sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970))
            try bind(kind.rawValue, 3, stmt)
            try bind(detail, 4, stmt)
            if let session = session { try bind(session.uuidString, 5, stmt) }
            else { try check(sqlite3_bind_null(stmt, 5)) }
            try done(stmt)
        }
    }

    public func events(epoch: UUID, limit: Int = 1000) throws -> [HistoryEvent] {
        lock.lock(); defer { lock.unlock() }
        guard (1...10000).contains(limit) else { throw HistoryError.invalidSample }
        return try statement("SELECT id,captured_at,kind,detail,session FROM history_event WHERE epoch=? ORDER BY id DESC LIMIT ?") { stmt in
            try bind(epoch.uuidString, 1, stmt)
            try check(sqlite3_bind_int64(stmt, 2, Int64(limit)))
            var values: [HistoryEvent] = []
            while true {
                let result = sqlite3_step(stmt)
                if result == SQLITE_DONE { return values }
                guard result == SQLITE_ROW, let kind = sqlite3_column_text(stmt, 2),
                      let eventKind = HistoryEventKind(rawValue: String(cString: kind)),
                      let detail = sqlite3_column_text(stmt, 3) else { throw HistoryError.sqlite(result) }
                let session = sqlite3_column_text(stmt, 4).flatMap { UUID(uuidString: String(cString: $0)) }
                values.append(HistoryEvent(id: sqlite3_column_int64(stmt, 0),
                    capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                    kind: eventKind, detail: String(cString: detail), session: session))
            }
        }
    }

    // Export an immutable, transactionally consistent JSON Lines stream without
    // loading the entire history into memory. The caller supplies a new file.
    public func export(epoch: UUID, to url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        guard url.isFileURL, !FileManager.default.fileExists(atPath: url.path) else {
            throw HistoryError.unsafeExportDestination
        }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".durly-export-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil,
                attributes: [.posixPermissions: 0o600]) else { throw HistoryError.unsafeExportDestination }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        func write(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            data.append(10)
            try handle.write(contentsOf: data)
        }
        try execute("BEGIN")
        do {
            try statement("SELECT created_at FROM battery_epoch WHERE id=?") { stmt in
                try bind(epoch.uuidString, 1, stmt)
                guard sqlite3_step(stmt) == SQLITE_ROW else { throw HistoryError.unknownEpoch }
                try write(["type": "metadata", "version": 1, "epoch": epoch.uuidString,
                           "registeredUnixSeconds": sqlite3_column_double(stmt, 0),
                           "coverage": "Samples without session are legacy; unclosed sessions have unknown end. Do not infer continuous coverage."])
            }
            try statement("SELECT id,captured_at,payload,session FROM sample WHERE epoch=? ORDER BY id") { stmt in
                try bind(epoch.uuidString, 1, stmt)
                while true {
                    let result = sqlite3_step(stmt)
                    if result == SQLITE_DONE { break }
                    guard result == SQLITE_ROW, let value = sqlite3_column_text(stmt, 2) else {
                        throw HistoryError.sqlite(result)
                    }
                    let payload = try JSONSerialization.jsonObject(with: Data(String(cString: value).utf8))
                    var row: [String: Any] = ["type": "sample", "id": sqlite3_column_int64(stmt, 0),
                               "unixSeconds": sqlite3_column_double(stmt, 1), "snapshot": payload]
                    if let session = sqlite3_column_text(stmt, 3) { row["session"] = String(cString: session) }
                    try write(row)
                }
            }
            try statement("SELECT id,captured_at,kind,detail,session FROM history_event WHERE epoch=? ORDER BY id") { stmt in
                try bind(epoch.uuidString, 1, stmt)
                while true {
                    let result = sqlite3_step(stmt)
                    if result == SQLITE_DONE { break }
                    guard result == SQLITE_ROW, let kind = sqlite3_column_text(stmt, 2),
                          let detail = sqlite3_column_text(stmt, 3) else { throw HistoryError.sqlite(result) }
                    var row: [String: Any] = ["type": "event", "id": sqlite3_column_int64(stmt, 0),
                        "unixSeconds": sqlite3_column_double(stmt, 1), "kind": String(cString: kind),
                        "detail": String(cString: detail)]
                    if let session = sqlite3_column_text(stmt, 4) { row["session"] = String(cString: session) }
                    try write(row)
                }
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
        try handle.synchronize()
        try handle.close()
        try FileManager.default.moveItem(at: temporary, to: url)
    }

    // Only historical epochs can be removed. The latest remains available for
    // explicit confirmation on launch, even if recording is currently stopped.
    public func deleteArchivedEpoch(_ epoch: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            try statement("SELECT id FROM battery_epoch ORDER BY rowid DESC LIMIT 1") { stmt in
                guard sqlite3_step(stmt) == SQLITE_ROW, let value = sqlite3_column_text(stmt, 0) else {
                    throw HistoryError.unknownEpoch
                }
                guard String(cString: value) != epoch.uuidString else { throw HistoryError.activeEpoch }
            }
            for sql in ["DELETE FROM sample WHERE epoch=?", "DELETE FROM history_event WHERE epoch=?", "DELETE FROM battery_epoch WHERE id=?"] {
                try statement(sql) { stmt in
                    try bind(epoch.uuidString, 1, stmt)
                    try done(stmt)
                }
            }
            guard sqlite3_changes(db) == 1 else { throw HistoryError.unknownEpoch }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    public func epochs() throws -> [BatteryEpoch] {
        lock.lock(); defer { lock.unlock() }
        return try statement("SELECT e.id,e.created_at,e.rowid,(SELECT COUNT(*) FROM sample s WHERE s.epoch=e.id) FROM battery_epoch e ORDER BY e.rowid DESC") { stmt in
            var values: [BatteryEpoch] = []
            while true {
                let result = sqlite3_step(stmt)
                if result == SQLITE_DONE { return values }
                guard result == SQLITE_ROW, let value = sqlite3_column_text(stmt, 0),
                      let id = UUID(uuidString: String(cString: value)) else {
                    throw HistoryError.sqlite(result)
                }
                values.append(BatteryEpoch(id: id,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                    number: sqlite3_column_int64(stmt, 2),
                    sampleCount: sqlite3_column_int64(stmt, 3)))
            }
        }
    }

    public func observedBaseline(epoch: UUID) throws -> BatterySnapshot? {
        lock.lock(); defer { lock.unlock() }
        return try statement("SELECT payload FROM sample WHERE epoch=? ORDER BY id ASC LIMIT 1") { stmt in
            try bind(epoch.uuidString, 1, stmt)
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW, let value = sqlite3_column_text(stmt, 0) else {
                throw HistoryError.sqlite(result)
            }
            return try JSONDecoder().decode(BatterySnapshot.self, from: Data(String(cString: value).utf8))
        }
    }

    public func latestEpoch() throws -> UUID? {
        lock.lock(); defer { lock.unlock() }
        return try statement("SELECT id FROM battery_epoch ORDER BY rowid DESC LIMIT 1") { stmt in
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW, let value = sqlite3_column_text(stmt, 0),
                  let id = UUID(uuidString: String(cString: value)) else {
                throw HistoryError.unknownEpoch
            }
            return id
        }
    }

    // The caller must explicitly select a confirmed epoch. Never infer replacement
    // from capacity or cycles. A duplicate timestamp is rejected, not overwritten.
    public func append(_ sample: BatterySnapshot, epoch: UUID, session: UUID? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        guard sample.capturedAt.timeIntervalSince1970.isFinite else { throw HistoryError.invalidSample }
        let data = try JSONEncoder().encode(sample)
        guard let payload = String(data: data, encoding: .utf8) else { throw HistoryError.invalidSample }
        try statement("INSERT INTO sample(epoch,captured_at,payload,session) VALUES (?,?,?,?)") { stmt in
            try bind(epoch.uuidString, 1, stmt)
            try check(sqlite3_bind_double(stmt, 2, sample.capturedAt.timeIntervalSince1970))
            try bind(payload, 3, stmt)
            if let session = session { try bind(session.uuidString, 4, stmt) }
            else { try check(sqlite3_bind_null(stmt, 4)) }
            try done(stmt)
        }
    }
    public func samples(epoch: UUID, limit: Int = 1000) throws -> [BatterySnapshot] {
        lock.lock(); defer { lock.unlock() }
        guard (1...10000).contains(limit) else { throw HistoryError.invalidSample }
        return try statement("SELECT payload FROM sample WHERE epoch=? ORDER BY captured_at DESC,id DESC LIMIT ?") { stmt in
            try bind(epoch.uuidString, 1, stmt)
            try check(sqlite3_bind_int64(stmt, 2, Int64(limit)))
            var values: [BatterySnapshot] = []
            while true {
                let result = sqlite3_step(stmt)
                if result == SQLITE_DONE { return values }
                guard result == SQLITE_ROW, let value = sqlite3_column_text(stmt, 0) else {
                    throw HistoryError.sqlite(result)
                }
                let data = Data(String(cString: value).utf8)
                values.append(try JSONDecoder().decode(BatterySnapshot.self, from: data))
            }
        }
    }
}
