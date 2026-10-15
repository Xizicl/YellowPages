import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

/// 举报上报异常定义
nonisolated public enum ReportError: LocalizedError, Sendable {
    case invalidPhoneNumber(String)
    case queueFailed(String)
    case uploadFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidPhoneNumber(let num): return "无法解析或不符合规范的手机号码: \(num)"
        case .queueFailed(let msg): return "保存待上报队列失败: \(msg)"
        case .uploadFailed(let msg): return "上传举报数据失败: \(msg)"
        }
    }
}

/// 举报上报服务（负责号码格式清洗规范化、本地持久化队列入队及异步上报防刷）
public actor ReportService {
    public static let shared = ReportService()
    
    private var baseURL: URL
    private let session: URLSession
    private let store: DirectoryStore
    private let deviceFingerprint: String
    
    public init(
        baseURL: URL = AppGroupConstants.serverBaseURL,
        session: URLSession = .shared,
        store: DirectoryStore = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.store = store
        self.deviceFingerprint = Self.resolveDeviceFingerprint()
    }

    /// 动态热更新服务端地址
    public func updateBaseURL(_ newURL: URL) {
        self.baseURL = newURL
    }

    /// 获取当前生效的服务端地址
    public func getBaseURL() -> URL {
        return self.baseURL
    }
    
    // MARK: - 设备指纹生成 (防刷反作弊)
    
    public static func resolveDeviceFingerprint() -> String {
        let key = "cn.xizicl.YellowPages.device_salt_uuid"
        let rawID: String
        
        if let stored = UserDefaults.standard.string(forKey: key) {
            rawID = stored
        } else {
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: key)
            rawID = newID
        }
        
        let salted = "salt_yellowpages_2026_" + rawID
        let digest = SHA256.hash(data: Data(salted.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - 号码清洗与规范化 (E.164 Pure Digits)
    
    /// 将用户输入的各形态号码统一清洗为 CallKit / E.164 纯数字
    /// 例如: "010-88888888" -> 861088888888, "13800138000" -> 8613800138000, "+86 138-0013-8000" -> 8613800138000
    public static func normalizeToE164(raw: String) -> Int64? {
        // 过滤非数字字符
        let digits = raw.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        
        // 针对中国大陆常见格式做规范化适配
        if digits.hasPrefix("86") {
            return Int64(digits)
        }
        
        // 11位手机号 (如 13800138000)
        if digits.count == 11, digits.hasPrefix("1") {
            return Int64("86" + digits)
        }
        
        // 带区号座机 (如 01088888888, 021...) -> 去掉前导 0 加 86
        if digits.hasPrefix("0") && digits.count >= 10 {
            let withoutLeadingZero = String(digits.dropFirst())
            return Int64("86" + withoutLeadingZero)
        }
        
        // 400/800 服务电话 (如 4008888888) -> 加 86
        if digits.hasPrefix("400") || digits.hasPrefix("800") {
            return Int64("86" + digits)
        }
        
        return Int64(digits)
    }
    
    // MARK: - 提交标记举报
    
    /// 提交一次标记上报
    @discardableResult
    public func submitReport(
        rawPhoneNumber: String,
        type: ReportType,
        category: NumberCategory,
        categoryRaw: String? = nil,
        customLabel: String? = nil,
        contentSnippet: String? = nil,
        actionSuggested: EntryAction = .identify
    ) async throws -> ReportRecord {
        guard let normalized = Self.normalizeToE164(raw: rawPhoneNumber) else {
            throw ReportError.invalidPhoneNumber(rawPhoneNumber)
        }
        
        let record = ReportRecord(
            rawPhoneNumber: rawPhoneNumber,
            normalizedPhone: normalized,
            reportType: type,
            category: category,
            categoryRaw: categoryRaw ?? category.rawValue,
            customLabel: customLabel,
            contentSnippet: contentSnippet,
            actionSuggested: actionSuggested,
            reportedAt: Int64(Date().timeIntervalSince1970 * 1000),
            status: .pending
        )
        
        // 1. 先持久化存入 SQLite 本地队列，保证离线可靠性
        do {
            try store.enqueueReport(record)
        } catch {
            throw ReportError.queueFailed(error.localizedDescription)
        }
        
        // 2. 尝试即时异步冲洗待办队列
        Task { [weak self] in
            await self?.flushPendingReports()
        }
        
        return record
    }
    
    // MARK: - 队列冲洗与网络上报
    
    /// 触发未完成队列的批量重试上传
    @discardableResult
    public func flushPendingReports(batchSize: Int = 20) async -> (successCount: Int, failedCount: Int) {
        guard let pending = try? store.fetchPendingReports(limit: batchSize), !pending.isEmpty else {
            return (0, 0)
        }
        
        var successCount = 0
        var failedCount = 0
        
        for record in pending {
            try? store.updateReportStatus(id: record.id, status: .uploading)
            
            do {
                try await uploadSingleReport(record)
                try? store.updateReportStatus(id: record.id, status: .uploaded)
                successCount += 1
            } catch {
                try? store.updateReportStatus(id: record.id, status: .failed, incrementRetry: true)
                failedCount += 1
            }
        }
        
        return (successCount, failedCount)
    }
    
    private func uploadSingleReport(_ record: ReportRecord) async throws {
        let url = baseURL.appendingPathComponent("/api/v1/reports")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceFingerprint, forHTTPHeaderField: "X-Device-Fingerprint")
        
        let isoFormatter = ISO8601DateFormatter()
        let dateString = isoFormatter.string(from: Date(timeIntervalSince1970: Double(record.reportedAt) / 1000.0))
        
        let body = ReportRequestBody(
            phoneNumber: String(record.normalizedPhone),
            reportType: record.reportType.rawValue,
            category: record.categoryRaw,
            label: record.customLabel,
            contentSnippet: record.contentSnippet,
            reportedAt: dateString,
            actionSuggested: record.actionSuggested.rawValue
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        let apiResponse = try Self.decodeReportResponse(from: data, response: response)
        guard apiResponse.isSuccess else {
            throw ReportError.uploadFailed(apiResponse.message)
        }
    }
    
    nonisolated private static func decodeReportResponse(from data: Data, response: URLResponse) throws -> APIResponse<ReportResponseData> {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReportError.uploadFailed("响应非 HTTP 格式")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ReportError.uploadFailed("服务端返回状态码: \(httpResponse.statusCode)")
        }
        
        return try JSONDecoder().decode(APIResponse<ReportResponseData>.self, from: data)
    }
}
