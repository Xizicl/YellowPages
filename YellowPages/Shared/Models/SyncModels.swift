import Foundation

// MARK: - 通用 API 响应封装

/// 统一定义的后端 RESTful 响应体
nonisolated public struct APIResponse<T: Sendable>: Sendable {
    public let code: Int
    public let message: String
    public let data: T?
    public let timestamp: Int64
    
    public var isSuccess: Bool {
        code == 0
    }
}

nonisolated extension APIResponse: Decodable where T: Decodable {}
nonisolated extension APIResponse: Encodable where T: Encodable {}

// MARK: - 设备信誉画像概要

nonisolated public struct DeviceProfileSummary: Sendable {
    public let deviceFingerprint: String
    public let creditLevel: String
    public let creditLevelName: String
    public let reputationScore: Double
    public let totalReports: Int
    public let approvedReports: Int
    public let isBlocked: Bool

    enum CodingKeys: String, CodingKey {
        case deviceFingerprint = "device_fingerprint"
        case creditLevel = "credit_level"
        case creditLevelName = "credit_level_name"
        case reputationScore = "reputation_score"
        case totalReports = "total_reports"
        case approvedReports = "approved_reports"
        case isBlocked = "is_blocked"
    }
}

nonisolated extension DeviceProfileSummary: Codable {}

// MARK: - 数据库版本与元信息

nonisolated public struct SyncMetadataResponse: Sendable {
    public let latestVersion: Int64
    public let minSupportedVersion: Int64
    public let identificationCount: Int
    public let blockingCount: Int
    public let fullSyncChunks: Int
    public let chunkSize: Int
    public let updatedAt: String
    public let deviceProfile: DeviceProfileSummary?
    
    enum CodingKeys: String, CodingKey {
        case latestVersion = "latest_version"
        case minSupportedVersion = "min_supported_version"
        case identificationCount = "identification_count"
        case blockingCount = "blocking_count"
        case fullSyncChunks = "full_sync_chunks"
        case chunkSize = "chunk_size"
        case updatedAt = "updated_at"
        case deviceProfile = "device_profile"
    }
}

nonisolated extension SyncMetadataResponse: Codable {}

// MARK: - 全量同步数据结构

