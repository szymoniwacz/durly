import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

public enum HistoryError: Error {
    case sqlite(Int32), unsupportedSchema, invalidSample, unknownEpoch
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
                } else if version != 1 { throw HistoryError.unsupportedSchema }
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
    // The caller must explicitly select a confirmed epoch. Never infer replacement
    // from capacity or cycles. A duplicate timestamp is rejected, not overwritten.
    public func append(_ sample: BatterySnapshot, epoch: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        guard sample.capturedAt.timeIntervalSince1970.isFinite else { throw HistoryError.invalidSample }
        let data = try JSONEncoder().encode(sample)
        guard let payload = String(data: data, encoding: .utf8) else { throw HistoryError.invalidSample }
        try statement("INSERT INTO sample(epoch,captured_at,payload) VALUES (?,?,?)") { stmt in
            try bind(epoch.uuidString, 1, stmt)
            try check(sqlite3_bind_double(stmt, 2, sample.capturedAt.timeIntervalSince1970))
            try bind(payload, 3, stmt)
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
