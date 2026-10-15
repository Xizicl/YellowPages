import Foundation
#if canImport(IdentityLookup)
import IdentityLookup
#endif

/// 短信识别与分类决策判定结果 (纯粹基于单一事实源号码库匹配，零正文猜测)
nonisolated public enum SMSFilterVerdict: String, Codable, Sendable {
    /// 正常短信（库中未收录发件人，或普通号码），保持原样留在主收件箱，绝不盲目误拦
    case none = "none"
    /// 垃圾信息拦截（发件人处于黑名单或高危骚扰/欺诈库），系统静默拦截归入垃圾箱
    case junk = "junk"
    /// 交易与重要服务信息（发件人为官方政企、银行金融、快递物流、外卖送餐）
    case transaction = "transaction"
    /// 商业推广信息（发件人为商业广告推销、房产中介）
    case promotion = "promotion"

    public var displayName: String {
        switch self {
        case .none: return "普通收件箱"
        case .junk: return "垃圾拦截"
        case .transaction: return "交易与服务"
        case .promotion: return "商业推广"
        }
    }

    #if canImport(IdentityLookup) && (os(iOS) || targetEnvironment(macCatalyst))
    /// 映射到 iOS 原生 IdentityLookup 过滤动作
    @available(iOS 14.0, *)
    public var ilAction: ILMessageFilterAction {
        switch self {
        case .none:
            return .none
        case .junk:
            return .junk
        case .transaction:
            return .transaction
        case .promotion:
            return .promotion
        }
    }
    #endif
}

/// 判定决策与证据 (包含一类主动作与二类细分子动作)
nonisolated public struct SMSFilterDecision: Sendable {
    public let verdict: SMSFilterVerdict
    public let reason: String
    public let primaryActionName: String
    public let subActionName: String?
    public let matchedSenderLabel: String?
    public let matchedCategory: NumberCategory?

    #if canImport(IdentityLookup) && (os(iOS) || targetEnvironment(macCatalyst))
    @available(iOS 14.0, *)
    public var ilAction: ILMessageFilterAction {
        verdict.ilAction
    }

    @available(iOS 16.0, *)
    public var ilSubAction: ILMessageFilterSubAction {
        guard let cat = matchedCategory else { return .none }
        switch cat {
        case .delivery: return .transactionalOrders
        case .official: return .transactionalPublicServices
        case .enterprise: return .transactionalFinance
        case .realEstate: return .promotionalOthers
        case .financeLoan, .marketing: return .promotionalOffers
        case .harassment, .fraud, .custom: return .none
        }
    }
    #endif

    public init(
        verdict: SMSFilterVerdict,
        reason: String,
        primaryActionName: String,
        subActionName: String? = nil,
        matchedSenderLabel: String? = nil,
        matchedCategory: NumberCategory? = nil
    ) {
        self.verdict = verdict
        self.reason = reason
        self.primaryActionName = primaryActionName
        self.subActionName = subActionName
        self.matchedSenderLabel = matchedSenderLabel
        self.matchedCategory = matchedCategory
    }
}

/// 确定性短信识别与过滤引擎
/// 严格遵循单一事实源原则：绝不进行正文文本关键词分词与猜测，100% 纯粹基于发件人号码匹配本地数据库！
nonisolated public final class SMSFilterEngine: Sendable {
    public static let shared = SMSFilterEngine()

    private let store: DirectoryStore

    public init(store: DirectoryStore = .shared) {
        self.store = store
    }

    private static func subActionName(for category: NumberCategory) -> String {
        switch category {
        case .delivery: return "订单与物流"
        case .official: return "公共政务服务"
        case .enterprise: return "金融银行服务"
        case .realEstate: return "其他商业推广"
        case .financeLoan, .marketing: return "商业优惠与营销"
        case .harassment, .fraud, .custom: return "无"
        }
    }

    /// 纯粹根据发件人号码进行数据库匹配决策（与电话识别逻辑 100% 对齐）
    public func evaluate(sender: String, messageBody: String? = nil) -> SMSFilterDecision {
        let cleanSender = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSender.isEmpty else {
            return SMSFilterDecision(
                verdict: .none,
                reason: "发件人号码为空，保持原样",
                primaryActionName: "正常放行",
                subActionName: nil,
                matchedSenderLabel: nil,
                matchedCategory: nil
            )
        }

        // 1. 发件人号码规范化为 E.164 纯数字
        guard let normalized = ReportService.normalizeToE164(raw: cleanSender) else {
            return SMSFilterDecision(
                verdict: .none,
                reason: "非标准号码格式，保持原样不打扰",
                primaryActionName: "正常放行",
                subActionName: nil,
                matchedSenderLabel: nil,
                matchedCategory: nil
            )
        }

        // 2. 查本地单一事实源数据库 phone_directory
        guard let entry = store.lookup(numericPhone: normalized) else {
            // 本地数据库未收录该发件人：绝不凭空猜测，直接放行留在正常收件箱
            return SMSFilterDecision(
                verdict: .none,
                reason: "本地号码库未收录该发件人，保持原样留存主收件箱",
                primaryActionName: "正常放行",
                subActionName: nil,
                matchedSenderLabel: nil,
                matchedCategory: nil
            )
        }

        // 3. 严格按收录属性确定性分类 (物理 SSOT)

        // 3.1 用户主动拉黑或系统拦截标记 -> 绝对拦截归入垃圾箱
        if entry.isBlocking || entry.action == .block {
            return SMSFilterDecision(
                verdict: .junk,
                reason: "发件人属于拦截黑名单 (\(entry.label))",
                primaryActionName: "垃圾拦截",
                subActionName: Self.subActionName(for: entry.category),
                matchedSenderLabel: entry.label,
                matchedCategory: entry.category
            )
        }

        // 3.2 负向风险分类（恶意骚扰、疑似诈骗） -> 拦截归入垃圾箱
        if entry.category == .fraud || entry.category == .harassment {
            return SMSFilterDecision(
                verdict: .junk,
                reason: "发件人已收录为 \(entry.category.displayName) (\(entry.label))",
                primaryActionName: "垃圾拦截",
                subActionName: Self.subActionName(for: entry.category),
                matchedSenderLabel: entry.label,
                matchedCategory: entry.category
            )
        }

        // 3.3 负向商业推销（房产中介、贷款理财、广告推销） -> 归入商业推广分组
        if entry.category == .marketing || entry.category == .realEstate || entry.category == .financeLoan {
            return SMSFilterDecision(
                verdict: .promotion,
                reason: "发件人已收录为 \(entry.category.displayName) (\(entry.label))",
                primaryActionName: "商业推广",
                subActionName: Self.subActionName(for: entry.category),
                matchedSenderLabel: entry.label,
                matchedCategory: entry.category
            )
        }

        // 3.4 正向与公信机构（快递外卖、官方政企、机构服务） -> 归入交易与重要服务分组
        if entry.category == .official || entry.category == .enterprise || entry.category == .delivery {
            return SMSFilterDecision(
                verdict: .transaction,
                reason: "发件人已收录为 \(entry.category.displayName) (\(entry.label))",
                primaryActionName: "交易与服务",
                subActionName: Self.subActionName(for: entry.category),
                matchedSenderLabel: entry.label,
                matchedCategory: entry.category
            )
        }

        // 3.5 自定义或其它已收录标记
        return SMSFilterDecision(
            verdict: .none,
            reason: "已识别发件人: \(entry.label)",
            primaryActionName: "正常放行",
            subActionName: Self.subActionName(for: entry.category),
            matchedSenderLabel: entry.label,
            matchedCategory: entry.category
        )
    }
}
