import Foundation
import CallKit
import SQLite3

final class CallDirectoryHandler: CXCallDirectoryProvider {

    private let appGroupID = "group.cn.xizicl.YellowPages"
    private let databaseFilename = "yellowpages_directory.sqlite"

    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self

        do {
            // 如果是增量请求，清空重置系统缓存，防止出现重复记录或状态不同步
            if context.isIncremental {
                context.removeAllBlockingEntries()
                context.removeAllIdentificationEntries()
            }

            try populateEntries(into: context)
            context.completeRequest()
        } catch {
            let nsError = NSError(
                domain: "cn.xizicl.YellowPages.CallDirectoryExtension",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
            )
            context.cancelRequest(withError: nsError)
        }
    }

    private func getDatabaseURL() -> URL? {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return containerURL.appendingPathComponent(databaseFilename)
        }
        return nil
    }

    private func populateEntries(into context: CXCallDirectoryExtensionContext) throws {
        guard let dbURL = getDatabaseURL(), FileManager.default.fileExists(atPath: dbURL.path) else {
            // 数据库尚未初始化时安全直接返回
            return
        }

        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(
            dbURL.path,
            &db,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let db = db else {
            throw NSError(
                domain: "cn.xizicl.YellowPages.CallDirectoryExtension",
                code: Int(openResult),
                userInfo: [NSLocalizedDescriptionKey: "无法打开单一事实源 SQLite 数据库: \(openResult)"]
            )
        }
        defer { sqlite3_close(db) }

        // 1. 注入黑名单拦截号码（严格数值单调递增升序）
        try streamBlockingEntries(db: db, into: context)

        // 2. 注入黄页识别号码（严格数值单调递增升序）
        try streamIdentificationEntries(db: db, into: context)
    }

    private func streamBlockingEntries(db: OpaquePointer, into context: CXCallDirectoryExtensionContext) throws {
        let sql = """
        SELECT numeric_phone FROM phone_directory
        WHERE is_deleted = 0 AND call_action = 1
        ORDER BY numeric_phone ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw NSError(
                domain: "cn.xizicl.YellowPages.CallDirectoryExtension",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "准备拦截查询失败: \(errmsg)"]
            )
        }
        defer { sqlite3_finalize(stmt) }

        var lastPhoneNumber: CXCallDirectoryPhoneNumber = 0

        while sqlite3_step(stmt) == SQLITE_ROW {
            let current = sqlite3_column_int64(stmt, 0)
            // 严格单调递增断言防御：CallKit 强制要求数值严格递增，相等或倒序将直接导致加载崩溃
            guard current > lastPhoneNumber else { continue }
            context.addBlockingEntry(withNextSequentialPhoneNumber: current)
            lastPhoneNumber = current
        }
    }

    private func categoryDisplayName(for rawCategory: String) -> String {
        switch rawCategory {
        case "delivery", "express", "takeaway":
            return "快递外卖"
        case "official":
            return "官方政企"
        case "enterprise", "institution", "finance":
            return "机构服务"
        case "real_estate", "realEstate":
            return "房产中介"
        case "finance_loan", "financeLoan", "finance_telemarketing":
            return "贷款理财"
        case "marketing", "telemarketing":
            return "广告推销"
        case "harassment":
            return "恶意骚扰"
        case "fraud":
            return "疑似诈骗"
        default:
            return "机构服务"
        }
    }

    private func streamIdentificationEntries(db: OpaquePointer, into context: CXCallDirectoryExtensionContext) throws {
        let sql = """
        SELECT numeric_phone, label, call_category FROM phone_directory
        WHERE is_deleted = 0 AND call_action = 0
        ORDER BY numeric_phone ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw NSError(
                domain: "cn.xizicl.YellowPages.CallDirectoryExtension",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "准备识别查询失败: \(errmsg)"]
            )
        }
        defer { sqlite3_finalize(stmt) }

        var lastPhoneNumber: CXCallDirectoryPhoneNumber = 0

        while sqlite3_step(stmt) == SQLITE_ROW {
            let current = sqlite3_column_int64(stmt, 0)
            guard current > lastPhoneNumber else { continue }

            guard let cString = sqlite3_column_text(stmt, 1) else { continue }
            let rawLabel = String(cString: cString).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawLabel.isEmpty else { continue }

            let categoryStr = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let catName = categoryDisplayName(for: categoryStr)
            let displayLabel = rawLabel.hasPrefix("[") ? rawLabel : "[\(catName)] \(rawLabel)"

            context.addIdentificationEntry(
                withNextSequentialPhoneNumber: current,
                label: displayLabel
            )
            lastPhoneNumber = current
        }
    }
}

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: Error) {
        // 请求失败系统回调
    }
}
