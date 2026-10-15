import Foundation

/// 上报通道类型
nonisolated public enum ReportType: String, Sendable, CaseIterable {
    case call = "call"
    case sms = "sms"
    
    public var displayName: String {
        switch self {
        case .call:
            return "来电举报"
        case .sms:
            return "短信举报"
        }
    }
}

nonisolated extension ReportType: Codable {}

/// 上报本地队列处理状态
nonisolated public enum ReportStatus: String, Sendable {
    case pending = "pending"
    case uploading = "uploading"
    case uploaded = "uploaded"
    case failed = "failed"
}

nonisolated extension ReportStatus: Codable {}

/// 用户标记与骚扰举报模型
nonisolated public struct ReportRecord: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    
    /// 用户输入的原始号码字符串（可能包含 +、空格、分机号或横杠）
    public let rawPhoneNumber: String
    
    /// 规范化后的 E.164 纯数字（例如 861088888888）
    public let normalizedPhone: Int64
    
    /// 上报渠道（电话或短信）
    public let reportType: ReportType
    
    /// 分类
    public let category: NumberCategory
    
    /// 原始分类代码（支持 CallCategory 与 SMSCategory）
    public let categoryRaw: String
    
    /// 用户填写的自定义标签（可选，如“某某中介”）
    public let customLabel: String?
    
    /// 短信内容摘录或通话记录摘要（可脱敏）
    public let contentSnippet: String?
    
    /// 用户建议的处理动作（识别展示或直接拦截）
    public let actionSuggested: EntryAction
    
    /// 事件上报发生时间（毫秒级时间戳）
    public let reportedAt: Int64
    
    /// 同步队列状态
    public var status: ReportStatus
    
    /// 重试次数
    public var retryCount: Int
    
    public init(
        id: String = UUID().uuidString,
        rawPhoneNumber: String,
        normalizedPhone: Int64,
        reportType: ReportType,
        category: NumberCategory,
        categoryRaw: String? = nil,
        customLabel: String? = nil,
        contentSnippet: String? = nil,
        actionSuggested: EntryAction = .identify,
        reportedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        status: ReportStatus = .pending,
        retryCount: Int = 0
    ) {
        self.id = id
        self.rawPhoneNumber = rawPhoneNumber
        self.normalizedPhone = normalizedPhone
        self.reportType = reportType
        self.category = category
        self.categoryRaw = categoryRaw ?? category.rawValue
        self.customLabel = customLabel
        self.contentSnippet = contentSnippet
        self.actionSuggested = actionSuggested
        self.reportedAt = reportedAt
        self.status = status
        self.retryCount = retryCount
    }
}

nonisolated extension ReportRecord: Codable {}
