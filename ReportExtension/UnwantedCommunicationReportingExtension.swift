import UIKit
import SwiftUI
import IdentityLookup
import IdentityLookupUI
import CallKit
import SQLite3

@objc(UnwantedCommunicationReportingExtension)
class UnwantedCommunicationReportingExtension: ILClassificationUIExtensionViewController {

    private let appGroupID = "group.cn.xizicl.YellowPages"
    private let databaseFilename = "yellowpages_directory.sqlite"

    // 默认执行拦截并标记
    private var classificationAction: ILClassificationAction = .reportJunk

    private var hostingController: UIHostingController<ReportExtensionView>?

    // 当前用户选择状态双向即时同步
    private var currentCategory: String = "harassment"
    private var currentCustomLabel: String? = nil
    private var currentAlsoBlock: Bool = true
    private var rawSender: String = "未知号码"
    private var messageBody: String?
    private var reportType: String = "call"
    private var dateReceived: Date = Date()
    private var isSaved: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 通知系统界面准备完成，激活系统导航栏右上角「✓」
        self.extensionContext.isReadyForClassificationResponse = true
    }
    
    // Customize UI based on the classification request before the view is loaded
    override func prepare(for classificationRequest: ILClassificationRequest) {
        rawSender = "未知号码"
        messageBody = nil
        reportType = "call"
        dateReceived = Date()
        isSaved = false

        if let messageRequest = classificationRequest as? ILMessageClassificationRequest {
            reportType = "sms"
            if let firstComm = messageRequest.messageCommunications.first {
                rawSender = firstComm.sender ?? "未知发件人"
                messageBody = firstComm.messageBody
                dateReceived = firstComm.dateReceived
            }
            currentCategory = "junk"
            currentAlsoBlock = true
        } else if let callRequest = classificationRequest as? ILCallClassificationRequest {
            reportType = "call"
            if let firstComm = callRequest.callCommunications.first {
                rawSender = firstComm.sender ?? "未知来电"
                dateReceived = firstComm.dateReceived
            }
            currentCategory = "harassment"
            currentAlsoBlock = true
        }

        // 移除旧的子控制器
        if let existing = hostingController {
            existing.willMove(toParent: nil)
            existing.view.removeFromSuperview()
            existing.removeFromParent()
        }

        // 装载现代化的 SwiftUI 原生标记面板
        let swiftUIView = ReportExtensionView(
            rawSender: rawSender,
            channel: reportType,
            snippet: messageBody,
            reportedDate: dateReceived,
            onStateChanged: { [weak self] category, customTag, alsoBlock in
                guard let self = self else { return }
                self.currentCategory = category.rawValue
                self.currentCustomLabel = customTag
                self.currentAlsoBlock = alsoBlock
                self.classificationAction = (alsoBlock || category.isRisk) ? .reportJunkAndBlockSender : .reportJunk
                self.extensionContext.isReadyForClassificationResponse = true
            }
        )

        let host = UIHostingController(rootView: swiftUIView)
        self.hostingController = host
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)

        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)

        self.classificationAction = currentAlsoBlock ? .reportJunkAndBlockSender : .reportJunk
        self.extensionContext.isReadyForClassificationResponse = true
    }
    
    // 当用户点击系统右上角原生「✓ (对号)」时，系统回调此方法获取分类响应
    override func classificationResponse(for request: ILClassificationRequest) -> ILClassificationResponse {
        performSaveIfNeeded()
        return ILClassificationResponse(action: self.classificationAction)
    }

    private func performSaveIfNeeded() {
        guard !isSaved else { return }
        isSaved = true
        saveReportToQueue(
            rawPhone: rawSender,
            reportType: reportType,
            category: currentCategory,
            customLabel: currentCustomLabel,
            contentSnippet: messageBody,
            alsoBlock: currentAlsoBlock,
            reportedAt: dateReceived
        )
        self.classificationAction = currentAlsoBlock ? .reportJunkAndBlockSender : .reportJunk
    }

    // MARK: - 写入 App Group SQLite

    private func getDatabaseURL() -> URL? {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return containerURL.appendingPathComponent(databaseFilename)
        }
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("YellowPagesSharedGroup")
        return dir.appendingPathComponent(databaseFilename)
    }

    private func normalizeToE164(raw: String) -> Int64? {
        let digits = raw.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }

        if digits.hasPrefix("86") {
            return Int64(digits)
        }
        if digits.count == 11, digits.hasPrefix("1") {
            return Int64("86" + digits)
        }
        if digits.hasPrefix("0") && digits.count >= 10 {
            return Int64("86" + digits.dropFirst())
        }
        if digits.hasPrefix("400") || digits.hasPrefix("800") {
            return Int64("86" + digits)
        }
        return Int64("86" + digits) ?? Int64(digits)
    }

    private func saveReportToQueue(
        rawPhone: String,
        reportType: String,
        category: String,
        customLabel: String?,
        contentSnippet: String?,
        alsoBlock: Bool,
        reportedAt: Date
    ) {
        guard let dbURL = getDatabaseURL() else {
            return
        }
        let dir = dbURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let db = db else {
            return
        }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)

        // 确保 phone_directory 与 report_queue 表完好
        let createPhoneDirectorySql = """
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
        sqlite3_exec(db, createPhoneDirectorySql, nil, nil, nil)

        let createTableSql = """
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
        """
        sqlite3_exec(db, createTableSql, nil, nil, nil)

        let insertSql = """
        INSERT INTO report_queue (
            id, raw_phone, numeric_phone, report_type, category, custom_label, content_snippet,
            action_suggested, reported_at, status, retry_count, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 0, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        let id = UUID().uuidString
        let numeric = normalizeToE164(raw: rawPhone) ?? 0
        let action = alsoBlock ? "block" : "identify"
        let reportedAtMs = Int64(reportedAt.timeIntervalSince1970 * 1000)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (rawPhone as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 3, numeric)
        sqlite3_bind_text(stmt, 4, (reportType as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (category as NSString).utf8String, -1, nil)
        if let label = customLabel, !label.isEmpty {
            sqlite3_bind_text(stmt, 6, (label as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        if let snippet = contentSnippet, !snippet.isEmpty {
            sqlite3_bind_text(stmt, 7, (snippet as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        sqlite3_bind_text(stmt, 8, (action as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 9, reportedAtMs)
        sqlite3_bind_int64(stmt, 10, nowMs)

        _ = sqlite3_step(stmt)

        // 无论拦截还是识别，只要解析出有效号码，均事务级原子落库 phone_directory 10 字段宽表
        if numeric > 0 {
            let isBlock = alsoBlock || category == "harassment" || category == "fraud"
            let callAct = isBlock ? 1 : 0
            let smsAct: Int
            let smsSub: Int
            if isBlock {
                smsAct = 2
                smsSub = 0
            } else {
                switch category {
                case "delivery":
                    smsAct = 4; smsSub = 10002
                case "official":
                    smsAct = 4; smsSub = 10008
                case "enterprise":
                    smsAct = 4; smsSub = 10001
                case "real_estate":
                    smsAct = 3; smsSub = 20000
                case "finance_loan", "marketing":
                    smsAct = 3; smsSub = 20001
                default:
                    smsAct = 4; smsSub = 0
                }
            }

            let effectiveLabel: String
            if let custom = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
                effectiveLabel = custom
            } else {
                effectiveLabel = self.defaultCategoryDisplayName(for: category)
            }

            let upsertSql = """
            INSERT INTO phone_directory (
                numeric_phone, label, call_action, call_category, sms_action, sms_sub_action, confidence, is_deleted, updated_at, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, 1.0, 0, ?, ?)
            ON CONFLICT(numeric_phone) DO UPDATE SET
                label = excluded.label,
                call_action = excluded.call_action,
                call_category = excluded.call_category,
                sms_action = excluded.sms_action,
                sms_sub_action = excluded.sms_sub_action,
                confidence = 1.0,
                is_deleted = 0,
                updated_at = excluded.updated_at;
            """
            var upsertStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, upsertSql, -1, &upsertStmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(upsertStmt, 1, numeric)
                sqlite3_bind_text(upsertStmt, 2, (effectiveLabel as NSString).utf8String, -1, nil)
                sqlite3_bind_int(upsertStmt, 3, Int32(callAct))
                sqlite3_bind_text(upsertStmt, 4, (category as NSString).utf8String, -1, nil)
                sqlite3_bind_int(upsertStmt, 5, Int32(smsAct))
                sqlite3_bind_int(upsertStmt, 6, Int32(smsSub))
                sqlite3_bind_int64(upsertStmt, 7, nowMs)
                sqlite3_bind_int64(upsertStmt, 8, nowMs)
                _ = sqlite3_step(upsertStmt)
                sqlite3_finalize(upsertStmt)
            }
        }

        sqlite3_exec(db, "PRAGMA wal_checkpoint(PASSIVE);", nil, nil, nil)

        // 强行通知 CallKit 扩展重载数据库，确保通话记录与拦截规则即时生效！
        CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: "cn.xizicl.YellowPages.CallDirectoryExtension") { error in
            if let error = error {
                NSLog("[ReportExtension] ⚠️ 触发 CallKit 扩展重载失败: %@", error.localizedDescription)
            } else {
                NSLog("[ReportExtension] ✅ 触发 CallKit 扩展重载成功，通话记录标签即时生效")
            }
        }
    }

    private func defaultCategoryDisplayName(for category: String) -> String {
        switch category {
        case "delivery": return "快递外卖"
        case "official": return "官方政企"
        case "enterprise": return "机构服务"
        case "real_estate": return "房产中介"
        case "finance_loan": return "贷款理财"
        case "marketing": return "广告推销"
        case "harassment": return "恶意骚扰"
        case "fraud": return "疑似诈骗"
        case "orders": return "订单与物流"
        case "finance": return "金融银行"
        case "public_services": return "公共政务"
        case "reminders": return "行程预订"
        case "offers": return "优惠营销"
        case "coupons": return "打折卡券"
        case "promotion_others": return "其他推广"
        case "junk": return "垃圾拦截"
        case "allow": return "验证码放行"
        default: return "自定义标记"
        }
    }
}