nonisolated public struct PhoneNumberEntryDTO: Sendable {
    public let numericPhone: Int64
    public let label: String
    public let callAction: Int
    public let callCategory: String
    public let smsAction: Int
    public let smsSubAction: Int
    public let confidence: Double
    public let isDeleted: Int
    public let updatedAt: Int64
    public let createdAt: Int64
    
    enum CodingKeys: String, CodingKey {
        case numericPhone = "numeric_phone"
        case label
        case callAction = "call_action"
        case callCategory = "call_category"
        case smsAction = "sms_action"
        case smsSubAction = "sms_sub_action"
        case confidence
        case isDeleted = "is_deleted"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.numericPhone = try c.decode(Int64.self, forKey: .numericPhone)
        self.label = try c.decode(String.self, forKey: .label)
        self.callAction = (try? c.decode(Int.self, forKey: .callAction)) ?? 0
        self.callCategory = (try? c.decode(String.self, forKey: .callCategory)) ?? "enterprise"
        self.smsAction = (try? c.decode(Int.self, forKey: .smsAction)) ?? 4
        self.smsSubAction = (try? c.decode(Int.self, forKey: .smsSubAction)) ?? 0
        self.confidence = (try? c.decode(Double.self, forKey: .confidence)) ?? 1.0
        self.isDeleted = (try? c.decode(Int.self, forKey: .isDeleted)) ?? 0
        self.updatedAt = (try? c.decode(Int64.self, forKey: .updatedAt)) ?? Int64(Date().timeIntervalSince1970 * 1000)
        self.createdAt = (try? c.decode(Int64.self, forKey: .createdAt)) ?? self.updatedAt
    }
    
    public func toEntry() -> PhoneNumberEntry {
        PhoneNumberEntry(
            numericPhone: numericPhone,
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
}

nonisolated extension PhoneNumberEntryDTO: Codable {}

nonisolated public struct SyncFullChunkResponse: Sendable {
    public let version: Int64
    public let chunkIndex: Int
    public let totalChunks: Int
    public let hasMore: Bool
    public let records: [PhoneNumberEntryDTO]
    
    enum CodingKeys: String, CodingKey {
        case version
        case chunkIndex = "chunk_index"
        case totalChunks = "total_chunks"
        case hasMore = "has_more"
        case records
    }
}

nonisolated extension SyncFullChunkResponse: Codable {}

// MARK: - 增量同步数据结构

nonisolated public enum DeltaOp: String, Sendable {
    case add = "add"
    case update = "update"
    case remove = "remove"
}

nonisolated extension DeltaOp: Codable {}

nonisolated public struct DeltaItem: Sendable {
    public let op: DeltaOp
    public let numericPhone: Int64
    public let label: String?
    public let callAction: Int?
    public let callCategory: String?
    public let smsAction: Int?
    public let smsSubAction: Int?
    public let confidence: Double?
    public let updatedAt: Int64?
    
    enum CodingKeys: String, CodingKey {
        case op
        case numericPhone = "numeric_phone"
        case label
        case callAction = "call_action"
        case callCategory = "call_category"
        case smsAction = "sms_action"
        case smsSubAction = "sms_sub_action"
        case confidence
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.op = (try? c.decode(DeltaOp.self, forKey: .op)) ?? .add
        self.numericPhone = try c.decode(Int64.self, forKey: .numericPhone)
        self.label = try? c.decode(String.self, forKey: .label)
        self.callAction = try? c.decode(Int.self, forKey: .callAction)
        self.callCategory = try? c.decode(String.self, forKey: .callCategory)
        self.smsAction = try? c.decode(Int.self, forKey: .smsAction)
        self.smsSubAction = try? c.decode(Int.self, forKey: .smsSubAction)
        self.confidence = try? c.decode(Double.self, forKey: .confidence)
        self.updatedAt = try? c.decode(Int64.self, forKey: .updatedAt)
    }
}

nonisolated extension DeltaItem: Codable {}

nonisolated public struct SyncDeltaResponse: Sendable {
    public let baseVersion: Int64
    public let targetVersion: Int64
    public let requireFullReload: Bool
    public let nextCursor: String?
    public let hasMore: Bool
    public let changes: [DeltaItem]
    
    enum CodingKeys: String, CodingKey {
        case baseVersion = "base_version"
        case targetVersion = "target_version"
        case requireFullReload = "require_full_reload"
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
        case changes
    }
}

nonisolated extension SyncDeltaResponse: Codable {}

// MARK: - 在线反查数据结构

nonisolated public struct LocationInfo: Sendable {
    public let province: String?
    public let city: String?
}

nonisolated extension LocationInfo: Codable {}

nonisolated public struct TagInfo: Sendable {
    public let label: String
    public let category: NumberCategory
    public let confidence: Double
    public let sourceType: String?
    public let isOfficial: Bool
    public let isBlocking: Bool
    public let primaryAction: String?
    public let primaryActionLabel: String?
    public let subAction: String?
    public let subActionLabel: String?
    
    enum CodingKeys: String, CodingKey {
        case label
        case category
        case confidence
        case sourceType = "source_type"
        case isOfficial = "is_official"
        case isBlocking = "is_blocking"
        case primaryAction = "primary_action"
        case primaryActionLabel = "primary_action_label"
        case subAction = "sub_action"
        case subActionLabel = "sub_action_label"
    }
}

nonisolated extension TagInfo: Codable {}

nonisolated public struct RiskInfo: Sendable {
    public let level: String
    public let score: Double
    public let reportCount: Int
    
    enum CodingKeys: String, CodingKey {
        case level
        case score
        case reportCount = "report_count"
    }
}

nonisolated extension RiskInfo: Codable {}

nonisolated public struct NumberLookupResult: Sendable {
    public let phoneNumber: String
    public let numericPhone: Int64?
    public let found: Bool?
    public let formatted: String?
    public let countryCode: String?
    public let carrier: String?
    public let location: LocationInfo?
    public let tagInfo: TagInfo?
    public let riskInfo: RiskInfo?
    
    enum CodingKeys: String, CodingKey {
        case phoneNumber = "phone_number"
        case numericPhone = "numeric_phone"
        case found
        case formatted
        case countryCode = "country_code"
        case carrier
        case location
        case tagInfo = "tag_info"
        case riskInfo = "risk_info"
    }
}

nonisolated extension NumberLookupResult: Codable {}

// MARK: - 举报上报数据结构

nonisolated public struct ReportRequestBody: Sendable {
    public let phoneNumber: String
    public let reportType: String
    public let category: String
    public let label: String?
    public let contentSnippet: String?
    public let reportedAt: String
    public let actionSuggested: String?
    
    enum CodingKeys: String, CodingKey {
        case phoneNumber = "phone_number"
        case reportType = "report_type"
        case category
        case label
        case contentSnippet = "content_snippet"
        case reportedAt = "reported_at"
        case actionSuggested = "action_suggested"
    }
    
    public init(
        phoneNumber: String,
        reportType: String,
        category: String,
        label: String? = nil,
        contentSnippet: String? = nil,
        reportedAt: String,
        actionSuggested: String? = nil
    ) {
        self.phoneNumber = phoneNumber
        self.reportType = reportType
        self.category = category
        self.label = label
        self.contentSnippet = contentSnippet
        self.reportedAt = reportedAt
        self.actionSuggested = actionSuggested
    }
}

nonisolated extension ReportRequestBody: Codable {}

nonisolated public struct ReportResponseData: Sendable {
    public let reportId: String
    public let status: String
    public let accepted: Bool
    
    enum CodingKeys: String, CodingKey {
        case reportId = "report_id"
        case status
        case accepted
    }
}

nonisolated extension ReportResponseData: Codable {}

// MARK: - 号码申诉与纠错数据结构

nonisolated public struct AppealRequestBody: Sendable {
    public let phoneNumber: String
    public let appealType: String
    public let reason: String
    public let contactPhone: String?
    public let contactEmail: String?
    public let contactInfo: String?
    public let proofSnippet: String?

    enum CodingKeys: String, CodingKey {
        case phoneNumber = "phone_number"
        case appealType = "appeal_type"
        case reason
        case contactPhone = "contact_phone"
        case contactEmail = "contact_email"
        case contactInfo = "contact_info"
        case proofSnippet = "proof_snippet"
    }

    public init(
        phoneNumber: String,
        appealType: String = "false_spam",
        reason: String,
        contactPhone: String? = nil,
        contactEmail: String? = nil,
        contactInfo: String? = nil,
        proofSnippet: String? = nil
    ) {
        self.phoneNumber = phoneNumber
        self.appealType = appealType
        self.reason = reason
        self.contactPhone = contactPhone
        self.contactEmail = contactEmail
        self.contactInfo = contactInfo ?? "\(contactPhone ?? "") | \(contactEmail ?? "")"
        self.proofSnippet = proofSnippet
    }
}

nonisolated extension AppealRequestBody: Codable {}

nonisolated public struct AppealResponseData: Sendable {
    public let appealId: Int
    public let status: String
    public let accepted: Bool
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case appealId = "appeal_id"
        case status
        case accepted
        case message
    }
}

nonisolated extension AppealResponseData: Codable {}
