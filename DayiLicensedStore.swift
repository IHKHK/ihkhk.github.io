import Foundation
import SQLite3

/// Read-only adapter for an officially licensed Dayi resource.
/// No Dayi roots or codes are embedded in source control.
final class DayiLicensedStore {
    static let shared = DayiLicensedStore()

    private let lock = NSLock()
    private var db: OpaquePointer?
    private var didValidate = false
    private var validationResult = false
    private var cachedLabels: [String: String] = [:]

    private init() {}

    deinit {
        if let db { sqlite3_close(db) }
    }

    var isAuthorizedAndReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        if didValidate { return validationResult }
        didValidate = true
        validationResult = openAndValidateLocked()
        return validationResult
    }

    func rootLabel(for key: String) -> String? {
        guard isAuthorizedAndReady else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedLabels[key] { return cached }
        guard let value = scalarLocked(
            "SELECT root_label FROM dayi_key_labels WHERE key = ? LIMIT 1",
            bindings: [key]
        ) else { return nil }
        cachedLabels[key] = value
        if cachedLabels.count > 512 { cachedLabels.removeAll(keepingCapacity: false) }
        return value
    }

    func lookupExact(code: String, limit: Int) -> [String] {
        lookup(
            sql: "SELECT text FROM dayi_entries WHERE code = ? ORDER BY weight DESC, text LIMIT ?",
            bindings: [code],
            limit: limit
        )
    }

    func lookupPrefix(code: String, limit: Int) -> [String] {
        lookup(
            sql: "SELECT text FROM dayi_entries WHERE code LIKE ? ESCAPE '\\' ORDER BY weight DESC, length(code), text LIMIT ?",
            bindings: [escapedLikePrefix(code) + "%"],
            limit: limit
        )
    }

    private func lookup(sql: String, bindings: [String], limit: Int) -> [String] {
        guard isAuthorizedAndReady else { return [] }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, KB_SQLITE_TRANSIENT)
        }
        sqlite3_bind_int(statement, Int32(bindings.count + 1), Int32(max(1, min(80, limit))))
        var output: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(statement, 0) else { continue }
            let value = String(cString: raw)
            if !value.isEmpty { output.append(value) }
        }
        return output
    }

    private func openAndValidateLocked() -> Bool {
        guard let url = resourceURL() else { return false }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let handle else {
            if handle != nil { sqlite3_close(handle) }
            return false
        }
        db = handle
        let required: [String: String] = [
            "schema_version": "1",
            "authorization": "licensed",
            "layout": "dayi40"
        ]
        for (key, expected) in required {
            guard scalarLocked(
                "SELECT value FROM dayi_metadata WHERE key = ? LIMIT 1",
                bindings: [key]
            ) == expected else {
                sqlite3_close(handle)
                db = nil
                return false
            }
        }
        guard let licensor = scalarLocked(
            "SELECT value FROM dayi_metadata WHERE key = 'licensor' LIMIT 1",
            bindings: []
        ), !licensor.isEmpty,
        let reference = scalarLocked(
            "SELECT value FROM dayi_metadata WHERE key = 'license_reference' LIMIT 1",
            bindings: []
        ), !reference.isEmpty else {
            sqlite3_close(handle)
            db = nil
            return false
        }
        return true
    }

    private func scalarLocked(_ sql: String, bindings: [String]) -> String? {
        guard let db else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, KB_SQLITE_TRANSIENT)
        }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let raw = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: raw)
    }

    private func resourceURL() -> URL? {
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.Pulse01"
        )?.appendingPathComponent("dayi.sqlite"),
           FileManager.default.fileExists(atPath: group.path) {
            return group
        }
        return Bundle.main.url(forResource: "dayi", withExtension: "sqlite")
    }

    private func escapedLikePrefix(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
