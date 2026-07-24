//
//  DatabaseBottstrap.swift
//  ProjectKey
//
//  Created by Kelvin Ip on 1/26/2026.
//
import Foundation
import SQLite3

final class DatabaseBootstrap {
    static let shared = DatabaseBootstrap()
    private init() {}
    
    private func bootLog(_ message: String) {
#if DEBUG
        guard isDebugLogEnabled() else { return }
        NSLog("%@", message)
#endif
    }

    private func isDebugLogEnabled() -> Bool {
#if DEBUG
        guard let obj = UserDefaults(suiteName: "group.Pulse01")?.object(forKey: "KB_DEBUG_LOG") else {
            return false
        }
        if let b = obj as? Bool { return b }
        if let n = obj as? NSNumber { return n.boolValue }
        return false
#else
        return false
#endif
    }

    private let groupId = "group.Pulse01"
    private let flagsVersion = "v2"
    private lazy var sharedFlags = UserDefaults(suiteName: groupId)

    /// 要確保檔案喺可用來源（extension bundle 或 main app 複製到 App Group）存在。
    private var files: [String] {
        var names = [
        "cangjie.sqlite",
        "quick3.sqlite",
        "stroke.sqlite",
        "ecdict.db",
        "english_ngram_small_prefix.db",
        "english_ngram_small.db",
        "traditional_regions.db",
        "pinyin_merged_bmp.db",
        "TSCharacters.sqlite"
        ]
#if DEBUG
        names.append("bopomofo.sqlite")
#endif
        // Dayi is proprietary. Copy it only when an authorized resource is actually
        // bundled; do not emit a missing-resource error in public builds without it.
        if bundledURL(for: "dayi.sqlite") != nil {
            names.append("dayi.sqlite")
        }
        return names
    }

    private func shouldNormalizeJournal(for name: String) -> Bool {
        // Only the shipped ngram DBs are known to be authored in WAL mode.
        return name == "english_ngram_small_prefix.db" ||
               name == "english_ngram_small.db" ||
               name == "traditional_regions.db" ||
               name == "pinyin_merged_bmp.db"
    }

    private func shouldOptimizeLookupIndexes(for name: String) -> Bool {
        name == "cangjie.sqlite" || name == "quick3.sqlite"
    }

    func prepareAll() {
        bootLog("[DB] prepareAll START groupId=\(groupId)")
        
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) else {
            NSLog("❌ AppGroup URL nil groupId=%@", groupId)
            return
        }
        bootLog("[DB] AppGroup Container URL: \(base.path)")

        for name in files {
            let didCopy: Bool
            let keepCached = (
                name == "english_ngram_small_prefix.db" ||
                name == "english_ngram_small.db" ||
                name == "traditional_regions.db" ||
                name == "pinyin_merged_bmp.db" ||
                 name == "TSCharacters.sqlite"
            )
            if keepCached {
                didCopy = ensureFile(name, to: base, overwrite: false)
            } else {
                didCopy = ensureFile(name, to: base)
            }

            // Normalize WAL->DELETE for shipped bigram DBs (even if already present).
            if shouldNormalizeJournal(for: name) {
                let dst = base.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: dst.path) {
                    let marker = markerKey("normalize", file: name)
                    let didNormalize = sharedFlags?.bool(forKey: marker) ?? false
                    // Safety: only mutate DB files right after copy to avoid racing active readers.
                    if didCopy && !didNormalize {
                        normalizeSQLiteJournalModeToDelete(at: dst)
                        sharedFlags?.set(true, forKey: marker)
                    }
                }
            }

