import Foundation
import SQLite3

/// 数据库存储错误类型
nonisolated public enum StoreError: LocalizedError, Sendable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case transactionFailed(String)
    case recordNotFound
    case databaseCorrupt
    
    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "打开数据库失败: \(msg)"
        case .prepareFailed(let msg): return "预编译 SQL 失败: \(msg)"
        case .stepFailed(let msg): return "执行 SQL 单步失败: \(msg)"
        case .transactionFailed(let msg): return "数据库事务执行失败: \(msg)"
        case .recordNotFound: return "未找到匹配记录"
        case .databaseCorrupt: return "数据库文件损坏"
        }
    }
}

/// 客户端本地快照备份元数据
nonisolated public struct DatabaseBackupItem: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { fileName }
    public let fileName: String
    public let fileURL: URL
    public let fileSizeText: String
    public let createdAt: Date
    public let recordCount: Int
    
    public init(
        fileName: String,
        fileURL: URL,
        fileSizeText: String,
        createdAt: Date,
        recordCount: Int
    ) {
        self.fileName = fileName
        self.fileURL = fileURL
        self.fileSizeText = fileSizeText
        self.createdAt = createdAt
        self.recordCount = recordCount
    }
}

/// 基于原生 SQLite3 C-API 实现的单一事实源（SSOT）离线存储层
/// 完全适配 CallKit Extension 15MB 严苛内存限制，支持 O(1) 内存流式遍历与 WAL 跨进程并发访问。
nonisolated public final class DirectoryStore: @unchecked Sendable {
    public static let shared = DirectoryStore()
    
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "cn.xizicl.YellowPages.DirectoryStore", qos: .userInitiated)
    private let dbPath: String
    
    public init(databaseURL: URL = AppGroupConstants.databaseURL) {
        self.dbPath = databaseURL.path
        openDatabase()
        createTables()
    }
    
    deinit {
        if let db = db {
            sqlite3_close_v2(db)
        }
    }
    
    // MARK: - 基础连接与建表
    
    private func openDatabase() {
        var dbPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        
        let rc = sqlite3_open_v2(dbPath, &dbPointer, flags, nil)
        guard rc == SQLITE_OK, let validDB = dbPointer else {
            let errorMsg = dbPointer != nil ? String(cString: sqlite3_errmsg(dbPointer)) : "Unknown"
            print("[DirectoryStore] 无法打开数据库: \(errorMsg)")
            return
        }
        
        self.db = validDB
        
        // 开启 WAL 模式以支持主 App 与 CallKit Extension 跨进程并发读取与写入
        executeRaw(sql: "PRAGMA journal_mode = WAL;")
        executeRaw(sql: "PRAGMA synchronous = NORMAL;")
        // 设置忙等超时，避免跨进程锁表直接失败
        sqlite3_busy_timeout(validDB, 5000)
    }
    
    private func executeRaw(sql: String) {
        guard let db = db else { return }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                let message = String(cString: errMsg)
                sqlite3_free(errMsg)
                print("[DirectoryStore] PRAGMA 执行失败: \(message)")
            }
        }
    }
    
    private func createTables() {
        queue.sync {
            guard db != nil else { return }

            // 1. 同步元数据版本表
            let createMetadataTable = """
            CREATE TABLE IF NOT EXISTS directory_metadata (
                key   TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """

            // 2. 号码主表（精准对齐 10 核心物理字段单一大宽表模式）
            let createDirectoryTable = """
            CREATE TABLE IF NOT EXISTS phone_directory (
                numeric_phone   INTEGER PRIMARY KEY,
                label           TEXT NOT NULL,
                call_action     INTEGER NOT NULL DEFAULT 0,
                call_category   TEXT NOT NULL,
                sms_action      INTEGER NOT NULL DEFAULT 4,
                sms_sub_action  INTEGER NOT NULL DEFAULT 0,
                confidence      REAL NOT NULL DEFAULT 1.0,
                is_deleted      INTEGER NOT NULL DEFAULT 0,
                updated_at      INTEGER NOT NULL,
                created_at      INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_phone_deleted ON phone_directory(is_deleted, numeric_phone ASC);
            CREATE INDEX IF NOT EXISTS idx_phone_call_action ON phone_directory(call_action, numeric_phone ASC);
            CREATE INDEX IF NOT EXISTS idx_phone_sms ON phone_directory(sms_action, sms_sub_action);
            """

            // 3. 极简短信规则表
            let createSmsRulesTable = """
            CREATE TABLE IF NOT EXISTS sms_rules (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                sender_pattern  TEXT NOT NULL,
                action          INTEGER NOT NULL,
                sub_action      INTEGER NOT NULL,
                keyword         TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_sms_rules_pattern ON sms_rules(sender_pattern);
            """
            
            // 4. 待上报本地队列
            let createReportQueueTable = """
            CREATE TABLE IF NOT EXISTS report_queue (
                id              TEXT PRIMARY KEY,
                raw_phone       TEXT NOT NULL,
                numeric_phone   INTEGER NOT NULL,
                report_type     TEXT NOT NULL,
                category        TEXT NOT NULL,
                custom_label    TEXT,
                content_snippet TEXT,
                action_suggested TEXT NOT NULL,
                reported_at     INTEGER NOT NULL,
                status          TEXT NOT NULL,
                retry_count     INTEGER NOT NULL DEFAULT 0,
                created_at      INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_report_status ON report_queue(status, created_at ASC);
            """
            
            executeRaw(sql: createMetadataTable)
            executeRaw(sql: createDirectoryTable)
            executeRaw(sql: createSmsRulesTable)
            executeRaw(sql: createReportQueueTable)
        }
    }
    
    // MARK: - 版本控制元数据
    
    public func getLocalVersion() -> Int64 {
        queue.sync {
            guard let db = db else { return 0 }
            let sql = "SELECT value FROM directory_metadata WHERE key = 'database_version' LIMIT 1;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    if let text = sqlite3_column_text(stmt, 0) {
                        return Int64(String(cString: text)) ?? 0
                    }
                }
            }
            return 0
        }
    }
    
    public func setLocalVersion(_ version: Int64) throws {
        try queue.sync {
            guard let db = db else { throw StoreError.openFailed("Database handle is nil") }
            let sql = "INSERT INTO directory_metadata (key, value) VALUES ('database_version', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(stmt, 1, "\(version)", -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }
    
    // MARK: - 全量与批量写入 (事务保障)
    
    public func batchUpsert(entries: [PhoneNumberEntry]) throws {
        try queue.sync {
            guard let db = db else { throw StoreError.openFailed("Database handle is nil") }
            guard !entries.isEmpty else { return }
            
            executeRaw(sql: "BEGIN IMMEDIATE TRANSACTION;")
            
            let sql = """
            INSERT INTO phone_directory (
                numeric_phone, label, call_action, call_category, sms_action, sms_sub_action, confidence, is_deleted, updated_at, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(numeric_phone) DO UPDATE SET
                label = excluded.label,
                call_action = excluded.call_action,
                call_category = excluded.call_category,
                sms_action = excluded.sms_action,
                sms_sub_action = excluded.sms_sub_action,
                confidence = excluded.confidence,
                is_deleted = excluded.is_deleted,
                updated_at = excluded.updated_at;
            """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                executeRaw(sql: "ROLLBACK;")
                throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            for entry in entries {
                sqlite3_reset(stmt)
                sqlite3_bind_int64(stmt, 1, entry.numericPhone)
                sqlite3_bind_text(stmt, 2, (entry.label as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 3, Int32(entry.callAction))
                sqlite3_bind_text(stmt, 4, (entry.callCategory as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 5, Int32(entry.smsAction))
                sqlite3_bind_int(stmt, 6, Int32(entry.smsSubAction))
                sqlite3_bind_double(stmt, 7, entry.confidence)
                sqlite3_bind_int(stmt, 8, Int32(entry.isDeleted))
                sqlite3_bind_int64(stmt, 9, entry.updatedAt)
                sqlite3_bind_int64(stmt, 10, entry.createdAt)
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    executeRaw(sql: "ROLLBACK;")
                    throw StoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
                }
            }
            
            executeRaw(sql: "COMMIT;")
        }
    }
    
    // MARK: - 增量 Diff 更新 (add/update/remove)
    
    public func applyDelta(changes: [DeltaItem]) throws {
        try queue.sync {
            guard let db = db else { throw StoreError.openFailed("Database handle is nil") }
            guard !changes.isEmpty else { return }
            
            executeRaw(sql: "BEGIN IMMEDIATE TRANSACTION;")
            
            let upsertSQL = """
            INSERT INTO phone_directory (
                numeric_phone, label, call_action, call_category, sms_action, sms_sub_action, confidence, is_deleted, updated_at, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
            ON CONFLICT(numeric_phone) DO UPDATE SET
                label = excluded.label,
                call_action = excluded.call_action,
                call_category = excluded.call_category,
                sms_action = excluded.sms_action,
                sms_sub_action = excluded.sms_sub_action,
                confidence = excluded.confidence,
                is_deleted = 0,
                updated_at = excluded.updated_at;
            """
            
            let deleteSQL = "DELETE FROM phone_directory WHERE numeric_phone = ?;"
            
            var upsertStmt: OpaquePointer?
            var deleteStmt: OpaquePointer?
            defer {
                sqlite3_finalize(upsertStmt)
                sqlite3_finalize(deleteStmt)
            }
            
            guard sqlite3_prepare_v2(db, upsertSQL, -1, &upsertStmt, nil) == SQLITE_OK,
                  sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK else {
                executeRaw(sql: "ROLLBACK;")
                throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            
            for item in changes {
                switch item.op {
                case .add, .update:
                    sqlite3_reset(upsertStmt)
                    sqlite3_bind_int64(upsertStmt, 1, item.numericPhone)
                    sqlite3_bind_text(upsertStmt, 2, ((item.label ?? "未知") as NSString).utf8String, -1, nil)
                    let callAct = item.callAction ?? 0
                    sqlite3_bind_int(upsertStmt, 3, Int32(callAct))
                    let callCat = item.callCategory ?? "enterprise"
                    sqlite3_bind_text(upsertStmt, 4, (callCat as NSString).utf8String, -1, nil)
                    sqlite3_bind_int(upsertStmt, 5, Int32(item.smsAction ?? (callAct == 1 ? 2 : 4)))
                    sqlite3_bind_int(upsertStmt, 6, Int32(item.smsSubAction ?? 0))
                    sqlite3_bind_double(upsertStmt, 7, item.confidence ?? 1.0)
                    sqlite3_bind_int64(upsertStmt, 8, item.updatedAt ?? now)
                    sqlite3_bind_int64(upsertStmt, 9, item.updatedAt ?? now)
                    
                    if sqlite3_step(upsertStmt) != SQLITE_DONE {
                        executeRaw(sql: "ROLLBACK;")
                        throw StoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
                    }
                    
                case .remove:
                    sqlite3_reset(deleteStmt)
                    sqlite3_bind_int64(deleteStmt, 1, item.numericPhone)
                    if sqlite3_step(deleteStmt) != SQLITE_DONE {
                        executeRaw(sql: "ROLLBACK;")
                        throw StoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
                    }
                }
            }
            
            executeRaw(sql: "COMMIT;")
        }
    }
    
    public func clearAllEntries() throws {
        try queue.sync {
            guard db != nil else { throw StoreError.openFailed("Database handle is nil") }
            executeRaw(sql: "DELETE FROM phone_directory;")
            executeRaw(sql: "DELETE FROM directory_metadata WHERE key = 'database_version';")
        }
    }

    /// 显式重建本地数据库（清空号码表与版本号，并重新创建 10 字段表与索引）
    public func rebuildDatabase() throws {
        try queue.sync {
            guard db != nil else { throw StoreError.openFailed("Database handle is nil") }
            executeRaw(sql: "DROP TABLE IF EXISTS phone_directory;")
            executeRaw(sql: "DELETE FROM directory_metadata WHERE key = 'database_version';")
            
            let createDirectoryTable = """
            CREATE TABLE IF NOT EXISTS phone_directory (
                numeric_phone   INTEGER PRIMARY KEY,
                label           TEXT NOT NULL,
                call_action     INTEGER NOT NULL DEFAULT 0,
                call_category   TEXT NOT NULL,
                sms_action      INTEGER NOT NULL DEFAULT 4,
                sms_sub_action  INTEGER NOT NULL DEFAULT 0,
                confidence      REAL NOT NULL DEFAULT 1.0,
                is_deleted      INTEGER NOT NULL DEFAULT 0,
                updated_at      INTEGER NOT NULL,
                created_at      INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_phone_deleted ON phone_directory(is_deleted, numeric_phone ASC);
            CREATE INDEX IF NOT EXISTS idx_phone_call_action ON phone_directory(call_action, numeric_phone ASC);
            CREATE INDEX IF NOT EXISTS idx_phone_sms ON phone_directory(sms_action, sms_sub_action);
            """
            executeRaw(sql: createDirectoryTable)
        }
    }

    // MARK: - 客户端快照备份管理 (Snapshot Backups)

    /// 创建当前数据库的本地快照备份，自动保留最近 maxKeep 次（默认 5 次）
    @discardableResult
    public func createBackup(maxKeep: Int = 5) throws -> DatabaseBackupItem {
        try queue.sync {
            guard let db = db else { throw StoreError.openFailed("Database handle is nil") }
            
            // 1. 先执行 WAL Checkpoint，强制将内存/WAL日志合并刷写至主库文件
            executeRaw(sql: "PRAGMA wal_checkpoint(TRUNCATE);")
            
            let dbURL = AppGroupConstants.databaseURL
            guard FileManager.default.fileExists(atPath: dbURL.path) else {
                throw StoreError.stepFailed("数据库文件不存在")
            }
            
            let backupDir = AppGroupConstants.backupsDirectoryURL
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestampStr = formatter.string(from: Date())
            let backupFileName = "yellowpages_backup_\(timestampStr).sqlite"
            let destURL = backupDir.appendingPathComponent(backupFileName)
            
            // 2. 复制数据库主文件
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: dbURL, to: destURL)
            let backupNow = Date()
            try? FileManager.default.setAttributes([.creationDate: backupNow, .modificationDate: backupNow], ofItemAtPath: destURL.path)
            
            // 3. 计算记录数与文件大小
            var count = 0
            let sql = "SELECT COUNT(1) FROM phone_directory WHERE is_deleted = 0;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    count = Int(sqlite3_column_int(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
            
            let size = (try? FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0
            let byteFormatter = ByteCountFormatter()
            byteFormatter.allowedUnits = [.useKB, .useMB]
            byteFormatter.countStyle = .file
            let sizeText = byteFormatter.string(fromByteCount: size)
            
            let backupItem = DatabaseBackupItem(
                fileName: backupFileName,
                fileURL: destURL,
                fileSizeText: sizeText,
                createdAt: Date(),
                recordCount: count
            )
            
            // 4. 自动保留最近 maxKeep 次备份，淘汰老备份
            pruneBackupsLocked(maxKeep: maxKeep)
            
            return backupItem
        }
    }

    /// 列出所有可用的历史备份（按创建时间倒序）
    public func listBackups() -> [DatabaseBackupItem] {
        let backupDir = AppGroupConstants.backupsDirectoryURL
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        
        let sqliteFiles = files.filter { $0.pathExtension == "sqlite" && $0.lastPathComponent.hasPrefix("yellowpages_backup_") }
        
        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useKB, .useMB]
        byteFormatter.countStyle = .file

        let filenameDateFormatter = DateFormatter()
        filenameDateFormatter.dateFormat = "yyyyMMdd_HHmmss"

        var items: [DatabaseBackupItem] = []
        for file in sqliteFiles {
            var date = Date()
            var size: Int64 = 0
            let filename = file.lastPathComponent

            // 优先从备份文件名中的毫秒/秒级时间戳反解（作为时间单一事实源，避免 copyItem 继承旧文件属性）
            if filename.hasPrefix("yellowpages_backup_") && filename.hasSuffix(".sqlite") {
                let timestampPart = filename
                    .replacingOccurrences(of: "yellowpages_backup_", with: "")
                    .replacingOccurrences(of: ".sqlite", with: "")
                if let parsed = filenameDateFormatter.date(from: timestampPart) {
                    date = parsed
                }
            } else if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path) {
                if let d = attrs[.creationDate] as? Date {
                    date = d
                } else if let d = attrs[.modificationDate] as? Date {
                    date = d
                }
            }

            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path) {
                if let s = attrs[.size] as? NSNumber {
                    size = s.int64Value
                }
            }
            let sizeText = byteFormatter.string(fromByteCount: size)
            
            // 探测备份中的条目数（使用 immutable=1 URI 只读模式，彻底避免 SQLite 查找不存在的 -wal 文件导致控制台打印 unix open 警告）
            var count = 0
            var tempDB: OpaquePointer?
            let uri = "file:\(file.path)?immutable=1"
            if sqlite3_open_v2(uri, &tempDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let tempDB = tempDB {
                var s: OpaquePointer?
                if sqlite3_prepare_v2(tempDB, "SELECT COUNT(1) FROM phone_directory WHERE is_deleted = 0;", -1, &s, nil) == SQLITE_OK {
                    if sqlite3_step(s) == SQLITE_ROW {
                        count = Int(sqlite3_column_int(s, 0))
                    }
                }
                sqlite3_finalize(s)
                sqlite3_close(tempDB)
            }
            
            items.append(
                DatabaseBackupItem(
                    fileName: file.lastPathComponent,
                    fileURL: file,
                    fileSizeText: sizeText,
                    createdAt: date,
                    recordCount: count
                )
            )
        }
        
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    /// 删除指定备份文件
    public func deleteBackup(fileName: String) throws {
        let backupDir = AppGroupConstants.backupsDirectoryURL
        let targetURL = backupDir.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
    }

    /// 淘汰超出数量限制的旧备份（内部锁内调用）
    private func pruneBackupsLocked(maxKeep: Int) {
        let backups = listBackups()
        if backups.count > maxKeep {
            let toRemove = backups.dropFirst(maxKeep)
            for item in toRemove {
                try? FileManager.default.removeItem(at: item.fileURL)
            }
        }
    }
    
    // MARK: - 本地黑名单管理 (Blacklist)

    /// 将单一号码快速加入本地拦截黑名单并设置为 blocking 动作
    public func addBlacklistNumber(phone: Int64, label: String, category: NumberCategory = .harassment) throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let entry = PhoneNumberEntry(
            numericPhone: phone,
            label: label,
            callAction: 1,
            callCategory: category.rawValue,
            smsAction: 2,
            smsSubAction: 0,
            confidence: 1.0,
            isDeleted: 0,
            updatedAt: now,
            createdAt: now
        )
        try batchUpsert(entries: [entry])
    }

    /// 查询指定号码是否已被加入本地黑名单
    public func isBlacklisted(phone: Int64) -> Bool {
        queue.sync {
            guard let db = db else { return false }
            let sql = "SELECT call_action FROM phone_directory WHERE numeric_phone = ? AND is_deleted = 0 LIMIT 1;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
            sqlite3_bind_int64(stmt, 1, phone)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int(stmt, 0) == 1
            }
            return false
        }
    }
    
    // MARK: - 单号码与模糊反查
    
    public func lookup(numericPhone: Int64) -> PhoneNumberEntry? {
        queue.sync {
            guard let db = db else { return nil }
            let sql = """
            SELECT numeric_phone, label, call_action, call_category, sms_action, sms_sub_action, confidence, is_deleted, updated_at, created_at
            FROM phone_directory
            WHERE numeric_phone = ? AND is_deleted = 0
            LIMIT 1;
            """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_int64(stmt, 1, numericPhone)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                let num = sqlite3_column_int64(stmt, 0)
                let label = String(cString: sqlite3_column_text(stmt, 1))
                let callAction = Int(sqlite3_column_int(stmt, 2))
                let callCategory = String(cString: sqlite3_column_text(stmt, 3))
                let smsAction = Int(sqlite3_column_int(stmt, 4))
                let smsSubAction = Int(sqlite3_column_int(stmt, 5))
                let confidence = sqlite3_column_double(stmt, 6)
                let isDeleted = Int(sqlite3_column_int(stmt, 7))
                let updatedAt = sqlite3_column_int64(stmt, 8)
                let createdAt = sqlite3_column_int64(stmt, 9)
                
                return PhoneNumberEntry(
                    numericPhone: num,
                    label: label,
                    callAction: callAction,
                    callCategory: callCategory,
                    smsAction: smsAction,
                    smsSubAction: smsSubAction,
                    confidence: confidence,
                    isDeleted: isDeleted,
                    updatedAt: updatedAt,
                    createdAt: createdAt
                )
            }
            return nil
        }
    }
    
    public func getRecordCount(action: EntryAction? = nil) -> Int {
        queue.sync {
            guard let db = db else { return 0 }
            let sql: String
            if let action = action {
                let actVal = (action == .block) ? 1 : 0
                sql = "SELECT COUNT(1) FROM phone_directory WHERE is_deleted = 0 AND call_action = \(actVal);"
            } else {
                sql = "SELECT COUNT(1) FROM phone_directory WHERE is_deleted = 0;"
            }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    return Int(sqlite3_column_int(stmt, 0))
                }
            }
            return 0
        }
    }

    /// 获取特定分类下的记录计数
    public func getCategoryCount(category: NumberCategory) -> Int {
        queue.sync {
            guard let db = db else { return 0 }
            let sql = "SELECT COUNT(1) FROM phone_directory WHERE is_deleted = 0 AND call_category = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (category.rawValue as NSString).utf8String, -1, nil)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    return Int(sqlite3_column_int(stmt, 0))
                }
            }
            return 0
        }
    }
    
    // MARK: - 报告待上报队列 (Report Queue)
    
    public func enqueueReport(_ report: ReportRecord) throws {
        try queue.sync {
            guard let db = db else { throw StoreError.openFailed("Database handle is nil") }
            let sql = """
            INSERT INTO report_queue (id, raw_phone, numeric_phone, report_type, category, custom_label, content_snippet, action_suggested, reported_at, status, retry_count, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            sqlite3_bind_text(stmt, 1, (report.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (report.rawPhoneNumber as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(stmt, 3, report.normalizedPhone)
            sqlite3_bind_text(stmt, 4, (report.reportType.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (report.categoryRaw as NSString).utf8String, -1, nil)
            if let label = report.customLabel {
                sqlite3_bind_text(stmt, 6, (label as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            if let snippet = report.contentSnippet {
                sqlite3_bind_text(stmt, 7, (snippet as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            sqlite3_bind_text(stmt, 8, (report.actionSuggested.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(stmt, 9, report.reportedAt)
            sqlite3_bind_text(stmt, 10, (report.status.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 11, Int32(report.retryCount))
            sqlite3_bind_int64(stmt, 12, now)
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
            executeRaw(sql: "PRAGMA wal_checkpoint(PASSIVE);")
        }
    }
    
    public func fetchPendingReports(limit: Int = 50) throws -> [ReportRecord] {
        try queue.sync {
            guard let db = db else { throw StoreError.openFailed("Database handle is nil") }
            let sql = """
            SELECT id, raw_phone, numeric_phone, report_type, category, custom_label, content_snippet, action_suggested, reported_at, status, retry_count
            FROM report_queue
            WHERE status IN ('pending', 'failed') AND retry_count < 5
            ORDER BY created_at ASC
            LIMIT ?;
            """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_int(stmt, 1, Int32(limit))
            
            var results: [ReportRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let rawPhone = String(cString: sqlite3_column_text(stmt, 1))
                let numericPhone = sqlite3_column_int64(stmt, 2)
                let reportTypeStr = String(cString: sqlite3_column_text(stmt, 3))
                let reportType = ReportType(rawValue: reportTypeStr) ?? .call
                let categoryStr = String(cString: sqlite3_column_text(stmt, 4))
                let category: NumberCategory
                if let direct = NumberCategory(rawValue: categoryStr) {
                    category = direct
                } else if categoryStr == "junk" {
                    category = .harassment
                } else if categoryStr == "orders" {
                    category = .delivery
                } else if categoryStr == "public_services" {
                    category = .official
                } else if categoryStr == "offers" || categoryStr == "coupons" || categoryStr == "promotion_others" {
                    category = .marketing
                } else {
                    category = .enterprise
                }
                
                var customLabel: String? = nil
                if let labelPtr = sqlite3_column_text(stmt, 5) {
                    customLabel = String(cString: labelPtr)
                }
                
                var contentSnippet: String? = nil
                if let snippetPtr = sqlite3_column_text(stmt, 6) {
                    contentSnippet = String(cString: snippetPtr)
                }
                
                let actionStr = String(cString: sqlite3_column_text(stmt, 7))
                let action: EntryAction = (actionStr == "block" || actionStr == "blocking") ? .block : .identify
                let reportedAt = sqlite3_column_int64(stmt, 8)
                let statusStr = String(cString: sqlite3_column_text(stmt, 9))
                let status = ReportStatus(rawValue: statusStr) ?? .pending
                let retryCount = Int(sqlite3_column_int(stmt, 10))
                
                let record = ReportRecord(
                    id: id,
                    rawPhoneNumber: rawPhone,
                    normalizedPhone: numericPhone,
                    reportType: reportType,
                    category: category,
                    customLabel: customLabel,
                    contentSnippet: contentSnippet,
                    actionSuggested: action,
                    reportedAt: reportedAt,
                    status: status,
                    retryCount: retryCount
                )
                results.append(record)
            }
            return results
        }
    }
    
    public func updateReportStatus(id: String, status: ReportStatus, incrementRetry: Bool = false) throws {
        try queue.sync {
            guard let db = db else { throw StoreError.openFailed("Database handle is nil") }
            let sql: String
            if incrementRetry {
                sql = "UPDATE report_queue SET status = ?, retry_count = retry_count + 1 WHERE id = ?;"
            } else {
                sql = "UPDATE report_queue SET status = ? WHERE id = ?;"
            }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(stmt, 1, (status.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }
    
    public func removeReport(id: String) throws {
        try queue.sync {
            guard let db = db else { throw StoreError.openFailed("Database handle is nil") }
            let sql = "DELETE FROM report_queue WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }
    
    /// 获取全部上报记录（倒序排列，用于主界面近期上报展示）
    public func fetchAllReports(limit: Int = 100) throws -> [ReportRecord] {
        try queue.sync {
            guard let db = db else { throw StoreError.openFailed("Database handle is nil") }
            let sql = """
            SELECT id, raw_phone, numeric_phone, report_type, category, custom_label, content_snippet, action_suggested, reported_at, status, retry_count
            FROM report_queue
            ORDER BY reported_at DESC
            LIMIT ?;
            """
            
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_int(stmt, 1, Int32(limit))
            
            var results: [ReportRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let rawPhone = String(cString: sqlite3_column_text(stmt, 1))
                let numericPhone = sqlite3_column_int64(stmt, 2)
                let reportTypeStr = String(cString: sqlite3_column_text(stmt, 3))
                let reportType = ReportType(rawValue: reportTypeStr) ?? .call
                let categoryStr = String(cString: sqlite3_column_text(stmt, 4))
                let category: NumberCategory
                if let direct = NumberCategory(rawValue: categoryStr) {
                    category = direct
                } else if categoryStr == "junk" {
                    category = .harassment
                } else if categoryStr == "orders" {
                    category = .delivery
                } else if categoryStr == "public_services" {
                    category = .official
                } else if categoryStr == "offers" || categoryStr == "coupons" || categoryStr == "promotion_others" {
                    category = .marketing
                } else {
                    category = .enterprise
                }
                
                var customLabel: String? = nil
                if let labelPtr = sqlite3_column_text(stmt, 5) {
                    customLabel = String(cString: labelPtr)
                }
                
                var contentSnippet: String? = nil
                if let snippetPtr = sqlite3_column_text(stmt, 6) {
                    contentSnippet = String(cString: snippetPtr)
                }
                
                let actionStr = String(cString: sqlite3_column_text(stmt, 7))
                let action: EntryAction = (actionStr == "block" || actionStr == "blocking") ? .block : .identify
                let reportedAt = sqlite3_column_int64(stmt, 8)
                let statusStr = String(cString: sqlite3_column_text(stmt, 9))
                let status = ReportStatus(rawValue: statusStr) ?? .pending
                let retryCount = Int(sqlite3_column_int(stmt, 10))
                
                let record = ReportRecord(
                    id: id,
                    rawPhoneNumber: rawPhone,
                    normalizedPhone: numericPhone,
                    reportType: reportType,
                    category: category,
                    customLabel: customLabel,
                    contentSnippet: contentSnippet,
                    actionSuggested: action,
                    reportedAt: reportedAt,
                    status: status,
                    retryCount: retryCount
                )
                results.append(record)
            }
            return results
        }
    }
}