            if shouldOptimizeLookupIndexes(for: name) {
                let dst = base.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: dst.path) {
                    let marker = markerKey("index", file: name)
                    let didIndex = sharedFlags?.bool(forKey: marker) ?? false
                    // Safety: only mutate DB files right after copy to avoid racing active readers.
                    if didCopy && !didIndex {
                        ensureLookupCoveringIndexes(at: dst, fileName: name)
                        sharedFlags?.set(true, forKey: marker)
                    }
                }
            }
        }
    }
    
    private func markerKey(_ kind: String, file: String) -> String {
        "db.bootstrap.\(flagsVersion).\(kind).\(file)"
    }
    
    private func ensureFile(_ name: String, to base: URL, overwrite: Bool = false) -> Bool {
        let dst = base.appendingPathComponent(name)

        guard let src = bundledURL(for: name) else {
            let parts = name.split(separator: ".", omittingEmptySubsequences: false)
            let res = String(parts.first ?? "")
            let ext = parts.count >= 2 ? String(parts.last ?? "") : ""
            NSLog("❌ missing resource in extension bundle: %@ (resource: %@, ext: %@, dst: %@) (check Copy Bundle Resources)", name, res, ext, dst.path)
            return false
        }

        let fm = FileManager.default
        let dstExists = fm.fileExists(atPath: dst.path)
        // Safety-first for keyboard extension runtime:
        // never replace an existing DB file in-place while extension may be reading it.
        if dstExists {
            bootLog("[DB] DB up-to-date: \(dst.path)")
            return false
        }

        do {
            try fm.copyItem(at: src, to: dst)
            bootLog("[DB] Copy success: \(src.path) -> \(dst.path)")

            // IMPORTANT: If the shipped DB was last closed in WAL mode, SQLite will try to open
            // ngram db-wal/-shm sidecars. If those files are missing, read-only opens can fail.
            // Normalize journal mode to DELETE for shipping DBs.
            return true
        } catch {
            NSLog("❌ copy fail %@: %@ (src: %@, dst: %@)", name, error.localizedDescription, src.path, dst.path)
            return false
        }
    }

    private func bundledURL(for name: String) -> URL? {
        // Try exact filename first (supports multi-dot names), then fallback to resource/ext split.
        if let exact = Bundle.main.url(forResource: name, withExtension: nil) {
            return exact
        }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        let res = String(parts.first ?? "")
        let ext = parts.count >= 2 ? String(parts.last ?? "") : ""
        return Bundle.main.url(forResource: res, withExtension: ext)
    }

    private func shouldReplaceExistingFile(src: URL, dst: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dst.path) else { return true }
        let srcValues = try? src.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let dstValues = try? dst.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let srcSize = srcValues?.fileSize ?? -1
        let dstSize = dstValues?.fileSize ?? -2
        if srcSize != dstSize { return true }
        let srcDate = srcValues?.contentModificationDate ?? .distantPast
        let dstDate = dstValues?.contentModificationDate ?? .distantFuture
        return srcDate > dstDate
    }
    private func normalizeSQLiteJournalModeToDelete(at dbURL: URL) {
        var db: OpaquePointer? = nil
        // Need read-write once to run PRAGMA and checkpoint.
        let rc = sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil)
        guard rc == SQLITE_OK, db != nil else {
            let msg = db != nil ? String(cString: sqlite3_errmsg(db)) : "open failed"
            NSLog("❌ [DB] normalize journal_mode failed: %@ (%@)", dbURL.path, msg)
            if db != nil { sqlite3_close(db) }
            return
        }
        defer { sqlite3_close(db) }

        // Try to checkpoint/truncate any WAL state, then force DELETE mode.
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)

        // Best-effort: remove sidecar files if they exist.
        // SQLite sidecars use "-wal" / "-shm" (dash), not ".wal".
        let wal = URL(fileURLWithPath: dbURL.path + "-wal")
        let shm = URL(fileURLWithPath: dbURL.path + "-shm")
        if FileManager.default.fileExists(atPath: wal.path) {
            try? FileManager.default.removeItem(at: wal)
        }
        if FileManager.default.fileExists(atPath: shm.path) {
            try? FileManager.default.removeItem(at: shm)
        }

        bootLog("[DB] normalized journal_mode=DELETE for \(dbURL.lastPathComponent)")
    }

    private func ensureLookupCoveringIndexes(at dbURL: URL, fileName: String) {
        var db: OpaquePointer? = nil
        let rc = sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = (db != nil) ? String(cString: sqlite3_errmsg(db)) : "open failed"
            NSLog("⚠️ [DB] index optimize open fail %@ (%@)", dbURL.lastPathComponent, msg)
            if db != nil { sqlite3_close(db) }
            return
        }
        defer { sqlite3_close(db) }

        let sql: String
        if fileName == "cangjie.sqlite" {
            sql = """
            CREATE INDEX IF NOT EXISTS idx_cj_code_freq_char1 ON cj(code, freq DESC, char1);
            PRAGMA optimize;
            """
        } else if fileName == "quick3.sqlite" {
            sql = """
            CREATE INDEX IF NOT EXISTS idx_q3_code_freq_char1 ON quick3(code, freq DESC, char1);
            PRAGMA optimize;
            """
        } else {
            return
        }

        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            NSLog("⚠️ [DB] index optimize failed %@ (%s)", dbURL.lastPathComponent, sqlite3_errmsg(db))
            return
        }
        bootLog("[DB] lookup indexes ready for \(dbURL.lastPathComponent)")
    }
}
